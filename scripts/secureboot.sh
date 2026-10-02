#!/bin/bash
# ==============================================================================
# scripts/secureboot.sh — Quản lý & Chuẩn hoá UEFI Secure Boot cho Hyggshi OS
# ==============================================================================
# MÔ HÌNH CHUỖI TIN CẬY (CHAIN OF TRUST):
#
#   PC Firmware (UEFI BIOS có sẵn cert "Microsoft Corporation UEFI CA 2011/2023" trong DB)
#        │
#        │ [Microsoft-trusted signature]
#        ▼
#   shim (BOOTX64.EFI / BOOTAA64.EFI) — ĐƯỢC MICROSOFT KÝ SẴN
#        │
#        │ [Distro trust: cert vendor nhúng sẵn trong shim hoặc qua MOK]
#        ▼
#   GRUB (grubx64.efi / gcda*.efi) — ĐƯỢC DISTRO KÝ (Debian/Canonical/Hyggshi)
#        │
#        │ [Distro trust: verification protocol]
#        ▼
#   Linux Kernel (/live/vmlinuz hoặc /boot/vmlinuz-*) — ĐƯỢC DISTRO KÝ
#        │
#        ▼
#   Hyggshi OS
#
# NGUYÊN TẮC BẢO MẬT CỰC KỲ QUAN TRỌNG:
# 1. KHÔNG YÊU CẦU END-USER VÀO BIOS ENROLL KEY THỦ CÔNG:
#    Người dùng phổ thông không thể và không nên vào BIOS thay thế PK/KEK/db.
#    Hệ thống chuẩn phải boot out-of-the-box nhờ shim đã được Microsoft ký.
#
# 2. KHÔNG COMMIT PRIVATE KEY VÀO GITHUB:
#    TUYỆT ĐỐI KHÔNG commit PK.key, KEK.key, db.key, MOK.key hay bất kỳ file .key nào vào repo.
#    Nếu cần ký kernel/module riêng trong GitHub Actions, private key PHẢI được lưu trong
#    GitHub Actions Secrets (vd: SECURE_BOOT_KEY, SECURE_BOOT_CERT) và nạp qua biến môi trường.
#
# 3. PHÂN BIỆT RÕ VAI TRÒ CỦA CÁC KEY:
#    - PK  (Platform Key): Khóa gốc của bo mạch chủ, kiểm soát quyền cập nhật KEK.
#    - KEK (Key Exchange Key): Khóa trung gian, kiểm soát quyền cập nhật db và dbx.
#    - db  (Signature Database): Danh sách cert/hash được firmware tin cậy (gồm Microsoft UEFI CA).
#    - dbx (Forbidden Database): Danh sách cert/hash bị thu hồi (revocation list).
#    - MOK (Machine Owner Key): Khóa do shim quản lý, cho phép nạp kernel/driver riêng mà không
#                               cần can thiệp vào UEFI database của bo mạch chủ.
# ==============================================================================

set -e
[ "$DEBUG_MODE" = "true" ] && set -x

# Kiểm tra xem một file EFI/PE có chữ ký Secure Boot hợp lệ hay không
hyggshi_sb_verify() {
  local target_file="$1"
  if [ ! -f "$target_file" ]; then
    echo "LỖI [sb_verify]: File không tồn tại: $target_file" >&2
    return 1
  fi

  if ! command -v sbverify >/dev/null 2>&1; then
    echo "CẢNH BÁO [sb_verify]: Công cụ sbverify (sbsigntool) chưa được cài đặt." >&2
    return 0
  fi

  if sbverify --list "$target_file" >/dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

# Kiểm tra xem file shim có chữ ký từ Microsoft UEFI CA hay không
hyggshi_sb_is_microsoft_signed() {
  local target_file="$1"
  if [ ! -f "$target_file" ]; then
    return 1
  fi

  if ! command -v sbverify >/dev/null 2>&1; then
    return 0
  fi

  local sig_info
  sig_info=$(sbverify --list "$target_file" 2>&1 || true)
  if echo "$sig_info" | grep -qi "Microsoft Corporation UEFI CA"; then
    return 0
  elif echo "$sig_info" | grep -qi "Microsoft Windows UEFI Driver Publisher"; then
    return 0
  else
    return 1
  fi
}

# Ký một file PE/EFI bằng sbsign (nếu có key & cert từ GitHub Secrets hoặc file an toàn)
hyggshi_sb_sign() {
  local input_file="$1"
  local output_file="${2:-$1}"
  local key_file="$3"
  local cert_file="$4"

  if [ -z "$key_file" ] || [ -z "$cert_file" ]; then
    echo "LỖI [sb_sign]: Thiếu đường dẫn key hoặc cert để ký." >&2
    return 1
  fi

  if [ ! -f "$key_file" ] || [ ! -f "$cert_file" ]; then
    echo "LỖI [sb_sign]: Không tìm thấy key_file ($key_file) hoặc cert_file ($cert_file)." >&2
    return 1
  fi

  if ! command -v sbsign >/dev/null 2>&1; then
    echo "LỖI [sb_sign]: Cần cài đặt công cụ sbsigntool để ký EFI binaries." >&2
    return 1
  fi

  echo "Đang ký Secure Boot: $input_file -> $output_file"
  sbsign --key "$key_file" --cert "$cert_file" --output "$output_file" "$input_file"
}

# Thiết lập cấu trúc thư mục ESP chuẩn cho UEFI Secure Boot
# Đảm bảo BOOTX64.EFI luôn là SHIM ĐÃ KÝ BỞI MICROSOFT, không bao giờ là GRUB unsigned!
hyggshi_sb_setup_esp_tree() {
  local esp_root="$1"
  local shim_bin="$2"
  local grub_bin="$3"
  local mm_bin="${4:-}"
  local arch="${5:-amd64}"

  if [ -z "$esp_root" ] || [ -z "$shim_bin" ] || [ -z "$grub_bin" ]; then
    echo "LỖI [setup_esp]: Thiếu tham số esp_root, shim_bin hoặc grub_bin." >&2
    return 1
  fi

  local shim_target_name="BOOTX64.EFI"
  local grub_target_name="grubx64.efi"
  local mm_target_name="mmx64.efi"

  if [ "$arch" = "arm64" ]; then
    shim_target_name="BOOTAA64.EFI"
    grub_target_name="grubaa64.efi"
    mm_target_name="mmaa64.efi"
  fi

  mkdir -p "$esp_root/EFI/BOOT"
  mkdir -p "$esp_root/EFI/hyggshi"
  mkdir -p "$esp_root/EFI/debian"
  mkdir -p "$esp_root/EFI/ubuntu"
  mkdir -p "$esp_root/boot/grub"

  # 1. Cài đặt vào EFI/BOOT (Removable & Fallback loader)
  # QUAN TRỌNG: File BOOTX64.EFI PHẢI LÀ SHIM (Microsoft-signed), TUYỆT ĐỐI KHÔNG COPY GRUB VÀO ĐÂY!
  # Nếu copy grubx64.efi thành BOOTX64.EFI, BIOS Dell/Lenovo/HP sẽ báo ngay:
  # "Operating System Loader has no signature. Incompatible with SecureBoot."
  cp -f "$shim_bin" "$esp_root/EFI/BOOT/$shim_target_name"
  cp -f "$grub_bin" "$esp_root/EFI/BOOT/$grub_target_name"
  [ -n "$mm_bin" ] && [ -f "$mm_bin" ] && cp -f "$mm_bin" "$esp_root/EFI/BOOT/$mm_target_name"

  # 2. Cài đặt vào EFI/hyggshi và EFI/debian (Distro NVRAM targets)
  for distro_dir in "$esp_root/EFI/hyggshi" "$esp_root/EFI/debian"; do
    cp -f "$shim_bin" "$distro_dir/$shim_target_name"
    cp -f "$shim_bin" "$distro_dir/shimx64.efi" 2>/dev/null || true
    [ "$arch" = "arm64" ] && cp -f "$shim_bin" "$distro_dir/shimaa64.efi" 2>/dev/null || true
    cp -f "$grub_bin" "$distro_dir/$grub_target_name"
    [ -n "$mm_bin" ] && [ -f "$mm_bin" ] && cp -f "$mm_bin" "$distro_dir/$mm_target_name"
  done

  # 3. Tạo grub.cfg redirect chuẩn trên ESP
  # Tự động tìm partition chứa /boot/grub/grub.cfg thật và nạp cấu hình
  local redir_cfg='search --file --no-floppy --set=hyggshi_root /boot/grub/grub.cfg
set prefix=($hyggshi_root)/boot/grub
configfile ($hyggshi_root)/boot/grub/grub.cfg'

  for target_cfg_dir in "$esp_root/EFI/BOOT" "$esp_root/EFI/hyggshi" "$esp_root/EFI/debian" "$esp_root/EFI/ubuntu" "$esp_root/boot/grub"; do
    mkdir -p "$target_cfg_dir"
    printf "%s\n" "$redir_cfg" > "$target_cfg_dir/grub.cfg"
  done

  echo "OK: Đã hoàn tất khởi tạo cấu trúc ESP Secure Boot tại: $esp_root"
}

# Ký tự động bằng GitHub Actions Secrets nếu được cấp (SECURE_BOOT_KEY / SECURE_BOOT_CERT)
hyggshi_sb_sign_with_secrets_if_available() {
  local target_file="$1"

  if [ -z "${SECURE_BOOT_KEY:-}" ] || [ -z "${SECURE_BOOT_CERT:-}" ]; then
    # Không có secret -> Sử dụng chuỗi tin cậy upstream của distro (Microsoft shim + Debian/Ubuntu signed GRUB/kernel)
    return 0
  fi

  echo "===== Phát hiện GitHub Actions Secrets: Chuẩn bị môi trường ký bảo mật ====="
  local sign_dir
  sign_dir=$(mktemp -d /tmp/hyggshi-sb-sign.XXXXXX)
  local key_file="$sign_dir/private_signing.key"
  local cert_file="$sign_dir/public_signing.crt"

  # Ghi key từ biến môi trường vào ramdisk tạm thời, phân quyền chặt chẽ 0600
  (
    umask 077
    printf "%s\n" "$SECURE_BOOT_KEY" > "$key_file"
    printf "%s\n" "$SECURE_BOOT_CERT" > "$cert_file"
  )

  if hyggshi_sb_sign "$target_file" "$target_file" "$key_file" "$cert_file"; then
    echo "OK: Đã ký bảo mật thành công cho: $target_file"
  else
    echo "CẢNH BÁO: Ký bằng GitHub Secrets thất bại, giữ nguyên file gốc." >&2
  fi

  # Dọn dẹp an toàn private key ngay sau khi ký xong
  shred -u "$key_file" 2>/dev/null || rm -f "$key_file"
  rm -rf "$sign_dir"
}
