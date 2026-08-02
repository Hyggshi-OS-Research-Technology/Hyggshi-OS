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
  if command -v convert > /dev/null 2>&1; then
    convert -size 1920x1080 gradient:'#1a2a4a-#0d1220' /tmp/wallpaper.png
    sudo cp /tmp/wallpaper.png "$CHROOT/usr/share/backgrounds/hyggshi/wallpaper.png"
  else
    echo "⚠️  imagemagick không cài được — bỏ qua wallpaper, giữ theme mặc định."
  fi
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
# 1. Ưu tiên file logo có sẵn trong repo (checkout local, không phân biệt hoa/thường)
LOGO_FILE=$(find iso-config/branding -maxdepth 1 -iname "logo.*" \
  \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" \) 2>/dev/null | head -n1)

# 2. Nếu không có, tải trực tiếp từ link người dùng dán vào ($LOGO_URL, xem workflow input "logo_url")
if [ -z "$LOGO_FILE" ] && [ -n "$LOGO_URL" ]; then
  echo "Không thấy logo trong repo local, tải trực tiếp từ \$LOGO_URL..."
  if curl -fsSL "$LOGO_URL" -o /tmp/logo-remote.png && [ -s /tmp/logo-remote.png ]; then
    LOGO_FILE=/tmp/logo-remote.png
    echo "Tải thành công: $LOGO_URL"
  else
    echo "Tải thất bại từ \$LOGO_URL"
  fi
fi

if [ -n "$LOGO_FILE" ]; then
  sudo apt-get install -y imagemagick > /dev/null 2>&1 || true
  if ! command -v convert > /dev/null 2>&1; then
    echo "⚠️  imagemagick không cài được — bỏ qua đổi distributor logo."
  else
  for size in 16 22 24 32 48 64 128 192 256; do
    DEST="$CHROOT/usr/share/icons/hicolor/${size}x${size}/apps"
    sudo mkdir -p "$DEST"
    convert "$LOGO_FILE" -resize ${size}x${size} "/tmp/logo-$size.png"
    sudo cp "/tmp/logo-$size.png" "$DEST/distributor-logo.png"
  done
  sudo chroot "$CHROOT" gtk-update-icon-cache -f /usr/share/icons/hicolor 2>/dev/null || true
  echo "Đã áp logo custom: $LOGO_FILE"
  fi
else
  echo "⚠️  Không thấy file logo trong iso-config/branding/ — vẫn giữ logo mặc định của distro gốc."
  echo "    Thêm file logo.png (khuyến nghị 256x256, nền trong suốt) vào iso-config/branding/ để đổi logo."
fi

echo "===== Plymouth boot splash (logo + chữ loading) ====="
# Theme riêng "hyggshi-boot" dùng module "script" của Plymouth — logo tự
# dán qua link (PLYMOUTH_LOGO_URL), không phụ thuộc theme có sẵn trong
# plymouth-themes. Chạy TRƯỚC bất kỳ desktop environment nào lúc boot nên
# áp dụng chung cho mọi DE, không đặt trong nhánh "if DE=xfce" bên dưới.

# 1. Ưu tiên file riêng cho Plymouth trong repo (đặt tên plymouth-logo.*)
PLYMOUTH_LOGO_FILE=$(find iso-config/branding -maxdepth 1 -iname "plymouth-logo.*" \
  \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" \) 2>/dev/null | head -n1)

# 2. Nếu không có, tải từ link người dùng dán riêng cho Plymouth
#    ($PLYMOUTH_LOGO_URL, xem workflow input "plymouth_logo_url")
if [ -z "$PLYMOUTH_LOGO_FILE" ] && [ -n "$PLYMOUTH_LOGO_URL" ]; then
  echo "Không thấy plymouth-logo trong repo local, tải từ \$PLYMOUTH_LOGO_URL..."
  if curl -fsSL "$PLYMOUTH_LOGO_URL" -o /tmp/plymouth-logo-remote.png && [ -s /tmp/plymouth-logo-remote.png ]; then
    PLYMOUTH_LOGO_FILE=/tmp/plymouth-logo-remote.png
    echo "Tải thành công: $PLYMOUTH_LOGO_URL"
  fi
fi

# 3. Nếu vẫn không có gì riêng cho Plymouth, dùng lại đúng logo distributor
#    ở trên (đã tải/tìm sẵn trong $LOGO_FILE) thay vì bỏ trắng màn hình chờ.
if [ -z "$PLYMOUTH_LOGO_FILE" ] && [ -n "$LOGO_FILE" ]; then
  PLYMOUTH_LOGO_FILE="$LOGO_FILE"
  echo "Dùng chung logo distributor cho Plymouth: $LOGO_FILE"
fi

if [ -z "$PLYMOUTH_LOGO_FILE" ]; then
  echo "⚠️  Không có logo nào cho Plymouth (thiếu file local, PLYMOUTH_LOGO_URL và LOGO_URL đều trống/tải lỗi) — bỏ qua, giữ Plymouth theme mặc định của distro gốc."
else
  THEME_DIR="$CHROOT/usr/share/plymouth/themes/hyggshi-boot"
  sudo mkdir -p "$THEME_DIR"
  # Bỏ dấu " khỏi DISTRO_NAME trước khi chèn vào file .plymouth (ini) và
  # .script (chuỗi kiểu C) — nếu không, 1 dấu " trong distro_name (input
  # người dùng tự đặt) sẽ làm hỏng cú pháp cả 2 file này.
  DISTRO_NAME_SAFE="${DISTRO_NAME//\"/}"

  sudo apt-get install -y imagemagick > /dev/null 2>&1 || true
  if command -v convert > /dev/null 2>&1; then
    convert "$PLYMOUTH_LOGO_FILE" -resize 256x256 /tmp/plymouth-logo.png
  else
    cp "$PLYMOUTH_LOGO_FILE" /tmp/plymouth-logo.png
  fi
  sudo cp /tmp/plymouth-logo.png "$THEME_DIR/logo.png"

  cat <<PLYMOUTHEOF | sudo tee "$THEME_DIR/hyggshi-boot.plymouth" > /dev/null
[Plymouth Theme]
Name=Hyggshi Boot
Description=$DISTRO_NAME_SAFE boot splash (logo + loading text)
ModuleName=script

[script]
ImageDir=/usr/share/plymouth/themes/hyggshi-boot
ScriptFile=/usr/share/plymouth/themes/hyggshi-boot/hyggshi-boot.script
PLYMOUTHEOF

  # Ngôn ngữ script riêng của Plymouth (cú pháp kiểu C, xem
  # freedesktop.org/wiki/Software/Plymouth/Scripts). Logo tĩnh ở giữa màn
  # hình + dòng chữ "<DISTRO_NAME> đang khởi động..." có dấu chấm chạy
  # (0-3 dấu chấm lặp lại) làm hiệu ứng loading, cập nhật qua
  # Plymouth.SetRefreshFunction (gọi ~50 lần/giây).
  cat <<SCRIPTEOF | sudo tee "$THEME_DIR/hyggshi-boot.script" > /dev/null
Window.SetBackgroundTopColor(0.05, 0.07, 0.12);
Window.SetBackgroundBottomColor(0.02, 0.03, 0.05);

window_width = Window.GetWidth();
window_height = Window.GetHeight();

logo.image = Image("logo.png");
logo.sprite = Sprite(logo.image);
logo_x = window_width / 2 - logo.image.GetWidth() / 2;
logo_y = window_height / 2 - logo.image.GetHeight() / 2 - 40;
logo.sprite.SetX(logo_x);
logo.sprite.SetY(logo_y);
logo.sprite.SetZ(10);

message_sprite = Sprite();
message_sprite.SetZ(10);
message_y = logo_y + logo.image.GetHeight() + 30;

dot_count = 0;

fun refresh_callback() {
  dot_count++;
  if (dot_count > 24) {
    dot_count = 0;
  }
  n_dots = dot_count / 8 + 1;
  dots = "";
  i = 0;
  while (i < n_dots) {
    dots = dots + ".";
    i++;
  }
  msg_text = "$DISTRO_NAME_SAFE đang khởi động" + dots;
  message_image = Image.Text(msg_text, 0.85, 0.85, 0.9, 1, "Sans 12");
  message_sprite.SetImage(message_image);
  message_sprite.SetX(window_width / 2 - message_image.GetWidth() / 2);
  message_sprite.SetY(message_y);
}
Plymouth.SetRefreshFunction(refresh_callback);
SCRIPTEOF

  echo "===== Đặt 'hyggshi-boot' làm Plymouth theme mặc định (-R tự rebuild initramfs) ====="
  # BẮT BUỘC rebuild initramfs mỗi khi đổi theme Plymouth, nếu không initrd
  # cũ (không có theme mới) vẫn được iso.sh lấy vào ISO — cờ -R của
  # plymouth-set-default-theme tự làm việc này (gọi update-initramfs -u).
  if sudo chroot "$CHROOT" bash -c 'command -v plymouth-set-default-theme' > /dev/null 2>&1; then
    if sudo chroot "$CHROOT" plymouth-set-default-theme -R hyggshi-boot 2>&1; then
      echo "OK: đã đặt Plymouth theme 'hyggshi-boot' làm mặc định."
    else
      echo "⚠️  plymouth-set-default-theme -R lỗi — thử lại không rebuild rồi tự update-initramfs."
      sudo chroot "$CHROOT" plymouth-set-default-theme hyggshi-boot || true
      sudo chroot "$CHROOT" update-initramfs -u || true
    fi
  else
    echo "⚠️  Không tìm thấy plymouth-set-default-theme trong chroot — bỏ qua, giữ Plymouth theme mặc định."
  fi
fi

echo "===== Fastfetch: gắn logo.txt custom (nhúng sẵn ANSI màu) ====="
# ĐẶT TRƯỚC nhánh "if DE != xfce -> exit 0" bên dưới để áp dụng cho MỌI DE
# (KDE/LXQt/GNOME/MATE/Cinnamon), không chỉ riêng XFCE.
# logo.txt là ASCII/ANSI-art ĐÃ CÓ SẴN mã màu (\033[38;2;r;g;bm...) — dùng
# "type": "file" trong config fastfetch để fastfetch IN THẲNG nội dung file,
# giữ nguyên escape sequence màu, KHÔNG convert lại từ ảnh (đỡ phải cài
# libchafa/imagemagick chỉ để render logo).
FASTFETCH_LOGO_SRC=$(find iso-config/branding -maxdepth 1 -iname "logo.txt" 2>/dev/null | head -n1)
if [ -n "$FASTFETCH_LOGO_SRC" ]; then
  LOGO_DEST_DIR="$CHROOT/usr/share/hyggshi/branding"
  sudo mkdir -p "$LOGO_DEST_DIR"
  sudo cp "$FASTFETCH_LOGO_SRC" "$LOGO_DEST_DIR/logo.txt"

  # Config mặc định — đặt trong /etc/xdg/fastfetch/ (system-wide default mà
  # fastfetch tự đọc nếu user chưa có config riêng ở ~/.config/fastfetch/).
  sudo mkdir -p "$CHROOT/etc/xdg/fastfetch"
  cat <<'FFCFG' | sudo tee "$CHROOT/etc/xdg/fastfetch/config.jsonc" > /dev/null
{
  "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
  "logo": {
    "type": "file",
    "source": "/usr/share/hyggshi/branding/logo.txt",
    "width": 48
  },
  "display": {
    "separator": " "
  },
  "modules": [
    "title",
    "separator",
    { "type": "os", "key": "OS" },
    { "type": "host", "key": "Máy" },
    { "type": "kernel", "key": "Kernel" },
    { "type": "uptime", "key": "Uptime" },
    { "type": "packages", "key": "Packages" },
    { "type": "shell", "key": "Shell" },
    { "type": "de", "key": "DE" },
    { "type": "wm", "key": "WM" },
    { "type": "display", "key": "Màn hình" },
    { "type": "theme", "key": "Theme" },
    { "type": "icons", "key": "Icons" },
    { "type": "terminal", "key": "Terminal" },
    "break",
    { "type": "cpu", "key": "CPU" },
    { "type": "gpu", "key": "GPU" },
    { "type": "memory", "key": "RAM" },
    { "type": "swap", "key": "Swap" },
    { "type": "disk", "key": "Disk" },
    { "type": "localip", "key": "IP" },
    "break",
    "colors"
  ]
}
FFCFG

  # Ghi vào skel (user Calamares tạo sau này) + user live hiện có — fastfetch
  # ưu tiên ~/.config/fastfetch/config.jsonc của user hơn /etc/xdg nếu có.
  sudo mkdir -p "$CHROOT/etc/skel/.config/fastfetch"
  sudo cp "$CHROOT/etc/xdg/fastfetch/config.jsonc" \
    "$CHROOT/etc/skel/.config/fastfetch/config.jsonc"

  # User live (useradd -m) đã được tạo TRƯỚC ở desktop.sh nên đã có sẵn
  # $USER_HOME — nhưng biến này (định nghĩa ở dưới, gần cuối file) chưa tồn
  # tại ở điểm này trong luồng chạy, nên tính lại tại chỗ.
  FF_USER_HOME="$CHROOT/home/$OS_USERNAME"
  if [ -d "$FF_USER_HOME" ]; then
    sudo mkdir -p "$FF_USER_HOME/.config/fastfetch"
    sudo cp "$CHROOT/etc/xdg/fastfetch/config.jsonc" \
      "$FF_USER_HOME/.config/fastfetch/config.jsonc"
    sudo chroot "$CHROOT" chown -R "$OS_USERNAME:$OS_USERNAME" "/home/$OS_USERNAME/.config/fastfetch"

    # Chạy fastfetch mỗi khi mở terminal mới — chỉ thêm nếu chưa có, tránh
    # nhân đôi khi build lại nhiều lần trên cùng chroot.
    for RC in "$CHROOT/etc/skel/.bashrc" "$FF_USER_HOME/.bashrc"; do
      if [ -f "$RC" ] && ! sudo grep -q "^command -v fastfetch" "$RC" 2>/dev/null; then
        printf '\n# Hyggshi OS: hiện thông tin hệ thống + logo khi mở terminal\ncommand -v fastfetch >/dev/null 2>&1 && fastfetch\n' \
          | sudo tee -a "$RC" > /dev/null
      fi
    done
    sudo chroot "$CHROOT" chown "$OS_USERNAME:$OS_USERNAME" "/home/$OS_USERNAME/.bashrc" 2>/dev/null || true
  fi

  echo "OK: đã gắn logo.txt custom cho fastfetch (/usr/share/hyggshi/branding/logo.txt)."
else
  echo "Không thấy iso-config/branding/logo.txt trong repo — fastfetch dùng logo tự nhận diện distro mặc định."
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
        <property name="workspace0" type="empty">
          <property name="last-image" type="string" value="/usr/share/backgrounds/hyggshi/wallpaper.png"/>
          <property name="image-style" type="int" value="5"/>
        </property>
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

# Chờ xfdesktop thật sự chạy (tối đa 20s), tránh race condition lúc login
for i in $(seq 1 20); do
  if pgrep -x xfdesktop >/dev/null; then
    echo "xfdesktop đã chạy sau ${i}s"
    break
  fi
  sleep 1
done

# Chờ THÊM để xfdesktop tự tạo xong cây property /backdrop của nó (lần đầu
# boot có thể chậm hơn hẳn so với chỉ chờ process xuất hiện — nếu ta đọc
# property quá sớm, danh sách sẽ RỖNG và script sẽ rơi vào fallback
# monitor0, trong khi tên monitor thật (vd "Virtual-1", "eDP-1"...) không
# khớp -> wallpaper không hề đổi trên màn hình dù bước "verify" bên dưới
# vẫn báo khớp, vì lúc đó nó chỉ đang so khớp với chính property fallback
# mà script tự tạo ra.
PROPS=""
for i in $(seq 1 20); do
  PROPS=$(xfconf-query -c xfce4-desktop -p /backdrop -l 2>/dev/null | grep 'last-image$')
  if [ -n "$PROPS" ]; then
    echo "Tìm thấy property sau ${i}s chờ"
    break
  fi
  sleep 1
done

apply_wallpaper() {
  # liệt kê MỌI property last-image mà xfdesktop đang thực sự dùng (tên
  # monitor như "monitor0" không đúng trên mọi máy/VM, QEMU thường đặt tên
  # khác như "Virtual-1")
  PROPS=$(xfconf-query -c xfce4-desktop -p /backdrop -l 2>/dev/null | grep 'last-image$')
  if [ -z "$PROPS" ]; then
    echo "Chưa có property nào — dò tên monitor thật qua xrandr, cộng thêm fallback monitor0"
    REAL_MONITORS=$(xrandr --query 2>/dev/null | awk '/ connected/{print $1}')
    PROPS="/backdrop/screen0/monitor0/workspace0/last-image"
    for m in $REAL_MONITORS; do
      PROPS="$PROPS
/backdrop/screen0/monitor${m}/workspace0/last-image"
    done
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
xfdesktop --reload 2>>"$LOG"
sleep 1

# LUÔN restart hẳn xfdesktop (không chỉ gọi --reload) sau khi set property,
# vì lần đầu TẠO property mới (-n) xfdesktop đang chạy thường không tự
# "nhìn thấy" giá trị vừa tạo chỉ bằng --reload — phải khởi động lại tiến
# trình để nó đọc lại toàn bộ cấu hình từ xfconf.
killall xfdesktop 2>>"$LOG" || true
sleep 1
nohup xfdesktop >>"$LOG" 2>&1 &
sleep 1

echo "--- verify sau khi set (chỉ để ghi log, không quyết định có restart hay không) ---"
CHECK=$(xfconf-query -c xfce4-desktop -p /backdrop -l 2>/dev/null | grep 'last-image$' | head -n1)
if [ -n "$CHECK" ]; then
  VAL=$(xfconf-query -c xfce4-desktop -p "$CHECK" 2>/dev/null)
  echo "verify: $CHECK = $VAL"
  if [ "$VAL" != "$WALL" ]; then
    echo "Verify không khớp, retry lần 2"
    apply_wallpaper
    killall xfdesktop 2>>"$LOG" || true
    sleep 1
    nohup xfdesktop >>"$LOG" 2>&1 &
  fi
fi

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
