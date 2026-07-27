#!/bin/bash

# desktop.sh — cài package cơ bản, DE (xfce/kde), user, hostname/timezone,
# icon/theme và wallpaper mặc định.
#
# Chạy BÊN TRONG chroot
# (được gọi qua `chroot ... env ... /tmp/desktop.sh`).

set -e

[ "$DEBUG_MODE" = "true" ] && set -x

export DEBIAN_FRONTEND=noninteractive


# ============================================================
# APT
# ============================================================

apt-get update

apt-get install -y \
  linux-image-generic \
  live-boot \
  systemd-sysv \
  plymouth \
  plymouth-themes \
  network-manager \
  sudo \
  locales \
  tzdata \
  lsb-release \
  calamares \
  calamares-settings-debian \
|| \
apt-get install -y \
  linux-image-amd64 \
  live-boot \
  systemd-sysv \
  plymouth \
  plymouth-themes \
  network-manager \
  sudo \
  locales \
  tzdata \
  lsb-release \
  calamares \
  calamares-settings-debian


# ============================================================
# HOSTNAME
# ============================================================

if [ -n "$OS_HOSTNAME" ]; then
    echo "$OS_HOSTNAME" > /etc/hostname

    # Xóa hostname cũ nếu có
    sed -i '/127\.0\.1\.1/d' /etc/hosts

    echo "127.0.1.1 $OS_HOSTNAME" >> /etc/hosts
fi


# ============================================================
# TIMEZONE
# ============================================================

if [ -n "$OS_TIMEZONE" ] && [ -f "/usr/share/zoneinfo/$OS_TIMEZONE" ]; then
    ln -sf "/usr/share/zoneinfo/$OS_TIMEZONE" /etc/localtime
    dpkg-reconfigure -f noninteractive tzdata || true
fi


# ============================================================
# XFCE
# ============================================================

if [ "$DE" = "kde" ]; then

    echo "===== Installing KDE Plasma ====="

    apt-get install -y \
      kde-plasma-desktop \
      sddm

else

    echo "===== Installing XFCE ====="

    apt-get install -y \
      task-xfce-desktop \
      lightdm \
      lightdm-gtk-greeter \
      xfce4-whiskermenu-plugin \
      xfconf \
      git \
      libgtk-3-bin

    # ========================================================
    # ICON THEME
    # ========================================================

    case "$ICON_THEME" in

        numix)
            apt-get install -y numix-icon-theme
            ;;

        breeze)
            apt-get install -y breeze-icon-theme
            ;;

        adwaita)
            apt-get install -y adwaita-icon-theme
            ;;

        *)
            apt-get install -y papirus-icon-theme
            ;;

    esac


    # ========================================================
    # WINDOWS 10 GTK THEME
    # ========================================================

    rm -rf /usr/share/themes/Windows-10

    git clone --depth=1 \
      https://github.com/B00merang-Project/Windows-10 \
      /usr/share/themes/Windows-10


    # ========================================================
    # HYGGSHI OS WALLPAPER
    # ========================================================

    echo "===== Installing Hyggshi OS wallpaper ====="

    WALLPAPER_DIR="/usr/share/backgrounds/hyggshi"
    WALLPAPER="$WALLPAPER_DIR/wallpaper.png"

    mkdir -p "$WALLPAPER_DIR"


    # Wallpaper được copy vào /tmp trước khi chroot
    if [ -f "/tmp/hyggshi-wallpaper.png" ]; then

        cp "/tmp/hyggshi-wallpaper.png" "$WALLPAPER"

        chmod 644 "$WALLPAPER"

        echo "Wallpaper installed:"
        echo "$WALLPAPER"

    else

        echo "WARNING: /tmp/hyggshi-wallpaper.png không tồn tại."
        echo "Wallpaper sẽ không được cài."

    fi


    # ========================================================
    # XFCE DEFAULT WALLPAPER CONFIG
    # ========================================================

    if [ -f "$WALLPAPER" ]; then

        echo "===== Configuring XFCE default wallpaper ====="

        mkdir -p \
          /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml


        cat > /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml <<EOF
<?xml version="1.0" encoding="UTF-8"?>

<channel name="xfce4-desktop" version="1.0">

  <property name="backdrop" type="empty">

    <property name="screen0" type="empty">

      <property name="monitor0" type="empty">

        <property name="workspace0" type="empty">

          <property
            name="last-image"
            type="string"
            value="$WALLPAPER"
          />

          <property
            name="image-style"
            type="int"
            value="5"
          />

        </property>

      </property>

    </property>

  </property>

</channel>
EOF

    fi


    # ========================================================
    # XFCE DESKTOP SETTINGS
    # ========================================================

    mkdir -p \
      /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml


    # Tắt icon mặc định trên desktop nếu muốn
    cat > /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml.tmp <<EOF
EOF

fi


# ============================================================
# BROWSER
# ============================================================

if [ "$INCLUDE_BROWSER" = "true" ]; then

    echo "===== Installing Firefox ====="

    apt-get install -y firefox-esr \
      || apt-get install -y firefox

fi


# ============================================================
# OFFICE
# ============================================================

if [ "$INCLUDE_OFFICE" = "true" ]; then

    echo "===== Installing LibreOffice ====="

    apt-get install -y libreoffice

else

    echo "INCLUDE_OFFICE=false — kiểm tra và gỡ LibreOffice nếu bị cài kèm"

    apt-get purge -y \
      'libreoffice*' \
      2>/dev/null || true

    apt-get autoremove -y \
      2>/dev/null || true

fi


# ============================================================
# EXTRA PACKAGES
# ============================================================

if [ -n "$EXTRA_PACKAGES" ]; then

    echo "===== Installing extra packages ====="

    apt-get install -y $EXTRA_PACKAGES \
      || true

fi


# ============================================================
# DEFAULT USER
# ============================================================

echo "===== Creating default user ====="

if [ -n "$OS_USERNAME" ]; then

    useradd \
      -m \
      -s /bin/bash \
      -G sudo \
      "$OS_USERNAME" \
      || true


    if [ -n "$OS_PASSWORD" ]; then

        echo "$OS_USERNAME:$OS_PASSWORD" | chpasswd

    fi

fi


# ============================================================
# COPY SKEL CONFIG TO USER
# ============================================================

if [ -n "$OS_USERNAME" ] && [ -d "/home/$OS_USERNAME" ]; then

    echo "===== Applying /etc/skel configuration ====="

    cp -a \
      /etc/skel/. \
      "/home/$OS_USERNAME/" \
      2>/dev/null || true


    chown -R \
      "$OS_USERNAME:$OS_USERNAME" \
      "/home/$OS_USERNAME"

fi


# ============================================================
# CLEAN APT
# ============================================================

echo "===== Cleaning APT ====="

apt-get clean

rm -rf /var/lib/apt/lists/*


# ============================================================
# DONE
# ============================================================

echo ""
echo "=============================================="
echo "       Hyggshi OS desktop.sh COMPLETE"
echo "=============================================="
echo ""

echo "DE:              $DE"
echo "Username:        $OS_USERNAME"
echo "Hostname:        $OS_HOSTNAME"
echo "Timezone:        $OS_TIMEZONE"
echo "Icon theme:      $ICON_THEME"
echo "Browser:         $INCLUDE_BROWSER"
echo "Office:          $INCLUDE_OFFICE"

if [ "$DE" != "kde" ]; then

    if [ -f "/usr/share/backgrounds/hyggshi/hyggshi-wallpaper.png" ]; then
        echo "Wallpaper:       ENABLED"
    else
        echo "Wallpaper:       NOT FOUND"
    fi

fi

echo ""
echo "===== desktop.sh xong ====="
