#!/bin/bash
# build.sh — chuẩn bị host + dispatch sang script bootstrap riêng của từng distro.
# Chạy trên HOST (runner), không chạy trong chroot.
#
# Phần bootstrap/apt-sources riêng cho từng distro giờ nằm ở
# scripts/distros/build-<distro>.sh (debian / ubuntu / linuxmint / alpine /
# arch), file này chỉ còn lo phần dùng chung (cài dependency trên host, dọn
# ổ đĩa) rồi source đúng script của $BASE_DISTRO.
set -e
[ "$DEBUG_MODE" = "true" ] && set -x

# GitHub Actions provides GITHUB_ENV automatically. Keep the same contract
# for local/Docker builds so distro scripts can persist resolved variables.
: "${GITHUB_ENV:=live-build/build.env}"
export GITHUB_ENV
mkdir -p "$(dirname "$GITHUB_ENV")"
: > "$GITHUB_ENV"

echo "===== Free up disk space ====="
sudo rm -rf /usr/share/dotnet /usr/local/lib/android /opt/ghc /opt/hostedtoolcache
sudo apt-get clean
df -h

echo "===== Install host build dependencies ====="
sudo apt-get update
sudo apt-get install -y \
  debootstrap squashfs-tools xorriso isolinux syslinux-efi \
  grub-pc-bin grub-efi-amd64-bin grub-common mtools dosfstools \
  live-boot live-boot-doc

mkdir -p live-build/chroot

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# LƯU Ý: file của arch tên là build-arch-iso.sh (không phải build-arch.sh
# như quy ước debian/ubuntu/linuxmint/alpine/fedora), vì nó dùng mkarchiso
# thay vì pacstrap+chroot tay. Map riêng ở đây để build.sh/local-build.sh
# không báo nhầm "Distro không hợp lệ" khi BASE_DISTRO=arch.
if [ "$BASE_DISTRO" = "arch" ]; then
  DISTRO_SCRIPT="$SCRIPT_DIR/distros/build-arch-iso.sh"
else
  DISTRO_SCRIPT="$SCRIPT_DIR/distros/build-${BASE_DISTRO}.sh"
fi

if [ ! -f "$DISTRO_SCRIPT" ]; then
  echo "Distro không hợp lệ: $BASE_DISTRO (không tìm thấy $DISTRO_SCRIPT)"
  echo "Các distro hỗ trợ: debian, ubuntu, linuxmint, alpine, arch"
  exit 1
fi

echo "===== Bootstrap rootfs riêng cho: $BASE_DISTRO ====="
# shellcheck source=/dev/null
source "$DISTRO_SCRIPT"

echo "===== build.sh xong ====="
