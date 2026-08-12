#!/bin/bash
set -e
[ "$DEBUG_MODE" = "true" ] && set -x

echo "===== Unmount chroot ====="
sudo chroot live-build/chroot umount /proc || true
sudo chroot live-build/chroot umount /sys || true
sudo umount live-build/chroot/run || true
sudo umount live-build/chroot/dev || true

echo "===== Build squashfs ====="
mkdir -p live-build/image/live
sudo mksquashfs live-build/chroot live-build/image/live/filesystem.squashfs \
  -comp xz -b 1M -Xbcj x86

echo "===== Copy kernel + initrd ====="
if ! sudo ls live-build/chroot/boot/vmlinuz-* >/dev/null 2>&1 || \
   ! sudo ls live-build/chroot/boot/initrd.img-* >/dev/null 2>&1; then
  echo "LỖI: thiếu kernel" >&2; exit 1
fi
VMLINUZ_FILE=$(sudo ls -t live-build/chroot/boot/vmlinuz-* | head -n1)
INITRD_FILE=$(sudo ls -t live-build/chroot/boot/initrd.img-* | head -n1)
sudo cp "$VMLINUZ_FILE" live-build/image/live/vmlinuz
sudo cp "$INITRD_FILE" live-build/image/live/initrd

echo "===== Secure Boot ====="
sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends \
  shim-signed grub-efi-amd64-signed grub-efi-amd64-bin mtools dosfstools || true

SHIM_BIN=$(sudo find /usr/lib/shim -maxdepth 1 -iname 'shimx64.efi.signed*' 2>/dev/null | sort | tail -n1)
MM_BIN=$(sudo find /usr/lib/shim -maxdepth 1 -iname 'mmx64.efi*' 2>/dev/null | sort | tail -n1)
GRUB_SIGNED_BIN=$(sudo find /usr/lib/grub/x86_64-efi-signed -maxdepth 1 -iname 'grubx64.efi.signed*' 2>/dev/null | sort | tail -n1)

SECURE_BOOT_OK=false
if [ -n "$SHIM_BIN" ] && [ -n "$GRUB_SIGNED_BIN" ]; then
  SECURE_BOOT_OK=true
  EFI_STAGE=$(mktemp -d)
  mkdir -p "$EFI_STAGE/EFI/BOOT"
  sudo install -m 0644 "$SHIM_BIN" "$EFI_STAGE/EFI/BOOT/BOOTX64.EFI"
  sudo install -m 0644 "$GRUB_SIGNED_BIN" "$EFI_STAGE/EFI/BOOT/grubx64.efi"
  [ -n "$MM_BIN" ] && sudo install -m 0644 "$MM_BIN" "$EFI_STAGE/EFI/BOOT/mmx64.efi"
  sudo chown -R "$(id -u)":"$(id -g)" "$EFI_STAGE"
  for REDIRECT_DIR in "$EFI_STAGE/EFI/ubuntu" "$EFI_STAGE/EFI/debian" "$EFI_STAGE/EFI/BOOT"; do
    mkdir -p "$REDIRECT_DIR"
    cat <<'REDIR_EOF' > "$REDIRECT_DIR/grub.cfg"
search --file --no-floppy --set=hyggshi_root /boot/grub/grub.cfg
configfile ($hyggshi_root)/boot/grub/grub.cfg
REDIR_EOF
  done
  dd if=/dev/zero of=live-build/image/boot/grub/efi.img bs=1M count=16 status=none
  mkfs.vfat -n HYGGSHI_ESP live-build/image/boot/grub/efi.img >/dev/null
  mmd -i live-build/image/boot/grub/efi.img ::EFI ::EFI/BOOT
  mcopy -i live-build/image/boot/grub/efi.img -s "$EFI_STAGE"/EFI/BOOT/* ::EFI/BOOT/
  for d in ubuntu debian; do
    if [ -d "$EFI_STAGE/EFI/$d" ]; then
      mmd -i live-build/image/boot/grub/efi.img "::EFI/$d" 2>/dev/null || true
      mcopy -i live-build/image/boot/grub/efi.img "$EFI_STAGE/EFI/$d/grub.cfg" "::EFI/$d/" 2>/dev/null || true
    fi
  done
  rm -rf "$EFI_STAGE"
  mkdir -p live-build/image/EFI/BOOT
  sudo cp "$SHIM_BIN" live-build/image/EFI/BOOT/BOOTX64.EFI
  sudo cp "$GRUB_SIGNED_BIN" live-build/image/EFI/BOOT/grubx64.efi
  [ -n "$MM_BIN" ] && sudo cp "$MM_BIN" live-build/image/EFI/BOOT/mmx64.efi
  sudo chown -R "$(id -u)":"$(id -g)" live-build/image/EFI
fi

echo "===== Build ISO ====="
KERNEL_CMDLINE_EXTRA="quiet splash"
if [ "$BASE_DISTRO" = "debian" ]; then
  source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/kernel-tuning.sh"
  KERNEL_CMDLINE_EXTRA=$(hyggshi_kernel_cmdline_extra "${EDITION:-normal}")
fi

mkdir -p live-build/image/boot/grub
cat <<EOF > live-build/image/boot/grub/grub.cfg
set timeout=10
set default=0
menuentry "$DISTRO_NAME Live" {
  linux /live/vmlinuz boot=live $KERNEL_CMDLINE_EXTRA
  initrd /live/initrd
}
EOF

sudo grub-mkrescue -o "$ISO_FILENAME" live-build/image --compress=xz -- -volid "HYGGSHI_OS"

if [ "$SECURE_BOOT_OK" = "true" ]; then
  if xorriso -indev "$ISO_FILENAME" -outdev "${ISO_FILENAME}.secureboot" \
             -boot_image any replay \
             -map live-build/image/boot/grub/efi.img /boot/grub/efi.img \
             -update_r live-build/image/EFI /EFI \
             -commit 2> xorriso-secureboot.log; then
    mv "${ISO_FILENAME}.secureboot" "$ISO_FILENAME"
    echo "OK: Secure Boot patched."
  else
    echo "LỖI xorriso replay, giữ ISO gốc" >&2
    rm -f "${ISO_FILENAME}.secureboot"
  fi
fi

sudo chmod 644 "$ISO_FILENAME" 2>/dev/null || true
sha256sum "$ISO_FILENAME" > "${ISO_FILENAME}.sha256"
echo "===== iso.sh xong ====="
ls -lh "$ISO_FILENAME"
