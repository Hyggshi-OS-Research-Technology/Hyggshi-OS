#!/usr/bin/env bash
# Host-side bootstrap for Hyggshi OS. Mint only.
set -Eeuo pipefail
[ "${DEBUG_MODE:-false}" = "true" ] && set -x

: "${CHROOT_DIR:=build/chroot}"
: "${GITHUB_ENV:=build/build.env}"
: "${MINT_VERSION:=22.3}"
: "${MINT_CODENAME:=zena}"
: "${BASE_CODENAME:=noble}"
export CHROOT_DIR GITHUB_ENV MINT_VERSION MINT_CODENAME BASE_CODENAME

mkdir -p "$(dirname "$GITHUB_ENV")" "$CHROOT_DIR"
: > "$GITHUB_ENV"

echo "===== Free disk space ====="
sudo rm -rf /usr/share/dotnet /usr/local/lib/android /opt/ghc /opt/hostedtoolcache || true
sudo apt-get clean
df -h

echo "===== Install host build dependencies ====="
sudo apt-get update
sudo apt-get install -y       debootstrap squashfs-tools xorriso isolinux syslinux-efi       grub-pc-bin grub-efi-amd64-bin grub-common mtools dosfstools       initramfs-tools live-boot

bash "$(dirname "$0")/../base/bootstrap-linuxmint.sh"
