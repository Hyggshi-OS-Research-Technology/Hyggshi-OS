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
sudo mksquashfs live-build/chroot live-build/image/live/filesystem.squashfs \
  -e boot -comp xz

echo "===== Prepare boot files (kernel + initrd) ====="
sudo cp live-build/chroot/boot/vmlinuz-* live-build/image/live/vmlinuz
sudo cp live-build/chroot/boot/initrd.img-* live-build/image/live/initrd

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
