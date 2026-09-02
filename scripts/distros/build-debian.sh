#!/bin/bash
# build-debian.sh — bootstrap base rootfs cho Debian.
# Được `source` từ scripts/build.sh (không tự chạy độc lập) nên dùng chung
# shell/biến môi trường: DEBIAN_VERSION, GITHUB_ENV, DEBUG_MODE...
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

BASE_CODENAME="$DEBIAN_VERSION"
MIRROR="http://deb.debian.org/debian/"
case "$BASE_CODENAME" in
  testing)  DISTRO_LABEL="Debian Testing" ;;
  unstable|sid) DISTRO_LABEL="Debian Unstable (Sid)" ;;
  *)        DISTRO_LABEL="Debian ${BASE_CODENAME}" ;;
esac

echo "Sẽ build trên: $DISTRO_LABEL"
# Ghi ra $GITHUB_ENV để các step/script sau (desktop.sh, branding.sh, iso.sh...) đọc được
{
  echo "BASE_CODENAME=$BASE_CODENAME"
  echo "MIRROR=$MIRROR"
  echo "DISTRO_LABEL=$DISTRO_LABEL"
  echo "ARCH=$ARCH"
} >> "$GITHUB_ENV"

echo "===== Debootstrap Debian ${BASE_CODENAME} (arch=$ARCH) ====="
sudo debootstrap --arch="$(hyggshi_debootstrap_arch "$ARCH")" --variant=minbase \
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

# BUG tương thích (chỉ lộ ra khi build debian_version=testing/unstable):
# 2 dòng "${BASE_CODENAME}-updates" và "${BASE_CODENAME}-security" CHỈ tồn
# tại cho Stable/Oldstable (cơ chế point-release + kho security riêng của
# Debian). Debian Testing/Unstable KHÔNG có suite "-security" hay
# "-updates" riêng — từ 2019 bản vá bảo mật đi thẳng vào testing qua
# unstable, không qua repo riêng. Với BASE_CODENAME=testing (hoặc sid/
# unstable), 2 dòng đó luôn 404 ngay ở apt update ĐẦU TIÊN trong
# desktop.sh, làm build fail hoàn toàn trước khi cài được gói nào —
# đây chính là lỗi tương thích khi build các bản khác trixie/bookworm/
# bullseye. Chỉ ghi suite chính cho testing/unstable/sid.
case "$BASE_CODENAME" in
  testing|unstable|sid)
    sudo tee live-build/chroot/etc/apt/sources.list > /dev/null <<EOF
deb http://deb.debian.org/debian ${BASE_CODENAME} main contrib non-free ${FIRMWARE_COMPONENT}
EOF
    ;;
  *)
    sudo tee live-build/chroot/etc/apt/sources.list > /dev/null <<EOF
deb http://deb.debian.org/debian ${BASE_CODENAME} main contrib non-free ${FIRMWARE_COMPONENT}
deb http://deb.debian.org/debian ${BASE_CODENAME}-updates main contrib non-free ${FIRMWARE_COMPONENT}
deb http://security.debian.org/debian-security ${BASE_CODENAME}-security main contrib non-free ${FIRMWARE_COMPONENT}
EOF
    ;;
esac
sudo cp /etc/resolv.conf live-build/chroot/etc/resolv.conf

echo "===== build-debian.sh xong ====="
