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
  # Đã xoá feh khỏi danh sách cài đặt
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

  # === THIẾT LẬP TỰ ĐỘNG APPLY WALLPAPER CHO XFCE ===
  # (Đảm bảo bạn đã copy file hình nền vào /usr/share/backgrounds/default-wallpaper.jpg ở script build trước đó)
  
  mkdir -p /usr/local/bin
  cat << 'EOF' > /usr/local/bin/set-xfce-wallpaper.sh
#!/bin/bash
# Đợi 2 giây để đảm bảo XFCE desktop (xfdesktop) và xfconf đã khởi động hoàn toàn
sleep 2 

WALLPAPER="/usr/share/backgrounds/default-wallpaper.jpg"

if [ -f "$WALLPAPER" ]; then
  # Quét toàn bộ màn hình/workspace hiện có và đổi hình nền thông qua xfconf-query
  for prop in $(xfconf-query -c xfce4-desktop -l | grep "last-image"); do
    xfconf-query -c xfce4-desktop -p "$prop" -s "$WALLPAPER"
  done
fi
EOF
  chmod +x /usr/local/bin/set-xfce-wallpaper.sh

  # Đưa script vào Autostart toàn hệ thống (áp dụng cho mọi user bao gồm cả user live session)
  mkdir -p /etc/xdg/autostart
  cat << 'EOF' > /etc/xdg/autostart/set-xfce-wallpaper.desktop
[Desktop Entry]
Type=Application
Name=Apply XFCE Wallpaper
Exec=/usr/local/bin/set-xfce-wallpaper.sh
NoDisplay=true
StartupNotify=false
Terminal=false
EOF
  # ===================================================
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
