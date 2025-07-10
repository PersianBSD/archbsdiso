
# بارگذاری متغیرها و توابع کمکی
source lib/config.sh
source lib/utils.sh
source lib/help.sh


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
