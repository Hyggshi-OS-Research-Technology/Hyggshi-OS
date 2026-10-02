#!/bin/sh
set -eu

# ==============================================================================
# hyggshi-secureboot-postinstall.sh — Thiết lập UEFI Secure Boot sau khi cài đặt
# ==============================================================================
# Script này chạy BÊN TRONG chroot target sau khi Calamares thực hiện bước bootloader.
#
# NGUYÊN NHÂN LỖI TRÊN DELL / LENOVO / HP:
# "Operating System Loader has no signature. Incompatible with SecureBoot. All bootable devices failed Secure Boot"
#
# Khi Calamares cài GRUB, mặc định nếu installEFIFallback=true nó sẽ copy file
# `grubx64.efi` vào `/boot/efi/EFI/BOOT/BOOTX64.EFI`.
# `grubx64.efi` KHÔNG có chữ ký từ Microsoft UEFI CA (chỉ có chữ ký Debian/Canonical
# hoặc không có chữ ký nếu do grub-install tự build).
# Khi BIOS/UEFI của Dell Vostro 3400 khởi động, nó kiểm tra chữ ký của BOOTX64.EFI
# đối chiếu với cơ sở dữ liệu `db` của bo mạch chủ (chỉ có Microsoft CA). Vì không
# có chữ ký Microsoft, BIOS lập tức ngắt quá trình boot và báo lỗi trên!
#
# GIẢI PHÁP:
# Đảm bảo /boot/efi/EFI/BOOT/BOOTX64.EFI LUÔN LUÔN LÀ SHIM (Microsoft-signed),
# đi kèm grubx64.efi đã ký và MokManager mmx64.efi.
# Đảm bảo NVRAM entry trỏ đúng vào shimx64.efi thay vì grubx64.efi.
# ==============================================================================

echo "===== [Hyggshi Secure Boot] Bắt đầu chuẩn hoá bootloader trên hệ thống mới ====="

# Kiểm tra xem hệ thống có phân vùng EFI hay không
if [ ! -d /boot/efi/EFI ]; then
  echo "Hệ thống cài đặt ở chế độ BIOS Legacy (không có /boot/efi/EFI). Bỏ qua Secure Boot setup."
  exit 0
fi

ARCH="amd64"
UNAME_M=$(uname -m 2>/dev/null || echo "x86_64")
if [ "$UNAME_M" = "aarch64" ] || [ "$UNAME_M" = "arm64" ]; then
  ARCH="arm64"
fi

if [ "$ARCH" = "arm64" ]; then
  SHIM_NAME="BOOTAA64.EFI"
  SHIM_DISTRO_NAME="shimaa64.efi"
  GRUB_NAME="grubaa64.efi"
  MM_NAME="mmaa64.efi"
else
  SHIM_NAME="BOOTX64.EFI"
  SHIM_DISTRO_NAME="shimx64.efi"
  GRUB_NAME="grubx64.efi"
  MM_NAME="mmx64.efi"
fi

SHIM_SRC=""
GRUB_SRC=""
MM_SRC=""

# 1. Tìm shim đã được Microsoft ký
for candidate in \
  /usr/lib/shim/shimx64.efi.signed \
  /usr/lib/shim/shimaa64.efi.signed \
  /usr/lib/shim/shimx64.efi \
  /usr/lib/shim/shimaa64.efi \
  /boot/efi/EFI/debian/shimx64.efi \
  /boot/efi/EFI/ubuntu/shimx64.efi \
  /boot/efi/EFI/hyggshi/shimx64.efi; do
  if [ -f "$candidate" ]; then
    SHIM_SRC="$candidate"
    break
  fi
done

# 2. Tìm GRUB signed
for candidate in \
  /usr/lib/grub/x86_64-efi-signed/gcdx64.efi.signed \
  /usr/lib/grub/x86_64-efi-signed/grubx64.efi.signed \
  /usr/lib/grub/arm64-efi-signed/gcdaa64.efi.signed \
  /usr/lib/grub/arm64-efi-signed/grubaa64.efi.signed \
  /boot/efi/EFI/debian/grubx64.efi \
  /boot/efi/EFI/ubuntu/grubx64.efi \
  /boot/efi/EFI/hyggshi/grubx64.efi; do
  if [ -f "$candidate" ]; then
    GRUB_SRC="$candidate"
    break
  fi
done

# 3. Tìm MokManager
for candidate in \
  /usr/lib/shim/mmx64.efi.signed \
  /usr/lib/shim/mmaa64.efi.signed \
  /usr/lib/shim/mmx64.efi \
  /usr/lib/shim/mmaa64.efi \
  /boot/efi/EFI/debian/mmx64.efi \
  /boot/efi/EFI/ubuntu/mmx64.efi; do
  if [ -f "$candidate" ]; then
    MM_SRC="$candidate"
    break
  fi
done

if [ -z "$SHIM_SRC" ]; then
  echo "CẢNH BÁO: Không tìm thấy shim EFI trong hệ thống. Cố gắng cài shim-signed..."
  apt-get update -qq || true
  apt-get install -y --no-install-recommends shim-signed grub-efi-amd64-signed || true
  for candidate in /usr/lib/shim/shimx64.efi.signed /usr/lib/shim/shimx64.efi; do
    [ -f "$candidate" ] && SHIM_SRC="$candidate" && break
  done
fi

if [ -n "$SHIM_SRC" ]; then
  echo "Tìm thấy SHIM: $SHIM_SRC"
  mkdir -p /boot/efi/EFI/BOOT
  mkdir -p /boot/efi/EFI/hyggshi
  mkdir -p /boot/efi/EFI/debian

  # Ghi đè BOOTX64.EFI bằng SHIM đã ký bởi Microsoft
  cp -f "$SHIM_SRC" "/boot/efi/EFI/BOOT/$SHIM_NAME"
  cp -f "$SHIM_SRC" "/boot/efi/EFI/hyggshi/$SHIM_DISTRO_NAME"
  cp -f "$SHIM_SRC" "/boot/efi/EFI/debian/$SHIM_DISTRO_NAME" 2>/dev/null || true

  if [ -n "$GRUB_SRC" ]; then
    echo "Tìm thấy GRUB: $GRUB_SRC"
    cp -f "$GRUB_SRC" "/boot/efi/EFI/BOOT/$GRUB_NAME"
    cp -f "$GRUB_SRC" "/boot/efi/EFI/hyggshi/$GRUB_NAME"
    cp -f "$GRUB_SRC" "/boot/efi/EFI/debian/$GRUB_NAME" 2>/dev/null || true
  fi

  if [ -n "$MM_SRC" ]; then
    echo "Tìm thấy MokManager: $MM_SRC"
    cp -f "$MM_SRC" "/boot/efi/EFI/BOOT/$MM_NAME"
    cp -f "$MM_SRC" "/boot/efi/EFI/hyggshi/$MM_NAME"
    cp -f "$MM_SRC" "/boot/efi/EFI/debian/$MM_NAME" 2>/dev/null || true
  fi

  # Cấu hình redirect grub.cfg
  cat <<'EOF' > /boot/efi/EFI/BOOT/grub.cfg
search --file --no-floppy --set=hyggshi_root /boot/grub/grub.cfg
set prefix=($hyggshi_root)/boot/grub
configfile ($hyggshi_root)/boot/grub/grub.cfg
EOF
  cp -f /boot/efi/EFI/BOOT/grub.cfg /boot/efi/EFI/hyggshi/grub.cfg
  cp -f /boot/efi/EFI/BOOT/grub.cfg /boot/efi/EFI/debian/grub.cfg 2>/dev/null || true

  echo "OK: Đã hoàn tất cài đặt Microsoft-signed SHIM vào /boot/efi/EFI/BOOT/$SHIM_NAME"
fi

# Đăng ký NVRAM entry trỏ vào shimx64.efi nếu efibootmgr khả dụng
if command -v efibootmgr >/dev/null 2>&1 && [ -d /sys/firmware/efi ]; then
  echo "===== Kiểm tra & Cập nhật UEFI Boot Manager (efibootmgr) ====="
  EFI_DEV=$(findmnt -n -o SOURCE /boot/efi 2>/dev/null || echo "")
  if [ -n "$EFI_DEV" ]; then
    DISK=$(echo "$EFI_DEV" | sed -E 's/p?[0-9]+$//')
    PART=$(echo "$EFI_DEV" | grep -o -E '[0-9]+$')
    if [ -n "$DISK" ] && [ -n "$PART" ]; then
      echo "Tạo NVRAM entry: Hyggshi OS -> Disk $DISK partition $PART loader \EFI\hyggshi\\$SHIM_DISTRO_NAME"
      efibootmgr -c -d "$DISK" -p "$PART" -L "Hyggshi OS" -l "\\EFI\\hyggshi\\$SHIM_DISTRO_NAME" 2>/dev/null || \
      efibootmgr -c -d "$DISK" -p "$PART" -L "Hyggshi OS" -l "\\EFI\\BOOT\\$SHIM_NAME" 2>/dev/null || true
    fi
  fi
fi

echo "===== [Hyggshi Secure Boot] Hoàn tất chuẩn bị bootloader. ====="
exit 0
