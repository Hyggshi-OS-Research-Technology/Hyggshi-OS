#!/usr/bin/env bash
# verify-secureboot.sh - Automated verification of UEFI Secure Boot chain for Hyggshi OS ISOs.
# Checks: Partition table, ESP, Shim, GRUB signature, Kernel signature, MOK cert, and UUIDs.
# Usage: ./tools/verify-secureboot.sh ISO_FILE [CERT_FILE]
set -euo pipefail

# Colors
C_RESET="\033[0m"
C_BOLD="\033[1m"
C_PASS="\033[38;2;158;206;106m"
C_FAIL="\033[38;2;247;118;142m"
C_WARN="\033[38;2;224;175;104m"
C_INFO="\033[38;2;122;162;247m"

pass() { echo -e "  ${C_PASS}✓${C_RESET} $1"; }
fail() { echo -e "  ${C_FAIL}✗${C_RESET} $1"; FAILED=1; }
warn() { echo -e "  ${C_WARN}!${C_RESET} $1"; }
info() { echo -e "${C_INFO}==>${C_RESET} ${C_BOLD}$1${C_RESET}"; }

if [[ "${1:-}" =~ ^(-h|--help)$ || $# -eq 0 ]]; then
    echo "Usage: $0 ISO_FILE [CERT_FILE]"
    exit 0
fi

ISO="$1"
CERT="${2:-}"
FAILED=0

[[ -f "$ISO" ]] || { echo "Error: ISO file '$ISO' not found" >&2; exit 1; }

for tool in sfdisk mcopy sbverify openssl xorriso dd; do
    command -v "$tool" >/dev/null || { echo "Missing required utility: $tool" >&2; exit 1; }
done

info "Analyzing Secure Boot Chain for: $(basename "$ISO")"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
esp_dir="$work/esp"
mkdir -p "$esp_dir"

# 1. Partition Table & ESP Check
info "1. Validating Partition Table & Hybrid MBR"
ptable=$(sfdisk -d "$ISO" 2>/dev/null || true)
if echo "$ptable" | grep -qiE 'type=ef|type=c12a7328-f81f-11d2-ba4b-00a0c93ec93b'; then
    pass "UEFI System Partition (ESP) found in partition table"
else
    fail "No EFI System Partition found in partition table"
fi

if dd if="$ISO" bs=1 count=2 skip=510 2>/dev/null | grep -q $'\x55\xaa'; then
    pass "Bootable MBR signature (0x55AA) verified"
else
    fail "Missing bootable MBR signature"
fi

# 2. Extract ESP
info "2. Extracting & Inspecting EFI System Partition (ESP)"
read -r start size < <(sfdisk -J "$ISO" 2>/dev/null | python3 -c '
import json,sys
try:
    p=json.load(sys.stdin)["partitiontable"]["partitions"]
    efi=[x for x in p if x.get("type","").lower() in ("ef","c12a7328-f81f-11d2-ba4b-00a0c93ec93b")] or p
    x=efi[-1]
    print(x["start"], x["size"])
except Exception:
    sys.exit(1)
')

if [[ -z "$start" || -z "$size" ]]; then
    fail "Could not determine ESP offset and size"
else
    dd if="$ISO" of="$work/esp.img" bs=512 skip="$start" count="$size" status=none
    mcopy -s -n -i "$work/esp.img" ::/ "$esp_dir/" 2>/dev/null || true

    # Check required EFI binaries
    if [[ -f "$esp_dir/EFI/BOOT/BOOTx64.EFI" ]]; then
        pass "EFI/BOOT/BOOTx64.EFI present (Shim entrypoint)"
    else
        fail "EFI/BOOT/BOOTx64.EFI is missing"
    fi

    if [[ -f "$esp_dir/EFI/BOOT/grubx64.efi" ]]; then
        pass "EFI/BOOT/grubx64.efi present (Chained bootloader)"
    else
        fail "EFI/BOOT/grubx64.efi is missing"
    fi

    if [[ -f "$esp_dir/EFI/BOOT/mmx64.efi" ]]; then
        pass "EFI/BOOT/mmx64.efi present (MokManager)"
    else
        warn "EFI/BOOT/mmx64.efi missing (Key enrollment fallback disabled)"
    fi

    # MOK Certificate presence
    found_cert=""
    for c in "$esp_dir/EFI/BOOT/hyggshi-secureboot.cer" "$esp_dir/hyggshi-secureboot.cer"; do
        if [[ -f "$c" ]]; then
            found_cert="$c"
            break
        fi
    done

    if [[ -n "$found_cert" ]]; then
        pass "MOK certificate located on ESP: $(basename "$found_cert")"
        if [[ -z "$CERT" ]]; then
            # Convert DER to PEM for sbverify
            openssl x509 -inform DER -in "$found_cert" -out "$work/extracted-cert.pem" 2>/dev/null || true
            if [[ -f "$work/extracted-cert.pem" ]]; then
                CERT="$work/extracted-cert.pem"
                pass "Extracted signing certificate from ESP for signature validation"
            fi
        fi
    else
        warn "hyggshi-secureboot.cer not found directly on ESP"
    fi
fi

# 3. Signature Verification
info "3. Cryptographic Signature Verification"
if [[ -n "$CERT" && -f "$CERT" ]]; then
    # Verify grubx64.efi
    if [[ -f "$esp_dir/EFI/BOOT/grubx64.efi" ]]; then
        if sbverify --cert "$CERT" "$esp_dir/EFI/BOOT/grubx64.efi" >/dev/null 2>&1; then
            pass "grubx64.efi digital signature VALID"
        else
            fail "grubx64.efi signature verification FAILED"
        fi
    fi

    # Extract & verify kernel from ISO tree
    mkdir -p "$work/kernel"
    xorriso -osirrox on -indev "$ISO" -extract_regex '/arch/boot/x86_64/vmlinuz.*' "$work/kernel" 2>/dev/null || true
    kernel_file=$(find "$work/kernel" -type f -name "vmlinuz*" | head -n1)
    if [[ -n "$kernel_file" && -f "$kernel_file" ]]; then
        if sbverify --cert "$CERT" "$kernel_file" >/dev/null 2>&1; then
            pass "Kernel ($(basename "$kernel_file")) digital signature VALID"
        else
            fail "Kernel ($(basename "$kernel_file")) digital signature INVALID"
        fi
    else
        warn "Could not extract kernel from ISO to test signature"
    fi
else
    warn "No verification certificate provided or found; skipping sbverify checks"
fi

# 4. ISO UUID & Label Check
info "4. ISO Metadata and Filesystem UUID Integrity"
pvd=$(xorriso -no_rc -indev "$ISO" -pvd_info 2>/dev/null || true)
volid=$(echo "$pvd" | sed -n "s/^Volume Id *: *//p" | head -n1)
if [[ -n "$volid" ]]; then
    pass "Volume ID: $volid"
fi

iso_uuid=$(blkid -s UUID -o value "$ISO" 2>/dev/null || true)
if [[ -n "$iso_uuid" ]]; then
    pass "ISO UUID: $iso_uuid"
else
    warn "Could not read ISO block UUID (normal if blkid requires root or loop device)"
fi

echo ""
if [[ "$FAILED" -eq 0 ]]; then
    echo -e "${C_PASS}${C_BOLD}✓ SECURE BOOT VERIFICATION PASSED SUCCESSFULLY!${C_RESET}"
    exit 0
else
    echo -e "${C_FAIL}${C_BOLD}✗ SECURE BOOT VERIFICATION ENCOUNTERED FAILURES!${C_RESET}"
    exit 1
fi
