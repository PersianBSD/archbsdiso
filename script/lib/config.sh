#!/bin/bash
# فایل config.sh - تنظیمات پایه برای ArchBSD

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
