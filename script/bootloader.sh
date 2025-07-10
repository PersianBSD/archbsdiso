#!/bin/bash
# bootloader.sh - Install and configure FreeBSD bootloader for ArchBSD ISO
set -euo pipefail

# بارگذاری متغیرها و توابع کمکی
source lib/config.sh
source lib/utils.sh
source lib/help.sh


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

