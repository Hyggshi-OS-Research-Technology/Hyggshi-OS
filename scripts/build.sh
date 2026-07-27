#!/bin/bash
# build.sh — chuẩn bị host + dispatch sang script bootstrap riêng của từng distro.
# Chạy trên HOST (runner), không chạy trong chroot.
#
# Phần bootstrap/apt-sources riêng cho từng distro giờ nằm ở
# scripts/distros/build-<distro>.sh (debian / ubuntu / linuxmint / alpine),
# file này chỉ còn lo phần dùng chung (cài dependency trên host, dọn ổ đĩa)
# rồi source đúng script của $BASE_DISTRO.
set -e
[ "$DEBUG_MODE" = "true" ] && set -x

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
DISTRO_SCRIPT="$SCRIPT_DIR/distros/build-${BASE_DISTRO}.sh"

if [ ! -f "$DISTRO_SCRIPT" ]; then
  echo "Distro không hợp lệ: $BASE_DISTRO (không tìm thấy $DISTRO_SCRIPT)"
  echo "Các distro hỗ trợ: debian, ubuntu, linuxmint, alpine"
  exit 1
fi

echo "===== Bootstrap rootfs riêng cho: $BASE_DISTRO ====="
# shellcheck source=/dev/null
source "$DISTRO_SCRIPT"

echo "===== build.sh xong ====="
