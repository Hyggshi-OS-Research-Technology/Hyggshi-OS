#!/bin/bash
# build-alpine.sh — bootstrap base rootfs cho Alpine Linux (apk + musl).
# Được `source` từ scripts/build.sh (không tự chạy độc lập) nên dùng chung
# shell/biến môi trường: ALPINE_VERSION, GITHUB_ENV, DEBUG_MODE...
#
# EXPERIMENTAL: Alpine dùng apk + musl, KHÔNG dùng debootstrap/apt/dpkg.
# Nhánh này chỉ build base rootfs bằng apk-tools-static. desktop.sh/
# branding.sh/iso.sh hiện tại gọi apt-get/dpkg/calamares/live-boot thẳng nên
# SẼ LỖI ở các bước sau nếu chạy nguyên pipeline với distro=alpine — cần viết
# một bản alpine-desktop.sh (apk add xfce4 lightdm ...) và alpine-iso.sh
# (Alpine dùng mkinitfs/initramfs riêng, tên kernel/initrd khác
# linux-image-*/initrd.img-*) riêng thì mới chạy hết pipeline được. Coi đây
# là experimental/base-rootfs-only cho tới khi có 2 script đó.
set -e
[ "$DEBUG_MODE" = "true" ] && set -x

BASE_CODENAME="${ALPINE_VERSION:-v3.20}"
MIRROR="https://dl-cdn.alpinelinux.org/alpine"
DISTRO_LABEL="Alpine Linux ${BASE_CODENAME} (experimental — base rootfs only)"

echo "Sẽ build trên: $DISTRO_LABEL"
# Ghi ra $GITHUB_ENV để các step/script sau đọc được (dù desktop/branding/iso
# chưa hỗ trợ alpine, giữ cùng convention với các distro khác)
{
  echo "BASE_CODENAME=$BASE_CODENAME"
  echo "MIRROR=$MIRROR"
  echo "DISTRO_LABEL=$DISTRO_LABEL"
} >> "$GITHUB_ENV"

echo "===== Bootstrap Alpine bằng apk-tools-static (không có debootstrap cho Alpine) ====="
APK_STATIC_PKG=$(curl -fsSL "$MIRROR/${BASE_CODENAME}/main/x86_64/" \
  | grep -o 'apk-tools-static-[0-9][^"]*\.apk' | sort -V | tail -n1)
if [ -z "$APK_STATIC_PKG" ]; then
  echo "Không tìm được gói apk-tools-static trên $MIRROR/${BASE_CODENAME}/main/x86_64/"
  exit 1
fi
curl -fsSL "$MIRROR/${BASE_CODENAME}/main/x86_64/$APK_STATIC_PKG" -o /tmp/apk-tools-static.apk
mkdir -p /tmp/apk-static-extract
tar -xzf /tmp/apk-tools-static.apk -C /tmp/apk-static-extract
sudo /tmp/apk-static-extract/sbin/apk.static \
  -X "$MIRROR/${BASE_CODENAME}/main" -X "$MIRROR/${BASE_CODENAME}/community" \
  -U --allow-untrusted --arch x86_64 \
  --root live-build/chroot --initdb add alpine-base openrc

sudo mkdir -p live-build/chroot/etc/apk
cat <<EOF | sudo tee live-build/chroot/etc/apk/repositories > /dev/null
$MIRROR/${BASE_CODENAME}/main
$MIRROR/${BASE_CODENAME}/community
EOF

echo "===== apk bootstrap xong — CHƯA có desktop/branding/iso riêng cho Alpine ====="
echo "===== build-alpine.sh xong ====="
