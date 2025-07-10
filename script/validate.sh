#!/bin/bash

# بارگذاری متغیرها و توابع کمکی
source lib/config.sh
source lib/utils.sh
source lib/help.sh

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
