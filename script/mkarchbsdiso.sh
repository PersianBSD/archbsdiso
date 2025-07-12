#!/bin/bash

set -euo pipefail
shopt -s extglob

#----------------------------------config
# کنترل محیط
umask 0022
export LC_ALL="C.UTF-8"
[[ -v SOURCE_DATE_EPOCH ]] || printf -v SOURCE_DATE_EPOCH '%(%s)T' -1
export SOURCE_DATE_EPOCH
# نام برنامه (اسکریپت) از نام فایل اجرایی
app_name="archbsd"

quiet=""
arch="$(uname -m)"
cert_list=()
declare -i need_external_ucodes=0

# تعریف متغیرهای سراسری
pkg_list=(
    "bash"
    "sudo"
    "vim"
    "nano"
)

# لیست بسته‌های پایه در صورت خالی بودن pkg_list
base_pkg_list=(
    "base"
    "kernel"
    "openrc"
    "dhcpcd"
    "ca_root_nss"
)

pkg_conf="/etc/archbsd.conf"
packages=""


bootstrap_pkg_list=()
bootmodes=()
bootstrap_tarball_compression=""
bootstrap_parent="$(dirname "${pkg_dir}")"
efiboot_files=()

#directories

work_dir="./work"
out_dir="./out"
rootfs_dir="./work/rootfs"
isofs_dir="./work/iso"
install_dir="${app_name}"
pkg_dir="${rootfs_dir}"

rm_work_dir=0

gpg_key=""
gpg_sender=""

iso_label="${app_name^^}_ISO"
iso_version="1.0.0"
iso_name="${app_name}"
iso_publisher="${app_name}"
iso_application="${app_name} ISO"

airootfs_image_type=""
airootfs_image_tool_options=()

search_filename=""
declare -A file_permissions=()

buildmodes=('iso')
profile
override_buildmodes 





# اگر pkg_list خالی بود، آن را با بسته‌های پایه جایگزین کن
if (( ${#pkg_list[@]} == 0 )); then
    pkg_list=("${base_pkg_list[@]}")
fi

# نمایش تنظیمات فعلی - برای دیباگ و گزارش
_show_config() {
    local build_date
    printf -v build_date '%(%FT%R%z)T' "${SOURCE_DATE_EPOCH:-$(date +%s)}"
    _msg_info "${app_name} configuration settings"
    _msg_info "             Architecture:   ${arch}"
    _msg_info "        Working directory:   ${work_dir}"
    _msg_info "   Installation directory:   ${install_dir}"
    _msg_info "               Build date:   ${build_date}"
    _msg_info "         Output directory:   ${out_dir}"
    _msg_info "       Current build mode:   ${buildmode}"
    _msg_info "              Build modes:   ${buildmodes[*]}"
    _msg_info "                  GPG key:   ${gpg_key:-None}"
    _msg_info "               GPG signer:   ${gpg_sender:-None}"
    _msg_info "Code signing certificates:   ${cert_list[*]:-None}"
    _msg_info "                  Profile:   ${profile:-None}"
    _msg_info "Pacman configuration file:   ${pacman_conf:-None}"
    _msg_info "          Image file name:   ${image_name:-None}"
    _msg_info "         ISO volume label:   ${iso_label}"
    _msg_info "            ISO publisher:   ${iso_publisher}"
    _msg_info "          ISO application:   ${iso_application}"
    _msg_info "               Boot modes:   ${bootmodes[*]:-None}"
    _msg_info "            Packages File:   ${buildmode_packages:-None}"
    _msg_info "                 Packages:   ${pkg_list[*]}"
}

#--------------------------------------util

# نمایش پیام INFO
# پارامتر $1: متن پیام
_msg_info() {
    local _msg="${1}"
    # اگر quiet فعال نیست پیام را نمایش بده
    [[ "${quiet}" == "y" ]] || printf '[%s] INFO: %s\n' "${app_name}" "${_msg}"
}

# نمایش پیام WARNING
# پارامتر $1: متن پیام
_msg_warning() {
    local _msg="${1}"
    printf '[%s] WARNING: %s\n' "${app_name}" "${_msg}" >&2
}

# نمایش پیام ERROR و خروج با کد وضعیت
# پارامتر $1: متن پیام
# پارامتر $2: کد خروج (0 یعنی بدون خروج)
_msg_error() {
    local _msg="${1}"
    local _error=${2:-0}
    printf '[%s] ERROR: %s\n' "${app_name}" "${_msg}" >&2
    if (( _error > 0 )); then
        exit "${_error}"
    fi
}

# اجرای یک تابع تنها یک بار در طول اجرای اسکریپت
# پارامتر $1: نام تابع
_run_once() {
    if [[ ! -e "${work_dir}/${run_once_mode}.${1}" ]]; then
        "$1"
        touch "${work_dir}/${run_once_mode}.${1}"
    fi
}

# ساخت فایل‌های ورژن و افزودن مشخصات به os-release و سایر مکان‌ها
_make_version() {
    local _os_release

    _msg_info "Creating version files..."
    # حذف نسخه قبلی و نوشتن ورژن جدید در مسیر نصب
    rm -f -- "${pacstrap_dir}/version"
    printf '%s\n' "${iso_version}" >"${pacstrap_dir}/version"

    # برای حالت‌های iso و netboot، ورژن را در ایزو هم بنویس
    if [[ "${buildmode}" == @("iso"|"netboot") ]]; then
        install -d -m 0755 -- "${isofs_dir}/${install_dir}"
        printf '%s\n' "${iso_version}" >"${isofs_dir}/${install_dir}/version"
    fi

    # برای iso یک grubenv محدود بساز که ورژن را نگه دارد
    if [[ "${buildmode}" == "iso" ]]; then
        rm -f -- "${isofs_dir}/${install_dir}/grubenv"
        printf '%.1024s' "$(printf '# GRUB Environment Block\nNAME=%s\nVERSION=%s\n%s' \
            "${iso_name}" "${iso_version}" "$(printf '%0.1s' "#"{1..1024})")" \
            >"${isofs_dir}/${install_dir}/grubenv"

        # ساخت یک فایل UUID منحصر به فرد برای GRUB جستجو در ISO
        search_filename="/boot/${iso_uuid}.uuid"
        install -d -m 755 -- "${isofs_dir}/boot"
        : >"${isofs_dir}${search_filename}"
    fi

    # افزودن IMAGE_ID و IMAGE_VERSION به فایل os-release (اگر موجود باشد)
    _os_release="$(realpath -- "${pacstrap_dir}/etc/os-release" 2>/dev/null)"
    if [[ ! -e "${pacstrap_dir}/etc/os-release" && -e "${pacstrap_dir}/usr/lib/os-release" ]]; then
        _os_release="$(realpath -- "${pacstrap_dir}/usr/lib/os-release")"
    fi
    if [[ "${_os_release}" != "${pacstrap_dir}"* ]]; then
        _msg_warning "os-release file '${_os_release}' is outside of valid path."
    else
        [[ ! -e "${_os_release}" ]] || sed -i '/^IMAGE_ID=/d;/^IMAGE_VERSION=/d' "${_os_release}"
        printf 'IMAGE_ID=%s\nIMAGE_VERSION=%s\n' "${iso_name}" "${iso_version}" >>"${_os_release}"
    fi

    # ایجاد فایل timestamp برای پشتیبانی از سیستم‌هایی با ساعت معیوب
    touch -m -d"@${SOURCE_DATE_EPOCH}" -- "${pacstrap_dir}/usr/lib/clock-epoch"

    _msg_info "Done!"
}

#--------------------------------help

# Show help usage and exit with status
# $1: exit status code
_usage() {
    IFS='' read -r -d '' usagetext <<ENDUSAGETEXT || true
usage: ${app_name} [options] <profile_dir>

options:
  -A <application>  Set the application name for the ISO (default: '${iso_application}')
  -C <file>         Package manager config file (default: '${pacman_conf}')
  -D <install_dir>  Installation directory inside the ISO (default: '${install_dir}')
  -L <label>        ISO volume label (default: '${iso_label}')
  -m [mode ..]      Build mode(s) to use ('bootstrap', 'iso', 'netboot')
                    Multiple modes separated by spaces.
  -o <out_dir>      Output directory (default: '${out_dir}')
  -p [package ..]   Package(s) to install (space separated list)
  -r                Remove working directory after build
  -v                Enable verbose output
  -w <work_dir>     Working directory (default: '${work_dir}')
  -h                Show this help and exit

profile_dir:
  Directory of the profile to build the ISO from

ENDUSAGETEXT
    printf '%s' "${usagetext}"
    exit "${1}"
}
#----------------------------profile


# Load profile variables from profiledef.sh
_read_profile() {
    if [[ -z "$profile" ]]; then
        _msg_error "No profile specified!" 1
    fi
    if [[ ! -d "$profile" ]]; then
        _msg_error "Profile '$profile' does not exist!" 1
    elif [[ ! -e "$profile/profile.sh" ]]; then
        _msg_error "Profile '$profile' is missing 'profile.sh'!" 1
    else
        cd -- "$profile" || _msg_error "Failed to cd into profile directory" 1

        # Source profile's variables
        # shellcheck source=configs/releng/profiledef.sh
        . "$profile/profile.sh"

        # Resolve paths of expected files
        : "${arch:=$(uname -m)}"
        : "${packages:=$profile/packages.$arch}"
        pkg_list_file="${profile}/pkg.list"
        pkg_conf_file="${profile}/pkg.conf"
        ٫packages="$(realpath -- "$packages")"
       

    # بررسی وجود فایل‌ها
    [[ -f "${pkg_list_file}" ]] || _msg_warning "Package list '${pkg_list_file}' not found."
    [[ -f "${pkg_conf_file}" ]] || _msg_warning "Package config '${pkg_conf_file}' not found."


        cd - >/dev/null || _msg_error "Failed to cd back to previous directory" 1
    fi
}

# Set defaults and apply overrides from command line
_set_overrides() {
    # Buildmodes override
    if [[ -v override_buildmodes ]]; then
        buildmodes=("${override_buildmodes[@]}")
    fi
    (( ${#buildmodes[@]} )) || buildmodes=('iso')

    # Work dir override or default
    if [[ -v override_work_dir ]]; then
        work_dir="$override_work_dir"
    elif [[ -z "${work_dir-}" ]]; then
        work_dir='./work'
    fi
    work_dir="$(realpath -- "$work_dir")"

    # Output dir override or default
    if [[ -v override_out_dir ]]; then
        out_dir="$override_out_dir"
    elif [[ -z "${out_dir-}" ]]; then
        out_dir='./out'
    fi
    out_dir="$(realpath -- "$out_dir")"

    # Pacman config override or default
    if [[ -v override_pacman_conf ]]; then
        pacman_conf="$override_pacman_conf"
    elif [[ -z "${pacman_conf-}" ]]; then
        pacman_conf="/etc/pacman.conf"
    fi
    pacman_conf="$(realpath -- "$pacman_conf")"

    # Package list override
    if [[ -v override_pkg_list ]]; then
        pkg_list+=("${override_pkg_list[@]}")
    fi

    # ISO label override or default
    if [[ -v override_iso_label ]]; then
        iso_label="$override_iso_label"
    elif [[ -z "${iso_label-}" ]]; then
        iso_label="${app_name^^}"
    fi

    # ISO publisher override or default
    if [[ -v override_iso_publisher ]]; then
        iso_publisher="$override_iso_publisher"
    elif [[ -z "${iso_publisher-}" ]]; then
        iso_publisher="$app_name"
    fi

    # ISO application override or default
    if [[ -v override_iso_application ]]; then
        iso_application="$override_iso_application"
    elif [[ -z "${iso_application-}" ]]; then
        iso_application="${app_name} iso"
    fi

    # Install dir override or default
    if [[ -v override_install_dir ]]; then
        install_dir="$override_install_dir"
    elif [[ -z "${install_dir-}" ]]; then
        install_dir="$app_name"
    fi

    # GPG overrides
    [[ -v override_gpg_key ]] && gpg_key="$override_gpg_key"
    [[ -v override_gpg_sender ]] && gpg_sender="$override_gpg_sender"

    # Cert list override, convert to real paths
    if [[ -v override_cert_list ]]; then
        mapfile -t cert_list < <(realpath -- "${override_cert_list[@]}")
    fi

    # Quiet flag override or default
    if [[ -v override_quiet ]]; then
        quiet="$override_quiet"
    elif [[ -z "${quiet-}" ]]; then
        quiet="y"
    fi

    # Remove work dir override
    [[ -v override_rm_work_dir ]] && rm_work_dir="$override_rm_work_dir"

    # Defaults for unset variables
    airootfs_image_type="${airootfs_image_type:-squashfs}"
    iso_name="${iso_name:-$app_name}"

    # Precalculate ISO UUID based on SOURCE_DATE_EPOCH (required)
    TZ=UTC printf -v iso_uuid '%(%F-%H-%M-%S-00)T' "$SOURCE_DATE_EPOCH"
}


#----------------------------bootloader


# Create EFI System Partition (ESP) as a file for ISO
_make_esp_file() {
    local esp_file="$1"
    local size_mb="${2:-50}"  # Default 50MB

    _msg_info "Creating EFI System Partition image (${size_mb}MB)..."
    rm -f "${esp_file}"
    mkfile "${size_mb}m" "${esp_file}"

    _msg_info "Formatting ESP as FAT32..."
    newfs_msdos -F 32 -c 1 "${esp_file}"

    _msg_info "Mounting ESP to copy EFI bootloader files..."
    local mnt_dir
    mnt_dir=$(mktemp -d)
    mount -t msdosfs -o loop "${esp_file}" "${mnt_dir}"

    mkdir -p "${mnt_dir}/EFI/BOOT"
    if [[ -e "/boot/loader.efi" ]]; then
        cp /boot/loader.efi "${mnt_dir}/EFI/BOOT/BOOTX64.EFI"
    else
        _msg_warning "EFI bootloader /boot/loader.efi not found!"
    fi

    umount "${mnt_dir}"
    rmdir "${mnt_dir}"

    _msg_info "ESP image created at: ${esp_file}"
}

# Install boot0 MBR bootcode to ISO image (for BIOS boot)
_install_mbr_bootcode() {
    local iso_path="$1"
    _msg_info "Installing MBR boot code to ISO..."
    boot0cfg -B "${iso_path}"
    _msg_info "MBR boot code installed."
}

# Setup bootloader for hybrid ISO (MBR+GPT)
_setup_hybrid_boot() {
    local iso_path="$1"
    local esp_file="${work_dir}/efiboot.img"

    _make_esp_file "${esp_file}" 50
    _install_mbr_bootcode "${iso_path}"

    _msg_info "Attaching ESP image to ISO as second partition (GPT)..."
    # ساخت ISO هیبرید با استفاده از mkisofs یا xorrisofs باید اینجا انجام شود.
    # تابع ساخت ISO باید این فایل esp_file را به ISO الحاق کند.
}

# تابع اصلی بوت‌لودر (مثلاً در buildiso.sh فراخوانی شود)
_make_bootloader() {
    local iso_path="${isofs_dir}/${install_dir}/${arch}/archbsd.iso"

    case "${iso_build_mode}" in
        simple)
            _msg_info "Simple bootloader setup (makefs + MBR)..."
            makefs -t cd9660 -o rockridge -o label="${iso_label}" "${iso_path}" "${rootfs_dir}"
            _install_mbr_bootcode "${iso_path}"
            ;;

        uefi)
            _msg_info "UEFI bootloader setup with ESP..."
            makefs -t cd9660 -o rockridge -o label="${iso_label}" "${iso_path}" "${rootfs_dir}"
            _make_esp_file "${work_dir}/efiboot.img"
            # در ساخت ISO باید efiboot.img الحاق شود
            ;;

        hybrid)
            _msg_info "Hybrid bootloader setup (MBR + GPT + ESP)..."
            _setup_hybrid_boot "${iso_path}"
            ;;

        *)
            _msg_error "Invalid iso_build_mode '${iso_build_mode}' for bootloader setup." 1
            ;;
    esac

    _msg_info "Bootloader setup complete. ISO located at: ${iso_path}"
}

#---------------------------------------------------rootfs

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

#-----------------------------------------------pkg

_make_pkglist() {
    _msg_info "Creating a list of installed packages on live environment..."

    case "${buildmode}" in
        "bootstrap")
            # استخراج لیست بسته‌ها از محیط ریشه bootstrap
            pkg -r "${pacstrap_dir}" info > "${bootstrap_parent}/pkglist.${arch}.txt"
            ;;
        "iso"|"netboot")
            install -d -m 0755 -- "${isofs_dir}/${install_dir}"
            # استخراج لیست بسته‌ها از محیط ریشه ایزو یا نتبوت
            pkg -r "${pacstrap_dir}" info > "${isofs_dir}/${install_dir}/pkglist.${arch}.txt"
            ;;
        *)
            _msg_warning "Unknown buildmode '${buildmode}', skipping pkglist creation."
            ;;
    esac

    _msg_info "Done!"
}

# نصب پکیج‌ها داخل chroot با pkg
_make_packages() {
    _msg_info "Installing packages into '${rootfs_dir}'..."

    if [[ -v gpg_publickey ]]; then
        exec {ARCHISO_GNUPG_FD}<"$gpg_publickey"
        export ARCHISO_GNUPG_FD
    fi
    if [[ -v cert_list[0] ]]; then
        exec {ARCHISO_TLS_FD}<"${cert_list[0]}"
        export ARCHISO_TLS_FD
    fi
    if [[ -v cert_list[2] ]]; then
        exec {ARCHISO_TLSCA_FD}<"${cert_list[2]}"
        export ARCHISO_TLSCA_FD
    fi

    chroot "${rootfs_dir}" env ASSUME_ALWAYS_YES=yes pkg bootstrap

    if [[ "${quiet}" == "y" ]]; then
        chroot "${rootfs_dir}" env ASSUME_ALWAYS_YES=yes pkg install -y "${buildmode_pkg_list[@]}" >/dev/null
    else
        chroot "${rootfs_dir}" env ASSUME_ALWAYS_YES=yes pkg install -y "${buildmode_pkg_list[@]}"
    fi

    if [[ -v cert_list[0] ]]; then
        exec {ARCHISO_TLS_FD}<&-
        unset ARCHISO_TLS_FD
    fi
    if [[ -v cert_list[2] ]]; then
        exec {ARCHISO_TLSCA_FD}<&-
        unset ARCHISO_TLSCA_FD
    fi
    if [[ -v gpg_publickey ]]; then
        exec {ARCHISO_GNUPG_FD}<&-
        unset ARCHISO_GNUPG_FD
    fi

    _msg_info "Done! Packages installed successfully."
}

# پاکسازی دایرکتوری pkg_dir (محل نصب بسته‌ها)
_cleanup_pkg_dir() {
    _msg_info "Cleaning up package directory '${pkg_dir}'..."

    if [[ -d "${pkg_dir}" ]]; then
        # حذف کش pkg
        if [[ -d "${pkg_dir}/var/cache/pkg" ]]; then
            find "${pkg_dir}/var/cache/pkg" -type f -exec rm -f {} + || true
        fi

        # حذف دیتابیس pkg
        if [[ -d "${pkg_dir}/var/db/pkg" ]]; then
            find "${pkg_dir}/var/db/pkg" -mindepth 1 -exec rm -rf {} + || true
        fi

        # حذف لاگ‌ها
        if [[ -d "${pkg_dir}/var/log" ]]; then
            find "${pkg_dir}/var/log" -type f -exec rm -f {} + || true
        fi

        # حذف فایل‌های موقت
        if [[ -d "${pkg_dir}/var/tmp" ]]; then
            find "${pkg_dir}/var/tmp" -mindepth 1 -exec rm -rf {} + || true
        fi

        # حذف فایل hostid (اگر هست)
        rm -f -- "${pkg_dir}/etc/hostid" 2>/dev/null || true
    fi

    _msg_info "Package directory cleanup done."
}


#---------------------------------------validate 

_export_gpg_publickey() {
    gpg_publickey="${work_dir}/pubkey.gpg"
    rm -f -- "$gpg_publickey"
    if ! gpg --batch --no-armor --output "$gpg_publickey" --export "${gpg_key}"; then
        _msg_warning "Failed to export GPG public key '${gpg_key}'."
        return 1
    fi
    if [[ ! -s "$gpg_publickey" ]]; then
        _msg_warning "Exported GPG public key file is empty."
        return 1
    fi
}

_mkchecksum() {
    _msg_info "Creating checksum file for self-test..."
    cd -- "${isofs_dir}/${install_dir}/${arch}" || _msg_error "Failed to cd to ${isofs_dir}/${install_dir}/${arch}" 1

    if [[ -e "archbsd.iso" ]]; then
        sha512 archbsd.iso > archbsd.sha512
    elif [[ -e "rootfs.img" ]]; then
        sha512 rootfs.img > rootfs.sha512
    else
        _msg_warning "No rootfs image found to checksum."
    fi

    cd -- "${OLDPWD}" || true
    _msg_info "Done!"
}

_mk_pgp_signature() {
    local gpg_options=()
    local rootfs_image_filename="${1}"
    _msg_info "Signing rootfs image using GPG..."

    rm -f -- "${rootfs_image_filename}.sig"
    [[ -n "${gpg_sender}" ]] && gpg_options+=('--sender' "${gpg_sender}")

    gpg --batch --no-armor --no-include-key-block --output "${rootfs_image_filename}.sig" --detach-sign \
        --default-key "${gpg_key}" "${gpg_options[@]}" "${rootfs_image_filename}"

    _msg_info "Done!"
}
#۱. توابع اعتبارسنجی پایه برای FreeBSD
_validate_requirements_airootfs_image_type_ufs() {
    # FreeBSD معمولا از UFS استفاده می‌کند، پس چک کنیم ابزار ساخت آن موجود است
    if ! command -v newfs &>/dev/null; then
        (( validation_error=validation_error+1 ))
        _msg_error "Validating '${airootfs_image_type}': newfs is not available on this host. Install base system utilities!" 0
    fi
}

_validate_requirements_airootfs_image_type_zfs() {
    # بررسی وجود zfs tools
    if ! command -v zfs &>/dev/null || ! command -v zpool &>/dev/null; then
        (( validation_error=validation_error+1 ))
        _msg_error "Validating '${airootfs_image_type}': zfs or zpool command not found. Install ZFS utilities!" 0
    fi
}
#۲. اعتبارسنجی ابزارهای پایه برای ساخت ISO و rootfs
_validate_common_requirements_buildmode_all() {
 
    if ! command -v pkg &>/dev/null; then
        (( validation_error=validation_error+1 ))
        _msg_error "Validating build mode '${_buildmode}': pkg is not available on this host. Install pkg!" 0
    fi

    if ! command -v find &>/dev/null; then
        (( validation_error=validation_error+1 ))
        _msg_error "Validating build mode '${_buildmode}': find is not available on this host. Install findutils!" 0
    fi

    if ! command -v gzip &>/dev/null; then
        (( validation_error=validation_error+1 ))
        _msg_error "Validating build mode '${_buildmode}': gzip is not available on this host. Install gzip!" 0
    fi
}
#۳. اعتبارسنجی برای ساخت Bootstrap
_validate_requirements_buildmode_bootstrap() {
    local bootstrap_pkg_list_from_file=()

    if [[ -e "${bootstrap_packages}" ]]; then
        mapfile -t bootstrap_pkg_list_from_file < <(sed '/^[[:blank:]]*#.*/d;s/#.*//;/^[[:blank:]]*$/d' "${bootstrap_packages}")
        bootstrap_pkg_list+=("${bootstrap_pkg_list_from_file[@]}")
        if (( ${#bootstrap_pkg_list_from_file[@]} < 1 )); then
            (( validation_error=validation_error+1 ))
            _msg_error "No package specified in '${bootstrap_packages}'." 0
        fi
    else
        (( validation_error=validation_error+1 ))
        _msg_error "Bootstrap packages file '${bootstrap_packages}' does not exist." 0
    fi

    _validate_common_requirements_buildmode_all

    if ! command -v bsdtar &>/dev/null; then
        (( validation_error=validation_error+1 ))
        _msg_error "Validating build mode '${_buildmode}': bsdtar is not available on this host. Install libarchive!" 0
    fi

    # بررسی فشرده‌سازی معمول در FreeBSD (gzip, bzip2, xz, zstd)
    if (( ${#bootstrap_tarball_compression[@]} )); then
        case "${bootstrap_tarball_compression[0]}" in
            'bzip'|'gzip'|'lzma'|'xz'|'zstd')
                if ! command -v "${bootstrap_tarball_compression[0]}" &>/dev/null; then
                    (( validation_error=validation_error+1 ))
                    _msg_error "Validating build mode '${_buildmode}': '${bootstrap_tarball_compression[0]}' is not available on this host. Install it!" 0
                fi
                ;;
            *)
                (( validation_error=validation_error+1 ))
                _msg_error "Validating build mode '${_buildmode}': '${bootstrap_tarball_compression[0]}' is not a supported compression method!" 0
                ;;
        esac
    fi
}

_validate_requirements_buildmode_iso() {
    _validate_common_requirements_buildmode_iso_netboot
    _validate_common_requirements_buildmode_all

    if (( ${#bootmodes[@]} < 1 )); then
        (( validation_error=validation_error+1 ))
        _msg_error "No boot modes specified in '${profile}/profiledef.sh'." 0
    fi

    local bootmode
    for bootmode in "${bootmodes[@]}"; do
        if typeset -f "_make_bootmode_${bootmode}" &>/dev/null; then
            if typeset -f "_validate_requirements_bootmode_${bootmode}" &>/dev/null; then
                "_validate_requirements_bootmode_${bootmode}"
            else
                _msg_warning "Function '_validate_requirements_bootmode_${bootmode}' does not exist. Skipping validation."
            fi
        else
            (( validation_error=validation_error+1 ))
            _msg_error "${bootmode} is not a valid boot mode!" 0
        fi
    done

    if ! command -v awk &>/dev/null; then
        (( validation_error=validation_error+1 ))
        _msg_error "Validating build mode '${_buildmode}': awk is not available on this host. Install awk!" 0
    fi
}

_validate_options() {
    local validation_error=0 _buildmode certfile

    _msg_info "Validating options..."

    if [[ ! -e "${pkg_conf}" ]]; then
        (( validation_error++ ))
        _msg_error "File '${pkg_conf}' does not exist." 0
    fi

    for certfile in "${cert_list[@]}"; do
        if [[ ! -e "$certfile" ]]; then
            (( validation_error++ ))
            _msg_error "Code signing certificate '${certfile}' does not exist." 0
        fi
    done

    for _buildmode in "${buildmodes[@]}"; do
        if typeset -f "_build_buildmode_${_buildmode}" &>/dev/null; then
            if typeset -f "_validate_requirements_buildmode_${_buildmode}" &>/dev/null; then
                "_validate_requirements_buildmode_${_buildmode}"
            else
                _msg_warning "Function '_validate_requirements_buildmode_${_buildmode}' does not exist. Validating requirements not possible."
            fi
        else
            (( validation_error++ ))
            _msg_error "${_buildmode} is not a valid build mode!" 0
        fi
    done

    if (( validation_error )); then
        _msg_error "${validation_error} errors found during validation. Aborting." 1
    fi

    _msg_info "Done!"
}

#--------------------------------------------------iso
_make_work_dir() {
    if [[ ! -d "${work_dir}" ]]; then
        install -d -- "${work_dir}"
    elif (( rm_work_dir )); then
        rm_work_dir=0
        _msg_warning "Working directory removal requested, but '${work_dir}' already exists. It will not be removed!" 0
    fi
}


# ساخت ایمیج پایه (Bootstrap image) به صورت tar فشرده با zstd (قابل تغییر)
_build_base_image() {
    local image_name="${iso_name}-bootstrap-${iso_version}-${arch}.tar.zst"
    local image_path="${out_dir}/${image_name}"

    _msg_info "Building base bootstrap image '${image_name}'..."

    # اطمینان از وجود دایرکتوری خروجی
    install -d -- "${out_dir}"

    # ایجاد tar فشرده با zstd
    tar --use-compress-program="zstd -T0 -19" -cf "${image_path}" -C "${pkg_dir}" .

    _msg_info "Base bootstrap image created at '${image_path}'"
}



# build the base for an ISO and/or a netboot target
_build_iso_base() {
    local run_once_mode="base"
    local buildmode_packages="${packages}"
    # Set the package list to use
    local buildmode_pkg_list=("${pkg_list[@]}")
    # Set up essential directory paths
    pkg_dir="${work_dir}/${arch}/airootfs"
    isofs_dir="${work_dir}/iso"

    # Create working directory
    _run_once _make_work_dir
    # Write build date to file if it does not exist already
    [[ -e "${work_dir}/build_date" ]] || printf '%s\n' "$SOURCE_DATE_EPOCH" >"${work_dir}/build_date"

    [[ "${quiet}" == "y" ]] || _show_config
    _run_once _make_pacman_conf
    [[ -z "${gpg_key}" ]] || _run_once _export_gpg_publickey
    _run_once _make_custom_airootfs
    _run_once _make_packages
    _run_once _make_version
    _run_once _make_customize_airootfs
    _run_once _make_pkglist
    _run_once _check_if_initramfs_has_ucode
    if [[ "${buildmode}" == 'netboot' ]]; then
        _run_once _make_boot_on_iso9660
    else
        _make_bootmodes
    fi
    _run_once _cleanup_pkg_dir
    _run_once _prepare_airootfs_image
}


# Build the bootstrap buildmode
_build_buildmode_bootstrap() {
    local image_name="${iso_name}-bootstrap-${iso_version}-${arch}.tar"
    local run_once_mode="${buildmode}"
    local buildmode_packages="${bootstrap_packages}"
    # Set the package list to use
    local buildmode_pkg_list=("${bootstrap_pkg_list[@]}")

    # Set up essential directory paths
    pacstrap_dir="${work_dir}/${arch}/bootstrap/root.${arch}"
    bootstrap_parent="$(dirname -- "${pacstrap_dir}")"
    [[ -d "${work_dir}" ]] || install -d -- "${work_dir}"
    install -d -m 0755 -o 0 -g 0 -- "${pacstrap_dir}"

    # Set tarball extension
    case "${bootstrap_tarball_compression[0]}" in
        'bzip') image_name="${image_name}.b2z" ;;
        'gzip') image_name="${image_name}.gz" ;;
        'lrzip') image_name="${image_name}.lrz" ;;
        'lzip') image_name="${image_name}.lz" ;;
        'lzop') image_name="${image_name}.lzo" ;;
        'xz') image_name="${image_name}.xz" ;;
        'zstd'|'zstdmt') image_name="${image_name}.zst" ;;
    esac

    [[ "${quiet}" == "y" ]] || _show_config
    _run_once _make_pkg_conf
    _run_once _make_version
    _run_once _make_pkglist
    _run_once _cleanup_pkg_dir
    _run_once _build_base_image
}


# Build the ISO buildmode
_build_buildmode_iso() {
    local image_name="${iso_name}-${iso_version}-${arch}.iso"
    local run_once_mode="${buildmode}"
    efibootimg="${work_dir}/efiboot.img"
    _build_iso_base
    _run_once _build_iso_image
}

# build all buildmodes
_build() {
    local buildmode
    local run_once_mode="build"

    for buildmode in "${buildmodes[@]}"; do
        _run_once "_build_buildmode_${buildmode}"
    done
    if (( rm_work_dir )); then
        _msg_info 'Removing the working directory...'
        rm -rf -- "${work_dir:?}/"
        _msg_info 'Done!'
    fi
}

#--------------------------------------------main

while getopts 'c:p:C:L:P:A:D:w:m:o:g:G:vrh?' arg; do
    case "${arg}" in
        p) read -r -a override_pkg_list <<<"${OPTARG}" ;;
        C) override_pacman_conf="${OPTARG}" ;;
        L) override_iso_label="${OPTARG}" ;;
        P) override_iso_publisher="${OPTARG}" ;;
        A) override_iso_application="${OPTARG}" ;;
        D) override_install_dir="${OPTARG}" ;;
        c) read -r -a override_cert_list <<<"${OPTARG}" ;;
        w) override_work_dir="${OPTARG}" ;;
        m) read -r -a override_buildmodes <<<"${OPTARG}" ;;
        o) override_out_dir="${OPTARG}" ;;
        g) override_gpg_key="${OPTARG}" ;;
        G) override_gpg_sender="${OPTARG}" ;;
        v) override_quiet="n" ;;
        r) declare -i override_rm_work_dir=1 ;;
        h|?) _usage 0 ;;
        *)
            _msg_error "Invalid argument '${arg}'" 0
            _usage 1
            ;;
    esac
done

shift $((OPTIND - 1))

if (( $# < 1 )); then
    _msg_error "No profile specified" 0
    _usage 1
fi

if (( EUID != 0 )); then
    _msg_error "${app_name} must be run as root." 1
fi

# get the absolute path representation of the first non-option argument
profile="$(realpath -- "${1}")"

# Read SOURCE_DATE_EPOCH from file early
build_date_file="$(realpath -q -- "${override_work_dir:-./work}/build_date")" || :
if [[ -f "$build_date_file" ]]; then
    SOURCE_DATE_EPOCH="$(<"$build_date_file")"
fi
unset build_date_file

_read_profile
_set_overrides
_validate_options
_build