#!/bin/bash
set -e
[ "$DEBUG_MODE" = "true" ] && set -x

BASE_CODENAME="${DEBIAN_VERSION:-trixie}"
MIRROR="http://deb.debian.org/debian/"
DISTRO_LABEL="Debian ${BASE_CODENAME}"

{
  echo "BASE_CODENAME=$BASE_CODENAME"
  echo "MIRROR=$MIRROR"
  echo "DISTRO_LABEL=$DISTRO_LABEL"
} >> "$GITHUB_ENV"

echo "===== Debootstrap $DISTRO_LABEL ====="
sudo debootstrap --arch=amd64 --variant=minbase \
  "$BASE_CODENAME" live-build/chroot "$MIRROR"

echo "===== Mount virtual filesystems ====="
sudo mount --bind /dev live-build/chroot/dev
sudo mount --bind /run live-build/chroot/run
sudo chroot live-build/chroot mount -t proc none /proc
sudo chroot live-build/chroot mount -t sysfs none /sys

echo "===== Configure APT sources ====="
if [ "$BASE_CODENAME" = "bullseye" ]; then
  FIRMWARE_COMPONENT=""
else
  FIRMWARE_COMPONENT="non-free-firmware"
fi
sudo tee live-build/chroot/etc/apt/sources.list > /dev/null <<EOF
deb http://deb.debian.org/debian ${BASE_CODENAME} main contrib non-free ${FIRMWARE_COMPONENT}
deb http://deb.debian.org/debian ${BASE_CODENAME}-updates main contrib non-free ${FIRMWARE_COMPONENT}
deb http://security.debian.org/debian-security ${BASE_CODENAME}-security main contrib non-free ${FIRMWARE_COMPONENT}
EOF
sudo cp /etc/resolv.conf live-build/chroot/etc/resolv.conf
echo "===== build-debian.sh xong ====="
