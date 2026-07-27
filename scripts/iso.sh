#!/bin/bash
# iso.sh — unmount chroot, build squashfs, đóng gói thành ISO bootable (grub).
# Chạy trên HOST.
set -e
[ "$DEBUG_MODE" = "true" ] && set -x

echo "===== Unmount chroot filesystems ====="
sudo chroot live-build/chroot umount /proc || true
sudo chroot live-build/chroot umount /sys || true
sudo umount live-build/chroot/run || true
sudo umount live-build/chroot/dev || true

echo "===== Build squashfs from chroot ====="
mkdir -p live-build/image/live
# LƯU Ý: KHÔNG loại trừ /boot (-e boot) khỏi squashfs. Nếu loại trừ, hệ
# thống live boot vẫn chạy được (vì /live/vmlinuz và /live/initrd được GRUB
# nạp trực tiếp từ ISO, không qua squashfs) — nhưng sau khi Calamares cài
# đặt (chép squashfs vào đĩa) thì /boot của hệ thống ĐÃ CÀI sẽ trống rỗng
# (không có vmlinuz/initrd/System.map/config, cũng không có sẵn để
# grub-install/update-grub chạy trong target), khiến máy sau khi cài xong
# không boot được. Đây chính là lỗi Calamares hay gặp trước đây.
sudo mksquashfs live-build/chroot live-build/image/live/filesystem.squashfs \
  -comp xz

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

echo "===== Build bootable ISO with grub ====="
mkdir -p live-build/image/boot/grub
cat <<EOF > live-build/image/boot/grub/grub.cfg
set timeout=10
set default=0
menuentry "$DISTRO_NAME Live" {
  linux /live/vmlinuz boot=live quiet splash
  initrd /live/initrd
}
EOF

sudo grub-mkrescue -o "$ISO_FILENAME" live-build/image \
  --compress=xz -- -volid "HYGGSHI_OS"

ls -lh "$ISO_FILENAME"
echo "===== iso.sh xong ====="
