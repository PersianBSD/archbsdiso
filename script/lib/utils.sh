#!/bin/bash
# فایل utils.sh - توابع کمکی برای ArchBSD

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
