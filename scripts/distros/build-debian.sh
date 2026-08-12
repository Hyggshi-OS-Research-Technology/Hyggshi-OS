#!/bin/bash
# build-debian.sh — bootstrap base rootfs cho Debian.
# Được `source` từ scripts/build.sh (không tự chạy độc lập) nên dùng chung
# shell/biến môi trường: DEBIAN_VERSION, GITHUB_ENV, DEBUG_MODE...
set -e
[ "$DEBUG_MODE" = "true" ] && set -x

BASE_CODENAME="$DEBIAN_VERSION"
MIRROR="http://deb.debian.org/debian/"
DISTRO_LABEL="Debian ${BASE_CODENAME}"

echo "Sẽ build trên: $DISTRO_LABEL"
# Ghi ra $GITHUB_ENV để các step/script sau (desktop.sh, branding.sh, iso.sh...) đọc được
{
  echo "BASE_CODENAME=$BASE_CODENAME"
  echo "MIRROR=$MIRROR"
  echo "DISTRO_LABEL=$DISTRO_LABEL"
} >> "$GITHUB_ENV"

echo "===== Debootstrap Debian ${BASE_CODENAME} ====="
sudo debootstrap --arch=amd64 --variant=minbase \
  "$BASE_CODENAME" live-build/chroot "$MIRROR"

echo "===== Mount virtual filesystems for chroot ====="
sudo mount --bind /dev live-build/chroot/dev
sudo mount --bind /run live-build/chroot/run
sudo chroot live-build/chroot mount -t proc none /proc
sudo chroot live-build/chroot mount -t sysfs none /sys

echo "===== Configure APT sources inside chroot ====="
# non-free-firmware chỉ tồn tại từ Debian 12 (bookworm) trở đi.
# bullseye (Debian 11) không có component này -> phải bỏ ra, nếu không
# apt update sẽ lỗi 404/"Invalid" component ngay từ đầu.
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
