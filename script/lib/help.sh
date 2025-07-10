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
