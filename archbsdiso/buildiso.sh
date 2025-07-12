
#!/bin/bash

set -euo pipefail
shopt -s extglob
# کنترل محیط
umask 0022
# بارگذاری ماژول‌ها
source lib/config.sh
source lib/utils.sh
source ./read_profile.sh
source ./buildrootfs.sh
source ./validate.sh
source ./pkglist.sh
source ./bootloader.sh


export LC_ALL="C.UTF-8"
[[ -v SOURCE_DATE_EPOCH ]] || printf -v SOURCE_DATE_EPOCH '%(%s)T' -1
export SOURCE_DATE_EPOCH

# Create working directory
_make_work_dir() {
    if [[ ! -d "${work_dir}" ]]; then
        install -d -- "${work_dir}"
    elif (( rm_work_dir )); then
        rm_work_dir=0
        _msg_warning "Working directory removal requested, but '${work_dir}' already exists. It will not be removed!" 0
    fi
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
    _run_once _cleanup_pacstrap_dir
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