#!/bin/bash
set -Eeuo pipefail

: "${BASE_DISTRO:=debian}"
: "${DEBIAN_VERSION:=trixie}"
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
: "${WALLPAPER_URL:=}"
: "${LOGO_URL:=}"
: "${PLYMOUTH_LOGO_URL:=}"

export BASE_DISTRO DEBIAN_VERSION DISTRO_NAME EDITION DE PANEL_STYLE ICON_THEME
export OS_USERNAME OS_PASSWORD OS_HOSTNAME OS_TIMEZONE
export INCLUDE_BROWSER INCLUDE_OFFICE EXTRA_PACKAGES DEBUG_MODE ISO_FILENAME
export WALLPAPER_URL LOGO_URL PLYMOUTH_LOGO_URL
export GITHUB_ENV="$PWD/live-build/build.env"

bash scripts/build.sh
source "$GITHUB_ENV"

sudo cp scripts/desktop.sh live-build/chroot/tmp/desktop.sh
sudo cp scripts/kernel-tuning.sh live-build/chroot/tmp/kernel-tuning.sh
sudo chmod +x live-build/chroot/tmp/desktop.sh

# Copy iso-config vào chroot để desktop.sh đọc packages
sudo mkdir -p live-build/chroot/tmp/iso-config
sudo cp -r iso-config/packages live-build/chroot/tmp/iso-config/

sudo chroot live-build/chroot env \
  BASE_DISTRO="$BASE_DISTRO" DE="$DE" EDITION="$EDITION" DEBUG_MODE="$DEBUG_MODE" \
  ICON_THEME="$ICON_THEME" OS_USERNAME="$OS_USERNAME" OS_PASSWORD="$OS_PASSWORD" \
  OS_HOSTNAME="$OS_HOSTNAME" OS_TIMEZONE="$OS_TIMEZONE" \
  INCLUDE_BROWSER="$INCLUDE_BROWSER" INCLUDE_OFFICE="$INCLUDE_OFFICE" \
  EXTRA_PACKAGES="$EXTRA_PACKAGES" /tmp/desktop.sh

bash scripts/branding.sh
bash scripts/iso.sh
