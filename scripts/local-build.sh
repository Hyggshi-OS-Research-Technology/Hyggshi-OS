#!/bin/bash
# Build a Debian, Ubuntu, or Linux Mint ISO locally or inside the supplied
# Docker image. Native-container builders remain available through Actions.
set -Eeuo pipefail

: "${BASE_DISTRO:=debian}"
: "${DEBIAN_VERSION:=trixie}"
: "${UBUNTU_VERSION:=noble}"
: "${MINT_VERSION:=22}"
: "${DISTRO_NAME:=Hyggshi OS}"
: "${HYGGSHI_VERSION_ID:=1.0}"
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
: "${WELCOME_WIZARD:=true}"
: "${HYGGSHI_CODENAME:=}"
: "${WALLPAPER_URL:=https://github.com/Hyggshi-OS-Research-Technology/Hyggshi-OS/blob/main/iso-config/branding/Wallpaper.png?raw=true}"
: "${LOGO_URL:=https://github.com/Hyggshi-OS-Research-Technology/Hyggshi-OS/blob/main/iso-config/branding/Logo.png?raw=true}"
: "${PLYMOUTH_LOGO_URL:=}"

if ! printf '%s' "$HYGGSHI_VERSION_ID" | grep -Eq '^[0-9]+([.][0-9]+)*$'; then
  echo "HYGGSHI_VERSION_ID phải là dạng số, ví dụ 1.0, 1.1 hoặc 2.0." >&2
  exit 2
fi

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

export BASE_DISTRO DEBIAN_VERSION UBUNTU_VERSION MINT_VERSION DISTRO_NAME HYGGSHI_VERSION_ID EDITION
export DE PANEL_STYLE ICON_THEME OS_USERNAME OS_PASSWORD OS_HOSTNAME OS_TIMEZONE
export INCLUDE_BROWSER INCLUDE_OFFICE EXTRA_PACKAGES DEBUG_MODE ISO_FILENAME
export WALLPAPER_URL LOGO_URL PLYMOUTH_LOGO_URL WELCOME_WIZARD HYGGSHI_CODENAME
export GITHUB_ENV="$PWD/live-build/build.env"

bash scripts/build.sh
# build.sh writes the resolved base codename/label using the same environment
# file contract that GitHub Actions uses between workflow steps.
# shellcheck disable=SC1090
source "$GITHUB_ENV"

sudo cp scripts/desktop.sh live-build/chroot/tmp/desktop.sh
sudo cp scripts/kernel-tuning.sh live-build/chroot/tmp/kernel-tuning.sh
# Stage the repository's complete Calamares configuration.
sudo rm -rf live-build/chroot/tmp/calamares
sudo cp -a iso-config/calamares live-build/chroot/tmp/calamares
# Stage installer branding so desktop.sh can rebrand the Calamares launcher.
sudo cp iso-config/branding/Hyggshi-OS-Installer.png live-build/chroot/tmp/Hyggshi-OS-Installer.png
sudo chmod 0644 live-build/chroot/tmp/Hyggshi-OS-Installer.png
sudo chmod +x live-build/chroot/tmp/desktop.sh
sudo chroot live-build/chroot env \
  BASE_DISTRO="$BASE_DISTRO" DE="$DE" EDITION="$EDITION" DEBUG_MODE="$DEBUG_MODE" \
  ICON_THEME="$ICON_THEME" OS_USERNAME="$OS_USERNAME" OS_PASSWORD="$OS_PASSWORD" \
  OS_HOSTNAME="$OS_HOSTNAME" OS_TIMEZONE="$OS_TIMEZONE" \
  INCLUDE_BROWSER="$INCLUDE_BROWSER" INCLUDE_OFFICE="$INCLUDE_OFFICE" \
  EXTRA_PACKAGES="$EXTRA_PACKAGES ${HCL_PACKAGES:-}" /tmp/desktop.sh

# ===== ECOSYSTEM: cài nexfetch, nexcode, nexwm... =====
echo "===== Cài hệ sinh thái Hyggshi (trong chroot) ====="
sudo mkdir -p live-build/chroot/tmp/app-for-hyggshi
sudo cp -r app-for-hyggshi/. live-build/chroot/tmp/app-for-hyggshi/
sudo cp scripts/install-ecosystem-for-hyggshi.sh live-build/chroot/tmp/install-ecosystem-for-hyggshi.sh
sudo chmod +x live-build/chroot/tmp/install-ecosystem-for-hyggshi.sh
sudo chroot live-build/chroot env \
  DEBUG_MODE="$DEBUG_MODE" \
  APP_DIR="/tmp/app-for-hyggshi" \
  HCL_APP_INSTALLS="${HCL_APP_INSTALLS:-}" \
  /tmp/install-ecosystem-for-hyggshi.sh

# ===== WELCOME: build + cài Hyggshi Welcome (wizard chào mừng lần đầu đăng
# nhập) từ source đã commit tại app-for-hyggshi/hyggshi-welcome/ =====
# TRƯỚC ĐÂY: bước này chỉ tồn tại trong workflow GitHub Actions
# (.github/workflows/Build-Hyggshi-OS-ISO.yml, job "[welcome.sh]"), nên ISO
# build qua local-build.sh/Docker KHÔNG BAO GIỜ có Hyggshi Welcome — app tự
# thoát nếu chưa cài, nên user build local sẽ không bao giờ thấy màn hình
# chào mừng dù binary hyggshi-welcome đã autostart-guard đúng logic
# first-boot (marker $XDG_CONFIG_HOME/hyggshi/welcome-shown, xem
# app-for-hyggshi/hyggshi-welcome/src/main.cpp). Copy + chạy welcome.sh
# giống hệt bước tương ứng trong workflow để 2 đường build cho ra cùng 1
# kết quả.
if [ "$WELCOME_WIZARD" = "true" ]; then
  echo "===== Build & cài Hyggshi Welcome (chạy trong chroot) ====="
  sudo mkdir -p live-build/chroot/tmp/hyggshi-welcome-src
  sudo cp -r app-for-hyggshi/hyggshi-welcome/. live-build/chroot/tmp/hyggshi-welcome-src/
  sudo cp app-for-hyggshi/welcome.sh live-build/chroot/tmp/welcome.sh
  sudo chmod +x live-build/chroot/tmp/welcome.sh
  sudo chroot live-build/chroot env \
    DEBUG_MODE="$DEBUG_MODE" \
    SRC_DIR="/tmp/hyggshi-welcome-src" \
    /tmp/welcome.sh
else
  echo "WELCOME_WIZARD=false — bỏ qua cài Hyggshi Welcome."
fi

bash scripts/branding.sh
bash scripts/iso.sh
