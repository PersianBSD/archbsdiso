=========
buildiso
=========

------------------------
ArchBSD ISO generator
------------------------

:Version: buildiso |version|
:Manual section: 1

Synopsis
========

**buildiso** [options] *profile_directory*

Description
===========

**mkbuildiso** creates an ISO, artifacts and a bootstrap tarball and optionally signs them.

Options
=======

-A application          | Set an application name for the ISO.
                        | Default: |iso_application|.
-C file                 | pacman configuration file.
                        | Default: |pacman_conf|.
-D install_dir          | Set an install_dir. All files will be located here.
                        | Default: |install_dir|.
                        | NOTE: Max 8 characters, use only *a-z0-9*.
-L label                | Set the ISO volume label.
                        | Default: |iso_label|.
-P publisher            | Set the ISO publisher.
                        | Default: |iso_publisher|.
-c cert_and_key         | Provide certificates for codesigning of netboot artifacts as well as the rootfs artifact.
                        | Multiple files are provided as quoted, space delimited list.
                        | The first file is considered as the signing certificate, the second as the key and the third as the optional certificate authority.
-g gpg_key              | Set the PGP key ID to be used for signing the rootfs image. Passed to gpg as the value for **--default-key**.
-G mbox                 | Set the PGP signer (must include an email address). Passed to gpg as the value for **--sender**.
-h                      | Help message.
-m mode                 | Build mode(s) to use (valid modes are: *bootstrap*, *iso* and *netboot*). Multiple build modes are provided as quoted, space delimited list.
-o out_dir              | Set the output directory.
                        | Default: |out_dir|.
-p packages             | Package(s) to install.
                        | Multiple packages are provided as quoted, space delimited list.
-r                      | Delete the working directory at the end.
-v                      | Enable verbose output.
-w work_dir             | Set the working directory.
                        | Default: |work_dir|.

Examples
========

Build the releng profile
------------------------

   buildiso |profile_dir|/configs/base

Bugs
====

https://github.com/PersianBSD/archbsdiso.git

Authors
=======

archbsdiso is maintained by the ArchBSD team Refer to the *AUTHORS* file for a full list of contributors.

Copyright
=========

Copyright 🄯 archbsdiso contributors. 