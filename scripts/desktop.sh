#!/bin/bash
set -e
[ "$DEBUG_MODE" = "true" ] && set -x
export DEBIAN_FRONTEND=noninteractive

source /tmp/kernel-tuning.sh
: "${EDITION:=normal}"
: "${AUTOLOGIN:=true}"
: "${AUTOSCALE_DISPLAY:=true}"

apt-get update

# Giảm kích thước ISO
mkdir -p /etc/dpkg/dpkg.cfg.d
cat > /etc/dpkg/dpkg.cfg.d/01-hyggshi-nodoc <<'DPKGCFGEOF'
path-exclude=/usr/share/doc/*
path-include=/usr/share/doc/*/copyright
path-exclude=/usr/share/man/*
path-exclude=/usr/share/groff/*
path-exclude=/usr/share/info/*
path-exclude=/usr/share/lintian/*
path-exclude=/usr/share/linda/*
DPKGCFGEOF

echo "===== Cài kernel + base ====="
apt-get install -y linux-image-generic live-boot systemd-sysv \
  plymouth plymouth-themes network-manager sudo locales tzdata \
  lsb-release || \
apt-get install -y linux-image-amd64 live-boot systemd-sysv \
  plymouth plymouth-themes network-manager sudo locales tzdata \
  lsb-release

echo "===== Cài GRUB + Calamares deps ====="
echo "grub-pc grub-pc/install_devices_empty boolean true" | debconf-set-selections
echo "grub-pc grub-pc/install_devices multiselect" | debconf-set-selections
echo "grub-pc grub-pc/install_devices_disks_changed multiselect" | debconf-set-selections

GRUB_INSTALL_FAILED=0
for pkg in grub-pc grub-pc-bin grub-efi-amd64-bin grub-common efibootmgr parted dosfstools; do
  apt-get install -y "$pkg" || GRUB_INSTALL_FAILED=1
done
[ "$GRUB_INSTALL_FAILED" = "1" ] && { echo "LỖI GRUB"; exit 1; }

echo "===== Cài Calamares ====="
apt-get install -y calamares calamares-settings-debian || \
apt-get install -y calamares || \
echo "CẢNH BÁO: không có Calamares"

echo "===== Kiểm tra kernel ====="
if ! ls /boot/vmlinuz-* >/dev/null 2>&1 || ! ls /boot/initrd.img-* >/dev/null 2>&1; then
  echo "LỖI: thiếu kernel image" >&2; exit 1
fi

# Khóa kernel
KERNEL_PKGS=$(dpkg-query -W -f='${Package}\n' 2>/dev/null | grep -E '^linux-(image|modules|headers)-' || true)
[ -n "$KERNEL_PKGS" ] && echo "$KERNEL_PKGS" | xargs apt-mark hold

echo "===== Cài firmware ====="
if [ "$BASE_DISTRO" = "debian" ]; then
  apt-get install -y firmware-linux-free firmware-misc-nonfree \
    firmware-realtek firmware-iwlwifi firmware-atheros os-prober pciutils usbutils || true
else
  apt-get install -y linux-firmware os-prober pciutils usbutils || true
fi

# Hostname & Timezone
echo "$OS_HOSTNAME" > /etc/hostname
echo "127.0.1.1 $OS_HOSTNAME" >> /etc/hosts
ln -sf "/usr/share/zoneinfo/$OS_TIMEZONE" /etc/localtime
dpkg-reconfigure -f noninteractive tzdata || true

echo "===== Cài DE: $DE ====="
case "$DE" in
  kde)
    apt-get install -y kde-plasma-desktop sddm
    ;;
  lxqt)
    apt-get install -y lxqt sddm lxqt-config lxqt-panel lxqt-session pcmanfm-qt xterm
    ;;
  gnome)
    apt-get install -y gnome-session gnome-shell gdm3 gnome-terminal nautilus gnome-tweaks
    ;;
  mate)
    apt-get install -y mate-desktop-environment lightdm lightdm-gtk-greeter
    ;;
  cinnamon)
    apt-get install -y cinnamon-desktop-environment lightdm lightdm-gtk-greeter
    ;;
  *)
    apt-get install -y task-xfce-desktop lightdm lightdm-gtk-greeter \
      xfce4-whiskermenu-plugin git libgtk-3-bin x11-xserver-utils
    if ! git clone --depth=1 https://github.com/B00merang-Project/Windows-10 \
        /usr/share/themes/Windows-10 2>/dev/null; then
      echo "⚠️ Clone theme Windows-10 thất bại"
    fi
    ;;
esac

# Icon theme
case "$ICON_THEME" in
  numix)   apt-get install -y numix-icon-theme ;;
  breeze)  apt-get install -y breeze-icon-theme ;;
  adwaita) apt-get install -y adwaita-icon-theme ;;
  *)       apt-get install -y papirus-icon-theme ;;
esac

echo "===== Cài packages từ iso-config/packages/ ====="
PKG_DIR="/tmp/iso-config/packages"
if [ -d "$PKG_DIR" ]; then
  for list in "$PKG_DIR"/*.list; do
    [ -f "$list" ] || continue
    echo "--- Cài từ $list ---"
    while IFS= read -r pkg || [ -n "$pkg" ]; do
      pkg=$(echo "$pkg" | sed 's/#.*//;s/^[[:space:]]*//;s/[[:space:]]*$//')
      [ -z "$pkg" ] && continue
      apt-get install -y "$pkg" || echo "⚠️ Bỏ qua $pkg"
    done < "$list"
  done
fi

# Browser & Office
[ "$INCLUDE_BROWSER" = "true" ] && { apt-get install -y firefox-esr || apt-get install -y firefox || true; }
if [ "$INCLUDE_OFFICE" = "true" ]; then
  apt-get install -y libreoffice || true
else
  apt-get purge -y 'libreoffice*' 2>/dev/null || true
  apt-get autoremove -y 2>/dev/null || true
fi

echo "===== Fastfetch ====="
if ! apt-get install -y fastfetch; then
  FASTFETCH_VER=$(curl -fsSL https://api.github.com/repos/fastfetch-cli/fastfetch/releases/latest \
    | grep -m1 '"tag_name"' | cut -d'"' -f4)
  if [ -n "$FASTFETCH_VER" ] && curl -fsSL -o /tmp/fastfetch.deb \
      "https://github.com/fastfetch-cli/fastfetch/releases/download/${FASTFETCH_VER}/fastfetch-linux-amd64.deb"; then
    apt-get install -y /tmp/fastfetch.deb || true
    rm -f /tmp/fastfetch.deb
  fi
fi

echo "===== Dev tools ====="
for pkg in cmake gcc; do
  apt-get install -y "$pkg" || echo "⚠️ Thiếu $pkg"
done

echo "===== Bộ gõ tiếng Việt ====="
for pkg in fcitx5 fcitx5-unikey fcitx5-config-qt fcitx5-frontend-gtk3 fcitx5-frontend-qt5; do
  apt-get install -y "$pkg" || echo "⚠️ Thiếu $pkg"
done
if command -v fcitx5 >/dev/null 2>&1 && ! grep -q '^GTK_IM_MODULE=' /etc/environment 2>/dev/null; then
  cat >> /etc/environment <<'ENVEOF'
GTK_IM_MODULE=fcitx
QT_IM_MODULE=fcitx
XMODIFIERS=@im=fcitx
SDL_IM_MODULE=fcitx
ENVEOF
fi

# Extra packages
if [ -n "$EXTRA_PACKAGES" ]; then
  read -r -a EXTRA_PACKAGE_LIST <<< "$EXTRA_PACKAGES"
  apt-get install -y "${EXTRA_PACKAGE_LIST[@]}" || true
fi

# User live
useradd -m -s /bin/bash -G sudo "$OS_USERNAME" || true
{ set +x; } 2>/dev/null
echo "$OS_USERNAME:$OS_PASSWORD" | chpasswd
[ "$DEBUG_MODE" = "true" ] && set -x

echo "===== Autologin ====="
if [ "$AUTOLOGIN" = "true" ]; then
  case "$DE" in
    kde|lxqt)
      mkdir -p /etc/sddm.conf.d
      SESSION="plasma"; [ "$DE" = "lxqt" ] && SESSION="lxqt"
      cat <<EOF > /etc/sddm.conf.d/hyggshi-autologin.conf
[Autologin]
User=$OS_USERNAME
Session=$SESSION
EOF
      ;;
    gnome)
      mkdir -p /etc/gdm3
      cat <<EOF > /etc/gdm3/custom.conf
[daemon]
AutomaticLoginEnable = true
AutomaticLogin = $OS_USERNAME
EOF
      ;;
    mate)
      mkdir -p /etc/lightdm/lightdm.conf.d
      cat <<EOF > /etc/lightdm/lightdm.conf.d/50-hyggshi-autologin.conf
[Seat:*]
autologin-user=$OS_USERNAME
autologin-user-timeout=0
autologin-session=mate
EOF
      ;;
    cinnamon)
      mkdir -p /etc/lightdm/lightdm.conf.d
      cat <<EOF > /etc/lightdm/lightdm.conf.d/50-hyggshi-autologin.conf
[Seat:*]
autologin-user=$OS_USERNAME
autologin-user-timeout=0
autologin-session=cinnamon
EOF
      ;;
    *)
      mkdir -p /etc/lightdm/lightdm.conf.d
      cat <<EOF > /etc/lightdm/lightdm.conf.d/50-hyggshi-autologin.conf
[Seat:*]
autologin-user=$OS_USERNAME
autologin-user-timeout=0
autologin-session=xfce
EOF
      ;;
  esac
fi

echo "===== Autoscale display ====="
if [ "$AUTOSCALE_DISPLAY" = "true" ]; then
  cat <<'SCRIPT' > /usr/local/bin/hyggshi-autoscale.sh
#!/bin/bash
LOG="$HOME/.cache/hyggshi-autoscale.log"
mkdir -p "$HOME/.cache"
echo "=== $(date) ===" >> "$LOG"
command -v xrandr >/dev/null 2>&1 || { echo "Không có xrandr" >> "$LOG"; exit 0; }
CONNECTED=$(xrandr --query | awk '/ connected/{print $1}')
for OUT in $CONNECTED; do
  xrandr --output "$OUT" --auto >> "$LOG" 2>&1 || true
done
PRIMARY=$(echo "$CONNECTED" | head -n1)
if [ -n "$PRIMARY" ]; then
  HEIGHT=$(xrandr --query | awk -v o="$PRIMARY" '$1==o && / connected/{ \
    for(i=1;i<=NF;i++){ if ($i ~ /^[0-9]+x[0-9]+\+/) { split($i,a,"x"); split(a[2],b,"+"); print b[1]; exit } } }')
  if [ -n "$HEIGHT" ] && [ "$HEIGHT" -ge 1440 ] 2>/dev/null; then
    xrdb -merge <<< "Xft.dpi: 144" 2>/dev/null || true
    echo "HiDPI -> Xft.dpi=144" >> "$LOG"
  fi
fi
SCRIPT
  chmod +x /usr/local/bin/hyggshi-autoscale.sh
  mkdir -p /etc/xdg/autostart
  cat <<'DESKTOP' > /etc/xdg/autostart/hyggshi-autoscale.desktop
[Desktop Entry]
Type=Application
Name=Hyggshi Auto Scale
Exec=/usr/local/bin/hyggshi-autoscale.sh
X-GNOME-Autostart-enabled=true
NoDisplay=true
DESKTOP
fi

echo "===== Calamares config ====="
if command -v calamares >/dev/null 2>&1; then
  mkdir -p /etc/calamares/modules
  cat <<EOF > /etc/calamares/modules/users.conf
---
defaultGroups:
  - sudo
  - live
  - network
  - plugdev
  - video
  - audio
autologinGroup: autologin
doAutologin: false
sudoersGroup: sudo
setRootPassword: false
doReusePassword: true
allowWeakPasswords: true
allowWeakPasswordsDefault: true
userShell: /bin/bash
hostname: $OS_HOSTNAME
EOF

  # Packages.conf
  CANDIDATE_LIVE_PKGS="live-boot live-boot-doc live-config live-config-doc live-config-systemd live-tools live-task-localisation live-task-recommended calamares calamares-settings-debian"
  INSTALLED_LIVE_PKGS=""
  for p in $CANDIDATE_LIVE_PKGS; do
    dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q "^install ok installed$" && INSTALLED_LIVE_PKGS="$INSTALLED_LIVE_PKGS $p"
  done
  {
    echo "backend: apt"; echo ""; echo "operations:"
    if [ -n "$INSTALLED_LIVE_PKGS" ]; then
      echo "  - remove:"
      for p in $INSTALLED_LIVE_PKGS; do echo "      - '$p'"; done
    else
      echo "  []"
    fi
  } > /etc/calamares/modules/packages.conf

  # Remove autologin on installed system
  cat <<'EOF' > /etc/calamares/modules/shellprocess-removeautologin.conf
---
dontChroot: false
timeout: 15
exec:
  - "rm -f /etc/lightdm/lightdm.conf.d/50-hyggshi-autologin.conf"
  - "rm -f /etc/sddm.conf.d/hyggshi-autologin.conf"
  - "sh -c \"[ -f /etc/gdm3/custom.conf ] && sed -i -E 's/^#?AutomaticLoginEnable[[:space:]]*=.*/AutomaticLoginEnable = false/' /etc/gdm3/custom.conf; true\""
EOF

  if [ -f /etc/calamares/settings.conf ]; then
    grep -Eq '^\s*-\s*shellprocess@removeautologin\s*$' /etc/calamares/settings.conf || \
      sed -i -E 's/^([[:space:]]*)-[[:space:]]*packages[[:space:]]*$/&\n\1- shellprocess@removeautologin/' /etc/calamares/settings.conf
  fi

  # License module
  mkdir -p /usr/share/hyggshi-os
  if [ -f /tmp/LICENSE ]; then
    cp /tmp/LICENSE /usr/share/hyggshi-os/LICENSE.txt
  else
    cat <<'LICTXT' > /usr/share/hyggshi-os/LICENSE.txt
Hyggshi OS — HOSL-1.3 / MIT
Xem đầy đủ tại: https://hyggshi-os-website.pages.dev/license
LICTXT
  fi
  cat <<'EOF' > /etc/calamares/modules/license.conf
---
entries:
  - id:          "hyggshi-os"
    name:        "Hyggshi OS"
    vendor:      "Hyggshi OS Research Technology (HORT)"
    url:         "https://hyggshi-os-website.pages.dev/license"
    file:        "/usr/share/hyggshi-os/LICENSE.txt"
    isMandatory: true
    isOptedIn:   false
EOF
  if [ -f /etc/calamares/settings.conf ]; then
    grep -Eq '^\s*-\s*license\s*$' /etc/calamares/settings.conf || \
      sed -i -E 's/^([[:space:]]*)-[[:space:]]*welcome[[:space:]]*$/&\n\1- license/' /etc/calamares/settings.conf
  fi
fi

# Edition tuning
if [ "$BASE_DISTRO" = "debian" ]; then
  mkdir -p /etc/sysctl.d
  hyggshi_sysctl_conf "$EDITION" > /etc/sysctl.d/99-hyggshi-tuning.conf
  EDITION_PKGS=$(hyggshi_edition_packages_apt "$EDITION")
  [ -n "$EDITION_PKGS" ] && apt-get install -y $EDITION_PKGS || true
  ZRAM_CONF=$(hyggshi_zram_conf "$EDITION")
  [ -n "$ZRAM_CONF" ] && echo "$ZRAM_CONF" > /etc/default/zramswap
  for svc in $(hyggshi_edition_services_mask "$EDITION"); do
    systemctl mask "$svc" 2>/dev/null || true
  done
fi

apt-get clean
rm -rf /var/lib/apt/lists/*

# Dọn dẹp
find /usr/share/doc -mindepth 1 -maxdepth 1 -type d 2>/dev/null | while read -r d; do
  [ -f "$d/copyright" ] && cp "$d/copyright" "/tmp/$(basename "$d")-copyright" 2>/dev/null
done
rm -rf /usr/share/doc/* /usr/share/man/* /usr/share/info/* /usr/share/groff/* 2>/dev/null || true
mkdir -p /usr/share/doc
for f in /tmp/*-copyright; do
  [ -f "$f" ] || continue
  pkgname="$(basename "$f" -copyright)"
  mkdir -p "/usr/share/doc/$pkgname"
  mv "$f" "/usr/share/doc/$pkgname/copyright"
done
rm -rf /var/cache/apt/archives/*.deb /tmp/* /var/tmp/* 2>/dev/null || true
find /var/log -type f -exec truncate -s 0 {} \; 2>/dev/null || true
rm -rf /usr/share/themes/Windows-10/.git 2>/dev/null || true

echo "===== desktop.sh xong ====="
