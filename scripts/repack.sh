#!/bin/bash
# scripts/repack.sh — Bước 7: Đóng gói squashfs + ISO bootable
set -e
[ "${DEBUG_MODE:-false}" = "true" ] && set -x

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${WORK_DIR:-live-build}"
OUTPUT_ISO="${OUTPUT_ISO:-${ISO_FILENAME:-hyggshi-os.iso}}"
SQUASHFS_COMP="${SQUASHFS_COMP:-xz}"
SQUASHFS_OPTS="${SQUASHFS_OPTS:--b 1M -Xdict-size 100%}"
VOLID="${VOLID:-${ISO_VOLID:-${DISTRO_NAME:-Hyggshi-OS}}}"

info() { echo -e "ℹ️  $*"; }
ok()   { echo -e "✅ $*"; }
warn() { echo -e "⚠️  $*" >&2; }

ensure_work_tree() {
    mkdir -p "$WORK_DIR/squashfs" "$WORK_DIR/custom" 2>/dev/null || true
}

umount_chroot() {
    local SFS="$WORK_DIR/squashfs"
    [ -d "$WORK_DIR/chroot" ] && [ ! -d "$SFS" ] && SFS="$WORK_DIR/chroot"
    sudo umount -lf "$SFS/dev/pts" 2>/dev/null || true
    sudo umount -lf "$SFS/dev" 2>/dev/null || true
    sudo chroot "$SFS" umount /proc 2>/dev/null || sudo umount -lf "$SFS/proc" 2>/dev/null || true
    sudo chroot "$SFS" umount /sys 2>/dev/null || sudo umount -lf "$SFS/sys" 2>/dev/null || true
    sudo umount -lf "$SFS/run" 2>/dev/null || true
    sudo umount -lf "$SFS/var/cache/apt/archives" 2>/dev/null || true
}

clean_virtual_dirs() {
    local SFS="$WORK_DIR/squashfs"
    [ -d "$WORK_DIR/chroot" ] && [ ! -d "$SFS" ] && SFS="$WORK_DIR/chroot"

    # Dọn file tạm trước khi pack. Nếu build bị Ctrl+C giữa hook
    # (đặc biệt WPS repack cũ), /tmp có thể còn .deb/data.tar.xz/opt rất lớn
    # và make quick sẽ vô tình đóng gói chúng vào ISO.
    sudo rm -rf "$SFS/tmp"/* "$SFS/tmp"/.* "$SFS/var/tmp"/* "$SFS/var/tmp"/.* 2>/dev/null || true

    # Đảm bảo các virtual fs dir trống sạch trước khi pack vào squashfs.
    # KHÔNG dùng -e proc/sys/dev/run để loại trừ — nếu loại trừ, các thư mục
    # này sẽ KHÔNG TỒN TẠI trong squashfs, casper sẽ không có chỗ để mount
    # devtmpfs/proc/sysfs vào → /dev/null không tồn tại → boot crash.
    # Các dir phải có mặt nhưng TRỐNG; chúng đã được umount ở step_customize.
    for dir in proc sys dev run; do
        if [ -d "$SFS/$dir" ]; then
            # Xoá nội dung bên trong nhưng giữ thư mục gốc
            sudo find "$SFS/$dir" -mindepth 1 -delete 2>/dev/null || true
        else
            # Thư mục không tồn tại → tạo lại để casper có chỗ mount
            sudo mkdir -p "$SFS/$dir"
        fi
    done
}

step_repack_squashfs() {
    ensure_work_tree
    umount_chroot
    clean_virtual_dirs

    local SFS="$WORK_DIR/squashfs"
    [ -d "$WORK_DIR/chroot" ] && [ ! -d "$SFS" ] && SFS="$WORK_DIR/chroot"

    local CUSTOM="$WORK_DIR/custom"
    [ -d "$WORK_DIR/image" ] && [ ! -d "$CUSTOM" ] && CUSTOM="$WORK_DIR/image"

    local CASPER_DIR="$CUSTOM/casper"
    if [ ! -d "$CASPER_DIR" ] && [ -d "$CUSTOM/live" ]; then
        CASPER_DIR="$CUSTOM/live"
    fi
    sudo mkdir -p "$CASPER_DIR"

    info "  → Tạo filesystem.squashfs (${SQUASHFS_COMP})..."
    sudo mksquashfs "$SFS" "$CASPER_DIR/filesystem.squashfs" \
        -comp "$SQUASHFS_COMP" $SQUASHFS_OPTS
    ok "squashfs xong."

    # Cập nhật filesystem.size
    local SFS_SIZE
    SFS_SIZE="$(sudo du -sx --block-size=1 "$SFS" | cut -f1)"
    printf '%s' "$SFS_SIZE" | sudo tee "$CASPER_DIR/filesystem.size" >/dev/null

    # Live ISO boot dùng build/custom/casper/initrd.lz, KHÔNG tự dùng file
    # /boot/initrd.img-* trong squashfs. Hook Plymouth đã regenerate initramfs
    # trong rootfs, nên phải copy file mới này ra casper/initrd.lz.
    local latest_initrd
    latest_initrd=$(sudo ls -1t "$SFS"/boot/initrd.img-* 2>/dev/null | head -1 || true)
    local latest_vmlinuz
    latest_vmlinuz=$(sudo ls -1t "$SFS"/boot/vmlinuz-* 2>/dev/null | head -1 || true)

    if [ -n "$latest_vmlinuz" ] && sudo test -f "$latest_vmlinuz"; then
        sudo cp "$latest_vmlinuz" "$CASPER_DIR/vmlinuz"
    fi

    if [ -n "$latest_initrd" ] && sudo test -f "$latest_initrd"; then
        if [ -d "$CUSTOM/casper" ]; then
            sudo cp "$latest_initrd" "$CUSTOM/casper/initrd.lz"
            ok "live initrd đã cập nhật: $(basename "$latest_initrd") → casper/initrd.lz"
        else
            sudo cp "$latest_initrd" "$CASPER_DIR/initrd"
            ok "live initrd đã cập nhật: $(basename "$latest_initrd") → $CASPER_DIR/initrd"
        fi
    else
        warn "không tìm thấy initrd.img-* trong rootfs để cập nhật casper/initrd.lz"
    fi
}

step_repack_iso() {
    ensure_work_tree

    local CUSTOM="$WORK_DIR/custom"
    [ -d "$WORK_DIR/image" ] && [ ! -d "$CUSTOM" ] && CUSTOM="$WORK_DIR/image"

    # Cập nhật md5sum
    info "  → Cập nhật md5sum.txt..."
    (
        cd "$CUSTOM"
        sudo rm -f md5sum.txt
        sudo find . -type f ! -name 'md5sum.txt' ! -path './boot/grub/efi.img' -print0 | xargs -0 sudo md5sum | sudo tee md5sum.txt >/dev/null || true
    )

    # Tạo ISO — detect boot structure từ ISO Mint / Debian
    info "  → Tạo ISO..."

    local SAFE_VOLID
    SAFE_VOLID=$(printf '%s' "$VOLID" | tr ' ' '_' | cut -c1-32)

    XORRISO_ARGS=(
        -as mkisofs
        -iso-level 3
        -full-iso9660-filenames
        -volid "$SAFE_VOLID"
    )

    # BIOS boot: isolinux (Mint) hoặc GRUB
    if [ -f "$CUSTOM/isolinux/isolinux.bin" ]; then
        info "    Boot: isolinux (BIOS)"
        XORRISO_ARGS+=(
            -b isolinux/isolinux.bin
            -c isolinux/boot.cat
            -no-emul-boot -boot-load-size 4 -boot-info-table
        )
    elif [ -f "$CUSTOM/boot/grub/bios.img" ]; then
        info "    Boot: GRUB (BIOS)"
        XORRISO_ARGS+=(
            -eltorito-boot boot/grub/bios.img
            -no-emul-boot -boot-load-size 4 -boot-info-table
            --grub2-boot-info --grub2-mbr /usr/lib/grub/i386-pc/boot_hybrid.img
        )
    elif [ -f "$CUSTOM/boot/grub/i386-pc/eltorito.img" ]; then
        info "    Boot: GRUB i386-pc"
        XORRISO_ARGS+=(
            -b boot/grub/i386-pc/eltorito.img
            -no-emul-boot -boot-load-size 4 -boot-info-table
            --grub2-boot-info
        )
        [ -f /usr/lib/grub/i386-pc/boot_hybrid.img ] && XORRISO_ARGS+=(--grub2-mbr /usr/lib/grub/i386-pc/boot_hybrid.img)
    fi

    # UEFI boot
    if [ -f "$CUSTOM/EFI/boot/efiboot.img" ]; then
        info "    Boot: EFI"
        XORRISO_ARGS+=(
            -eltorito-alt-boot
            -e EFI/boot/efiboot.img
            -no-emul-boot
            -append_partition 2 0xef EFI/boot/efiboot.img
        )
    elif [ -f "$CUSTOM/boot/grub/efi.img" ]; then
        info "    Boot: GRUB EFI"
        XORRISO_ARGS+=(
            -eltorito-alt-boot
            -e boot/grub/efi.img
            -no-emul-boot
            -append_partition 2 0xef boot/grub/efi.img
        )
    fi

    # Isohybrid (cho ghi USB)
    if [ -f "$CUSTOM/isolinux/isolinux.bin" ] && [ -f /usr/lib/ISOLINUX/isohdpfx.bin ]; then
        XORRISO_ARGS+=(-isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin)
    elif [ -f "$CUSTOM/isolinux/isolinux.bin" ] && [ -f /usr/lib/syslinux/isohdpfx.bin ]; then
        XORRISO_ARGS+=(-isohybrid-mbr /usr/lib/syslinux/isohdpfx.bin)
    fi

    local TARGET_OUT="$OUTPUT_ISO"
    if [[ "$TARGET_OUT" != /* ]]; then
        TARGET_OUT="$SCRIPT_DIR/$OUTPUT_ISO"
    fi

    XORRISO_ARGS+=(-output "$TARGET_OUT" .)

    (cd "$CUSTOM" && sudo xorriso "${XORRISO_ARGS[@]}")
    ok "Đã tạo ISO: $TARGET_OUT"
}

step_repack() {
    info "[7/7] Đóng gói ISO..."
    step_repack_squashfs
    step_repack_iso
}

safe_remove_work_dirs() {
    info "Dọn dẹp thư mục tạm..."
    sudo rm -rf "$WORK_DIR/tmp" 2>/dev/null || true
}

step_repack_and_clean() {
    step_repack
    safe_remove_work_dirs
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    step_repack
fi
