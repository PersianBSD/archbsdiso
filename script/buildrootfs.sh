#!/bin/bash

# بارگذاری متغیرها و توابع کمکی
source lib/config.sh
source lib/utils.sh
source lib/help.sh

# تابع ساخت ISO از دایرکتوری rootfs با makefs
_make_iso_from_rootfs() {
    local iso_path="${isofs_dir}/${install_dir}/${arch}/archbsd.iso"
    local esp_file="${work_dir}/efiboot.img"

    case "${iso_build_mode}" in
        simple)
            _msg_info "Creating simple ISO with makefs..."
            makefs -t cd9660 -o rockridge -o label="${iso_label}" "${iso_path}" "${rootfs_dir}"
            ;;

        uefi)
            _msg_info "Creating UEFI ISO with makefs..."
            makefs -t cd9660 -o rockridge -o label="${iso_label}" "${iso_path}" "${rootfs_dir}"
            ;;

        hybrid)
            _msg_info "Creating hybrid ISO with xorrisofs..."
            mkdir -p "${rootfs_dir}/EFI/BOOT"
            cp "${esp_file}" "${rootfs_dir}/EFI/BOOT/efiboot.img"

            xorrisofs -no-emul-boot \
                -boot-load-size 4 \
                -boot-info-table \
                -isohybrid-mbr /usr/share/syslinux/isohdpfx.bin \
                -eltorito-alt-boot \
                -e --interval:appended_partition_2:all:: \
                -no-emul-boot \
                -isohybrid-gpt-basdat \
                -output "${iso_path}" \
                "${rootfs_dir}"
            ;;
        *)
            _msg_error "Invalid iso_build_mode '${iso_build_mode}' for ISO creation." 1
            ;;
    esac

    _msg_info "ISO image created at: ${iso_path}"
}

# تابع ساخت ایمیج UFS برای بوت یا ماشین مجازی
_make_ufs_image() {
    local ufs_img="${isofs_dir}/${install_dir}/${arch}/rootfs.img"
    local size="2G" # سایز قابل تغییر

    [[ -e "${rootfs_dir}" ]] || _msg_error "The path '${rootfs_dir}' does not exist" 1

    _msg_info "Creating blank UFS image file of size ${size}..."
    rm -f "${ufs_img}"
    mkfile "${size}" "${ufs_img}"

    _msg_info "Formatting image with UFS..."
    mkfs.ufs -s 1m -o space "${ufs_img}"

    _msg_info "Mounting image to copy rootfs content..."
    mkdir -p /mnt/ufs_img
    mount -t ufs -o loop "${ufs_img}" /mnt/ufs_img

    cp -a "${rootfs_dir}/." /mnt/ufs_img/

    umount /mnt/ufs_img
    rmdir /mnt/ufs_img

    _msg_info "UFS image created at ${ufs_img}"
}

# تابع اصلی برای انتخاب نوع ساخت rootfs
build_rootfs_image() {
    case "${rootfs_image_type}" in
        iso)
            _make_iso_from_rootfs
            ;;
        ufs)
            _make_ufs_image
            ;;
        zfs)
            _make_rootfs_zfs
            ;;
        *)
            _msg_error "Unsupported rootfs_image_type: ${rootfs_image_type}" 1
            ;;
    esac
}




# Build airootfs filesystem image
_prepare_airootfs_image() {
    _run_once "_mkairootfs_${airootfs_image_type}"
    _mkchecksum

    if [[ -e "${isofs_dir}/${install_dir}/${arch}/airootfs.sfs" ]]; then
        airootfs_image_filename="${isofs_dir}/${install_dir}/${arch}/airootfs.sfs"
    elif [[ -e "${isofs_dir}/${install_dir}/${arch}/airootfs.erofs" ]]; then
        airootfs_image_filename="${isofs_dir}/${install_dir}/${arch}/airootfs.erofs"
    fi

    if [[ -n "${gpg_key}" ]]; then
        _mk_pgp_signature "${airootfs_image_filename}"
    fi
    if [[ -v cert_list ]]; then
        _cms_sign_artifact "${airootfs_image_filename}"
    fi
}


_cms_sign_artifact() {
    local artifact="${1}"
    local openssl_flags=(
        "-sign"
        "-binary"
        "-nocerts"
        "-noattr"
        "-outform" "DER" "-out" "${artifact}.cms.sig"
        "-in" "${artifact}"
        "-signer" "${cert_list[0]}"
        "-inkey" "${cert_list[1]}"
    )

    if (( ${#cert_list[@]} > 2 )); then
        openssl_flags+=("-certfile" "${cert_list[2]}")
    fi

    _msg_info "Signing ${artifact} image using openssl cms..."

    rm -f -- "${artifact}.cms.sig"

    openssl cms "${openssl_flags[@]}"

    _msg_info "Done!"
}


# آماده‌سازی rootfs با کپی فایل‌های سفارشی و تنظیم مجوزها
_make_custom_rootfs() {
    install -d -m 0755 -o 0 -g 0 -- "${rootfs_dir}"

    if [[ -d "${profile}/rootfs" ]]; then
        _msg_info "Copying custom rootfs files..."
        cp -af --no-preserve=ownership,mode -- "${profile}/rootfs/." "${rootfs_dir}"

        for filename in "${!file_permissions[@]}"; do
            IFS=':' read -ra permissions <<<"${file_permissions["${filename}"]}"
            target_path="${rootfs_dir}${filename}"
            if [[ "$(realpath -q -- "${target_path}")" != "${rootfs_dir}"* ]]; then
                _msg_error "Failed to set permissions on '${target_path}'. Outside of valid path." 1
            elif [[ ! -e "${target_path}" ]]; then
                _msg_warning "Cannot change permissions of '${target_path}'. The file or directory does not exist."
            else
                if [[ "${filename: -1}" == "/" ]]; then
                    chown -fhR -- "${permissions[0]}:${permissions[1]}" "${target_path}"
                    chmod -fR -- "${permissions[2]}" "${target_path}"
                else
                    chown -fh -- "${permissions[0]}:${permissions[1]}" "${target_path}"
                    chmod -f -- "${permissions[2]}" "${target_path}"
                fi
            fi
        done
        _msg_info "Done!"
    fi
}

# سفارشی‌سازی نهایی rootfs، کپی /etc/skel و اجرای اسکریپت دلخواه داخل chroot
_make_customize_rootfs() {
    local passwd_line=()

    if [[ -e "${profile}/rootfs/etc/passwd" ]]; then
        _msg_info "Copying /etc/skel/* to user home directories..."
        while IFS=':' read -r -a passwd_line; do
            (( passwd_line[2] >= 1000 && passwd_line[2] < 60000 )) || continue
            [[ "${passwd_line[5]}" == '/' ]] && continue
            [[ -z "${passwd_line[5]}" ]] && continue
            if [[ "$(realpath -q -- "${rootfs_dir}${passwd_line[5]}")" == "${rootfs_dir}"* ]]; then
                [[ ! -d "${rootfs_dir}${passwd_line[5]}" ]] && install -d -m 0750 -o "${passwd_line[2]}" -g "${passwd_line[3]}" -- "${rootfs_dir}${passwd_line[5]}"
                cp -dRT --update=none --preserve=mode,timestamps,links -- "${rootfs_dir}/etc/skel/." "${rootfs_dir}${passwd_line[5]}"
                chmod -f 0750 -- "${rootfs_dir}${passwd_line[5]}"
                chown -hR -- "${passwd_line[2]}:${passwd_line[3]}" "${rootfs_dir}${passwd_line[5]}"
            else
                _msg_error "Failed to set permissions on '${rootfs_dir}${passwd_line[5]}'. Outside of valid path." 1
            fi
        done < "${profile}/rootfs/etc/passwd"
        _msg_info "Done!"
    fi

    if [[ -e "${rootfs_dir}/root/customize_rootfs.sh" ]]; then
        _msg_info "Running customize_rootfs.sh in chroot..."
        chmod +x "${rootfs_dir}/root/customize_rootfs.sh"
        chroot "${rootfs_dir}" /bin/sh -c "/root/customize_rootfs.sh"
        rm -f "${rootfs_dir}/root/customize_rootfs.sh"
        _msg_info "Done! customize_rootfs.sh run successfully."
    fi
}

_cleanup_chroot_dir() {
    _msg_info "Cleaning up FreeBSD root filesystem..."

    # حذف محتویات boot
    [[ -d "${rootfs_dir}/boot" ]] && find "${rootfs_dir}/boot" -mindepth 1 -delete

    # حذف کش pkg
    [[ -d "${rootfs_dir}/var/cache/pkg" ]] && find "${rootfs_dir}/var/cache/pkg" -type f -delete

    # حذف دیتابیس pkg
    [[ -d "${rootfs_dir}/var/db/pkg" ]] && find "${rootfs_dir}/var/db/pkg" -mindepth 1 -delete

    # حذف لاگ‌ها
    [[ -d "${rootfs_dir}/var/log" ]] && find "${rootfs_dir}/var/log" -type f -delete

    # حذف فایل‌های موقت
    [[ -d "${rootfs_dir}/var/tmp" ]] && find "${rootfs_dir}/var/tmp" -mindepth 1 -delete

    # حذف hostid (اگر وجود داشته باشد)
    rm -f -- "${rootfs_dir}/etc/hostid"

    _msg_info "Cleanup done!"
}

# ساخت rootfs روی ZFS pool به نام rpool
_make_rootfs_zfs() {
    local zfs_pool="rpool"
    local zfs_dataset="${zfs_pool}/rootfs"
    local mountpoint="${rootfs_dir}"

    _msg_info "Creating ZFS dataset ${zfs_dataset} for rootfs..."

    # بررسی وجود دیتاست و حذف آن در صورت وجود
    if zfs list "${zfs_dataset}" &>/dev/null; then
        _msg_warning "ZFS dataset ${zfs_dataset} already exists, destroying it..."
        zfs destroy -r "${zfs_dataset}"
    fi

    # ساخت دیتاست جدید
    zfs create -o mountpoint="${mountpoint}" "${zfs_dataset}"

    # مطمئن شو mountpoint درست ست شده
    zfs mount "${zfs_dataset}"

    _msg_info "Copying rootfs files to ZFS dataset mountpoint..."
    # پاک کردن محتوای قدیمی در صورت وجود
    rm -rf "${mountpoint:?}/"*
    cp -a "${profile}/rootfs/." "${mountpoint}/"

    _msg_info "Rootfs copied to ZFS dataset ${zfs_dataset}"
}
