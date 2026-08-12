#!/bin/bash
# Build a Debian, Ubuntu, or Linux Mint ISO locally or inside the supplied
# Docker image. Native-container builders remain available through Actions.
set -Eeuo pipefail

: "${BASE_DISTRO:=debian}"
: "${DEBIAN_VERSION:=trixie}"
: "${UBUNTU_VERSION:=noble}"
: "${MINT_VERSION:=22}"
: "${DISTRO_NAME:=Hyggshi OS}"
: "${EDITION:=normal}"
: "${DE:=xfce}"
: "${PANEL_STYLE:=windows10}"
: "${ICON_THEME:=papirus}"
: "${OS_USERNAME:=hyggshi}"
: "${OS_PASSWORD:=hyggshi}"
: "${OS_HOSTNAME:=hyggshi-os}"
: "${OS_TIMEZONE:=Asia/Ho_Chi_Minh}"
: "${INCLUDE_BROWSER:=true}"
: "${INCLUDE_OFFICE:=false}"
: "${EXTRA_PACKAGES:=}"
: "${DEBUG_MODE:=false}"
: "${ISO_FILENAME:=hyggshi-os-local.iso}"
: "${WALLPAPER_URL:=https://github.com/Hyggshi-OS-Research-Technology/Hyggshi-OS/blob/main/iso-config/branding/Wallpaper.png?raw=true}"
: "${LOGO_URL:=https://github.com/Hyggshi-OS-Research-Technology/Hyggshi-OS/blob/main/iso-config/branding/Logo.png?raw=true}"
: "${PLYMOUTH_LOGO_URL:=}"

case "$BASE_DISTRO" in
  debian|ubuntu|linuxmint) ;;
  *)
    echo "Local builds support debian, ubuntu, and linuxmint. Use GitHub Actions for $BASE_DISTRO." >&2
    exit 2
    ;;
esac

if [ "$(id -u)" -ne 0 ] && ! command -v sudo >/dev/null; then
  echo "This build needs root privileges; install sudo or run it as root." >&2
  exit 1
fi

export BASE_DISTRO DEBIAN_VERSION UBUNTU_VERSION MINT_VERSION DISTRO_NAME EDITION
export DE PANEL_STYLE ICON_THEME OS_USERNAME OS_PASSWORD OS_HOSTNAME OS_TIMEZONE
export INCLUDE_BROWSER INCLUDE_OFFICE EXTRA_PACKAGES DEBUG_MODE ISO_FILENAME
export WALLPAPER_URL LOGO_URL PLYMOUTH_LOGO_URL
export GITHUB_ENV="$PWD/live-build/build.env"

bash scripts/build.sh
# build.sh writes the resolved base codename/label using the same environment
# file contract that GitHub Actions uses between workflow steps.
# shellcheck disable=SC1090
source "$GITHUB_ENV"

sudo cp scripts/desktop.sh live-build/chroot/tmp/desktop.sh
sudo cp scripts/kernel-tuning.sh live-build/chroot/tmp/kernel-tuning.sh
sudo rm -rf live-build/chroot/tmp/packages
sudo cp -r iso-config/packages live-build/chroot/tmp/packages
sudo chmod +x live-build/chroot/tmp/desktop.sh
sudo chroot live-build/chroot env \
  BASE_DISTRO="$BASE_DISTRO" DE="$DE" EDITION="$EDITION" DEBUG_MODE="$DEBUG_MODE" \
  ICON_THEME="$ICON_THEME" OS_USERNAME="$OS_USERNAME" OS_PASSWORD="$OS_PASSWORD" \
  OS_HOSTNAME="$OS_HOSTNAME" OS_TIMEZONE="$OS_TIMEZONE" \
  INCLUDE_BROWSER="$INCLUDE_BROWSER" INCLUDE_OFFICE="$INCLUDE_OFFICE" \
  EXTRA_PACKAGES="$EXTRA_PACKAGES" /tmp/desktop.sh

bash scripts/branding.sh
bash scripts/iso.sh
