#!/usr/bin/env bash
# run-qemu.sh — boot the built Hyggshi OS ISO with a persistent virtual disk.
# This avoids the common Calamares error shown on the Welcome page when QEMU
# is started with only -cdrom and no HDD/SSD attached.
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ISO="${1:-$ROOT_DIR/hyggshi-os-local.iso}"
DISK="${2:-$ROOT_DIR/build/hyggshi-test.qcow2}"
DISK_SIZE="${QEMU_DISK_SIZE:-32G}"
RAM="${QEMU_RAM:-4G}"
SMP="${QEMU_SMP:-4}"

if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
  echo "ERROR: qemu-system-x86_64 is not installed." >&2
  echo "Ubuntu/Mint: sudo apt install qemu-system-x86 qemu-utils" >&2
  exit 1
fi

if [ ! -f "$ISO" ]; then
  echo "ERROR: ISO not found: $ISO" >&2
  exit 1
fi

mkdir -p "$(dirname "$DISK")"
if [ ! -f "$DISK" ]; then
  echo "===== Creating QEMU test disk: $DISK_SIZE ====="
  qemu-img create -f qcow2 "$DISK" "$DISK_SIZE"
fi

QEMU_ARGS=(
  -enable-kvm
  -m "$RAM"
  -smp "$SMP"
  -machine q35
  -cpu host
  -display gtk,gl=on
  -boot order=d
  -cdrom "$ISO"
  -drive "file=$DISK,if=virtio,format=qcow2,cache=writeback"
  -nic user,model=virtio-net-pci
)

# Prefer UEFI when OVMF is installed; otherwise run BIOS mode.
OVMF_CODE=""
OVMF_VARS=""
for code in \
  /usr/share/OVMF/OVMF_CODE_4M.fd \
  /usr/share/edk2/ovmf/x64/OVMF_CODE.fd \
  /usr/share/OVMF/OVMF_CODE.fd; do
  if [ -f "$code" ]; then OVMF_CODE="$code"; break; fi
done
for vars in \
  /usr/share/OVMF/OVMF_VARS_4M.fd \
  /usr/share/edk2/ovmf/x64/OVMF_VARS.fd \
  /usr/share/OVMF/OVMF_VARS.fd; do
  if [ -f "$vars" ]; then OVMF_VARS="$vars"; break; fi
done

if [ -n "$OVMF_CODE" ] && [ -n "$OVMF_VARS" ]; then
  VARS_COPY="${DISK}.uefi-vars.fd"
  if [ ! -f "$VARS_COPY" ]; then
    cp "$OVMF_VARS" "$VARS_COPY"
  fi
  QEMU_ARGS+=(
    -drive "if=pflash,format=raw,readonly=on,file=$OVMF_CODE"
    -drive "if=pflash,format=raw,file=$VARS_COPY"
  )
  echo "UEFI: $OVMF_CODE"
else
  echo "OVMF not found — starting QEMU in legacy BIOS mode."
fi

echo "ISO : $ISO"
echo "DISK: $DISK"
echo "RAM : $RAM"
echo "SMP : $SMP"
echo
echo "Calamares should now see /dev/vda (or /dev/sda) as an installation target."
exec qemu-system-x86_64 "${QEMU_ARGS[@]}"
