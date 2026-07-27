#!/bin/bash
# branding.sh — wallpaper, distributor logo, rebrand os-release/lsb-release,
# panel style + icon theme XFCE, autostart. Chạy trên HOST, ghi thẳng vào
# thư mục chroot (không cần chroot exec, trừ gtk-update-icon-cache).
set -e
[ "$DEBUG_MODE" = "true" ] && set -x
CHROOT=live-build/chroot

echo "===== Copy Plymouth branding (nếu có) ====="
if [ -d "iso-config/branding" ]; then
  sudo cp -r iso-config/branding/* "$CHROOT/usr/share/plymouth/themes/" 2>/dev/null || true
fi

echo "===== Wallpaper ====="
sudo mkdir -p "$CHROOT/usr/share/backgrounds/hyggshi"

# 1. Ưu tiên file wallpaper có sẵn trong repo (checkout local, không phân biệt hoa/thường)
WALLPAPER_FILE=$(find iso-config/branding -maxdepth 1 -iname "wallpaper.*" \
  \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" \) 2>/dev/null | head -n1)

# 2. Nếu không có, tải trực tiếp từ GitHub
if [ -z "$WALLPAPER_FILE" ]; then
  echo "Không thấy wallpaper trong repo local, tải trực tiếp từ GitHub..."
  if curl -fsSL "$WALLPAPER_URL" -o /tmp/wallpaper-remote.png && [ -s /tmp/wallpaper-remote.png ]; then
    WALLPAPER_FILE=/tmp/wallpaper-remote.png
    echo "Tải thành công: $WALLPAPER_URL"
  else
    echo "Tải thất bại từ raw.githubusercontent.com"
  fi
fi

# 3. Áp dụng, hoặc fallback gradient nếu cả 2 cách trên đều fail
if [ -n "$WALLPAPER_FILE" ]; then
  sudo cp "$WALLPAPER_FILE" "$CHROOT/usr/share/backgrounds/hyggshi/wallpaper.png"
  echo "Đã dùng wallpaper: $WALLPAPER_FILE"
else
  echo "⚠️  Không lấy được wallpaper — tự tạo wallpaper gradient tạm thời."
  sudo apt-get install -y imagemagick > /dev/null 2>&1 || true
  convert -size 1920x1080 gradient:'#1a2a4a-#0d1220' /tmp/wallpaper.png
  sudo cp /tmp/wallpaper.png "$CHROOT/usr/share/backgrounds/hyggshi/wallpaper.png"
fi

echo "===== Ghi đè default wallpaper qua update-alternatives (KHÔNG phụ thuộc"
echo "     tên monitor hay script chạy lúc login — đây là cơ chế Debian dùng"
echo "     để chọn ảnh nền mặc định, ổn định hơn nhiều so với xfconf runtime) ====="
for LINK in "$CHROOT/etc/alternatives/desktop-background" \
            "$CHROOT/usr/share/backgrounds/desktop-background" \
            "$CHROOT/usr/share/images/desktop-base/desktop-background"; do
  if [ -e "$LINK" ] || [ -L "$LINK" ]; then
    sudo rm -f "$LINK"
    sudo ln -sf /usr/share/backgrounds/hyggshi/wallpaper.png "$LINK"
    echo "Đã trỏ $LINK -> wallpaper.png"
  fi
done

# "desktop-background" thực ra do update-alternatives QUẢN LÝ (đã xác nhận
# qua log build: gói desktop-base đăng ký nó với auto mode), nên chỉ rm+ln
# tay có thể không "chính chủ" / dễ bị coi là lỗi bởi dpkg. Đăng ký đàng
# hoàng qua update-alternatives để chắc chắn được công nhận là active:
if sudo chroot "$CHROOT" bash -c 'command -v update-alternatives' > /dev/null 2>&1; then
  sudo chroot "$CHROOT" update-alternatives --install \
    /usr/share/images/desktop-base/desktop-background desktop-background \
    /usr/share/backgrounds/hyggshi/wallpaper.png 100 2>&1 || true
  sudo chroot "$CHROOT" update-alternatives --set \
    desktop-background /usr/share/backgrounds/hyggshi/wallpaper.png 2>&1 || true
  echo "--- update-alternatives --display desktop-background ---"
  sudo chroot "$CHROOT" update-alternatives --display desktop-background 2>&1 || true
fi

echo "===== Patch trực tiếp mọi xfce4-desktop.xml có sẵn trong hệ thống (không"
echo "     phải file skel do ta tạo) — phòng trường hợp gói cài sẵn ghi đè lại ====="
FOUND_XMLS=$(sudo find "$CHROOT/etc/xdg" "$CHROOT/usr/share" -name "xfce4-desktop.xml" 2>/dev/null || true)
for f in $FOUND_XMLS; do
  echo "Patch: $f"
  sudo sed -i -E \
    -e 's#(<property name="last-image" type="string" value=")[^"]*(")#\1/usr/share/backgrounds/hyggshi/wallpaper.png\2#g' \
    -e 's#(<property name="last-single-image" type="string" value=")[^"]*(")#\1/usr/share/backgrounds/hyggshi/wallpaper.png\2#g' \
    -e 's#(<property name="image-path" type="string" value=")[^"]*(")#\1/usr/share/backgrounds/hyggshi/wallpaper.png\2#g' \
    -e 's#(<property name="image-style" type="int" value=")[0-9]+(")#\g<1>5\2#g' \
    "$f" 2>/dev/null || true
done

echo "===== Rebrand os-release / lsb-release / banner ====="
# Debian mặc định để /etc/os-release là symlink -> ../usr/lib/os-release.
# Xoá symlink cũ, ghi nội dung THẬT vào usr/lib/os-release, rồi tạo lại
# /etc/os-release như symlink TƯƠNG ĐỐI (không phải tuyệt đối) trỏ tới nó.
sudo rm -f "$CHROOT/etc/os-release" "$CHROOT/usr/lib/os-release"

if [ "$BASE_DISTRO" = "debian" ]; then
  ID_LIKE_VALUE="debian"
else
  ID_LIKE_VALUE="ubuntu debian"
fi

cat <<EOF | sudo tee "$CHROOT/usr/lib/os-release" > /dev/null
PRETTY_NAME="$DISTRO_NAME 1.0 (dựa trên $DISTRO_LABEL)"
NAME="$DISTRO_NAME"
VERSION_ID="1.0"
VERSION="1.0 ($DISTRO_LABEL)"
VERSION_CODENAME=$BASE_CODENAME
ID=hyggshios
ID_LIKE=$ID_LIKE_VALUE
HOME_URL="https://github.com/Hyggshi-OS-Research-Technology"
SUPPORT_URL="https://github.com/Hyggshi-OS-Research-Technology/Hyggshi-OS/issues"
BUG_REPORT_URL="https://github.com/Hyggshi-OS-Research-Technology/Hyggshi-OS/issues"
LOGO=distributor-logo
EOF
sudo ln -sf ../usr/lib/os-release "$CHROOT/etc/os-release"

cat <<EOF | sudo tee "$CHROOT/etc/lsb-release" > /dev/null
DISTRIB_ID=HyggshiOS
DISTRIB_RELEASE=1.0
DISTRIB_CODENAME=$BASE_CODENAME
DISTRIB_DESCRIPTION="$DISTRO_NAME 1.0 ($DISTRO_LABEL)"
EOF

printf "%s \\n \\l\n\n" "$DISTRO_NAME" | sudo tee "$CHROOT/etc/issue" > /dev/null
echo "Welcome to $DISTRO_NAME — built on $DISTRO_LABEL" | sudo tee "$CHROOT/etc/motd" > /dev/null

echo "===== Distributor logo ====="
LOGO_FILE=$(find iso-config/branding -maxdepth 1 -iname "logo.*" \
  \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" \) 2>/dev/null | head -n1)
if [ -n "$LOGO_FILE" ]; then
  sudo apt-get install -y imagemagick > /dev/null 2>&1 || true
  for size in 16 22 24 32 48 64 128 192 256; do
    DEST="$CHROOT/usr/share/icons/hicolor/${size}x${size}/apps"
    sudo mkdir -p "$DEST"
    convert "$LOGO_FILE" -resize ${size}x${size} "/tmp/logo-$size.png"
    sudo cp "/tmp/logo-$size.png" "$DEST/distributor-logo.png"
  done
  sudo chroot "$CHROOT" gtk-update-icon-cache -f /usr/share/icons/hicolor 2>/dev/null || true
  echo "Đã áp logo custom: $LOGO_FILE"
else
  echo "⚠️  Không thấy file logo trong iso-config/branding/ — vẫn giữ logo mặc định của distro gốc."
  echo "    Thêm file logo.png (khuyến nghị 256x256, nền trong suốt) vào iso-config/branding/ để đổi logo."
fi

if [ "$DE" != "xfce" ]; then
  echo "DE=$DE, bỏ qua cấu hình panel/theme XFCE."
  echo "===== branding.sh xong ====="
  exit 0
fi

echo "===== XFCE panel style + icon theme + wallpaper (skel profile) ====="
SKEL="$CHROOT/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml"
sudo mkdir -p "$SKEL"

case "$ICON_THEME" in
  numix)   ICON_NAME="Numix" ;;
  breeze)  ICON_NAME="breeze" ;;
  adwaita) ICON_NAME="Adwaita" ;;
  *)       ICON_NAME="Papirus" ;;
esac

if [ "$PANEL_STYLE" = "windows10" ]; then
cat <<XML | sudo tee "$SKEL/xfce4-panel.xml" > /dev/null
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-panel" version="1.0">
  <property name="configver" type="int" value="2"/>
  <property name="panels" type="array">
    <value type="int" value="1"/>
    <property name="panel-1" type="empty">
      <property name="position" type="string" value="p=8;x=0;y=0"/>
      <property name="length" type="uint" value="100"/>
      <property name="length-adjust" type="bool" value="true"/>
      <property name="position-locked" type="bool" value="true"/>
      <property name="size" type="uint" value="34"/>
      <property name="mode" type="uint" value="0"/>
      <property name="autohide-behavior" type="uint" value="0"/>
      <property name="plugin-ids" type="array">
        <value type="int" value="1"/>
        <value type="int" value="2"/>
        <value type="int" value="3"/>
        <value type="int" value="4"/>
        <value type="int" value="5"/>
      </property>
    </property>
  </property>
  <property name="plugins" type="empty">
    <property name="plugin-1" type="string" value="whiskermenu">
      <property name="button-title" type="string" value=""/>
      <property name="button-icon" type="string" value="start-here"/>
      <property name="show-button-title" type="bool" value="false"/>
    </property>
    <property name="plugin-2" type="string" value="tasklist">
      <property name="grouping" type="uint" value="1"/>
      <property name="show-labels" type="bool" value="false"/>
      <property name="show-handle" type="bool" value="false"/>
    </property>
    <property name="plugin-3" type="string" value="separator">
      <property name="expand" type="bool" value="true"/>
      <property name="style" type="uint" value="0"/>
    </property>
    <property name="plugin-4" type="string" value="systray"/>
    <property name="plugin-5" type="string" value="clock">
      <property name="digital-format" type="string" value="%H:%M  %d/%m/%Y"/>
      <property name="digital-layout" type="uint" value="2"/>
    </property>
  </property>
</channel>
XML
fi

cat <<XML | sudo tee "$SKEL/xfce4-desktop.xml" > /dev/null
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-desktop" version="1.0">
  <property name="backdrop" type="empty">
    <property name="screen0" type="empty">
      <property name="monitor0" type="empty">
        <property name="image-path" type="string" value="/usr/share/backgrounds/hyggshi/wallpaper.png"/>
        <property name="image-show" type="bool" value="true"/>
        <property name="image-style" type="int" value="5"/>
        <property name="color-style" type="int" value="0"/>
        <property name="last-image" type="string" value="/usr/share/backgrounds/hyggshi/wallpaper.png"/>
        <property name="last-single-image" type="string" value="/usr/share/backgrounds/hyggshi/wallpaper.png"/>
        <property name="workspace0" type="empty">
          <property name="last-image" type="string" value="/usr/share/backgrounds/hyggshi/wallpaper.png"/>
          <property name="image-style" type="int" value="5"/>
        </property>
      </property>
      <property name="monitor1" type="empty">
        <property name="image-path" type="string" value="/usr/share/backgrounds/hyggshi/wallpaper.png"/>
        <property name="image-show" type="bool" value="true"/>
        <property name="image-style" type="int" value="5"/>
        <property name="color-style" type="int" value="0"/>
        <property name="last-image" type="string" value="/usr/share/backgrounds/hyggshi/wallpaper.png"/>
        <property name="last-single-image" type="string" value="/usr/share/backgrounds/hyggshi/wallpaper.png"/>
      </property>
    </property>
  </property>
</channel>
XML

cat <<XML | sudo tee "$SKEL/xsettings.xml" > /dev/null
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xsettings" version="1.0">
  <property name="Net" type="empty">
    <property name="IconThemeName" type="string" value="$ICON_NAME"/>
    <property name="ThemeName" type="string" value="Windows-10"/>
  </property>
</channel>
XML

cat <<XML | sudo tee "$SKEL/xfwm4.xml" > /dev/null
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="theme" type="string" value="Windows-10"/>
    <property name="button_layout" type="string" value="O|SHMC"/>
  </property>
</channel>
XML

sudo chroot "$CHROOT" chown -R root:root /etc/skel/.config

echo "===== Script tự set wallpaper lúc login (dò đúng property monitor) ====="
cat <<'SCRIPT' | sudo tee "$CHROOT/usr/local/bin/hyggshi-set-wallpaper.sh" > /dev/null
#!/bin/bash
LOG="/tmp/hyggshi-wallpaper.log"
exec > "$LOG" 2>&1
echo "=== hyggshi-set-wallpaper.sh $(date) ==="

WALL="/usr/share/backgrounds/hyggshi/wallpaper.png"
if [ ! -f "$WALL" ]; then
  echo "LỖI: không tìm thấy file wallpaper, dừng."
  exit 0
fi

# Chờ xfdesktop thật sự chạy (tối đa 15s), tránh race condition lúc login
for i in $(seq 1 15); do
  if pgrep -x xfdesktop >/dev/null; then
    echo "xfdesktop đã chạy sau ${i}s"
    break
  fi
  sleep 1
done
sleep 1

apply_wallpaper() {
  # liệt kê MỌI property last-image mà xfdesktop đang thực sự dùng (tên
  # monitor như "monitor0" không đúng trên mọi máy/VM, QEMU thường đặt tên
  # khác như "Virtual-1")
  PROPS=$(xfconf-query -c xfce4-desktop -p /backdrop -l 2>/dev/null | grep 'last-image$')
  if [ -z "$PROPS" ]; then
    echo "Chưa có property nào, fallback monitor0 (schema không có workspace)"
    PROPS="/backdrop/screen0/monitor0/last-image"
  fi
  echo "PROPS tìm được:"
  echo "$PROPS"

  while read -r PROP; do
    [ -z "$PROP" ] && continue
    STYLE="${PROP%last-image}image-style"
    xfconf-query -c xfce4-desktop -p "$PROP" -n -t string -s "$WALL" 2>>"$LOG" \
      || xfconf-query -c xfce4-desktop -p "$PROP" -s "$WALL" 2>>"$LOG"
    xfconf-query -c xfce4-desktop -p "$STYLE" -n -t int -s 5 2>>"$LOG" \
      || xfconf-query -c xfce4-desktop -p "$STYLE" -s 5 2>>"$LOG"
    echo "Set $PROP -> $WALL"
  done <<< "$PROPS"
}

apply_wallpaper

echo "--- verify sau khi set ---"
CHECK=$(xfconf-query -c xfce4-desktop -p /backdrop -l 2>/dev/null | grep 'last-image$' | head -n1)
if [ -n "$CHECK" ]; then
  VAL=$(xfconf-query -c xfce4-desktop -p "$CHECK" 2>/dev/null)
  echo "verify: $CHECK = $VAL"
fi

# --reload không đủ để ép xfdesktop vẽ lại backdrop trong môi trường này
# (đã xác nhận qua log: property set đúng, verify khớp, nhưng ảnh nền vẫn
# không đổi cho tới khi restart hẳn tiến trình). Nên LUÔN kill + khởi động
# lại xfdesktop, không phụ thuộc kết quả verify nữa.
echo "Restart xfdesktop để ép vẽ lại backdrop..."
killall xfdesktop 2>>"$LOG"
sleep 1
DISPLAY="${DISPLAY:-:0}" nohup xfdesktop >>"$LOG" 2>&1 &
disown
sleep 2

echo "=== xong ==="
SCRIPT
sudo chmod +x "$CHROOT/usr/local/bin/hyggshi-set-wallpaper.sh"

sudo mkdir -p "$CHROOT/etc/skel/.config/autostart"
cat <<'DESKTOP' | sudo tee "$CHROOT/etc/skel/.config/autostart/hyggshi-wallpaper.desktop" > /dev/null
[Desktop Entry]
Type=Application
Name=Hyggshi Wallpaper Setup
Exec=/usr/local/bin/hyggshi-set-wallpaper.sh
X-GNOME-Autostart-enabled=true
NoDisplay=true
DESKTOP

# === QUAN TRỌNG: cài vào /etc/xdg/autostart (system-wide, chuẩn XDG) thay vì
# chỉ copy vào ~/.config/autostart của 1 user cụ thể. Áp dụng cho MỌI user,
# kể cả user do Calamares tạo sau khi cài đặt thật (không phải "hyggshi") ===
sudo mkdir -p "$CHROOT/etc/xdg/autostart"
sudo cp "$CHROOT/etc/skel/.config/autostart/hyggshi-wallpaper.desktop" \
  "$CHROOT/etc/xdg/autostart/hyggshi-wallpaper.desktop"

if [ -f "$CHROOT/etc/xdg/autostart/hyggshi-wallpaper.desktop" ]; then
  echo "OK: đã cài autostart system-wide vào /etc/xdg/autostart/"
else
  echo "LỖI: cài autostart system-wide thất bại!"
  exit 1
fi

# user đã được tạo (useradd -m trong desktop.sh) TRƯỚC bước này nên đã copy
# sẵn config skel cũ. Ghi đè thẳng vào home để tránh dính config panel mặc
# định. (autostart không còn phụ thuộc bước này, nhưng vẫn giữ để đồng bộ
# theme/panel cho user live-session)
USER_HOME="$CHROOT/home/$OS_USERNAME"
if [ -d "$USER_HOME" ]; then
  sudo rm -rf "$USER_HOME/.config/xfce4" "$USER_HOME/.cache"
  sudo mkdir -p "$USER_HOME/.config"
  sudo cp -r "$CHROOT/etc/skel/.config/xfce4" "$USER_HOME/.config/xfce4" \
    && echo "OK: copy xfce4 config vào $USER_HOME" \
    || echo "CẢNH BÁO: copy xfce4 config vào $USER_HOME thất bại"
  sudo chroot "$CHROOT" chown -R "$OS_USERNAME:$OS_USERNAME" "/home/$OS_USERNAME/.config"
else
  echo "CẢNH BÁO: không tìm thấy $USER_HOME, bỏ qua copy config riêng cho user (autostart vẫn hoạt động vì đã ở system-wide)"
fi

echo "===== branding.sh xong ====="
