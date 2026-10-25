#!/usr/bin/env bash
# Make a built Hyggshi/archiso ISO bootable with UEFI Secure Boot (via shim + MOK).
#
#   secureboot-iso.sh IN.iso OUT.iso SB.key SB.crt
#
# What it does
#   * signs the kernel (and memtest/UEFI shell if present) and the standalone GRUB with SB.key
#   * puts Microsoft-signed shim at EFI/BOOT/BOOTx64.EFI, GRUB as grubx64.efi, plus MokManager
#   * puts the public certificate (hyggshi-secureboot.cer) in the EFI partition so it can be
#     enrolled with "Enroll key from disk" on the first boot
#   * rebuilds the ISO with the same boot setup mkarchiso uses (BIOS syslinux + UEFI GRUB)
#
# Needs: xorriso mtools dosfstools sbsigntool openssl util-linux(sfdisk) and the Ubuntu/Debian
# `shim-signed` package (or SHIM_DIR pointing at shimx64.efi.signed + mmx64.efi).
set -euo pipefail

in_iso=${1:?usage: $0 IN.iso OUT.iso SB.key SB.crt}
out_iso=${2:?}
key=${3:?}
crt=${4:?}
SHIM_DIR=${SHIM_DIR:-/usr/lib/shim}

shim=$SHIM_DIR/shimx64.efi.signed
[[ -f $shim ]] || shim=$SHIM_DIR/shimx64.efi.signed.latest
mm=$SHIM_DIR/mmx64.efi
for f in "$in_iso" "$key" "$crt" "$shim" "$mm"; do [[ -f $f ]] || { echo "missing file: $f" >&2; exit 1; }; done
for t in xorriso mcopy mkfs.fat sbsign sbverify openssl sfdisk dd; do
    command -v "$t" >/dev/null || { echo "missing tool: $t" >&2; exit 1; }
done

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
tree=$work/tree; esp=$work/esp
mkdir -p "$tree" "$esp"

echo "==> Extracting ISO contents"
xorriso -no_rc -osirrox on -indev "$in_iso" -extract / "$tree" 2>&1 | grep -vE '^(xorriso|Drive|Media|Boot|Volume|libisofs|ISO image|$)' || true
chmod -R u+rwX "$tree"
[[ -f $tree/EFI/BOOT/BOOTx64.EFI ]] || { echo "no EFI/BOOT/BOOTx64.EFI in ISO (is this an uefi.grub archiso image?)" >&2; exit 1; }
[[ -f $tree/boot/syslinux/isolinux.bin && -f $tree/boot/syslinux/isohdpfx.bin ]] \
    || { echo "syslinux files missing; unexpected ISO layout" >&2; exit 1; }

echo "==> Reading the EFI system partition"
read -r start size < <(sfdisk -J "$in_iso" | python3 -c '
import json,sys
p=json.load(sys.stdin)["partitiontable"]["partitions"]
efi=[x for x in p if x.get("type","").lower() in ("ef","c12a7328-f81f-11d2-ba4b-00a0c93ec93b")] or p
x=efi[-1]; print(x["start"], x["size"])')
dd if="$in_iso" of="$work/esp-old.img" bs=512 skip="$start" count="$size" status=none
mcopy -s -n -i "$work/esp-old.img" ::/ "$esp/"
[[ -d $esp/EFI/BOOT ]] || { echo "EFI partition does not look like an archiso ESP" >&2; exit 1; }

sign() { sbsign --key "$key" --cert "$crt" --output "$1.signed" "$1" >/dev/null && mv -f "$1.signed" "$1"; }

echo "==> Signing GRUB, kernel and extra EFI binaries"
cp "$tree/EFI/BOOT/BOOTx64.EFI" "$work/grubx64.efi"
sign "$work/grubx64.efi"
kernels=("$tree"/arch/boot/x86_64/vmlinuz-*)
[[ -f ${kernels[0]} ]] || { echo "kernel not found under arch/boot/x86_64" >&2; exit 1; }
for k in "${kernels[@]}"; do sign "$k"; done
for f in "$tree"/boot/memtest86+/memtest.efi "$tree"/shellx64.efi "$esp"/shellx64.efi; do
    [[ -f $f ]] && sign "$f"
done

echo "==> Installing shim, MokManager and the certificate"
openssl x509 -in "$crt" -outform DER -out "$work/hyggshi-secureboot.cer"
for d in "$tree" "$esp"; do
    install -m 0644 "$shim"               "$d/EFI/BOOT/BOOTx64.EFI"
    install -m 0644 "$work/grubx64.efi"   "$d/EFI/BOOT/grubx64.efi"
    install -m 0644 "$mm"                 "$d/EFI/BOOT/mmx64.efi"
    install -m 0644 "$work/hyggshi-secureboot.cer" "$d/EFI/BOOT/hyggshi-secureboot.cer"
    install -m 0644 "$work/hyggshi-secureboot.cer" "$d/hyggshi-secureboot.cer"
done

echo "==> Building the new EFI system partition image"
kib=$(du -sk "$esp" | awk '{print $1}')
img_kib=$(( (kib / 1024 + 16) * 1024 ))
fat_opts=(-C -n ARCHISO_EFI)
(( img_kib >= 36864 )) && fat_opts+=(-F 32)
rm -f "$work/efiboot.img"
mkfs.fat "${fat_opts[@]}" "$work/efiboot.img" "$img_kib" >/dev/null
( cd "$esp" && mcopy -s -i "$work/efiboot.img" ./* ::/ )

echo "==> Rebuilding the ISO"
pvd=$(xorriso -no_rc -indev "$in_iso" -pvd_info 2>&1)
field() { printf '%s\n' "$pvd" | sed -n "s/^$1 *: *//p" | head -n1; }
volid=$(field 'Volume Id'); publisher=$(field 'Publisher Id'); appid=$(field 'App Id')
mod_time=$(field 'Modif. Time' | xargs)
[[ -n $volid ]] || { echo "could not read the volume id" >&2; exit 1; }

# Preserve modification timestamp so that the ISO filesystem UUID matches %ARCHISO_UUID%
if [[ -z "$mod_time" ]]; then
    uuid_file=$(find "$tree/boot" -maxdepth 1 -name "*.uuid" -printf "%f\n" 2>/dev/null | head -n1)
    if [[ -n "$uuid_file" ]]; then
        mod_time="${uuid_file%.uuid}"
        mod_time="${mod_time//[^0-9]/}"
    fi
fi

if [[ -n "$mod_time" && ${#mod_time} -ge 14 ]]; then
    iso_epoch=$(date -u -d "${mod_time:0:4}-${mod_time:4:2}-${mod_time:6:2} ${mod_time:8:2}:${mod_time:10:2}:${mod_time:12:2}" +%s 2>/dev/null || true)
    if [[ -n "$iso_epoch" ]]; then
        export SOURCE_DATE_EPOCH="$iso_epoch"
    fi
fi

extra=()
(( $(du -s --apparent-size -B1M "$tree" | awk '{print $1}') > 900 )) && extra+=(-no-pad)
[[ -n "$mod_time" ]] && extra+=(--modification-date="$mod_time")

rm -f "$out_iso"
xorriso -no_rc -as mkisofs \
    -iso-level 3 -full-iso9660-filenames -joliet -joliet-long -rational-rock \
    -volid "$volid" -appid "$appid" -publisher "$publisher" -preparer "prepared by mkarchiso + secureboot-iso.sh" \
    -eltorito-boot boot/syslinux/isolinux.bin -eltorito-catalog boot/syslinux/boot.cat \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    -isohybrid-mbr "$tree/boot/syslinux/isohdpfx.bin" --mbr-force-bootable \
    -partition_offset 16 \
    -append_partition 2 C12A7328-F81F-11D2-BA4B-00A0C93EC93B "$work/efiboot.img" \
    -isohybrid-gpt-basdat \
    -eltorito-alt-boot -e --interval:appended_partition_2:all:: -no-emul-boot \
    "${extra[@]}" \
    -output "$out_iso" "$tree/" >/dev/null

echo "==> Verifying"
sbverify --cert "$crt" "${kernels[0]}" >/dev/null && echo "  kernel signature OK"
sbverify --cert "$crt" "$work/grubx64.efi" >/dev/null && echo "  grub signature OK"
sfdisk -d "$out_iso" | grep -q 'type=ef\|C12A7328' && echo "  EFI partition present"
in_uuid=$(blkid -s UUID -o value "$in_iso" 2>/dev/null || true)
out_uuid=$(blkid -s UUID -o value "$out_iso" 2>/dev/null || true)
echo "  in_iso UUID:  $in_uuid"
echo "  out_iso UUID: $out_uuid"
if [[ -n "$in_uuid" && -n "$out_uuid" && "$in_uuid" != "$out_uuid" ]]; then
    echo "::error::UUID mismatch between original ($in_uuid) and signed ($out_uuid)!"
    exit 1
fi
echo "Done: $out_iso"
echo "First boot with Secure Boot ON: choose 'Enroll key from disk' in MokManager and pick hyggshi-secureboot.cer."
