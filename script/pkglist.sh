# بارگذاری متغیرها و توابع کمکی
source lib/config.sh
source lib/utils.sh
source lib/help.sh

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