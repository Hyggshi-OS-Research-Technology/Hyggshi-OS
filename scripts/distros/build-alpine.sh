#!/bin/bash
# build-alpine.sh — bootstrap base rootfs cho Alpine Linux.
# CHẠY BÊN TRONG CONTAINER `alpine:latest` (xem job build-alpine trong
# .github/workflows/Build-Hyggshi-OS-ISO.yml), KHÔNG chạy trên ubuntu-latest
# runner trần. Vì vậy script này dùng thẳng `apk` có sẵn của container —
# không cần tải apk-tools-static / giả lập apk như bản debootstrap-style cũ.
# Job chạy trong container nên tiến trình đã là root sẵn, không cần `sudo`.
#
# EXPERIMENTAL: chỉ dựng base rootfs. desktop.sh/branding.sh/iso.sh hiện tại
# viết cho apt-get/dpkg (Debian/Ubuntu/Mint) nên SẼ LỖI nếu chạy tiếp sau
# bước này — cần alpine-desktop.sh (apk add xfce4 lightdm ...) và
# alpine-iso.sh (Alpine dùng mkinitfs/initramfs riêng, không phải
# update-initramfs, và không có gói tương đương live-boot) riêng thì mới
# chạy hết pipeline được.
set -e
[ "$DEBUG_MODE" = "true" ] && set -x

BASE_CODENAME="${ALPINE_VERSION:-v3.20}"
DISTRO_LABEL="Alpine Linux ${BASE_CODENAME} (native container build — experimental, base rootfs only)"

echo "Sẽ build trên: $DISTRO_LABEL"
# Ghi ra $GITHUB_ENV để các step sau đọc được (dù desktop/branding/iso chưa
# hỗ trợ Alpine, giữ cùng convention với các distro khác)
{
  echo "BASE_CODENAME=$BASE_CODENAME"
  echo "DISTRO_LABEL=$DISTRO_LABEL"
} >> "$GITHUB_ENV"

echo "===== apk update (dùng repositories có sẵn của container) ====="
apk update

echo "===== Dựng base rootfs vào live-build/chroot bằng apk --root ====="
# --root: cài vào 1 thư mục con thay vì cài đè lên rootfs của chính
# container CI (tách biệt rõ ràng "máy build" và "rootfs sản phẩm").
# --initdb: khởi tạo database apk mới trong --root vì thư mục đó rỗng.
mkdir -p live-build/chroot
apk add --no-cache --root live-build/chroot --initdb alpine-base openrc

echo "===== Copy resolv.conf + apk repositories vào rootfs ====="
cp /etc/resolv.conf live-build/chroot/etc/resolv.conf
mkdir -p live-build/chroot/etc/apk
cp /etc/apk/repositories live-build/chroot/etc/apk/repositories

echo "===== apk bootstrap xong — CHƯA có desktop/branding/iso riêng cho Alpine ====="
echo "===== build-alpine.sh xong ====="
