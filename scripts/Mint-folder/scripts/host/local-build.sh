#!/bin/bash
# Build a Debian, Ubuntu, or Linux Mint ISO locally or inside the supplied
# Docker image. Native-container builders remain available through Actions.
set -Eeuo pipefail

: "${BASE_DISTRO:=linuxmint}"
: "${MINT_VERSION:=22.3}"
: "${MINT_CODENAME:=zena}"
: "${BASE_CODENAME:=noble}"

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
: "${WALLPAPER_URL:=https://github.com/Hyggshi-OS-Research-Technology/Hyggshi-OS/blob/main/config/branding/Wallpaper.png?raw=true}"
: "${LOGO_URL:=https://github.com/Hyggshi-OS-Research-Technology/Hyggshi-OS/blob/main/config/branding/Logo.png?raw=true}"
: "${PLYMOUTH_LOGO_URL:=}"

if ! printf '%s' "$HYGGSHI_VERSION_ID" | grep -Eq '^[0-9]+([.][0-9]+)*$'; then
  echo "HYGGSHI_VERSION_ID phải là dạng số, ví dụ 1.0, 1.1 hoặc 2.0." >&2
  exit 2
fi

if [ "$BASE_DISTRO" != "linuxmint" ]; then
  echo "Only Linux Mint builds are supported." >&2
  exit 2
fi

if [ "$(id -u)" -ne 0 ] && ! command -v sudo >/dev/null; then
  echo "This build needs root privileges; install sudo or run it as root." >&2
  exit 1
fi

export BASE_DISTRO MINT_VERSION MINT_CODENAME DISTRO_NAME HYGGSHI_VERSION_ID EDITION BASE_CODENAME
export DE PANEL_STYLE ICON_THEME OS_USERNAME OS_PASSWORD OS_HOSTNAME OS_TIMEZONE
export INCLUDE_BROWSER INCLUDE_OFFICE EXTRA_PACKAGES DEBUG_MODE ISO_FILENAME
export WALLPAPER_URL LOGO_URL PLYMOUTH_LOGO_URL WELCOME_WIZARD HYGGSHI_CODENAME
export GITHUB_ENV="$PWD/build/build.env"

bash scripts/host/build.sh
# build.sh writes the resolved base codename/label using the same environment
# file contract that GitHub Actions uses between workflow steps.
# shellcheck disable=SC1090
source "$GITHUB_ENV"

sudo cp scripts/target/desktop.sh build/chroot/tmp/desktop.sh
sudo cp scripts/target/kernel-tuning.sh build/chroot/tmp/kernel-tuning.sh
sudo cp scripts/target/fix-cinnamon-tela-persistence.sh build/chroot/tmp/fix-cinnamon-tela-persistence.sh
sudo cp LICENSE build/chroot/tmp/LICENSE
# Stage the repository's complete Calamares configuration.
sudo rm -rf build/chroot/tmp/calamares
sudo cp -a config/calamares build/chroot/tmp/calamares
# Stage installer branding so desktop.sh can rebrand the Calamares launcher.
sudo cp config/branding/Hyggshi-OS-Installer.png build/chroot/tmp/Hyggshi-OS-Installer.png
sudo chmod 0644 build/chroot/tmp/Hyggshi-OS-Installer.png
sudo chmod +x build/chroot/tmp/desktop.sh
sudo chroot build/chroot env \
  BASE_DISTRO="$BASE_DISTRO" MINT_VERSION="$MINT_VERSION" MINT_CODENAME="$MINT_CODENAME" BASE_CODENAME="$BASE_CODENAME" DE="$DE" EDITION="$EDITION" DEBUG_MODE="$DEBUG_MODE" \
  ICON_THEME="$ICON_THEME" OS_USERNAME="$OS_USERNAME" OS_PASSWORD="$OS_PASSWORD" \
  OS_HOSTNAME="$OS_HOSTNAME" OS_TIMEZONE="$OS_TIMEZONE" \
  INCLUDE_BROWSER="$INCLUDE_BROWSER" INCLUDE_OFFICE="$INCLUDE_OFFICE" \
  EXTRA_PACKAGES="$EXTRA_PACKAGES" /tmp/desktop.sh

# ===== WELCOME: build + cài Hyggshi Welcome (wizard chào mừng lần đầu đăng
# nhập) từ source đã commit tại packages/hyggshi/hyggshi-welcome/ =====
# TRƯỚC ĐÂY: bước này chỉ tồn tại trong workflow GitHub Actions
# (.github/workflows/build-hyggshi-os.yml, job "[welcome.sh]"), nên ISO
# build qua local-build.sh/Docker KHÔNG BAO GIỜ có Hyggshi Welcome — app tự
# thoát nếu chưa cài, nên user build local sẽ không bao giờ thấy màn hình
# chào mừng dù binary hyggshi-welcome đã autostart-guard đúng logic
# first-boot (marker $XDG_CONFIG_HOME/hyggshi/welcome-shown, xem
# packages/hyggshi/hyggshi-welcome/src/main.cpp). Copy + chạy welcome.sh
# giống hệt bước tương ứng trong workflow để 2 đường build cho ra cùng 1
# kết quả.
if [ "$WELCOME_WIZARD" = "true" ]; then
  echo "===== Build & cài Hyggshi Welcome (chạy trong chroot) ====="
  sudo mkdir -p build/chroot/tmp/hyggshi-welcome-src
  sudo cp -r packages/hyggshi/hyggshi-welcome/. build/chroot/tmp/hyggshi-welcome-src/
  sudo cp scripts/target/welcome.sh build/chroot/tmp/welcome.sh
  sudo chmod +x build/chroot/tmp/welcome.sh
  sudo chroot build/chroot env \
    DEBUG_MODE="$DEBUG_MODE" \
    SRC_DIR="/tmp/hyggshi-welcome-src" \
    /tmp/welcome.sh
else
  echo "WELCOME_WIZARD=false — bỏ qua cài Hyggshi Welcome."
fi

# Fail early if the default Hyggshi Welcome feature was requested but the
# binary/desktop entry was not installed successfully.
if [ "$WELCOME_WIZARD" = "true" ]; then
  if ! sudo chroot build/chroot test -x /usr/bin/hyggshi-welcome; then
    echo "ERROR: WELCOME_WIZARD=true nhưng /usr/bin/hyggshi-welcome không tồn tại." >&2
    exit 1
  fi
  if ! sudo chroot build/chroot test -f /etc/xdg/autostart/hyggshi-welcome.desktop; then
    echo "ERROR: Hyggshi Welcome binary có nhưng autostart entry bị thiếu." >&2
    exit 1
  fi
fi

bash scripts/target/branding.sh
bash scripts/host/build-iso.sh
