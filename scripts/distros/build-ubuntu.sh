#!/bin/bash
# build-ubuntu.sh — bootstrap base rootfs cho Ubuntu.
# Được `source` từ scripts/build.sh (không tự chạy độc lập) nên dùng chung
# shell/biến môi trường: UBUNTU_VERSION, GITHUB_ENV, DEBUG_MODE...
set -e
[ "$DEBUG_MODE" = "true" ] && set -x

BASE_CODENAME="$UBUNTU_VERSION"
MIRROR="http://archive.ubuntu.com/ubuntu/"
DISTRO_LABEL="Ubuntu ${BASE_CODENAME}"

echo "Sẽ build trên: $DISTRO_LABEL"
# Ghi ra $GITHUB_ENV để các step/script sau (desktop.sh, branding.sh, iso.sh...) đọc được
{
  echo "BASE_CODENAME=$BASE_CODENAME"
  echo "MIRROR=$MIRROR"
  echo "DISTRO_LABEL=$DISTRO_LABEL"
} >> "$GITHUB_ENV"

echo "===== Debootstrap Ubuntu ${BASE_CODENAME} ====="
sudo debootstrap --arch=amd64 --variant=minbase \
  "$BASE_CODENAME" live-build/chroot "$MIRROR"

echo "===== Mount virtual filesystems for chroot ====="
sudo mount --bind /dev live-build/chroot/dev
sudo mount --bind /run live-build/chroot/run
sudo chroot live-build/chroot mount -t proc none /proc
sudo chroot live-build/chroot mount -t sysfs none /sys

echo "===== Configure APT sources inside chroot ====="
sudo tee live-build/chroot/etc/apt/sources.list > /dev/null <<EOF
deb http://archive.ubuntu.com/ubuntu ${BASE_CODENAME} main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu ${BASE_CODENAME}-updates main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu ${BASE_CODENAME}-security main restricted universe multiverse
EOF
sudo cp /etc/resolv.conf live-build/chroot/etc/resolv.conf

echo "===== build-ubuntu.sh xong ====="
