#!/usr/bin/env bash
# shellcheck disable=SC2034

iso_name="hyggshi-os-arch"
iso_label="HYGGSHI_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="Hyggshi OS <https://github.com/Hyggshi-OS-Research-Technology/Hyggshi-OS/tree/main/scripts/Arch-folder>"
iso_application="Hyggshi OS Arch Live/Install DVD"
iso_version="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m.%d)"
install_dir="arch"
buildmodes=('iso')
bootmodes=('bios.syslinux'
           'uefi.grub')
arch="x86_64"
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'zstd' '-Xcompression-level' '19')
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/etc/sudoers.d/10-liveuser"]="0:0:440"
  ["/etc/pam.d/sddm-autologin"]="0:0:644"
  ["/root"]="0:0:750"
  ["/root/.automated_script.sh"]="0:0:755"
  ["/root/.gnupg"]="0:0:700"
  ["/usr/local/bin/choose-mirror"]="0:0:755"
  ["/usr/local/bin/Installation_guide"]="0:0:755"
  ["/usr/local/bin/livecd-sound"]="0:0:755"
  ["/usr/local/bin/hyggshi-live-setup"]="0:0:755"
  ["/usr/local/bin/hyggshi-rebrand"]="0:0:755"
  ["/usr/local/bin/hyggshi-secureboot"]="0:0:755"
  ["/usr/local/bin/hyggshi-icons"]="0:0:755"
  ["/usr/local/bin/hyggshi-post-install"]="0:0:755"
  ["/usr/local/bin/hyggshi-welcome"]="0:0:755"
  ["/usr/local/bin/hyggshi-hardware"]="0:0:755"
  ["/usr/local/share/hyggshi/install-hyggshi.desktop"]="0:0:755"
)
