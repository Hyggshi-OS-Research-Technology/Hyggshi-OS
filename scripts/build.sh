#!/bin/bash
set -e
[ "$DEBUG_MODE" = "true" ] && set -x

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
DISTRO_SCRIPT="$SCRIPT_DIR/build-${BASE_DISTRO}.sh"

if [ ! -f "$DISTRO_SCRIPT" ]; then
  echo "Distro không hợp lệ: $BASE_DISTRO (không tìm thấy $DISTRO_SCRIPT)"
  exit 1
fi

echo "===== Bootstrap rootfs: $BASE_DISTRO ====="
source "$DISTRO_SCRIPT"
echo "===== build.sh xong ====="
