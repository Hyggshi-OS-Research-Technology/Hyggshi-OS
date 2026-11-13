#!/bin/bash
# build.sh — chuẩn bị host + dispatch sang script bootstrap riêng của từng distro.
# Chạy trên HOST (runner), không chạy trong chroot.
#
# Phần bootstrap/apt-sources riêng cho từng distro nằm cạnh các script build;
# Linux Mint dùng builder riêng trong scripts/Mint-folder.
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
# Các gói GRUB phụ thuộc kiến trúc: amd64 cần grub-pc-bin + grub-efi-amd64-bin,
# arm64 cần grub-efi-arm64-bin (không có grub-pc-bin vì BIOS/MBR không dùng trên ARM).
_HOST_ARCH="$(dpkg --print-architecture)"
_GRUB_ARCH_PKGS="grub-common"
if [ "$_HOST_ARCH" = "amd64" ] || [ "${ARCH:-amd64}" != "arm64" ]; then
  _GRUB_ARCH_PKGS="$_GRUB_ARCH_PKGS grub-pc-bin grub-efi-amd64-bin"
fi
if [ "$_HOST_ARCH" = "arm64" ] || [ "${ARCH:-}" = "arm64" ]; then
  _GRUB_ARCH_PKGS="$_GRUB_ARCH_PKGS grub-efi-arm64-bin"
fi
sudo apt-get install -y \
  debootstrap squashfs-tools xorriso isolinux syslinux-efi \
  $_GRUB_ARCH_PKGS mtools dosfstools \
  initramfs-tools live-boot live-boot-doc sbsigntool binutils

CHROOT_DIR="live-build/chroot"
DE_MARKER="$CHROOT_DIR/.hyggshi-last-de"

# BUG: build.sh chỉ mkdir -p chroot, KHÔNG BAO GIỜ xoá chroot cũ. Nếu build
# trước đó dùng DE=kde (hoặc bất kỳ DE nào khác) và lần này đổi sang
# DE=lxqt, toàn bộ package/xsession/sddm-config của DE cũ vẫn còn nguyên
# trong chroot — desktop.sh chỉ CỘNG THÊM lxqt vào, phần purge KDE trong
# nhánh lxqt của desktop.sh có thể fail âm thầm (|| true) nếu còn gói khác
# phụ thuộc — kết quả: SDDM hiện cả 2 session "Plasma" và "LXQt" dù chỉ
# chọn LXQt. Fix: lưu DE của lần build trước vào 1 marker file trong
# chroot; nếu DE lần này khác, xoá sạch chroot để build lại từ đầu cho
# đúng 1 DE. Build lại cùng 1 DE (không đổi) thì giữ nguyên chroot cũ như
# trước (không mất tốc độ cache debootstrap).
if [ -d "$CHROOT_DIR" ] && [ -f "$DE_MARKER" ] && [ "$(cat "$DE_MARKER" 2>/dev/null)" != "$DE" ]; then
  echo "===== DE đổi từ '$(cat "$DE_MARKER" 2>/dev/null)' sang '$DE' — xoá chroot cũ để tránh cài chồng 2 desktop environment =====" >&2
  sudo rm -rf "$CHROOT_DIR"
fi

mkdir -p "$CHROOT_DIR"
echo "$DE" | sudo tee "$DE_MARKER" >/dev/null

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ "$BASE_DISTRO" = "linuxmint" ]; then
  MINT_FOLDER="${HCL_MINT_FOLDER:-scripts/Mint-folder}"
  MINT_BOOTSTRAP="${HCL_MINT_BOOTSTRAP:-scripts/Mint-folder/scripts/base/bootstrap-linuxmint.sh}"
  DISTRO_SCRIPT="$MINT_BOOTSTRAP"
  export MINT_FOLDER
  echo "MINT_FOLDER=$MINT_FOLDER" >> "$GITHUB_ENV"
else
  DISTRO_SCRIPT="$SCRIPT_DIR/distros/build-${BASE_DISTRO}.sh"
fi

if [[ "$DISTRO_SCRIPT" != /* ]]; then
  DISTRO_SCRIPT="$PWD/${DISTRO_SCRIPT#./}"
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
