#!/bin/bash
# iso.sh — unmount chroot, build squashfs, đóng gói thành ISO bootable (grub).
# Chạy trên HOST.
set -e
[ "$DEBUG_MODE" = "true" ] && set -x
: "${ARCH:=amd64}"
: "${BASE_DISTRO:=debian}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
[ -f "$SCRIPT_DIR/arch.sh" ] && source "$SCRIPT_DIR/arch.sh"

echo "===== Unmount chroot filesystems ====="
sudo umount -lf live-build/chroot/dev/pts 2>/dev/null || true
sudo umount -lf live-build/chroot/dev 2>/dev/null || true
sudo chroot live-build/chroot umount /proc 2>/dev/null || sudo umount -lf live-build/chroot/proc 2>/dev/null || true
sudo chroot live-build/chroot umount /sys 2>/dev/null || sudo umount -lf live-build/chroot/sys 2>/dev/null || true
sudo umount -lf live-build/chroot/run 2>/dev/null || true
# Bind-mount cache .deb (xem step "Mount apt cache vào chroot" trong
# workflow) PHẢI được unmount trước khi mksquashfs — nếu không toàn bộ
# .deb đã tải sẽ bị đóng gói lẫn vào filesystem.squashfs, làm ISO phình to
# vô ích (những .deb này chỉ cần tồn tại trên HOST để actions/cache lưu
# lại dùng cho lần build sau, không cần có trong ISO cuối cùng).
sudo umount -lf live-build/chroot/var/cache/apt/archives 2>/dev/null || true

echo "===== Dọn sạch rác, cache, build artifacts và temporary files trong chroot trước khi mksquashfs ====="
# Xoá toàn bộ file tạm và build artifacts trong /tmp và /var/tmp của chroot (bao gồm .deb 100MB của nexcode, zip, .o...)
sudo rm -rf live-build/chroot/tmp/* live-build/chroot/tmp/.* 2>/dev/null || true
sudo rm -rf live-build/chroot/var/tmp/* live-build/chroot/var/tmp/.* 2>/dev/null || true

# Xoá cache apt và apt list index (Debian testing index tốn hàng trăm MB)
sudo rm -rf live-build/chroot/var/cache/apt/archives/*.deb live-build/chroot/var/cache/apt/archives/partial/* 2>/dev/null || true
sudo rm -rf live-build/chroot/var/lib/apt/lists/* 2>/dev/null || true

# Xoá cache user/root
sudo rm -rf live-build/chroot/root/.cache/* live-build/chroot/home/*/.cache/* 2>/dev/null || true

# Truncate logs
sudo find live-build/chroot/var/log -type f -exec truncate -s 0 {} \; 2>/dev/null || true

echo "===== Build squashfs from chroot ====="
mkdir -p live-build/image/live
# QUAN TRỌNG: KHÔNG loại trừ /boot khỏi squashfs. Nếu loại trừ (-e boot),
# hệ thống live boot vẫn chạy được (vì /live/vmlinuz và /live/initrd được
# GRUB nạp trực tiếp từ ISO, không qua squashfs) — NHƯNG sau khi Calamares
# cài đặt (chép squashfs vào đĩa) thì /boot của hệ thống ĐÃ CÀI sẽ trống
# rỗng (không có vmlinuz/initrd/System.map/config, cũng không có sẵn để
# grub-install/update-grub chạy trong target). Kết quả: lỗi "grub-pc has
# no installation candidate" + "update-grub: No such file or directory".

# Xác định chế độ nén squashfs (đọc từ env, /tmp/hcl-resolved.json, hoặc config.ini)
MAX_COMP="${HCL_SQUASHFS_MAX_COMPRESSION:-${SQUASHFS_MAX_COMPRESSION:-}}"
if [ -z "$MAX_COMP" ] || [ "$MAX_COMP" = "false" ]; then
  if [ -f /tmp/hcl-resolved.json ]; then
    MAX_COMP=$(python3 -c "import json; print(str(bool(json.load(open('/tmp/hcl-resolved.json'))['base_profile'].get('config', {}).get('squashfs-max-compression'))).lower())" 2>/dev/null || echo "")
  fi
fi
if [ -z "$MAX_COMP" ] || [ "$MAX_COMP" = "false" ]; then
  if [ -f iso-config/config/config.ini ]; then
    MAX_COMP=$(grep -E '^[[:space:]]*squashfs-max-compression[[:space:]]*=' iso-config/config/config.ini 2>/dev/null | tail -n1 | tr -d ' "' | cut -d'=' -f2 | tr '[:upper:]' '[:lower:]' || echo "false")
  fi
fi

EXCLUDE_OPTS=(-wildcards -e "tmp/*" -e "tmp/.*" -e "var/tmp/*" -e "var/tmp/.*" -e "var/cache/apt/archives/*" -e "var/lib/apt/lists/*" -e "root/.cache/*" -e "home/*/.cache/*")

if [ "$MAX_COMP" = "true" ]; then
  echo "squashfs-max-compression=true -> dùng xz nén tối đa (block 1M, dict-size 100%, ISO nhỏ nhất)"
  if [ "$ARCH" = "amd64" ] || [ "$ARCH" = "x86_64" ]; then
    sudo mksquashfs live-build/chroot live-build/image/live/filesystem.squashfs \
      -comp xz -b 1M -Xbcj x86 -Xdict-size 100% -processors "$(nproc)" "${EXCLUDE_OPTS[@]}"
  else
    sudo mksquashfs live-build/chroot live-build/image/live/filesystem.squashfs \
      -comp xz -b 1M -Xdict-size 100% -processors "$(nproc)" "${EXCLUDE_OPTS[@]}"
  fi
else
  echo "squashfs-max-compression=false -> dùng zstd nhanh (mặc định)"
  sudo mksquashfs live-build/chroot live-build/image/live/filesystem.squashfs \
    -comp zstd -b 1M -Xcompression-level 19 -processors "$(nproc)" "${EXCLUDE_OPTS[@]}"
fi

echo "===== Prepare boot files (kernel + initrd) ====="
# Dùng ls -t + head -n1 thay vì cp trực tiếp theo glob: nếu vì lý do gì đó
# /boot có nhiều hơn 1 vmlinuz-*/initrd.img-* (ví dụ update kernel giữa
# chừng), cp với nhiều nguồn vào 1 đích sẽ lỗi "target is not a directory".
# Luôn lấy bản mới nhất theo thời gian sửa đổi.
if ! sudo ls live-build/chroot/boot/vmlinuz-* >/dev/null 2>&1 || \
   ! sudo ls live-build/chroot/boot/initrd.img-* >/dev/null 2>&1; then
  echo "LỖI: live-build/chroot/boot/ không có vmlinuz-*/initrd.img-*." >&2
  echo "Nguyên nhân nằm ở bước cài kernel trong desktop.sh (chạy trước iso.sh)," >&2
  echo "không phải ở iso.sh này. Kiểm tra lại log của desktop.sh." >&2
  echo "Nội dung /boot hiện có:" >&2
  sudo ls -la live-build/chroot/boot >&2 || true
  exit 1
fi
VMLINUZ_FILE=$(sudo ls -t live-build/chroot/boot/vmlinuz-* | head -n1)
INITRD_FILE=$(sudo ls -t live-build/chroot/boot/initrd.img-* | head -n1)
sudo cp "$VMLINUZ_FILE" live-build/image/live/vmlinuz
sudo cp "$INITRD_FILE" live-build/image/live/initrd

# Fail-fast: không cho phép tạo ISO nếu initrd lại chứa Plymouth mặc định
# thay vì theme Hyggshi. Đây chính là nguyên nhân màn hình QEMU trước đó chỉ
# hiện nền tối + 3 chấm của spinner mặc định.
if command -v lsinitramfs >/dev/null 2>&1; then
  if ! sudo lsinitramfs "$INITRD_FILE" 2>/dev/null | grep -q 'usr/share/plymouth/themes/hyggshi-boot/hyggshi-boot.plymouth'; then
    echo "LỖI: initrd $INITRD_FILE không chứa Hyggshi Plymouth theme." >&2
    echo "Không tiếp tục tạo ISO để tránh phát hành bản boot splash sai." >&2
    exit 1
  fi
  echo "OK: initrd ISO chứa Hyggshi Plymouth theme."
fi

echo "===== Dò memtest86+ trong chroot (cho mục 'Kiểm tra RAM' trong GRUB, best-effort) ====="
# Tên file binary memtest86+ đổi khác nhau tuỳ version đóng gói (Debian
# 12/bookworm dùng bản 5.x -> /boot/memtest86+.bin; Debian 13/trixie+ dùng
# bản 6.x/7.x rebrand từ PCMemTest -> /boot/memtest86+x64.bin, có khi nằm ở
# /usr/lib/memtest86+/ thay vì /boot/). KHÔNG hardcode 1 tên duy nhất — dò
# theo pattern rồi lấy file đầu tiên khớp, bỏ qua hẳn mục GRUB này nếu
# desktop.sh không cài được gói (không fatal, xem ghi chú trong desktop.sh).
MEMTEST_BIN=""
for CANDIDATE in \
  live-build/chroot/boot/memtest86+x64.bin \
  live-build/chroot/boot/memtest86+.bin \
  live-build/chroot/usr/lib/memtest86+/memtest86+x64.bin \
  live-build/chroot/usr/lib/memtest86+/memtest86+.bin; do
  if sudo test -f "$CANDIDATE"; then
    MEMTEST_BIN="$CANDIDATE"
    break
  fi
done
if [ -z "$MEMTEST_BIN" ]; then
  FOUND=$(sudo find live-build/chroot/boot live-build/chroot/usr/lib/memtest86+ \
    -maxdepth 1 -iname 'memtest86+*.bin' 2>/dev/null | sort | head -n1)
  [ -n "$FOUND" ] && MEMTEST_BIN="$FOUND"
fi
if [ -n "$MEMTEST_BIN" ]; then
  sudo cp "$MEMTEST_BIN" live-build/image/live/memtest86+.bin
  sudo chown "$(id -u)":"$(id -g)" live-build/image/live/memtest86+.bin
  echo "OK: đã chép memtest86+ ($MEMTEST_BIN) -> live-build/image/live/memtest86+.bin"
else
  echo "CẢNH BÁO: không tìm thấy binary memtest86+ trong chroot — bỏ qua mục 'Kiểm tra RAM' trong GRUB." >&2
fi

# Xác định tên file EFI theo kiến trúc
if declare -f hyggshi_shim_efi_name >/dev/null 2>&1; then
  SHIM_TARGET_NAME=$(hyggshi_shim_efi_name "$ARCH")
  GRUB_TARGET_NAME=$(hyggshi_grub_efi_name "$ARCH")
  MM_TARGET_NAME=$(hyggshi_mm_efi_name "$ARCH")
  FB_TARGET_NAME=$(hyggshi_fb_efi_name "$ARCH")
else
  if [ "$ARCH" = "arm64" ]; then
    SHIM_TARGET_NAME="BOOTAA64.EFI"
    GRUB_TARGET_NAME="grubaa64.efi"
    MM_TARGET_NAME="mmaa64.efi"
    FB_TARGET_NAME="fbaa64.efi"
  else
    SHIM_TARGET_NAME="BOOTX64.EFI"
    GRUB_TARGET_NAME="grubx64.efi"
    MM_TARGET_NAME="mmx64.efi"
    FB_TARGET_NAME="fbx64.efi"
  fi
fi

# Cài đặt công cụ host runner (mtools, dosfstools, xorriso, grub-pc-bin, grub-efi-amd64-bin)
echo "===== Cài đặt công cụ ISO / EFI trên host runner ====="
sudo apt-get update -qq || true
sudo apt-get install -y --no-install-recommends \
  grub-common grub-pc-bin grub-efi-amd64-bin mtools dosfstools xorriso \
  || echo "CẢNH BÁO: apt-get install công cụ EFI trên host gặp lỗi, tiếp tục thử..."

SHIM_BIN=""
GRUB_SIGNED_BIN=""
MM_BIN=""
FB_BIN=""

if [ "$BASE_DISTRO" = "debian" ] || [ -z "$BASE_DISTRO" ]; then
  echo "===== UEFI Secure Boot: Dùng shim-signed từ Debian (Microsoft ký sẵn) làm bootloader trung gian ====="
  # CHUỖI TIN CẬY ĐÚNG (chuẩn Debian chính thức):
  #   firmware (tin sẵn Microsoft 3rd Party UEFI CA trong DB)
  #     -> shimx64.efi.signed (từ Debian, ký bởi Microsoft Corporation UEFI CA)
  #     -> grubx64.efi.signed (từ Debian, ký bởi Debian Secure Boot CA — shim chứa sẵn cert Debian)
  #     -> /live/vmlinuz      (kernel Debian, ký bởi Debian Secure Boot CA — shim xác thực qua verify protocol)

  # Cách 1: Tìm trong live-build/chroot (đã cài đặt bởi desktop.sh)
  # LƯU Ý: gcd*.efi.signed (GRUB CD/removable media) có embedded prefix là /boot/grub
  # (khác grub*.efi.signed có prefix /EFI/debian cho ổ cứng cài đặt) — ưu tiên dùng gcd
  # làm grubx64.efi/grubaa64.efi để bootloader trỏ thẳng tới /boot/grub/grub.cfg.
  if [ "$ARCH" = "arm64" ]; then
    [ -f "live-build/chroot/usr/lib/shim/shimaa64.efi.signed" ] && SHIM_BIN="live-build/chroot/usr/lib/shim/shimaa64.efi.signed"
    [ -z "$SHIM_BIN" ] && [ -f "live-build/chroot/usr/lib/shim/shimaa64.efi" ] && SHIM_BIN="live-build/chroot/usr/lib/shim/shimaa64.efi"
    [ -f "live-build/chroot/usr/lib/grub/arm64-efi-signed/gcdaa64.efi.signed" ] && GRUB_SIGNED_BIN="live-build/chroot/usr/lib/grub/arm64-efi-signed/gcdaa64.efi.signed"
    [ -z "$GRUB_SIGNED_BIN" ] && [ -f "live-build/chroot/usr/lib/grub/arm64-efi-signed/grubaa64.efi.signed" ] && GRUB_SIGNED_BIN="live-build/chroot/usr/lib/grub/arm64-efi-signed/grubaa64.efi.signed"
    [ -f "live-build/chroot/usr/lib/shim/mmaa64.efi.signed" ] && MM_BIN="live-build/chroot/usr/lib/shim/mmaa64.efi.signed"
    [ -z "$MM_BIN" ] && [ -f "live-build/chroot/usr/lib/shim/mmaa64.efi" ] && MM_BIN="live-build/chroot/usr/lib/shim/mmaa64.efi"
    [ -f "live-build/chroot/usr/lib/shim/fbaa64.efi.signed" ] && FB_BIN="live-build/chroot/usr/lib/shim/fbaa64.efi.signed"
    [ -z "$FB_BIN" ] && [ -f "live-build/chroot/usr/lib/shim/fbaa64.efi" ] && FB_BIN="live-build/chroot/usr/lib/shim/fbaa64.efi"
  else
    [ -f "live-build/chroot/usr/lib/shim/shimx64.efi.signed" ] && SHIM_BIN="live-build/chroot/usr/lib/shim/shimx64.efi.signed"
    [ -z "$SHIM_BIN" ] && [ -f "live-build/chroot/usr/lib/shim/shimx64.efi" ] && SHIM_BIN="live-build/chroot/usr/lib/shim/shimx64.efi"
    [ -f "live-build/chroot/usr/lib/grub/x86_64-efi-signed/gcdx64.efi.signed" ] && GRUB_SIGNED_BIN="live-build/chroot/usr/lib/grub/x86_64-efi-signed/gcdx64.efi.signed"
    [ -z "$GRUB_SIGNED_BIN" ] && [ -f "live-build/chroot/usr/lib/grub/x86_64-efi-signed/grubx64.efi.signed" ] && GRUB_SIGNED_BIN="live-build/chroot/usr/lib/grub/x86_64-efi-signed/grubx64.efi.signed"
    [ -f "live-build/chroot/usr/lib/shim/mmx64.efi.signed" ] && MM_BIN="live-build/chroot/usr/lib/shim/mmx64.efi.signed"
    [ -z "$MM_BIN" ] && [ -f "live-build/chroot/usr/lib/shim/mmx64.efi" ] && MM_BIN="live-build/chroot/usr/lib/shim/mmx64.efi"
    [ -f "live-build/chroot/usr/lib/shim/fbx64.efi.signed" ] && FB_BIN="live-build/chroot/usr/lib/shim/fbx64.efi.signed"
    [ -z "$FB_BIN" ] && [ -f "live-build/chroot/usr/lib/shim/fbx64.efi" ] && FB_BIN="live-build/chroot/usr/lib/shim/fbx64.efi"
  fi

  # Cách 2: Nếu chroot chưa có, tải gói .deb chính thức từ Debian repository và giải nén bằng dpkg-deb
  if [ -z "$SHIM_BIN" ] || [ -z "$GRUB_SIGNED_BIN" ]; then
    echo "Chưa thấy đủ shim/grub Debian trong chroot -> Tải gói .deb từ Debian mirror..."
    DEBIAN_EFI_TMP=$(mktemp -d)
    mkdir -p "$DEBIAN_EFI_TMP/lists/partial" "$DEBIAN_EFI_TMP/archives/partial" "$DEBIAN_EFI_TMP/etc/apt" "$DEBIAN_EFI_TMP/extracted"
    cat <<EOF > "$DEBIAN_EFI_TMP/etc/apt/sources.list"
deb [trusted=yes] http://deb.debian.org/debian ${BASE_CODENAME:-trixie} main
EOF

    apt-get -o Dir="$DEBIAN_EFI_TMP" \
            -o Dir::State="$DEBIAN_EFI_TMP" \
            -o Dir::State::status="/dev/null" \
            -o Dir::Cache="$DEBIAN_EFI_TMP" \
            -o Dir::Etc="$DEBIAN_EFI_TMP/etc/apt" \
            -o Acquire::Languages="none" \
            update -qq || true

    SB_DL_PKGS="shim-signed grub-efi-amd64-signed shim-helpers-amd64-signed"
    [ "$ARCH" = "arm64" ] && SB_DL_PKGS="shim-signed grub-efi-arm64-signed shim-helpers-arm64-signed"

    (cd "$DEBIAN_EFI_TMP" && apt-get -o Dir="$DEBIAN_EFI_TMP" \
                                    -o Dir::State="$DEBIAN_EFI_TMP" \
                                    -o Dir::State::status="/dev/null" \
                                    -o Dir::Cache="$DEBIAN_EFI_TMP" \
                                    -o Dir::Etc="$DEBIAN_EFI_TMP/etc/apt" \
                                    download $SB_DL_PKGS 2>/dev/null || true)

    for deb in "$DEBIAN_EFI_TMP"/*.deb; do
      [ -f "$deb" ] && dpkg-deb -x "$deb" "$DEBIAN_EFI_TMP/extracted/" 2>/dev/null || true
    done

    if [ "$ARCH" = "arm64" ]; then
      [ -z "$SHIM_BIN" ] && SHIM_BIN=$(find "$DEBIAN_EFI_TMP/extracted/usr/lib/shim" -maxdepth 1 -iname 'shimaa64.efi*' 2>/dev/null | head -n1)
      [ -z "$GRUB_SIGNED_BIN" ] && GRUB_SIGNED_BIN=$(find "$DEBIAN_EFI_TMP/extracted/usr/lib/grub/arm64-efi-signed" -maxdepth 1 -iname 'gcdaa64.efi.signed*' 2>/dev/null | head -n1)
      [ -z "$GRUB_SIGNED_BIN" ] && GRUB_SIGNED_BIN=$(find "$DEBIAN_EFI_TMP/extracted/usr/lib/grub/arm64-efi-signed" -maxdepth 1 -iname 'grubaa64.efi.signed*' 2>/dev/null | head -n1)
      [ -z "$MM_BIN" ] && MM_BIN=$(find "$DEBIAN_EFI_TMP/extracted/usr/lib/shim" -maxdepth 1 -iname 'mmaa64.efi*' 2>/dev/null | head -n1)
      [ -z "$FB_BIN" ] && FB_BIN=$(find "$DEBIAN_EFI_TMP/extracted/usr/lib/shim" -maxdepth 1 -iname 'fbaa64.efi*' 2>/dev/null | head -n1)
    else
      [ -z "$SHIM_BIN" ] && SHIM_BIN=$(find "$DEBIAN_EFI_TMP/extracted/usr/lib/shim" -maxdepth 1 -iname 'shimx64.efi*' 2>/dev/null | head -n1)
      [ -z "$GRUB_SIGNED_BIN" ] && GRUB_SIGNED_BIN=$(find "$DEBIAN_EFI_TMP/extracted/usr/lib/grub/x86_64-efi-signed" -maxdepth 1 -iname 'gcdx64.efi.signed*' 2>/dev/null | head -n1)
      [ -z "$GRUB_SIGNED_BIN" ] && GRUB_SIGNED_BIN=$(find "$DEBIAN_EFI_TMP/extracted/usr/lib/grub/x86_64-efi-signed" -maxdepth 1 -iname 'grubx64.efi.signed*' 2>/dev/null | head -n1)
      [ -z "$MM_BIN" ] && MM_BIN=$(find "$DEBIAN_EFI_TMP/extracted/usr/lib/shim" -maxdepth 1 -iname 'mmx64.efi*' 2>/dev/null | head -n1)
      [ -z "$FB_BIN" ] && FB_BIN=$(find "$DEBIAN_EFI_TMP/extracted/usr/lib/shim" -maxdepth 1 -iname 'fbx64.efi*' 2>/dev/null | head -n1)
    fi
  fi

else
  # Distro là Ubuntu hoặc Mint: Dùng shim-signed / grub-signed của Ubuntu (phù hợp với kernel Ubuntu đã ký bởi Canonical)
  echo "===== UEFI Secure Boot: Cài shim-signed + GRUB signed từ Ubuntu/Mint (Canonical ký) ====="
  sudo apt-get install -y --no-install-recommends shim-signed grub-efi-amd64-signed || true
  SHIM_BIN=$(sudo find /usr/lib/shim -maxdepth 1 -iname 'shimx64.efi.signed*' 2>/dev/null | sort | tail -n1)
  MM_BIN=$(sudo find /usr/lib/shim -maxdepth 1 -iname 'mmx64.efi*' 2>/dev/null | sort | tail -n1)
  FB_BIN=$(sudo find /usr/lib/shim -maxdepth 1 -iname 'fbx64.efi*' 2>/dev/null | sort | tail -n1)
  GRUB_SIGNED_BIN=$(sudo find /usr/lib/grub/x86_64-efi-signed -maxdepth 1 -iname 'grubx64.efi.signed*' 2>/dev/null | sort | tail -n1)
fi

if [ -z "$SHIM_BIN" ] || [ -z "$GRUB_SIGNED_BIN" ]; then
  SECURE_BOOT_OK=false
  echo "CẢNH BÁO: không tìm thấy đầy đủ shim/grub ĐÃ KÝ." >&2
  echo "  shim: ${SHIM_BIN:-<không thấy>}" >&2
  echo "  grub: ${GRUB_SIGNED_BIN:-<không thấy>}" >&2
  echo "-> Fallback: build ISO bằng grub-mkrescue (vẫn boot bình thường ở máy TẮT Secure Boot)." >&2
else
  SECURE_BOOT_OK=true
  echo "OK: Đã tìm thấy shim-signed (Microsoft ký sẵn): $SHIM_BIN"
  echo "OK: Đã tìm thấy grub (signed): $GRUB_SIGNED_BIN"
  echo "OK: MokManager: ${MM_BIN:-<không có, bỏ qua>}"
  echo "OK: Fallback: ${FB_BIN:-<không có, bỏ qua>}"
fi

mkdir -p live-build/image/boot/grub

if [ "$SECURE_BOOT_OK" = "true" ]; then
  echo "===== Dựng EFI System Partition (FAT) chứa shim + grub đã ký ====="
  EFI_STAGE=$(mktemp -d)
  mkdir -p "$EFI_STAGE/EFI/BOOT"

  # BOOTX64.EFI / BOOTAA64.EFI = shim (đã được Microsoft ký sẵn) — firmware nạp file này đầu tiên
  sudo install -m 0644 "$SHIM_BIN" "$EFI_STAGE/EFI/BOOT/$SHIM_TARGET_NAME"
  sudo install -m 0644 "$GRUB_SIGNED_BIN" "$EFI_STAGE/EFI/BOOT/$GRUB_TARGET_NAME"
  [ -n "$MM_BIN" ] && sudo install -m 0644 "$MM_BIN" "$EFI_STAGE/EFI/BOOT/$MM_TARGET_NAME"
  [ -n "$FB_BIN" ] && sudo install -m 0644 "$FB_BIN" "$EFI_STAGE/EFI/BOOT/$FB_TARGET_NAME"
  sudo chown -R "$(id -u)":"$(id -g)" "$EFI_STAGE"

  # Redirect grub.cfg: đặt ở tất cả path mà GRUB đã ký có thể tìm
  # (/EFI/debian/grub.cfg, /EFI/BOOT/grub.cfg, /EFI/ubuntu/grub.cfg)
  # Redirect grub.cfg: đặt ở tất cả path mà GRUB đã ký có thể tìm
  # (/EFI/debian/grub.cfg, /EFI/BOOT/grub.cfg, /EFI/ubuntu/grub.cfg, /boot/grub/grub.cfg)
  for REDIRECT_DIR in "$EFI_STAGE/EFI/debian" "$EFI_STAGE/EFI/ubuntu" "$EFI_STAGE/EFI/BOOT" "$EFI_STAGE/boot/grub"; do
    mkdir -p "$REDIRECT_DIR"
    cat <<'REDIR_EOF' > "$REDIRECT_DIR/grub.cfg"
search --file --no-floppy --set=hyggshi_root /boot/grub/grub.cfg
set prefix=($hyggshi_root)/boot/grub
configfile ($hyggshi_root)/boot/grub/grub.cfg
REDIR_EOF
  done

  # Tạo efi.img (16MiB FAT filesystem)
  dd if=/dev/zero of=live-build/image/boot/grub/efi.img bs=1M count=16 status=none
  mkfs.vfat -n HYGGSHI_ESP live-build/image/boot/grub/efi.img >/dev/null
  mmd -i live-build/image/boot/grub/efi.img ::EFI ::EFI/BOOT ::boot ::boot/grub
  mcopy -i live-build/image/boot/grub/efi.img -s "$EFI_STAGE"/EFI/BOOT/* ::EFI/BOOT/
  for d in debian ubuntu; do
    if [ -d "$EFI_STAGE/EFI/$d" ]; then
      mmd -i live-build/image/boot/grub/efi.img "::EFI/$d" 2>/dev/null || true
      mcopy -i live-build/image/boot/grub/efi.img "$EFI_STAGE/EFI/$d/grub.cfg" "::EFI/$d/" 2>/dev/null || true
    fi
  done
  mcopy -i live-build/image/boot/grub/efi.img "$EFI_STAGE/boot/grub/grub.cfg" "::boot/grub/" 2>/dev/null || true
  rm -rf "$EFI_STAGE"

  # Chép vào cây thư mục ISO9660
  mkdir -p live-build/image/EFI/BOOT live-build/image/EFI/debian live-build/image/EFI/ubuntu
  sudo cp "$SHIM_BIN" "live-build/image/EFI/BOOT/$SHIM_TARGET_NAME"
  sudo cp "$GRUB_SIGNED_BIN" "live-build/image/EFI/BOOT/$GRUB_TARGET_NAME"
  [ -n "$MM_BIN" ] && sudo cp "$MM_BIN" "live-build/image/EFI/BOOT/$MM_TARGET_NAME"
  [ -n "$FB_BIN" ] && sudo cp "$FB_BIN" "live-build/image/EFI/BOOT/$FB_TARGET_NAME"

  # Redirect grub.cfg trong cây ISO
  for REDIRECT_DIR in live-build/image/EFI/debian live-build/image/EFI/ubuntu live-build/image/EFI/BOOT; do
    cat <<'REDIR_EOF' | sudo tee "$REDIRECT_DIR/grub.cfg" >/dev/null
search --file --no-floppy --set=hyggshi_root /boot/grub/grub.cfg
configfile ($hyggshi_root)/boot/grub/grub.cfg
REDIR_EOF
  done
  sudo chown -R "$(id -u)":"$(id -g)" live-build/image/EFI
fi

echo "===== Build bootable ISO with grub ====="
# Kernel cmdline thêm theo Edition — CHỈ áp dụng cho Debian (đúng phạm vi
# yêu cầu "arch và debian thêm tuỳ chọn chỉnh thông số kernel"); Ubuntu/Mint
# giữ nguyên "quiet splash" mặc định như trước.
KERNEL_CMDLINE_EXTRA="quiet splash"
if [ "$BASE_DISTRO" = "debian" ]; then
  # shellcheck source=/dev/null
  source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/kernel-tuning.sh"
  KERNEL_CMDLINE_EXTRA=$(hyggshi_kernel_cmdline_extra "${EDITION:-normal}")
fi
case " $KERNEL_CMDLINE_EXTRA " in
  *" quiet "*) ;;
  *) KERNEL_CMDLINE_EXTRA="quiet $KERNEL_CMDLINE_EXTRA" ;;
esac
case " $KERNEL_CMDLINE_EXTRA " in
  *" splash "*) ;;
  *) KERNEL_CMDLINE_EXTRA="$KERNEL_CMDLINE_EXTRA splash" ;;
esac

mkdir -p live-build/image/boot/grub

# ===== GRUB background: Hyggshi branding =====
# Nguồn cố định trong repo: ./iso-config/branding/desktop-grub.png
# và ./iso-config/branding/desktop-grub.svg. GRUB dùng PNG để render
# background; SVG vẫn được đóng gói kèm để giữ source branding/vector.
GRUB_BACKGROUND_APPLIED=false
if [ -f "iso-config/branding/desktop-grub.png" ]; then
  sudo install -m 0644 "iso-config/branding/desktop-grub.png" \
    live-build/image/boot/grub/desktop-grub.png
  # Ghi đè luôn bản desktop-base trong live filesystem nếu thư mục tồn tại.
  # Sau khi cài hệ thống, branding.sh sẽ áp lại vào /usr/share/images/desktop-base.
  sudo mkdir -p live-build/chroot/usr/share/images/desktop-base
  sudo install -m 0644 "iso-config/branding/desktop-grub.png" \
    live-build/chroot/usr/share/images/desktop-base/desktop-grub.png
  GRUB_BACKGROUND_APPLIED=true
  echo "OK: GRUB background = iso-config/branding/desktop-grub.png"
else
  echo "WARNING: không tìm thấy iso-config/branding/desktop-grub.png — GRUB giữ nền mặc định."
fi

if [ -f "iso-config/branding/desktop-grub.svg" ]; then
  sudo install -m 0644 "iso-config/branding/desktop-grub.svg" \
    live-build/image/boot/grub/desktop-grub.svg
  sudo mkdir -p live-build/chroot/usr/share/images/desktop-base
  sudo install -m 0644 "iso-config/branding/desktop-grub.svg" \
    live-build/chroot/usr/share/images/desktop-base/desktop-grub.svg
  echo "OK: đóng gói GRUB SVG = iso-config/branding/desktop-grub.svg"
else
  echo "WARNING: không tìm thấy iso-config/branding/desktop-grub.svg — bỏ qua SVG."
fi

# Đảm bảo font unicode.pf2 có sẵn trong boot/grub/fonts/ để gfxterm hiển thị font chuẩn
mkdir -p live-build/image/boot/grub/fonts
for font_candidate in \
  live-build/chroot/usr/share/grub/unicode.pf2 \
  /usr/share/grub/unicode.pf2; do
  if [ -f "$font_candidate" ]; then
    sudo cp "$font_candidate" live-build/image/boot/grub/fonts/unicode.pf2
    echo "OK: đã chép font GRUB ($font_candidate) -> live-build/image/boot/grub/fonts/unicode.pf2"
    break
  fi
done

{
  echo "set timeout=10"
  echo "set default=0"
  echo ""
  if [ "$GRUB_BACKGROUND_APPLIED" = "true" ]; then
    # Chuyển GRUB sang gfxterm và áp background PNG. Dùng if/then để nếu
    # firmware/GRUB thiếu module đồ hoạ thì menu text vẫn boot bình thường.
    echo "if [ -e /boot/grub/fonts/unicode.pf2 ]; then"
    echo "  loadfont /boot/grub/fonts/unicode.pf2"
    echo "fi"
    echo "if insmod gfxterm; then"
    echo "  if insmod png; then"
    echo "    set gfxmode=auto"
    echo "    terminal_output gfxterm"
    echo "    background_image /boot/grub/desktop-grub.png"
    echo "  fi"
    echo "fi"
    echo ""
  fi
  echo "menuentry \"$DISTRO_NAME Live\" {"
  echo "  linux /live/vmlinuz boot=live $KERNEL_CMDLINE_EXTRA"
  echo "  initrd /live/initrd"
  echo "}"
  echo ""
  # Chữ hiển thị trong GRUB PHẢI là tiếng Anh thuần ASCII — font console mặc
  # định grub-mkrescue dùng (không nạp unicode.pf2 + gfxterm) không có dấu
  # tiếng Việt, chữ có dấu bị vỡ thành "ch? ?? ??" như ảnh chụp thực tế.
  # Nạp font Unicode riêng cho GRUB text-mode là khả thi nhưng tốn thêm
  # module/font vào ISO chỉ để đổi mấy dòng menu — không đáng, giữ tiếng Anh
  # cho toàn bộ chữ hiển thị ở đây (comment trong script vẫn tiếng Việt bình
  # thường, không liên quan tới font GRUB).
  #
  # "Safe graphics / nomodeset" — tắt kernel mode-setting của driver GPU,
  # dùng khi màn hình đen/lỗi hiển thị lúc boot bình thường (driver GPU độc
  # quyền/không tương thích) — mục chuẩn có trên hầu hết live ISO Debian/Ubuntu.
  echo "menuentry \"$DISTRO_NAME Live (safe graphics / nomodeset)\" {"
  echo "  linux /live/vmlinuz boot=live $KERNEL_CMDLINE_EXTRA nomodeset"
  echo "  initrd /live/initrd"
  echo "}"
  echo ""
  # Chỉ thêm mục Memory test nếu iso.sh thực sự tìm/chép được binary
  # memtest86+ ở bước trên — tránh 1 mục GRUB trỏ tới file không tồn tại.
  # LƯU Ý: linux16 dùng boot protocol 16-bit real-mode — CHỈ chạy được khi
  # máy boot GRUB ở chế độ BIOS/legacy. Máy boot UEFI (kể cả Secure Boot đã
  # vá ở trên) chọn mục này sẽ không vào được Memtest86+ (không có gì hỏng,
  # chỉ đơn giản không chạy) — muốn hỗ trợ cả UEFI cần thêm biến thể .efi
  # riêng (memtest86+x64.efi) qua chainloader, nằm ngoài phạm vi sửa lần này.
  if [ -f live-build/image/live/memtest86+.bin ]; then
    echo "menuentry \"Memory test (Memtest86+)\" {"
    echo "  linux16 /live/memtest86+.bin"
    echo "}"
    echo ""
  fi
  # "Boot from first hard disk" — mục chuẩn trên live ISO Debian/Ubuntu để
  # thoát sang ổ cứng đã cài (hữu ích khi máy để USB live cắm sẵn nhưng
  # người dùng chỉ muốn boot bình thường vào hệ điều hành đã cài).
  echo "menuentry \"Boot from first hard disk\" {"
  echo "  set root=(hd0)"
  echo "  chainloader +1"
  echo "}"
} > live-build/image/boot/grub/grub.cfg

# Tạo .disk/info theo chuẩn Debian/Ubuntu để GRUB và live-boot nhận diện chính xác
mkdir -p live-build/image/.disk
echo "${DISTRO_NAME:-Hyggshi OS} ${HYGGSHI_VERSION_ID:-1.0} (${BASE_CODENAME:-trixie}) - Official Build" | sudo tee live-build/image/.disk/info >/dev/null
sudo touch live-build/image/.disk/base_installable

echo "===== Đóng gói bootable hybrid ISO (UEFI Secure Boot + BIOS Legacy) ====="

# 1. Chuẩn bị BIOS bootloader (i386-pc eltorito.img + MBR boot_hybrid.img)
GRUB_PC_DIR=""
if [ -d "live-build/chroot/usr/lib/grub/i386-pc" ]; then
  GRUB_PC_DIR="live-build/chroot/usr/lib/grub/i386-pc"
elif [ -d "/usr/lib/grub/i386-pc" ]; then
  GRUB_PC_DIR="/usr/lib/grub/i386-pc"
fi

GRUB_HYBRID_MBR=""
if [ -n "$GRUB_PC_DIR" ] && command -v grub-mkimage >/dev/null 2>&1; then
  echo "===== Chuẩn bị GRUB BIOS bootloader (i386-pc) ====="
  mkdir -p live-build/image/boot/grub/i386-pc
  sudo cp -a "$GRUB_PC_DIR"/*.mod "$GRUB_PC_DIR"/*.lst live-build/image/boot/grub/i386-pc/ 2>/dev/null || true
  
  CORE_IMG=$(mktemp)
  if grub-mkimage -d "$GRUB_PC_DIR" -o "$CORE_IMG" -O i386-pc --prefix=/boot/grub biosdisk iso9660; then
    cat "$GRUB_PC_DIR/cdboot.img" "$CORE_IMG" > live-build/image/boot/grub/i386-pc/eltorito.img
    sudo chmod 644 live-build/image/boot/grub/i386-pc/eltorito.img 2>/dev/null || true
    echo "OK: đã tạo live-build/image/boot/grub/i386-pc/eltorito.img cho BIOS boot."
  fi
  rm -f "$CORE_IMG"

  [ -f "$GRUB_PC_DIR/boot_hybrid.img" ] && GRUB_HYBRID_MBR="$GRUB_PC_DIR/boot_hybrid.img"
fi
[ -z "$GRUB_HYBRID_MBR" ] && [ -f "/usr/lib/grub/i386-pc/boot_hybrid.img" ] && GRUB_HYBRID_MBR="/usr/lib/grub/i386-pc/boot_hybrid.img"

# 2. Đóng gói ISO bằng xorriso (chuẩn Debian Live-Build / Ubuntu hybrid ISO)
# Thay vì grub-mkrescue (luôn tự biên dịch grub unsigned phá hỏng chuỗi tin cậy Secure Boot),
# dùng xorriso -as mkisofs trực tiếp gắn shim Microsoft ký sẵn + grub signed vào El Torito
# và phân vùng GPT EFI.
XORRISO_ARGS=(
  -iso-level 3
  -full-iso9660-filenames
  -volid "HYGGSHI_OS"
  -output "$ISO_FILENAME"
  -r
  -graft-points
)

# BIOS Legacy boot options
if [ -f "live-build/image/boot/grub/i386-pc/eltorito.img" ] && [ -n "$GRUB_HYBRID_MBR" ] && [ -f "$GRUB_HYBRID_MBR" ]; then
  echo "Thêm cấu hình BIOS Legacy (eltorito.img + MBR hybrid: $GRUB_HYBRID_MBR)"
  XORRISO_ARGS+=(
    --grub2-mbr "$GRUB_HYBRID_MBR"
    --protective-msdos-label
    -partition_cyl_align off
    -partition_offset 0
    -b boot/grub/i386-pc/eltorito.img
    -no-emul-boot -boot-load-size 4 -boot-info-table --grub2-boot-info
  )
fi

# UEFI Secure Boot options
if [ "$SECURE_BOOT_OK" = "true" ] && [ -f "live-build/image/boot/grub/efi.img" ]; then
  echo "Thêm cấu hình UEFI Secure Boot (shim-signed Microsoft ký sẵn + GRUB signed)"
  XORRISO_ARGS+=(
    -eltorito-alt-boot
    -e boot/grub/efi.img
    -no-emul-boot
    -isohybrid-gpt-basdat
    -efi-boot-part --efi-boot-image
  )
fi

XORRISO_ARGS+=(live-build/image)

echo "Thực thi: xorriso -as mkisofs ${XORRISO_ARGS[*]}"
if sudo xorriso -as mkisofs "${XORRISO_ARGS[@]}"; then
  echo "OK: đã đóng gói thành công $ISO_FILENAME bằng xorriso (hỗ trợ Secure Boot chuẩn)."
else
  echo "CẢNH BÁO: xorriso trực tiếp thất bại -> fallback sang grub-mkrescue (chỉ boot máy tắt Secure Boot)..." >&2
  sudo grub-mkrescue -o "$ISO_FILENAME" live-build/image --compress=xz -- -volid "HYGGSHI_OS"
fi

ls -lh "$ISO_FILENAME"

echo "===== Sinh SHA256SUMS để người dùng verify integrity sau khi tải ====="
# grub-mkrescue chạy bằng sudo -> file ISO thuộc root:root. sha256sum chỉ
# cần quyền đọc nên không cần sudo, nhưng thêm phòng trường hợp umask lạ
# khiến file không world-readable.
sudo chmod 644 "$ISO_FILENAME" 2>/dev/null || true
sha256sum "$ISO_FILENAME" > "${ISO_FILENAME}.sha256"
echo "Đã ghi ${ISO_FILENAME}.sha256:"
cat "${ISO_FILENAME}.sha256"
# GHI CHÚ: đây mới là checksum toàn vẹn (chống lỗi tải/hỏng file), KHÔNG
# phải chữ ký GPG (chống giả mạo nguồn) — ký GPG cần quản lý private key
# (vd qua GitHub Actions secret) nên chưa làm ở bước này.

echo "===== iso.sh xong ====="
