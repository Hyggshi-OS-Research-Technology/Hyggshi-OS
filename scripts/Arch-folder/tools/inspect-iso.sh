#!/usr/bin/env bash
# inspect-iso.sh - Inspects internal structure, boot headers and metadata of an ArchISO image.
# Usage: ./tools/inspect-iso.sh ISO_FILE
set -euo pipefail

C_RESET="\033[0m"
C_BOLD="\033[1m"
C_CYAN="\033[38;2;125;207;255m"
C_PURPLE="\033[38;2;187;154;247m"
C_GREEN="\033[38;2;158;206;106m"

if [[ "${1:-}" =~ ^(-h|--help)$ || $# -eq 0 ]]; then
    echo "Usage: $0 ISO_FILE"
    exit 0
fi

ISO="$1"
[[ -f "$ISO" ]] || { echo "File not found: $ISO" >&2; exit 1; }

echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
echo -e "${C_BOLD}  󰋊  Hyggshi ISO Inspector: $(basename "$ISO")${C_RESET}"
echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"

echo -e "\n${C_PURPLE}󰅂 General Image Info:${C_RESET}"
echo "  File:         $ISO"
echo "  Size:         $(du -h "$ISO" | awk '{print $1}') ($(stat -c%s "$ISO") bytes)"
if command -v sha256sum >/dev/null; then
    echo "  SHA256:       $(sha256sum "$ISO" | awk '{print $1}')"
fi

echo -e "\n${C_PURPLE}󰅂 ISO Header & Volume Descriptor:${C_RESET}"
if command -v xorriso >/dev/null; then
    pvd=$(xorriso -no_rc -indev "$ISO" -pvd_info 2>/dev/null || true)
    echo "  Volume ID:    $(echo "$pvd" | sed -n 's/^Volume Id *: *//p' | head -n1)"
    echo "  Publisher:    $(echo "$pvd" | sed -n 's/^Publisher Id *: *//p' | head -n1)"
    echo "  Application:  $(echo "$pvd" | sed -n 's/^App Id *: *//p' | head -n1)"
    echo "  Modif. Time:  $(echo "$pvd" | sed -n 's/^Modif\. Time *: *//p' | head -n1)"
fi

echo -e "\n${C_PURPLE}󰅂 Partition Layout:${C_RESET}"
if command -v sfdisk >/dev/null; then
    sfdisk -l "$ISO" 2>/dev/null | grep -E '^/|Disk |Units:' || sfdisk -d "$ISO" 2>/dev/null
fi

echo -e "\n${C_PURPLE}󰅂 Boot & EFI Contents:${C_RESET}"
if command -v xorriso >/dev/null; then
    echo "  Boot files found:"
    xorriso -no_rc -indev "$ISO" -find /boot /EFI -type f 2>/dev/null | sed 's/^/    • /' || echo "    (none)"
fi

echo -e "\n${C_PURPLE}󰅂 Secure Boot Status:${C_RESET}"
if [[ -x "$(dirname "$0")/verify-secureboot.sh" ]]; then
    "$(dirname "$0")/verify-secureboot.sh" "$ISO" 2>/dev/null && echo -e "  ${C_GREEN}✓ Secure Boot signature chain verified${C_RESET}" || echo "  ! Run ./tools/verify-secureboot.sh for detailed diagnostic"
fi

echo -e "\n${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}\n"
