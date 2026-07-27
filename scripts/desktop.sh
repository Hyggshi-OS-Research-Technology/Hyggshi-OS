#!/bin/bash
# desktop.sh — cài package cơ bản, DE (xfce/kde), user, hostname/timezone.
# Chạy BÊN TRONG chroot (được gọi qua `chroot ... env ... /tmp/desktop.sh`).
set -e
[ "$DEBUG_MODE" = "true" ] && set -x
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y linux-image-generic live-boot systemd-sysv \
  plymouth plymouth-themes network-manager sudo locales tzdata \
  lsb-release calamares calamares-settings-debian || \
apt-get install -y linux-image-amd64 live-boot systemd-sysv \
  plymouth plymouth-themes network-manager sudo locales tzdata \
  lsb-release calamares calamares-settings-debian

# hostname
echo "$OS_HOSTNAME" > /etc/hostname
echo "127.0.1.1 $OS_HOSTNAME" >> /etc/hosts

# timezone
ln -sf "/usr/share/zoneinfo/$OS_TIMEZONE" /etc/localtime
dpkg-reconfigure -f noninteractive tzdata || true

if [ "$DE" = "kde" ]; then
  apt-get install -y kde-plasma-desktop sddm
else
  apt-get install -y task-xfce-desktop lightdm lightdm-gtk-greeter \
    xfce4-whiskermenu-plugin git libgtk-3-bin

  # icon theme theo lựa chọn
  case "$ICON_THEME" in
    numix)   apt-get install -y numix-icon-theme ;;
    breeze)  apt-get install -y breeze-icon-theme ;;
    adwaita) apt-get install -y adwaita-icon-theme ;;
    *)       apt-get install -y papirus-icon-theme ;;
  esac

  # GTK theme cho khung cửa sổ/taskbar kiểu Windows 10 (B00merang-Project, open source)
  git clone --depth=1 https://github.com/B00merang-Project/Windows-10 \
    /usr/share/themes/Windows-10
fi

# trình duyệt / office (tùy chọn)
if [ "$INCLUDE_BROWSER" = "true" ]; then
  apt-get install -y firefox-esr || apt-get install -y firefox
fi

if [ "$INCLUDE_OFFICE" = "true" ]; then
  apt-get install -y libreoffice
else
  # một số gói (task-xfce-desktop, calamares-settings-debian...) có thể kéo
  # theo libreoffice qua "Recommends" dù ta không apt-get install nó trực
  # tiếp. Purge tường minh ở đây để đảm bảo đúng lựa chọn của người dùng.
  echo "INCLUDE_OFFICE=false — kiểm tra và gỡ LibreOffice nếu bị cài kèm theo Recommends"
  apt-get purge -y 'libreoffice*' 2>/dev/null || true
  apt-get autoremove -y 2>/dev/null || true
fi

# gói thêm do người dùng chỉ định
if [ -n "$EXTRA_PACKAGES" ]; then
  apt-get install -y $EXTRA_PACKAGES || true
fi

# user mặc định cho live session
useradd -m -s /bin/bash -G sudo "$OS_USERNAME" || true
echo "$OS_USERNAME:$OS_PASSWORD" | chpasswd

apt-get clean
rm -rf /var/lib/apt/lists/*

echo "===== desktop.sh xong ====="
