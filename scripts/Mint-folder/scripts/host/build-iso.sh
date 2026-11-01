#!/bin/bash
# iso.sh — unmount chroot, build squashfs, đóng gói thành ISO bootable (grub).
# Chạy trên HOST.
set -e
[ "$DEBUG_MODE" = "true" ] && set -x

echo "===== Unmount chroot filesystems ====="
sudo chroot build/chroot umount /proc || true
sudo chroot build/chroot umount /sys || true
sudo umount build/chroot/run || true
sudo umount build/chroot/dev || true
# Bind-mount cache .deb (xem step "Mount apt cache vào chroot" trong
# workflow) PHẢI được unmount trước khi mksquashfs — nếu không toàn bộ
# .deb đã tải sẽ bị đóng gói lẫn vào filesystem.squashfs, làm ISO phình to
# vô ích (những .deb này chỉ cần tồn tại trên HOST để actions/cache lưu
# lại dùng cho lần build sau, không cần có trong ISO cuối cùng).
sudo umount build/chroot/var/cache/apt/archives || true

echo "===== Build squashfs from chroot ====="
mkdir -p build/image/live
# QUAN TRỌNG: KHÔNG loại trừ /boot khỏi squashfs. Nếu loại trừ (-e boot),
# hệ thống live boot vẫn chạy được (vì /live/vmlinuz và /live/initrd được
# GRUB nạp trực tiếp từ ISO, không qua squashfs) — NHƯNG sau khi Calamares
# cài đặt (chép squashfs vào đĩa) thì /boot của hệ thống ĐÃ CÀI sẽ trống
# rỗng (không có vmlinuz/initrd/System.map/config, cũng không có sẵn để
# grub-install/update-grub chạy trong target). Kết quả: lỗi "grub-pc has
# no installation candidate" + "update-grub: No such file or directory".
#
# Nén bằng zstd thay vì xz: đây là bước tốn thời gian nhất trong cả pipeline
# (~18 phút với xz trên runner CI). zstd multi-threaded (-processors) nén
# nhanh hơn xz đáng kể (thường giảm 40-60% thời gian build squashfs) với
# dung lượng ISO chỉ nhỉnh hơn xz một chút không đáng kể — đánh đổi rất
# đáng vì đây là bottleneck chính của cả build.
#   -b 1M                     giữ nguyên block size 1MiB như bản xz cũ, cho
#                              tỷ lệ nén tốt trên nhiều file lặp lại (icon
#                              theme, locale, lib...).
#   -Xcompression-level 19    mức nén zstd (1-22). 19 cân bằng tốt giữa tốc
#                              độ và dung lượng; hạ xuống ~12-15 nếu vẫn cần
#                              nhanh hơn nữa và chấp nhận ISO to hơn 1 chút.
#   -processors $(nproc)      dùng hết số core runner có (mksquashfs hỗ trợ
#                              nén đa luồng với zstd, không như xz vốn gần
#                              như đơn luồng ở phần nén chính).
# LƯU Ý: KHÔNG dùng -Xbcj x86 nữa — filter BCJ đó chỉ dành riêng cho xz,
# zstd không hỗ trợ (mksquashfs sẽ báo lỗi option không hợp lệ nếu giữ lại).
sudo mksquashfs build/chroot build/image/live/filesystem.squashfs \
  -comp zstd -b 1M -Xcompression-level 19 -processors "$(nproc)"

echo "===== Prepare boot files (kernel + initrd) ====="
# Dùng ls -t + head -n1 thay vì cp trực tiếp theo glob: nếu vì lý do gì đó
# /boot có nhiều hơn 1 vmlinuz-*/initrd.img-* (ví dụ update kernel giữa
# chừng), cp với nhiều nguồn vào 1 đích sẽ lỗi "target is not a directory".
# Luôn lấy bản mới nhất theo thời gian sửa đổi.
if ! sudo ls build/chroot/boot/vmlinuz-* >/dev/null 2>&1 || \
   ! sudo ls build/chroot/boot/initrd.img-* >/dev/null 2>&1; then
  echo "LỖI: build/chroot/boot/ không có vmlinuz-*/initrd.img-*." >&2
  echo "Nguyên nhân nằm ở bước cài kernel trong desktop.sh (chạy trước iso.sh)," >&2
  echo "không phải ở iso.sh này. Kiểm tra lại log của desktop.sh." >&2
  echo "Nội dung /boot hiện có:" >&2
  sudo ls -la build/chroot/boot >&2 || true
  exit 1
fi
VMLINUZ_FILE=$(sudo ls -t build/chroot/boot/vmlinuz-* | head -n1)
INITRD_FILE=$(sudo ls -t build/chroot/boot/initrd.img-* | head -n1)
sudo cp "$VMLINUZ_FILE" build/image/live/vmlinuz
sudo cp "$INITRD_FILE" build/image/live/initrd

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
  build/chroot/boot/memtest86+x64.bin \
  build/chroot/boot/memtest86+.bin \
  build/chroot/usr/lib/memtest86+/memtest86+x64.bin \
  build/chroot/usr/lib/memtest86+/memtest86+.bin; do
  if sudo test -f "$CANDIDATE"; then
    MEMTEST_BIN="$CANDIDATE"
    break
  fi
done
if [ -z "$MEMTEST_BIN" ]; then
  FOUND=$(sudo find build/chroot/boot build/chroot/usr/lib/memtest86+ \
    -maxdepth 1 -iname 'memtest86+*.bin' 2>/dev/null | sort | head -n1)
  [ -n "$FOUND" ] && MEMTEST_BIN="$FOUND"
fi
if [ -n "$MEMTEST_BIN" ]; then
  sudo cp "$MEMTEST_BIN" build/image/live/memtest86+.bin
  sudo chown "$(id -u)":"$(id -g)" build/image/live/memtest86+.bin
  echo "OK: đã chép memtest86+ ($MEMTEST_BIN) -> build/image/live/memtest86+.bin"
else
  echo "CẢNH BÁO: không tìm thấy binary memtest86+ trong chroot — bỏ qua mục 'Kiểm tra RAM' trong GRUB." >&2
fi

echo "===== UEFI Secure Boot: cài shim + GRUB đã ký (chain of trust Microsoft/Canonical) ====="
# VẤN ĐỀ CŨ: grub-mkrescue tự build core.efi CHO CHÍNH NÓ, và core.efi đó
# KHÔNG hề được ký — firmware bật Secure Boot chặn ngay ở bước nạp
# BOOTX64.EFI ("not trusted" / rơi vào Secure Boot violation screen).
#
# CHUỖI TIN CẬY ĐÚNG (giống hệt Ubuntu/Debian live ISO thật):
#   firmware (tin sẵn Microsoft 3rd Party UEFI CA)
#     -> shimx64.efi   (ký bởi Microsoft — gói shim-signed)
#     -> grubx64.efi   (ký bởi Canonical, shim tin CA của Canonical nhúng sẵn
#                        bên trong nó — gói grub-efi-amd64-signed, KHÔNG PHẢI
#                        bản grub-mkrescue tự build)
#     -> grub.cfg -> kernel/initrd
# Runner là ubuntu-latest nên dùng shim/grub bản Canonical ký (cùng gốc CA
# Microsoft mà hầu hết firmware OEM đã tin sẵn).
sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends \
  shim-signed grub-efi-amd64-signed grub-efi-amd64-bin mtools dosfstools \
  || echo "CẢNH BÁO: apt-get install gói secure-boot thất bại, sẽ fallback bên dưới."

SHIM_BIN=$(sudo find /usr/lib/shim -maxdepth 1 -iname 'shimx64.efi.signed*' 2>/dev/null | sort | tail -n1)
MM_BIN=$(sudo find /usr/lib/shim -maxdepth 1 -iname 'mmx64.efi*' 2>/dev/null | sort | tail -n1)
GRUB_SIGNED_BIN=$(sudo find /usr/lib/grub/x86_64-efi-signed -maxdepth 1 -iname 'grubx64.efi.signed*' 2>/dev/null | sort | tail -n1)

if [ -z "$SHIM_BIN" ] || [ -z "$GRUB_SIGNED_BIN" ]; then
  SECURE_BOOT_OK=false
  echo "CẢNH BÁO: không tìm thấy shim/grub ĐÃ KÝ trên runner này." >&2
  echo "  shimx64.efi.signed*: ${SHIM_BIN:-<không thấy>}" >&2
  echo "  grubx64.efi.signed*: ${GRUB_SIGNED_BIN:-<không thấy>}" >&2
  echo "-> Fallback: build ISO như CŨ bằng grub-mkrescue (vẫn boot bình" >&2
  echo "   thường ở máy TẮT Secure Boot, giống hệt hành vi trước bản vá này)." >&2
else
  SECURE_BOOT_OK=true
  echo "OK: shim=$SHIM_BIN"
  echo "OK: grub(signed)=$GRUB_SIGNED_BIN"
  echo "OK: mokmanager=${MM_BIN:-<không có, bỏ qua — không bắt buộc để boot>}"
fi

mkdir -p build/image/boot/grub

if [ "$SECURE_BOOT_OK" = "true" ]; then
  echo "===== Dựng EFI System Partition (FAT) chứa shim + grub đã ký ====="
  EFI_STAGE=$(mktemp -d)
  mkdir -p "$EFI_STAGE/EFI/BOOT"
  # BOOTX64.EFI = shim (KHÔNG phải grub) — đây là file đầu tiên firmware nạp.
  sudo install -m 0644 "$SHIM_BIN" "$EFI_STAGE/EFI/BOOT/BOOTX64.EFI"
  sudo install -m 0644 "$GRUB_SIGNED_BIN" "$EFI_STAGE/EFI/BOOT/grubx64.efi"
  [ -n "$MM_BIN" ] && sudo install -m 0644 "$MM_BIN" "$EFI_STAGE/EFI/BOOT/mmx64.efi"
  sudo chown -R "$(id -u)":"$(id -g)" "$EFI_STAGE"

  # grubx64.efi bản ký sẵn của Canonical có prefix nhúng cứng lúc build
  # (thường trỏ /EFI/ubuntu/grub.cfg) mà ta không đổi được vì đã ký. Thay vì
  # đoán đúng 1 path, đặt SẴN 1 grub.cfg "dẫn hướng" ở TẤT CẢ path hay gặp
  # trong thực tế — mỗi file chỉ có 2 dòng, tự tìm và nạp lại config thật ở
  # /boot/grub/grub.cfg (đã sinh phía trên) trên chính ISO đang boot.
  for REDIRECT_DIR in "$EFI_STAGE/EFI/ubuntu" "$EFI_STAGE/EFI/BOOT"; do
    mkdir -p "$REDIRECT_DIR"
    cat <<'REDIR_EOF' > "$REDIRECT_DIR/grub.cfg"
search --file --no-floppy --set=hyggshi_root /boot/grub/grub.cfg
configfile ($hyggshi_root)/boot/grub/grub.cfg
REDIR_EOF
  done

  # File efi.img này là thứ firmware THỰC SỰ đọc lúc boot UEFI (El Torito
  # "no emulation" boot image) — không phải cây thư mục ISO9660 phía trên.
  # 16MiB dư dả cho shim + grub + mokmanager (thường chỉ ~2-3MiB tổng).
  dd if=/dev/zero of=build/image/boot/grub/efi.img bs=1M count=16 status=none
  mkfs.vfat -n HYGGSHI_ESP build/image/boot/grub/efi.img >/dev/null
  mmd -i build/image/boot/grub/efi.img ::EFI ::EFI/BOOT
  mcopy -i build/image/boot/grub/efi.img -s "$EFI_STAGE"/EFI/BOOT/* ::EFI/BOOT/
  for d in ubuntu; do
    if [ -d "$EFI_STAGE/EFI/$d" ]; then
      mmd -i build/image/boot/grub/efi.img "::EFI/$d" 2>/dev/null || true
      mcopy -i build/image/boot/grub/efi.img "$EFI_STAGE/EFI/$d/grub.cfg" "::EFI/$d/" 2>/dev/null || true
    fi
  done
  rm -rf "$EFI_STAGE"

  # Cũng chép các file .efi này vào cây ISO9660 thường (một số firmware đọc
  # trực tiếp /EFI/BOOT/ trên volume ISO thay vì el-torito efi.img).
  mkdir -p build/image/EFI/BOOT
  sudo cp "$SHIM_BIN" build/image/EFI/BOOT/BOOTX64.EFI
  sudo cp "$GRUB_SIGNED_BIN" build/image/EFI/BOOT/grubx64.efi
  [ -n "$MM_BIN" ] && sudo cp "$MM_BIN" build/image/EFI/BOOT/mmx64.efi
  sudo chown -R "$(id -u)":"$(id -g)" build/image/EFI
fi

echo "===== Build bootable ISO with grub ====="
# Kernel cmdline thêm theo Edition — CHỈ áp dụng cho Debian (đúng phạm vi
# yêu cầu "arch và debian thêm tuỳ chọn chỉnh thông số kernel"); Ubuntu/Mint
# giữ nguyên "quiet splash" mặc định như trước.
KERNEL_CMDLINE_EXTRA="quiet splash"
if false; then
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

mkdir -p build/image/boot/grub

# ===== GRUB background: Hyggshi branding =====
# Nguồn cố định trong repo: ./config/branding/desktop-grub.png
# và ./config/branding/desktop-grub.svg. GRUB dùng PNG để render
# background; SVG vẫn được đóng gói kèm để giữ source branding/vector.
GRUB_BACKGROUND_APPLIED=false
if [ -f "config/branding/desktop-grub.png" ]; then
  sudo install -m 0644 "config/branding/desktop-grub.png" \
    build/image/boot/grub/desktop-grub.png
  # Ghi đè luôn bản desktop-base trong live filesystem nếu thư mục tồn tại.
  # Sau khi cài hệ thống, branding.sh sẽ áp lại vào /usr/share/images/desktop-base.
  sudo mkdir -p build/chroot/usr/share/images/desktop-base
  sudo install -m 0644 "config/branding/desktop-grub.png" \
    build/chroot/usr/share/images/desktop-base/desktop-grub.png
  GRUB_BACKGROUND_APPLIED=true
  echo "OK: GRUB background = config/branding/desktop-grub.png"
else
  echo "WARNING: không tìm thấy config/branding/desktop-grub.png — GRUB giữ nền mặc định."
fi

if [ -f "config/branding/desktop-grub.svg" ]; then
  sudo install -m 0644 "config/branding/desktop-grub.svg" \
    build/image/boot/grub/desktop-grub.svg
  sudo mkdir -p build/chroot/usr/share/images/desktop-base
  sudo install -m 0644 "config/branding/desktop-grub.svg" \
    build/chroot/usr/share/images/desktop-base/desktop-grub.svg
  echo "OK: đóng gói GRUB SVG = config/branding/desktop-grub.svg"
else
  echo "WARNING: không tìm thấy config/branding/desktop-grub.svg — bỏ qua SVG."
fi

{
  echo "set timeout=10"
  echo "set default=0"
  echo ""
  if [ "$GRUB_BACKGROUND_APPLIED" = "true" ]; then
    # Chuyển GRUB sang gfxterm và áp background PNG. Dùng if/then để nếu
    # firmware/GRUB thiếu module đồ hoạ thì menu text vẫn boot bình thường.
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
  if [ -f build/image/live/memtest86+.bin ]; then
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
} > build/image/boot/grub/grub.cfg

sudo grub-mkrescue -o "$ISO_FILENAME" build/image \
  --compress=xz -- -volid "HYGGSHI_OS"

if [ "$SECURE_BOOT_OK" = "true" ]; then
  echo "===== Ghi đè EFI image bằng bản đã build sẵn (shim+grub ký sẵn) ====="
  # grub-mkrescue ở trên VẪN tự sinh 1 boot/grub/efi.img + /EFI/BOOT/*.efi
  # RIÊNG của nó (KHÔNG ký) rồi mới đóng gói — nên phải "replay" lại đúng
  # cấu trúc El Torito/GPT nó vừa tạo (BIOS boot giữ nguyên, không đụng vào)
  # nhưng thay nội dung phần EFI bằng bộ shim/grub đã ký ở bước trên.
  # Đây là kỹ thuật chuẩn để "vá" Secure Boot vào 1 ISO grub-mkrescue có sẵn,
  # KHÔNG phải tự dựng lại toàn bộ ISO bằng tay (rủi ro sai offset El Torito
  # cao hơn nhiều so với replay từ 1 ISO grub-mkrescue đã build đúng).
  if xorriso -indev "$ISO_FILENAME" \
             -outdev "${ISO_FILENAME}.secureboot" \
             -boot_image any replay \
             -map build/image/boot/grub/efi.img /boot/grub/efi.img \
             -update_r build/image/EFI /EFI \
             -commit 2> xorriso-secureboot.log; then
    mv "${ISO_FILENAME}.secureboot" "$ISO_FILENAME"
    echo "OK: đã ghép shim/grub đã ký vào $ISO_FILENAME."
  else
    echo "LỖI: xorriso replay thất bại khi vá Secure Boot — xem xorriso-secureboot.log." >&2
    echo "GIỮ NGUYÊN ISO gốc (bootable ở máy TẮT Secure Boot, y hệt trước bản vá)." >&2
    rm -f "${ISO_FILENAME}.secureboot"
    cat xorriso-secureboot.log >&2 || true
  fi
  echo "LƯU Ý QUAN TRỌNG: bước vá Secure Boot này build theo đúng chuẩn kỹ" \
       "thuật shim+grub ký sẵn của Ubuntu/Debian, nhưng CHƯA được boot-test" \
       "thật bằng QEMU+OVMF (Secure Boot bật) trong môi trường build này." \
       "Khuyến nghị: test bằng QEMU+OVMF trước khi tin tưởng trên máy thật" \
       "(xem mục 'Test tự động sau build' còn thiếu, chưa làm ở bản vá này)."
else
  echo "Bỏ qua vá Secure Boot (SECURE_BOOT_OK=false) — ISO chỉ boot được khi TẮT Secure Boot, y hệt hành vi cũ."
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
