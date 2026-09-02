#!/bin/bash
# arch.sh — helper tập trung cho kiến trúc CPU (amd64 | arm64), dùng chung
# cho build-debian.sh (chạy trên HOST runner, trước khi debootstrap) và
# desktop.sh (chạy BÊN TRONG chroot). Được `source`, KHÔNG tự chạy độc lập
# — giống hệt cách kernel-tuning.sh (profile Edition) đã làm.
#
# ARCH hợp lệ: amd64 | arm64 (mặc định amd64 nếu không set — xem
# `: "${ARCH:=amd64}"` ở build-debian.sh/desktop.sh).
#
# GIỚI HạN HIệN TạI (thành thật — xem thêm comment [Architecture] trong
# iso-config/config/config.ini):
#   - Chỉ Debian job (build-debian.sh + desktop.sh) đọc $ARCH. Ubuntu/Mint
#     (build-ubuntu.sh/build-linuxmint.sh) và job container Arch/Fedora/
#     Alpine chưa dùng file này, vẫn hardcode amd64.
#   - iso.sh (UEFI Secure Boot signing) chỉ xử lý amd64 — arm64 build vẫn
#     ra ISO boot được (grub-mkrescue fallback, giống hành vi trước khi có
#     patch secure boot) nhưng KHÔNG có chain-of-trust đã ký.

hyggshi_validate_arch() {
  case "${1:-amd64}" in
    amd64|arm64) return 0 ;;
    *)
      echo "ARCH không hợp lệ: '$1' (chỉ hỗ trợ amd64 hoặc arm64)." >&2
      return 1
      ;;
  esac
}

# Cờ --arch cho debootstrap.
hyggshi_debootstrap_arch() {
  local arch="${1:-amd64}"
  case "$arch" in
    arm64) echo "arm64" ;;
    *)     echo "amd64" ;;
  esac
}

# Meta-package kernel Debian theo kiến trúc (Debian không có gói
# "linux-image-generic" như Ubuntu — phải chọn đúng tên theo arch).
hyggshi_kernel_package() {
  local arch="${1:-amd64}"
  case "$arch" in
    arm64) echo "linux-image-arm64" ;;
    *)     echo "linux-image-amd64" ;;
  esac
}

# Gói GRUB EFI theo kiến trúc.
hyggshi_grub_efi_package() {
  local arch="${1:-amd64}"
  case "$arch" in
    arm64) echo "grub-efi-arm64-bin" ;;
    *)     echo "grub-efi-amd64-bin" ;;
  esac
}

# arm64 KHÔNG có BIOS/legacy boot (không có grub-pc/grub-pc-bin cho arch
# này) — chỉ amd64 mới cần cài 2 gói đó. desktop.sh dùng hàm này để build
# đúng danh sách gói GRUB cần cài thay vì hardcode list amd64-only, tránh
# lặp lại đúng loại bug "cài gói không tồn tại trên arch này -> apt-get
# không có candidate -> build fail cứng" (xem GRUB_INSTALL_FAILED trong
# desktop.sh).
hyggshi_grub_packages() {
  local arch="${1:-amd64}"
  local efi_pkg
  efi_pkg=$(hyggshi_grub_efi_package "$arch")
  case "$arch" in
    arm64) printf '%s\n' "$efi_pkg" grub-common efibootmgr parted dosfstools ;;
    *)     printf '%s\n' grub-pc grub-pc-bin "$efi_pkg" grub-common efibootmgr parted dosfstools ;;
  esac
}

# true nếu build đang cross-arch trên runner (vd runner amd64 build arm64)
# -> cần QEMU user-mode binfmt đã đăng ký (docker/setup-qemu-action trong
# workflow) để debootstrap + chroot chạy được binary arm64 trên host amd64.
hyggshi_needs_qemu_binfmt() {
  local arch="${1:-amd64}"
  local host_arch
  host_arch=$(uname -m)
  case "$arch:$host_arch" in
    arm64:x86_64|arm64:amd64) echo "true" ;;
    *)                        echo "false" ;;
  esac
}
