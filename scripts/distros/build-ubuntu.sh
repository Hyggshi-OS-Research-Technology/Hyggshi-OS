#!/bin/bash
# build-ubuntu.sh — bootstrap base rootfs cho Ubuntu.
# Được `source` từ scripts/build.sh (không tự chạy độc lập) nên dùng chung
# shell/biến môi trường: UBUNTU_VERSION, GITHUB_ENV, DEBUG_MODE...
set -e
[ "$DEBUG_MODE" = "true" ] && set -x

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../arch.sh"
: "${ARCH:=amd64}"
hyggshi_validate_arch "$ARCH" || exit 1

if [ "$(hyggshi_needs_qemu_binfmt "$ARCH")" = "true" ] && \
   ! [ -e "/proc/sys/fs/binfmt_misc/qemu-aarch64" ]; then
  echo "CẢNH BÁO: build ARCH=$ARCH trên host $(uname -m) nhưng chưa thấy" >&2
  echo "binfmt_misc qemu-aarch64 đăng ký — debootstrap/chroot arm64 sẽ lỗi" >&2
  echo "'exec format error'. Workflow cần bước 'Set up QEMU' (docker/setup-qemu-action)" >&2
  echo "chạy TRƯỚC step này khi architecture=arm64." >&2
fi

BASE_CODENAME="$UBUNTU_VERSION"
MIRROR="$(hyggshi_ubuntu_mirror "$ARCH")"
SECURITY_MIRROR="$(hyggshi_ubuntu_security_mirror "$ARCH")"
DISTRO_LABEL="Ubuntu ${BASE_CODENAME} (${ARCH})"

echo "Sẽ build trên: $DISTRO_LABEL"
# Ghi ra $GITHUB_ENV để các step/script sau (desktop.sh, branding.sh, iso.sh...) đọc được
{
  echo "BASE_CODENAME=$BASE_CODENAME"
  echo "MIRROR=$MIRROR"
  echo "DISTRO_LABEL=$DISTRO_LABEL"
  echo "ARCH=$ARCH"
} >> "$GITHUB_ENV"

DEBOOTSTRAP_CACHE_DIR="/tmp/debootstrap-cache"
DEBOOTSTRAP_TARBALL="${DEBOOTSTRAP_CACHE_DIR}/debootstrap-ubuntu-${BASE_CODENAME}-${ARCH}.tar.zst"

if [ -f "$DEBOOTSTRAP_TARBALL" ]; then
  echo "===== Phục hồi base rootfs Ubuntu từ cache: $DEBOOTSTRAP_TARBALL ====="
  sudo mkdir -p live-build/chroot
  sudo tar --zstd -xf "$DEBOOTSTRAP_TARBALL" -C live-build/chroot
else
  echo "===== Debootstrap Ubuntu ${BASE_CODENAME} (arch=$ARCH) ====="
  sudo debootstrap --arch="$(hyggshi_debootstrap_arch "$ARCH")" --variant=minbase \
    "$BASE_CODENAME" live-build/chroot "$MIRROR"
  if [ -d "$DEBOOTSTRAP_CACHE_DIR" ]; then
    echo "===== Lưu base rootfs Ubuntu vào cache: $DEBOOTSTRAP_TARBALL ====="
    sudo tar --zstd -cf "$DEBOOTSTRAP_TARBALL" -C live-build/chroot .
  fi
fi

echo "===== Mount virtual filesystems for chroot ====="
sudo mount --bind /dev live-build/chroot/dev
sudo mount --bind /run live-build/chroot/run
sudo chroot live-build/chroot mount -t proc none /proc
sudo chroot live-build/chroot mount -t sysfs none /sys

echo "===== Configure APT sources inside chroot ====="
sudo tee live-build/chroot/etc/apt/sources.list > /dev/null <<EOF
deb ${MIRROR} ${BASE_CODENAME} main restricted universe multiverse
deb ${MIRROR} ${BASE_CODENAME}-updates main restricted universe multiverse
deb ${SECURITY_MIRROR} ${BASE_CODENAME}-security main restricted universe multiverse
EOF
sudo cp /etc/resolv.conf live-build/chroot/etc/resolv.conf

echo "===== build-ubuntu.sh xong ====="
