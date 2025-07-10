ArchBSD-ISO Builder

ArchBSD-ISO Builder is a toolset for creating live installation media and bootstrap images for the ArchBSD operating system — a BSD-based distribution inspired by Arch Linux.

---

Introduction

This tool automates the process of building bootable ISO images and bootstrap tarballs for ArchBSD, supporting BIOS and UEFI boot modes. It is designed to be modular and extensible for customization and supports multiple desktop environments.

---

Features

- Build ArchBSD installation ISOs from package lists  
- Support for desktop environments such as MATE and XFCE  
- Hybrid ISO images for both DVD and USB installation media  
- Support for UEFI and BIOS boot modes  
- GPG and CMS signing of images for security and integrity  
- Modular scripts for flexible customization  

---

Requirements

To build ArchBSD ISO images, the following tools and packages are required on the build host:

- FreeBSD base system utilities (newfs, makefs, boot0cfg, etc.)  
- pkg (FreeBSD package manager)  
- OpenSSL  
- bsdtar (libarchive tools)  
- gzip, bzip2, xz, zstd (compression tools)  
- find, awk, sed, grep (standard Unix tools)  
- mkfile (for creating disk images)  
- zfs utilities (optional, if building ZFS rootfs)  
- Linux compatibility layer with linux64 kernel module loaded (for some build dependencies)  
- Additional packages: git, rsync, transmission-utils (for downloading sources and packages)  

---

Supported Platforms

- The build environment is based on FreeBSD 12.x or newer (including ArchBSD itself)  
- The generated images support amd64 architecture  
- Tested on VirtualBox, VMware, and physical hardware  

---

Setup

1. Ensure the required tools are installed (see Requirements above).  
2. Load the Linux compatibility module on FreeBSD:  
   kldload linux64  
   sysrc -f /etc/rc.conf kld_list="linux64"  
3. Clone the ArchBSD repository:  
   git clone https://github.com/PersianBSD/ArchBSD.git  
   cd ArchBSD  
4. Install additional tools via pkg as needed:  
   pkg install git transmission-utils rsync  

---

Usage

Run the build script with desired options:

- Build ArchBSD ISO with MATE desktop (unstable branch):  
  ./build.sh -d mate -b unstable  

- Build ArchBSD ISO with MATE desktop (release branch):  
  ./build.sh -d mate -b release  

- Build ArchBSD ISO with XFCE desktop (unstable branch):  
  ./build.sh -d xfce -b unstable  

---

Profiles

Build profiles define package sets, build modes, and customizations. Profiles are located in the profiles/ directory.

Each profile contains:  
- profiledef.sh — core profile settings  
- packages.* — package lists per architecture  
- bootstrap_packages.* — bootstrap package lists (optional)  
- Custom root filesystem overlays  

You can create custom profiles by copying and modifying existing ones.

---

Building Process Overview

1. Reading profile and configuration options  
2. Setting overrides and defaults  
3. Validating environment and dependencies  
4. Preparing root filesystem (base system + packages)  
5. Applying customizations and overlays  
6. Creating airootfs images (squashfs, ufs, or zfs)  
7. Building ISO images with EFI and BIOS boot support  
8. Signing images with GPG and CMS (optional)  
9. Cleaning up temporary build directories  

---

Testing Images

You can test your built ISO in QEMU with BIOS or UEFI boot:

- BIOS boot:  
  qemu-system-x86_64 -cdrom path/to/archbsd.iso -m 2G  

- UEFI boot (with OVMF firmware):  
  qemu-system-x86_64 -drive file=path/to/archbsd.iso,format=raw,media=cdrom -m 2G -bios /usr/local/share/ovmf/OVMF_CODE.fd  

---

Contribution

We welcome contributions! Before contributing:  
- Review the Code of Conduct  
- Follow the Contribution Guidelines  

You can report issues, propose features, or submit pull requests on our GitHub repository.

---

License

ArchBSD-ISO Builder is released under the BSD 2-Clause License. See LICENSE file for details.

---

Authors and Maintainers

- Project Lead: PersianBSD Team  
- Contributors: See AUTHORS file  

---

Acknowledgments

Inspired by Arch Linux's archiso project, FreeBSD, and various open-source communities.
