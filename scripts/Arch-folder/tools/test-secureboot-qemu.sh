#!/usr/bin/env bash
# test-secureboot-qemu.sh - Launches an ISO inside QEMU with UEFI Secure Boot enabled.
# Automatically discovers OVMF secboot firmware, provisions temporary NVRAM vars, and boots.
# Usage: ./tools/test-secureboot-qemu.sh [OPTIONS] ISO_FILE
set -euo pipefail

# Options
SECURE_BOOT=1
HEADLESS=0
RAM="4G"
CORES="4"
TIMEOUT=0
ISO=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-secure-boot) SECURE_BOOT=0; shift ;;
        --secure-boot)    SECURE_BOOT=1; shift ;;
        --headless)       HEADLESS=1; shift ;;
        --ram)            RAM="$2"; shift 2 ;;
        --smp)            CORES="$2"; shift 2 ;;
        --timeout)        TIMEOUT="$2"; shift 2 ;;
        -*) echo "Unknown option: $1" >&2; exit 1 ;;
        *) ISO="$1"; shift ;;
    esac
done

[[ -n "$ISO" ]] || {
    echo "Usage: $0 [--no-secure-boot] [--headless] [--ram 4G] [--smp 4] [--timeout N] ISO_FILE" >&2
    exit 1
}

[[ -f "$ISO" ]] || { echo "ISO file not found: $ISO" >&2; exit 1; }

# Locate OVMF Code and Vars
OVMF_CODE=""
OVMF_VARS=""

CODE_CANDIDATES=(
    "/usr/share/OVMF/OVMF_CODE_4M.secboot.fd"
    "/usr/share/OVMF/OVMF_CODE_4M.ms.fd"
    "/usr/share/edk2/x64/OVMF_CODE.secboot.fd"
    "/usr/share/edk2-ovmf/x64/OVMF_CODE.secboot.fd"
    "/usr/share/ovmf/x64/OVMF_CODE.fd"
)

VARS_CANDIDATES=(
    "/usr/share/OVMF/OVMF_VARS_4M.ms.fd"
    "/usr/share/OVMF/OVMF_VARS_4M.secboot.fd"
    "/usr/share/OVMF/OVMF_VARS_4M.fd"
    "/usr/share/edk2/x64/OVMF_VARS.secboot.fd"
    "/usr/share/edk2-ovmf/x64/OVMF_VARS.secboot.fd"
)

for c in "${CODE_CANDIDATES[@]}"; do
    if [[ -f "$c" ]]; then
        OVMF_CODE="$c"
        break
    fi
done

for v in "${VARS_CANDIDATES[@]}"; do
    if [[ -f "$v" ]]; then
        OVMF_VARS="$v"
        break
    fi
done

if [[ -z "$OVMF_CODE" ]]; then
    echo "Error: Could not find OVMF secboot firmware code image." >&2
    echo "Please install edk2-ovmf or ovmf." >&2
    exit 1
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

TEMP_VARS="$work/OVMF_VARS.fd"
if [[ -n "$OVMF_VARS" ]]; then
    cp "$OVMF_VARS" "$TEMP_VARS"
else
    # Create empty 4MB file if no template exists
    truncate -s 4M "$TEMP_VARS"
fi

QEMU_CMD=(qemu-system-x86_64)

# Hardware acceleration if available
if [[ -e /dev/kvm && -r /dev/kvm && -w /dev/kvm ]]; then
    QEMU_CMD+=(-enable-kvm -cpu host)
else
    QEMU_CMD+=(-cpu max)
fi

QEMU_CMD+=(
    -m "$RAM"
    -smp "$CORES"
    -drive "if=pflash,format=raw,readonly=on,file=$OVMF_CODE"
    -drive "if=pflash,format=raw,file=$TEMP_VARS"
    -cdrom "$ISO"
    -boot order=d,menu=on
    -net nic,model=virtio -net user
)

if [[ "$SECURE_BOOT" -eq 1 ]]; then
    QEMU_CMD+=(-machine q35,smm=on -global "ICH9-LPC.disable_s3=1")
    echo "==> UEFI Secure Boot: ENABLED"
else
    QEMU_CMD+=(-machine q35)
    echo "==> UEFI Secure Boot: DISABLED (Standard UEFI)"
fi

echo "  OVMF Code: $OVMF_CODE"
echo "  OVMF Vars: $TEMP_VARS"
echo "  ISO:       $ISO"

if [[ "$HEADLESS" -eq 1 ]]; then
    QEMU_CMD+=(-nographic -serial mon:stdio)
    echo "==> Running in HEADLESS mode"
else
    QEMU_CMD+=(-vga std -display gtk)
fi

if [[ "$TIMEOUT" -gt 0 ]]; then
    echo "==> Setting execution timeout to ${TIMEOUT}s..."
    timeout --preserve-status "$TIMEOUT" "${QEMU_CMD[@]}" || true
else
    "${QEMU_CMD[@]}"
fi
