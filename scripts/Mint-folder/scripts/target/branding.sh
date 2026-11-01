#!/bin/bash
# branding.sh — wallpaper, distributor logo, rebrand os-release/lsb-release,
# panel style + icon theme XFCE, autostart. Chạy trên HOST, ghi thẳng vào
# thư mục chroot (không cần chroot exec, trừ gtk-update-icon-cache).
set -e
[ "$DEBUG_MODE" = "true" ] && set -x
CHROOT=build/chroot

# ===== Hyggshi OS Codename =====
# Codename RIÊNG của Hyggshi OS (kiểu Ubuntu "Jammy Jellyfish"), KHÔNG phải
# codename của base distro ($BASE_CODENAME, vd "bookworm"/"noble" — cái đó
# vẫn được giữ nguyên, chỉ đổi vai trò sang HYGGSHI_BASE_CODENAME trong
# os-release). Không thêm workflow input mới (đã chạm giới hạn 25 input của
# workflow_dispatch — xem ghi chú trong build-hyggshi-os.yml), nên chọn
# theo VERSION_ID hiện có, có thể override bằng biến môi trường
# HYGGSHI_CODENAME nếu build script nào đó (local-build.sh...) muốn set tay.
: "${HYGGSHI_VERSION_ID:=1.0}"
declare -A HYGGSHI_CODENAMES=(
  ["1.0"]="Sen Vàng"
  ["1.1"]="Trúc Xanh"
  ["1.2"]="Mây Ngàn"
  ["2.0"]="Sương Mai"
)
if [ -z "$HYGGSHI_CODENAME" ]; then
  HYGGSHI_CODENAME="${HYGGSHI_CODENAMES[$HYGGSHI_VERSION_ID]:-Sen Vàng}"
fi
echo "Hyggshi OS Codename: $HYGGSHI_CODENAME (version $HYGGSHI_VERSION_ID)"

echo "===== Copy Plymouth branding (nếu có) ====="
if [ -d "config/branding" ]; then
  sudo cp -r config/branding/* "$CHROOT/usr/share/plymouth/themes/" 2>/dev/null || true
fi

echo "===== GRUB/Desktop-base branding ====="
# Luôn ghi đè file desktop-base bằng branding riêng của Hyggshi OS.
# Nguồn repo: ./config/branding/desktop-grub.png và desktop-grub.svg
# Đây là file mà desktop-base/GRUB của hệ thống dùng tại:
#   /usr/share/images/desktop-base/desktop-grub.png
GRUB_BRANDING_DIR="$CHROOT/usr/share/images/desktop-base"
sudo mkdir -p "$GRUB_BRANDING_DIR"
if [ -f "config/branding/desktop-grub.png" ]; then
  sudo install -m 0644 "config/branding/desktop-grub.png" \
    "$GRUB_BRANDING_DIR/desktop-grub.png"
  echo "OK: ghi đè $GRUB_BRANDING_DIR/desktop-grub.png"
else
  echo "WARNING: thiếu config/branding/desktop-grub.png — không ghi đè desktop-base background."
fi
if [ -f "config/branding/desktop-grub.svg" ]; then
  sudo install -m 0644 "config/branding/desktop-grub.svg" \
    "$GRUB_BRANDING_DIR/desktop-grub.svg"
  echo "OK: copy $GRUB_BRANDING_DIR/desktop-grub.svg"
fi

echo "===== Wallpaper ====="
sudo mkdir -p "$CHROOT/usr/share/backgrounds/hyggshi"

# Wallpaper mặc định riêng cho Cinnamon/Hyggshi OS. File này được copy vào
# đúng đường dẫn mà lệnh GSettings lúc login sử dụng.
if [ -f "config/branding/Verdant-Valley.png" ]; then
  sudo install -m 0644 "config/branding/Verdant-Valley.png" \
    "$CHROOT/usr/share/backgrounds/hyggshi/Verdant-Valley.png"
  echo "Đã copy Verdant-Valley.png vào /usr/share/backgrounds/hyggshi/"
else
  echo "⚠️ Không thấy config/branding/Verdant-Valley.png — Cinnamon sẽ dùng wallpaper fallback hiện có."
fi

# car-light.png / car-Dark.png: wallpaper riêng cho theme Sáng/Tối, được
# hyggshi-welcome (packages/hyggshi/hyggshi-welcome/) áp tự động khi user chọn theme ở trang
# "Chọn giao diện". Copy sẵn vào đây (không phụ thuộc cmake install của app)
# để có mặt ngay cả khi app hyggshi-welcome chưa từng được build/cài riêng.
for CAR_FILE in car-light.png car-Dark.png car-auto.png; do
  if [ -f "config/branding/$CAR_FILE" ]; then
    sudo cp "config/branding/$CAR_FILE" "$CHROOT/usr/share/backgrounds/hyggshi/$CAR_FILE"
    echo "Đã copy $CAR_FILE vào /usr/share/backgrounds/hyggshi/"
  else
    echo "⚠️  Không thấy config/branding/$CAR_FILE — hyggshi-welcome sẽ bỏ qua đổi wallpaper cho theme tương ứng."
  fi
done

# 1. Ưu tiên file wallpaper có sẵn trong repo (checkout local, không phân biệt hoa/thường)
WALLPAPER_FILE=$(find config/branding -maxdepth 1 -iname "wallpaper.*" \
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

# 3. Áp dụng, hoặc fallback gradient nếu cả 2 cách trên đều fail. KHÔNG còn
# hardcode coi như wallpaper.png luôn tồn tại ở các bước sau — WALLPAPER_APPLIED
# ghi lại đúng thực tế có/không có file, để mọi bước áp dụng (update-alternatives,
# patch xfce4-desktop.xml, skel property, autostart script) chỉ chạy khi thật sự
# có wallpaper, tránh trỏ vào 1 file không tồn tại.
WALLPAPER_APPLIED=false
if [ -n "$WALLPAPER_FILE" ]; then
  sudo cp "$WALLPAPER_FILE" "$CHROOT/usr/share/backgrounds/hyggshi/wallpaper.png"
  WALLPAPER_APPLIED=true
  echo "Đã dùng wallpaper: $WALLPAPER_FILE"
else
  echo "⚠️  Không lấy được wallpaper — tự tạo wallpaper gradient tạm thời."
  sudo apt-get install -y imagemagick > /dev/null 2>&1 || true
  if command -v convert > /dev/null 2>&1; then
    convert -size 1920x1080 gradient:'#1a2a4a-#0d1220' /tmp/wallpaper.png
    sudo cp /tmp/wallpaper.png "$CHROOT/usr/share/backgrounds/hyggshi/wallpaper.png"
    WALLPAPER_APPLIED=true
  else
    echo "⚠️  imagemagick không cài được — bỏ qua wallpaper, giữ theme mặc định."
  fi
fi

if [ "$WALLPAPER_APPLIED" = "true" ]; then
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
else
  echo "===== Bỏ qua update-alternatives / patch xfce4-desktop.xml (không có wallpaper.png thật) ====="
fi

echo "===== Custom màn hình đăng nhập (LightDM GTK Greeter) ====="
# Mặc định lightdm-gtk-greeter dùng theme GTK gốc của hệ thống -> ra cái hộp
# thoại trắng vuông vức, avatar xám xịt như ảnh mô tả trong issue. Ở đây ta
# tự viết 1 GTK3 theme riêng CHỈ áp cho greeter (không đụng tới GTK theme
# của desktop bên trong phiên đăng nhập), nên không phụ thuộc Windows-10/
# Orchis theme có clone được hay không (xem khối clone theme trong desktop.sh).
GREETER_THEME_DIR="$CHROOT/usr/share/themes/Hyggshi-Greeter/gtk-3.0"
sudo mkdir -p "$GREETER_THEME_DIR"

sudo tee "$CHROOT/usr/share/themes/Hyggshi-Greeter/index.theme" > /dev/null <<EOF
[Desktop Entry]
Type=X-GNOME-Metatheme
Name=Hyggshi-Greeter
Comment=Giao diện đăng nhập tuỳ chỉnh cho Hyggshi OS
Encoding=UTF-8

[X-GNOME-Metatheme]
GtkTheme=Hyggshi-Greeter
IconTheme=Papirus-Dark
CursorTheme=Bibata-Modern-Classic
EOF

sudo tee "$GREETER_THEME_DIR/gtk.css" > /dev/null <<'CSS'
/* Hyggshi OS — theme riêng cho lightdm-gtk-greeter, viết từ đầu để không
   phụ thuộc theme nào khác. Chỉ nhắm tới các widget-id mà lightdm-gtk-greeter
   đặt sẵn (#login_window, #panel_window...) nên không ảnh hưởng theme GTK
   của desktop session bên trong. */

* {
  font-family: "Ubuntu", "Noto Sans", sans-serif;
}

window {
  background-color: transparent;
}

/* Thanh panel trên cùng: đồng hồ, chọn session/ngôn ngữ, nút tắt máy */
#panel_window {
  background-color: rgba(13, 18, 32, 0.55);
  color: #f2f5f7;
}
#panel_window button,
#panel_window menuitem,
#panel_window GtkLabel {
  color: #f2f5f7;
}

/* Hộp đăng nhập chính — thay cho ô vuông trắng mặc định */
#login_window {
  background-color: rgba(15, 23, 38, 0.85);
  border-radius: 18px;
  border: 1px solid rgba(255, 255, 255, 0.12);
  box-shadow: 0 12px 40px rgba(0, 0, 0, 0.45);
  padding: 28px 32px;
  color: #f2f5f7;
}
#login_window GtkLabel { color: #f2f5f7; }

/* Ô nhập username / password */
#login_window entry,
#login_window GtkEntry {
  background-color: rgba(255, 255, 255, 0.08);
  color: #ffffff;
  border: 1px solid rgba(255, 255, 255, 0.18);
  border-radius: 10px;
  padding: 8px 12px;
  min-height: 22px;
}
#login_window entry:focus {
  border-color: #7fd8c8;
  box-shadow: 0 0 0 2px rgba(127, 216, 200, 0.25);
}

/* Nút Cancel / Log In */
#login_window button,
#login_window GtkButton {
  background-image: none;
  background-color: rgba(255, 255, 255, 0.1);
  color: #ffffff;
  border: 1px solid rgba(255, 255, 255, 0.16);
  border-radius: 10px;
  padding: 8px 18px;
}
#login_window button:hover,
#login_window GtkButton:hover {
  background-color: rgba(127, 216, 200, 0.22);
  border-color: #7fd8c8;
}
#login_window #button_login,
#login_window #login_button {
  background-color: #2fae94;
  border-color: #2fae94;
  font-weight: 600;
}
#login_window #button_login:hover,
#login_window #login_button:hover {
  background-color: #37c6a8;
  border-color: #37c6a8;
}

/* Dropdown chọn user / session / ngôn ngữ */
#login_window combobox,
#login_window GtkComboBox {
  background-color: rgba(255, 255, 255, 0.08);
  color: #ffffff;
  border-radius: 10px;
  border: 1px solid rgba(255, 255, 255, 0.18);
}

/* Avatar user bo tròn thay vì vuông xám */
#login_window GtkImage {
  border-radius: 50%;
}

/* Text lỗi khi gõ sai mật khẩu */
#login_window #message_label,
#login_window .error {
  color: #ff8a8a;
}

/* Menu power (Suspend/Hibernate/Restart/Shut Down) bung ra từ #panel_window
   khi bấm icon nguồn — mặc định GTK vẽ menu này trơ trọi, chỉ chữ đen trên
   nền trắng/xám (xem ảnh mô tả trong issue). Style lại thành khối tối bo
   góc đồng bộ với #login_window, có highlight khi rê chuột, thay vì nhìn
   như 1 tooltip lạc lõng giữa màn hình. */
menu,
GtkMenu {
  background-color: rgba(15, 23, 38, 0.92);
  border: 1px solid rgba(255, 255, 255, 0.14);
  border-radius: 12px;
  padding: 6px;
  box-shadow: 0 12px 32px rgba(0, 0, 0, 0.5);
}
menu menuitem,
GtkMenu GtkMenuItem {
  color: #f2f5f7;
  border-radius: 8px;
  padding: 8px 14px;
  min-width: 200px;
}
menu menuitem:hover,
GtkMenu GtkMenuItem:hover {
  background-color: rgba(127, 216, 200, 0.22);
}
/* Phím tắt (Alt+Delete, Alt+F4...) hiển thị mờ hơn chữ chính, đỡ rối mắt */
menu menuitem accelerator,
GtkMenu GtkMenuItem GtkAccelLabel {
  color: rgba(242, 245, 247, 0.55);
}
menu separator,
GtkMenu GtkSeparatorMenuItem {
  background-color: rgba(255, 255, 255, 0.12);
  margin: 4px 6px;
}
CSS

# Icon theme cho greeter: map theo $ICON_THEME đã chọn ở desktop.sh (mặc định papirus)
case "${ICON_THEME:-papirus}" in
  numix)   GREETER_ICON_THEME="Numix" ;;
  breeze)  GREETER_ICON_THEME="Breeze-Dark" ;;
  adwaita) GREETER_ICON_THEME="Adwaita" ;;
  tela)    GREETER_ICON_THEME="Tela-dark" ;;
  *)       GREETER_ICON_THEME="Papirus-Dark" ;;
esac

# Background cho greeter: dùng wallpaper thật nếu có, không thì fallback về
# màu nền gradient tối (lightdm-gtk-greeter nhận cả path ảnh lẫn mã màu hex
# trong key "background").
if [ "$WALLPAPER_APPLIED" = "true" ]; then
  GREETER_BACKGROUND="/usr/share/backgrounds/hyggshi/wallpaper.png"
else
  GREETER_BACKGROUND="#0d1220"
fi

sudo mkdir -p "$CHROOT/etc/lightdm"
sudo tee "$CHROOT/etc/lightdm/lightdm-gtk-greeter.conf" > /dev/null <<EOF
[greeter]
background=$GREETER_BACKGROUND
theme-name=Hyggshi-Greeter
icon-theme-name=$GREETER_ICON_THEME
font-name=Ubuntu 11
xft-antialias=true
xft-hintstyle=slight
xft-rgba=rgb
xft-dpi=96
indicators=~host;~spacer;~clock;~spacer;~language;~session;~a11y;~power
clock-format=%H:%M
position=50%,center 55%,center
hide-user-image=false
EOF
echo "Đã ghi $CHROOT/etc/lightdm/lightdm-gtk-greeter.conf (theme=Hyggshi-Greeter, icon=$GREETER_ICON_THEME)"

echo "===== Rebrand os-release / lsb-release / banner ====="
# Debian mặc định để /etc/os-release là symlink -> ../usr/lib/os-release.
# Xoá symlink cũ, ghi nội dung THẬT vào usr/lib/os-release, rồi tạo lại
# /etc/os-release như symlink TƯƠNG ĐỐI (không phải tuyệt đối) trỏ tới nó.
sudo rm -f "$CHROOT/etc/os-release" "$CHROOT/usr/lib/os-release"

ID_LIKE_VALUE="ubuntu debian"

cat <<EOF | sudo tee "$CHROOT/usr/lib/os-release" > /dev/null
PRETTY_NAME="$DISTRO_NAME $HYGGSHI_VERSION_ID $HYGGSHI_CODENAME"
NAME="$DISTRO_NAME"
VERSION_ID="$HYGGSHI_VERSION_ID"
VERSION="$HYGGSHI_VERSION_ID ($HYGGSHI_CODENAME) ($DISTRO_LABEL)"
VERSION_CODENAME="$HYGGSHI_CODENAME"
HYGGSHI_BASE_CODENAME=$BASE_CODENAME
ID=hyggshios
ID_LIKE=$ID_LIKE_VALUE
# Explicitly preserve the real base distro for Hyggshi applications.
# ID is branded as hyggshios, so apps must not guess the base from ID alone.
HYGGSHI_BASE_DISTRO=$BASE_DISTRO
HOME_URL="https://github.com/Hyggshi-OS-Research-Technology"
SUPPORT_URL="https://github.com/Hyggshi-OS-Research-Technology/Hyggshi-OS/issues"
BUG_REPORT_URL="https://github.com/Hyggshi-OS-Research-Technology/Hyggshi-OS/issues"
LOGO=distributor-logo
EOF
sudo ln -sf ../usr/lib/os-release "$CHROOT/etc/os-release"

cat <<EOF | sudo tee "$CHROOT/etc/lsb-release" > /dev/null
DISTRIB_ID=HyggshiOS
DISTRIB_RELEASE=$HYGGSHI_VERSION_ID
DISTRIB_CODENAME="$HYGGSHI_CODENAME"
DISTRIB_DESCRIPTION="$DISTRO_NAME $HYGGSHI_VERSION_ID \"$HYGGSHI_CODENAME\" ($DISTRO_LABEL)"
EOF

printf "%s \"%s\" \\n \\l\n\n" "$DISTRO_NAME" "$HYGGSHI_CODENAME" | sudo tee "$CHROOT/etc/issue" > /dev/null
echo "Welcome to $DISTRO_NAME \"$HYGGSHI_CODENAME\" — built on $DISTRO_LABEL" | sudo tee "$CHROOT/etc/motd" > /dev/null

echo "===== Distributor logo ====="
# 1. Ưu tiên file logo có sẵn trong repo (checkout local, không phân biệt hoa/thường)
LOGO_FILE=$(find config/branding -maxdepth 1 -iname "logo.*" \
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
  echo "⚠️  Không thấy file logo trong config/branding/ — vẫn giữ logo mặc định của distro gốc."
  echo "    Thêm file logo.png (khuyến nghị 256x256, nền trong suốt) vào config/branding/ để đổi logo."
fi

# ===== Persist Hyggshi icons/installer shortcut into the installed system =====
# branding.sh runs after the live user has been created and after Calamares has
# been installed. Put the same launcher/icon into /etc/skel so a user created
# by Calamares after installation does not receive the Debian default icon.
if [ -f "config/branding/Hyggshi-OS-Installer.png" ]; then
  echo "===== Persist Install Hyggshi OS icon + desktop entry ====="
  INSTALLER_ICON="$CHROOT/usr/share/icons/hicolor/256x256/apps/hyggshi-installer.png"
  sudo mkdir -p "$(dirname "$INSTALLER_ICON")" "$CHROOT/usr/share/pixmaps" "$CHROOT/etc/skel/Desktop"
  sudo install -m 0644 "config/branding/Hyggshi-OS-Installer.png" "$INSTALLER_ICON"
  sudo install -m 0644 "config/branding/Hyggshi-OS-Installer.png" "$CHROOT/usr/share/pixmaps/hyggshi-installer.png"
  sudo tee "$CHROOT/etc/skel/Desktop/install-hyggshi-os.desktop" > /dev/null <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Install Hyggshi OS
Comment=Cài đặt Hyggshi OS
Exec=pkexec calamares
Icon=hyggshi-installer
Terminal=false
Categories=System;Settings;
DESKTOP
  sudo chmod 0644 "$CHROOT/etc/skel/Desktop/install-hyggshi-os.desktop"

  # Also refresh the live user's shortcut if one exists.
  for user_desktop in "$CHROOT/home/*/Desktop" "$CHROOT/root/Desktop"; do
    [ -d "$user_desktop" ] || continue
    sudo cp "$CHROOT/etc/skel/Desktop/install-hyggshi-os.desktop" "$user_desktop/install-hyggshi-os.desktop" 2>/dev/null || true
  done
fi

# Make the Welcome icon robust against icon-theme/cache changes after install.
WELCOME_ICON_SRC="packages/hyggshi/hyggshi-welcome/resources/icons/logo.png"
if [ -f "$WELCOME_ICON_SRC" ]; then
  for size in 48 64 128 192 256; do
    DEST="$CHROOT/usr/share/icons/hicolor/${size}x${size}/apps"
    sudo mkdir -p "$DEST"
    if command -v convert >/dev/null 2>&1; then
      convert "$WELCOME_ICON_SRC" -resize ${size}x${size} "/tmp/hyggshi-welcome-$size.png"
      sudo cp "/tmp/hyggshi-welcome-$size.png" "$DEST/hyggshi-welcome.png"
    else
      sudo cp "$WELCOME_ICON_SRC" "$DEST/hyggshi-welcome.png"
    fi
  done
  sudo chroot "$CHROOT" gtk-update-icon-cache -f -t /usr/share/icons/hicolor 2>/dev/null || true
  echo "OK: Hyggshi Welcome icon đã được cài vào hicolor."
fi

echo "===== Calamares: đổi logo sidebar (branding.desc) ====="
# desktop.sh (chạy TRƯỚC branding.sh, xem thứ tự trong workflow .yml) đã cài
# calamares + calamares-settings-debian trong chroot, nên tới đây thư mục
# branding của calamares đã tồn tại sẵn để ghi đè.
CALAMARES_SETTINGS="$CHROOT/etc/calamares/settings.conf"
if [ -n "$LOGO_FILE" ] && [ -f "$CALAMARES_SETTINGS" ]; then
  sudo apt-get install -y imagemagick > /dev/null 2>&1 || true
  if ! command -v convert > /dev/null 2>&1; then
    echo "⚠️  imagemagick không cài được — bỏ qua đổi logo sidebar Calamares."
  else
    # Component branding thực sự đang được settings.conf trỏ tới (dòng
    # "branding: <tên>"). calamares-settings-debian dùng "debian" nhưng
    # fallback về đúng tên đó nếu không đọc được, thay vì đoán bừa.
    #
    # BUG ĐÃ SỬA #1: bản trước dùng `tr -d '"'"'"'\r'` — bên ngoài dấu nháy
    # đơn, "\r" trong bash KHÔNG phải carriage return, nó chỉ là ký tự "r"
    # thường (backslash chỉ triệt tiêu nghĩa đặc biệt của ký tự theo sau,
    # "r" vốn không có nghĩa đặc biệt gì). Hệ quả: lệnh tr này vô tình XOÁ
    # MỌI CHỮ "r" xuất hiện trong tên component/tên file, khiến "cp" ghi
    # nhầm đường dẫn. Dùng $'\r' (ANSI-C quoting) để có đúng ký tự carriage
    # return thật, không đụng tới chữ "r" thường trong tên file.
    #
    # BUG ĐÃ SỬA #2 (nguyên nhân THẬT SỰ khiến logo Calamares không đổi dù
    # bug #1 đã sửa): gói .deb "calamares-settings-debian" của Debian cài
    # branding.desc vào /etc/calamares/branding/debian/, KHÔNG PHẢI
    # /usr/share/calamares/branding/debian/ (path đó chỉ đúng khi build
    # Calamares từ source, src/branding/). Dùng sai path khiến script luôn
    # coi như "không tìm thấy branding.desc" và bỏ qua toàn bộ bước ghi đè,
    # dù file logo/branding.desc thật sự tồn tại sẵn trong chroot.
    BRANDING_COMPONENT=$(sudo grep -E '^\s*branding\s*:' "$CALAMARES_SETTINGS" \
      | head -n1 | sed -E 's/^[^:]*:[[:space:]]*//' | tr -d "\"'" | tr -d $'\r')
    [ -z "$BRANDING_COMPONENT" ] && BRANDING_COMPONENT="hyggshios"

    BRANDING_DIR="$CHROOT/etc/calamares/branding/$BRANDING_COMPONENT"
    BRANDING_DESC="$BRANDING_DIR/branding.desc"

    if [ -f "$BRANDING_DESC" ]; then
      # Lấy ĐÚNG tên file mà branding.desc khai báo cho "productLogo" (logo
      # hiển thị đầu sidebar) thay vì đoán "logo.png" — mỗi bản
      # calamares-settings-* có thể đặt tên file khác nhau.
      LOGO_IMG_NAME=$(sudo grep -E '^\s*productLogo\s*:' "$BRANDING_DESC" \
        | head -n1 | sed -E 's/^[^:]*:[[:space:]]*//' | tr -d "\"'" | tr -d $'\r')
      [ -z "$LOGO_IMG_NAME" ] && LOGO_IMG_NAME="logo.png"

      echo "DEBUG: BRANDING_COMPONENT='$BRANDING_COMPONENT' LOGO_IMG_NAME='$LOGO_IMG_NAME'"
      echo "DEBUG: sẽ ghi vào -> $BRANDING_DIR/$LOGO_IMG_NAME"

      # Resize giữ nguyên tỷ lệ trên nền trong suốt (không méo ảnh, không
      # méo khung vuông của sidebar) rồi ghi đè thẳng vào đúng file cũ.
      convert "$LOGO_FILE" -resize 256x256 -background none -gravity center \
        -extent 256x256 /tmp/calamares-sidebar-logo.png

      if [ ! -f "$BRANDING_DIR/$LOGO_IMG_NAME" ]; then
        echo "CẢNH BÁO: '$BRANDING_DIR/$LOGO_IMG_NAME' không tồn tại TRƯỚC khi ghi —" >&2
        echo "kiểm tra lại LOGO_IMG_NAME có bị cắt sai tên không (xem dòng DEBUG ở trên)." >&2
      fi

      sudo cp /tmp/calamares-sidebar-logo.png "$BRANDING_DIR/$LOGO_IMG_NAME"
      echo "Đã ghi đè: $BRANDING_DIR/$LOGO_IMG_NAME"

      # "productIcon" (icon cửa sổ/taskbar lúc chạy installer) thường trỏ
      # cùng file với productLogo — chỉ ghi đè thêm nếu nó là file KHÁC.
      ICON_IMG_NAME=$(sudo grep -E '^\s*productIcon\s*:' "$BRANDING_DESC" \
        | head -n1 | sed -E 's/^[^:]*:[[:space:]]*//' | tr -d "\"'" | tr -d $'\r')
      if [ -n "$ICON_IMG_NAME" ] && [ "$ICON_IMG_NAME" != "$LOGO_IMG_NAME" ]; then
        sudo cp /tmp/calamares-sidebar-logo.png "$BRANDING_DIR/$ICON_IMG_NAME"
        echo "Đã ghi đè thêm: $BRANDING_DIR/$ICON_IMG_NAME (productIcon)"
      fi

      echo "OK: đã đổi logo sidebar Calamares ($BRANDING_COMPONENT) bằng $LOGO_FILE"
    else
      echo "CẢNH BÁO: không thấy $BRANDING_DESC — bỏ qua đổi logo sidebar Calamares" >&2
      echo "    (calamares-settings-debian có thể chưa cài được, hoặc đổi tên component — xem log desktop.sh)." >&2
    fi
  fi
else
  echo "Bỏ qua đổi logo sidebar Calamares (thiếu file logo trong config/branding/, hoặc chưa có /etc/calamares/settings.conf)."
fi

echo "===== Plymouth boot splash (logo + spinner tròn xoay) ====="
# Theme riêng "hyggshi-boot" dùng module "script" của Plymouth — logo tự
# dán qua link (PLYMOUTH_LOGO_URL), không phụ thuộc theme có sẵn trong
# plymouth-themes. Chạy TRƯỚC bất kỳ desktop environment nào lúc boot nên
# áp dụng chung cho mọi DE, không đặt trong nhánh "if DE=xfce" bên dưới.
#
# Đã bỏ dòng chữ "... đang khởi động..." — thay bằng animation spinner
# hình tròn xoay bên dưới logo. Plymouth Script không có primitive vẽ
# cung tròn trực tiếp, nên cách chuẩn (giống theme "two-step" gốc của
# Plymouth) là NHÚNG SẴN một chuỗi frame PNG (mỗi frame là 1 góc xoay của
# vòng tròn, vẽ bằng ImageMagick lúc build) rồi cho script đảo khung hình
# liên tục — spinner mượt, không cần font/text nào.

# 1. Ưu tiên file riêng cho Plymouth trong repo (đặt tên plymouth-logo.*)
PLYMOUTH_LOGO_FILE=$(find config/branding -maxdepth 1 -iname "plymouth-logo.*" \
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
  DISTRO_NAME_SAFE="${DISTRO_NAME//\"/} ${HYGGSHI_CODENAME}"

  sudo apt-get install -y imagemagick > /dev/null 2>&1 || true
  if command -v convert > /dev/null 2>&1; then
    convert "$PLYMOUTH_LOGO_FILE" -resize 256x256 /tmp/plymouth-logo.png
  else
    cp "$PLYMOUTH_LOGO_FILE" /tmp/plymouth-logo.png
  fi
  sudo cp /tmp/plymouth-logo.png "$THEME_DIR/logo.png"

  echo "----- Vẽ frame dot-wave kiểu Fedora/Ubuntu (ImageMagick) -----"
  # Cả Fedora (theme "spinner" cũ) lẫn Ubuntu (theme mặc định hiện tại) đều
  # dùng chung 1 kiểu: nền ĐEN TUYỀN + một hàng chấm tròn nằm ngang bên
  # dưới logo, độ sáng từng chấm chạy thành sóng đuổi nhau trái->phải rồi
  # lặp lại (không phải xoay tròn như spinner cũ). Dùng awk tính màu mỗi
  # chấm theo hàm sin (offset pha theo index chấm) để có hiệu ứng mượt,
  # rồi vẽ tất cả DOTS_COUNT chấm trong CÙNG một lệnh convert/frame.
  DOTS_COUNT=5
  DOT_RADIUS=6
  DOT_GAP=26
  SPINNER_FRAMES=30
  DOT_ROW_WIDTH=$(( (DOTS_COUNT - 1) * DOT_GAP ))
  SPINNER_CANVAS_W=$(( DOT_ROW_WIDTH + DOT_RADIUS * 2 + 20 ))
  SPINNER_CANVAS_H=$(( DOT_RADIUS * 2 + 20 ))
  DOT_CY=$(( SPINNER_CANVAS_H / 2 ))
  if command -v convert > /dev/null 2>&1; then
    for i in $(seq 0 $((SPINNER_FRAMES - 1))); do
      # Màu từng chấm trong frame $i: chấm tối #262626 (gần đen, chìm vào
      # nền) -> chấm sáng #ffffff (trắng) theo pha sóng riêng của nó.
      read -ra DOT_COLORS <<< "$(awk -v frame="$i" -v frames="$SPINNER_FRAMES" -v dots="$DOTS_COUNT" 'BEGIN{
        pi = 3.14159265;
        base_r = 38; base_g = 38; base_b = 38;
        hi_r = 255; hi_g = 255; hi_b = 255;
        for (j = 0; j < dots; j++) {
          phase = 2 * pi * frame / frames - j * (2 * pi / dots);
          val = (sin(phase) + 1) / 2;
          r = base_r + (hi_r - base_r) * val;
          g = base_g + (hi_g - base_g) * val;
          b = base_b + (hi_b - base_b) * val;
          printf "#%02x%02x%02x ", r, g, b;
        }
      }')"

      DRAW_STR=""
      for j in $(seq 0 $((DOTS_COUNT - 1))); do
        DOT_CX=$(( DOT_RADIUS + 10 + j * DOT_GAP ))
        DRAW_STR="$DRAW_STR fill \"${DOT_COLORS[$j]}\" circle $DOT_CX,$DOT_CY $((DOT_CX + DOT_RADIUS)),$DOT_CY"
      done

      FRAME_NAME=$(printf "spinner-%02d.png" "$i")
      convert -size ${SPINNER_CANVAS_W}x${SPINNER_CANVAS_H} xc:none \
        -draw "$DRAW_STR" \
        "/tmp/$FRAME_NAME"
      sudo cp "/tmp/$FRAME_NAME" "$THEME_DIR/$FRAME_NAME"
    done
    echo "OK: đã tạo $SPINNER_FRAMES frame dot-wave trong $THEME_DIR"
  else
    echo "⚠️  imagemagick không cài được — không tạo được frame dot-wave, Plymouth sẽ chỉ hiện logo tĩnh."
    SPINNER_FRAMES=0
  fi

  cat <<PLYMOUTHEOF | sudo tee "$THEME_DIR/hyggshi-boot.plymouth" > /dev/null
[Plymouth Theme]
Name=Hyggshi Boot
Description=$DISTRO_NAME_SAFE boot splash (logo + dot-wave loading, nền đen kiểu Fedora/Ubuntu)
ModuleName=script

[script]
ImageDir=/usr/share/plymouth/themes/hyggshi-boot
ScriptFile=/usr/share/plymouth/themes/hyggshi-boot/hyggshi-boot.script
PLYMOUTHEOF

  # Ngôn ngữ script riêng của Plymouth (cú pháp kiểu C, xem
  # freedesktop.org/wiki/Software/Plymouth/Scripts). Logo tĩnh ở giữa màn
  # hình + hàng chấm dot-wave bên dưới, nền ĐEN TUYỀN (0,0,0) thay vì
  # gradient xanh navy như bản trước. Cơ chế nạp/đảo frame giữ nguyên như
  # bản spinner tròn (mảng ảnh preload + đổi frame mỗi SPINNER_TICKS lần
  # refresh_callback), chỉ khác nội dung ảnh từng frame.
  cat <<SCRIPTEOF | sudo tee "$THEME_DIR/hyggshi-boot.script" > /dev/null
Window.SetBackgroundTopColor(0, 0, 0);
Window.SetBackgroundBottomColor(0, 0, 0);

window_width = Window.GetWidth();
window_height = Window.GetHeight();

logo.image = Image("logo.png");
logo.sprite = Sprite(logo.image);
logo_x = window_width / 2 - logo.image.GetWidth() / 2;
logo_y = window_height / 2 - logo.image.GetHeight() / 2 - 40;
logo.sprite.SetX(logo_x);
logo.sprite.SetY(logo_y);
logo.sprite.SetZ(10);

spinner_frame_count = $SPINNER_FRAMES;
spinner_y = logo_y + logo.image.GetHeight() + 30;

if (spinner_frame_count > 0) {
  spinner_images[0] = Image("spinner-00.png");
  spinner_sprite = Sprite(spinner_images[0]);
  spinner_sprite.SetX(window_width / 2 - spinner_images[0].GetWidth() / 2);
  spinner_sprite.SetY(spinner_y);
  spinner_sprite.SetZ(10);

  i = 1;
  while (i < spinner_frame_count) {
    if (i < 10) {
      frame_suffix = "0" + i;
    } else {
      frame_suffix = "" + i;
    }
    spinner_images[i] = Image("spinner-" + frame_suffix + ".png");
    i++;
  }

  spinner_tick = 0;
  spinner_index = 0;
  SPINNER_TICKS = 3; # đổi frame mỗi 3 lần refresh (~50Hz) -> sóng chạy hết 1 vòng trong ~1.8s

  fun refresh_callback() {
    spinner_tick++;
    if (spinner_tick >= SPINNER_TICKS) {
      spinner_tick = 0;
      spinner_index++;
      if (spinner_index >= spinner_frame_count) {
        spinner_index = 0;
      }
      spinner_sprite.SetImage(spinner_images[spinner_index]);
      spinner_sprite.SetX(window_width / 2 - spinner_images[spinner_index].GetWidth() / 2);
      spinner_sprite.SetY(spinner_y);
    }
  }
  Plymouth.SetRefreshFunction(refresh_callback);
}
SCRIPTEOF

  echo "===== Ép Plymouth 'hyggshi-boot' làm theme mặc định + đóng gói vào initramfs ====="
  # Không chỉ gọi plymouth-set-default-theme rồi hy vọng initramfs tự nhận.
  # Ta ghi rõ plymouthd.conf + default.plymouth và thêm initramfs hook riêng.
  # Cách này tránh tình trạng ISO vẫn hiện spinner 3 chấm của Ubuntu/Debian dù
  # theme Hyggshi đã tồn tại trong /usr/share/plymouth/themes/.
  sudo mkdir -p "$CHROOT/etc/plymouth" "$CHROOT/usr/share/plymouth/themes"
  sudo tee "$CHROOT/etc/plymouth/plymouthd.conf" > /dev/null <<'PLYD_EOF'
[Daemon]
Theme=hyggshi-boot
ShowDelay=0
PLYD_EOF

  if sudo chroot "$CHROOT" sh -c 'command -v plymouth-set-default-theme' >/dev/null 2>&1; then
    sudo chroot "$CHROOT" plymouth-set-default-theme hyggshi-boot || true
  fi

  # plymouth-set-default-theme creates this symlink itself on Debian/Ubuntu.
  # Re-create it explicitly so the choice survives package postinst scripts.
  sudo rm -f "$CHROOT/usr/share/plymouth/themes/default.plymouth"
  sudo ln -s "hyggshi-boot/hyggshi-boot.plymouth" \
    "$CHROOT/usr/share/plymouth/themes/default.plymouth"

  # Explicit initramfs hook: copy the complete Hyggshi theme, selected theme
  # symlink, daemon config and the script plugin into every generated initrd.
  sudo tee "$CHROOT/etc/initramfs-tools/hooks/hyggshi-plymouth" > /dev/null <<'HOOK_EOF'
#!/bin/sh
# KHÔNG dùng "set -e" ở đây: nếu 1 bước phụ (copy plymouthd.conf, copy .so
# renderer) fail vì lý do vặt (thiếu file trên distro/kernel nào đó),
# set -e sẽ giết chết CẢ hook giữa chừng -> initramfs-tools coi hook fail
# -> update-initramfs rollback initrd (Removing *.dpkg-bak) -> initrd cuối
# cùng KHÔNG có theme dù phần copy theme (bước quan trọng nhất) đã chạy
# xong trước đó. Chỉ bước copy theme + tạo symlink default.plymouth mới
# thật sự bắt buộc; các bước còn lại luôn được best-effort.
PREREQ=""
prereqs() { echo "$PREREQ"; }
case "${1:-}" in
  prereqs) prereqs; exit 0 ;;
esac
. /usr/share/initramfs-tools/hook-functions

THEME=/usr/share/plymouth/themes/hyggshi-boot
if [ -d "$THEME" ]; then
  mkdir -p "${DESTDIR}${THEME}" || { echo "hyggshi-plymouth: mkdir theme dir FAILED" >&2; exit 1; }
  cp -a "$THEME/." "${DESTDIR}${THEME}/" || { echo "hyggshi-plymouth: cp theme FAILED" >&2; exit 1; }
else
  echo "hyggshi-plymouth: CANH BAO khong thay $THEME trong chroot, bo qua." >&2
fi

mkdir -p "${DESTDIR}/usr/share/plymouth/themes" || { echo "hyggshi-plymouth: mkdir themes dir FAILED" >&2; exit 1; }
rm -f "${DESTDIR}/usr/share/plymouth/themes/default.plymouth"
ln -s "hyggshi-boot/hyggshi-boot.plymouth" \
  "${DESTDIR}/usr/share/plymouth/themes/default.plymouth" \
  || { echo "hyggshi-plymouth: ln -s default.plymouth FAILED" >&2; exit 1; }

# Từ đây trở xuống là các bước PHỤ (config file, renderer .so) — best-effort,
# lỗi ở đây không được phép làm fail cả hook.
if [ -f /etc/plymouth/plymouthd.conf ]; then
  copy_file config /etc/plymouth/plymouthd.conf \
    || echo "hyggshi-plymouth: canh bao - copy plymouthd.conf that bai (bo qua)" >&2
fi

for so in \
  /usr/lib/x86_64-linux-gnu/plymouth/script.so \
  /usr/lib/x86_64-linux-gnu/plymouth/drm.so \
  /usr/lib/x86_64-linux-gnu/plymouth/renderers/drm.so \
  /usr/lib/x86_64-linux-gnu/plymouth/renderers/frame-buffer.so; do
  if [ -f "$so" ]; then
    copy_exec "$so" "$so" \
      || echo "hyggshi-plymouth: canh bao - copy_exec $so that bai (bo qua)" >&2
  fi
done

exit 0
HOOK_EOF
  sudo chmod 0755 "$CHROOT/etc/initramfs-tools/hooks/hyggshi-plymouth"

  # The hook above makes the initrd self-contained. Rebuild ALL kernels, not
  # only the newest one, because Calamares may install a different kernel on
  # the target and ISO generation picks the newest initrd.
  if sudo chroot "$CHROOT" sh -c 'command -v update-initramfs' >/dev/null 2>&1; then
    sudo chroot "$CHROOT" update-initramfs -u -k all -v
  else
    echo "CẢNH BÁO: không tìm thấy update-initramfs trong chroot — initramfs sẽ KHÔNG được rebuild, theme sẽ không nằm trong initrd." >&2
  fi
  if sudo chroot "$CHROOT" sh -c 'command -v plymouth-update-initrd' >/dev/null 2>&1; then
    sudo chroot "$CHROOT" plymouth-update-initrd || true
  fi

  # Hard validation: if the selected initrd does not contain the theme, fail
  # the build rather than producing another ISO that shows the default dots.
  INITRD_CHECK=$(sudo ls -t "$CHROOT"/boot/initrd.img-* 2>/dev/null | head -n1 || true)
  if [ -n "$INITRD_CHECK" ] && command -v lsinitramfs >/dev/null 2>&1; then
    if ! sudo lsinitramfs "$INITRD_CHECK" 2>/dev/null | grep -q 'usr/share/plymouth/themes/hyggshi-boot/hyggshi-boot.plymouth'; then
      echo "LỖI: initramfs mới không chứa Hyggshi Plymouth theme." >&2
      echo "Kiểm tra lại /etc/initramfs-tools/hooks/hyggshi-plymouth." >&2
      exit 1
    fi
    echo "OK: Hyggshi Plymouth theme đã nằm trong $INITRD_CHECK"
  fi
fi

echo "===== Fastfetch: gắn logo custom (logo.txt ưu tiên, Logo.png dự phòng) ====="
# ĐẶT TRƯỚC nhánh "if DE != xfce -> exit 0" bên dưới để áp dụng cho MỌI DE
# (KDE/LXQt/GNOME/MATE/Cinnamon), không chỉ riêng XFCE.
#
# Thứ tự ưu tiên:
#   1) config/branding/logo.txt  — ASCII/ANSI-art ĐÃ CÓ SẴN mã màu
#      (\033[38;2;r;g;bm...) -> dùng "type": "file", fastfetch IN THẲNG nội
#      dung, giữ nguyên escape sequence màu, KHÔNG cần imagemagick/chafa,
#      chạy đúng trên MỌI terminal (kể cả terminal không hỗ trợ image protocol).
#   2) config/branding/Logo.png  — fallback nếu không có logo.txt, dùng
#      "type": "kitty" (image protocol) — CHỈ hiển thị đúng trên terminal hỗ
#      trợ kitty graphics protocol (Kitty, WezTerm, Konsole mới...). Terminal
#      không hỗ trợ sẽ không hiện logo (chỉ hiện info bên phải), không lỗi.
#   3) Không có gì cả — bỏ qua, fastfetch tự dùng logo nhận diện distro mặc định.
FASTFETCH_LOGO_TXT=$(find config/branding -maxdepth 1 -iname "logo.txt" 2>/dev/null | head -n1)
FASTFETCH_LOGO_PNG=$(find config/branding -maxdepth 1 -iname "logo.png" 2>/dev/null | head -n1)

LOGO_DEST_DIR="$CHROOT/usr/share/hyggshi/branding"
LOGO_JSON=""

if [ -n "$FASTFETCH_LOGO_TXT" ]; then
  sudo mkdir -p "$LOGO_DEST_DIR"
  sudo cp "$FASTFETCH_LOGO_TXT" "$LOGO_DEST_DIR/logo.txt"
  # KHÔNG set width/height cứng: logo.txt chứa ANSI escape sequence
  # (\033[38;2;r;g;bm...) trên mỗi dòng — nếu fastfetch cắt bớt ký tự theo
  # width, nó dễ cắt NGANG giữa 1 mã escape, làm hỏng phần còn lại của
  # dòng và toàn bộ layout logo bị vỡ thành từng khối màu rời rạc. Để
  # trống, fastfetch in nguyên bản file, đúng kích thước đã thiết kế sẵn.
  LOGO_JSON='  "logo": {
    "type": "file",
    "source": "/usr/share/hyggshi/branding/logo.txt"
  },'
  echo "Dùng logo.txt (ANSI text, tương thích mọi terminal) làm logo fastfetch."

elif [ -n "$FASTFETCH_LOGO_PNG" ]; then
  sudo mkdir -p "$LOGO_DEST_DIR"
  sudo cp "$FASTFETCH_LOGO_PNG" "$LOGO_DEST_DIR/logo.png"
  LOGO_JSON='  "logo": {
    "type": "kitty",
    "source": "/usr/share/hyggshi/branding/logo.png",
    "height": 15
  },'
  echo "⚠️  Không thấy logo.txt — dùng Logo.png (kitty image protocol, cần terminal hỗ trợ) làm logo fastfetch."

else
  echo "Không thấy logo.txt hoặc Logo.png trong config/branding/ — fastfetch dùng logo tự nhận diện distro mặc định."
fi

if [ -n "$LOGO_JSON" ]; then
  # Config mặc định — đặt trong /etc/xdg/fastfetch/ (system-wide default mà
  # fastfetch tự đọc nếu user chưa có config riêng ở ~/.config/fastfetch/).
  sudo mkdir -p "$CHROOT/etc/xdg/fastfetch"
  cat <<FFCFG | sudo tee "$CHROOT/etc/xdg/fastfetch/config.jsonc" > /dev/null
{
  "\$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
$LOGO_JSON
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
    # QUAN TRỌNG: chown luôn "$HOME/.config" (KHÔNG chỉ .config/fastfetch).
    # useradd -m (desktop.sh) chạy TRƯỚC khi bất kỳ nội dung nào được thêm
    # vào /etc/skel/.config, nên tại thời điểm đó user CHƯA có sẵn thư mục
    # .config trong home. `sudo mkdir -p` ở trên chạy bằng HOST root (không
    # qua chroot exec) nên tự tạo mới CẢ ".config" lẫn ".config/fastfetch",
    # và cả hai đều thuộc về root:root. Nếu chỉ chown mỗi ".config/fastfetch"
    # như trước, ".config" gốc vẫn còn là root:root — mọi app khác cần ghi
    # config riêng vào trong đó (caja, mate-settings-daemon, v.v.) sẽ bị từ
    # chối quyền, gây đúng lỗi "The path for the directory containing caja
    # settings need read and write permissions: /home/<user>/.config/caja".
    sudo chroot "$CHROOT" chown -R "$OS_USERNAME:$OS_USERNAME" "/home/$OS_USERNAME/.config"

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

  echo "OK: đã gắn logo custom cho fastfetch."
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
  tela)    ICON_NAME="Tela" ;;
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

# CHỈ ghi property "last-image" trỏ vào wallpaper.png khi file đó THẬT SỰ
# tồn tại (WALLPAPER_APPLIED=true, xem khối wallpaper phía trên) — trước đây
# hardcode giá trị này bất kể có wallpaper hay không, khiến xfdesktop trỏ
# vào 1 file có thể không tồn tại. Không có wallpaper thì bỏ trống channel,
# giữ nguyên theme/wallpaper mặc định của DE gốc.
if [ "$WALLPAPER_APPLIED" = "true" ]; then
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
else
  echo "Bỏ qua tạo $SKEL/xfce4-desktop.xml (không có wallpaper.png thật) — giữ wallpaper mặc định của DE gốc."
fi

# NOTE: GTK ThemeName and xfwm4 theme below are both set to "Windows-10",
# which already gives the same end result as the Appearance dialog's
# "Set matching Xfwm4 theme if there is one" switch (new users get
# synced themes on first login regardless of the switch's own state).
#
# If you also want the switch itself to render ON in the live dialog,
# find its exact xfconf property first:
#   xfconf-query -c xsettings -lv > /tmp/before.txt
#   # toggle the switch ON in Appearance settings, then:
#   xfconf-query -c xsettings -lv > /tmp/after.txt
#   diff /tmp/before.txt /tmp/after.txt
# then add the discovered <property> line inside the "Net" block below.
cat <<XML | sudo tee "$SKEL/xsettings.xml" > /dev/null
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xsettings" version="1.0">
  <property name="Net" type="empty">
    <property name="IconThemeName" type="string" value="$ICON_NAME"/>
    <property name="ThemeName" type="string" value="Windows-10"/>
  </property>
</channel>
XML

# FIX "khung UI vỡ" ở hộp thoại Restart/Shut Down (xfce4-session-logout):
# khi có compositor, xfce4-session-logout KHÔNG vẽ như 1 GtkDialog thường
# (không có panel nền, không được xfwm4 canh giữa màn hình) — nó tự vẽ 1
# overlay toàn màn hình (icon + chữ + nút dạng link) đè lên backdrop đã làm
# mờ/tối, đây là hành vi ĐÚNG-THIẾT-KẾ của xfce4-session bản mới. Overlay
# này CHỈ được vẽ đúng khi compositor của xfwm4 (use_compositing) đang BẬT.
# Trước đây channel này không hề set use_compositing -> phụ thuộc default
# của gói xfwm4 trên distro nền (thường TẮT trên môi trường the old live-build layout) ->
# xfce4-session-logout rơi về chế độ fallback: cửa sổ KHÔNG có nền, KHÔNG
# được xfwm4 canh giữa, KHÔNG có lớp làm mờ phía sau — đúng y hệt ảnh chụp
# lỗi (chữ/nút nổi lệch trái, không khung, không nền). Bật tường minh ở đây
# để 2 đường build (Actions vs local-build.sh) không lệ thuộc default khác
# nhau giữa các phiên bản xfwm4/distro nền.
cat <<XML | sudo tee "$SKEL/xfwm4.xml" > /dev/null
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="theme" type="string" value="Windows-10"/>
    <property name="button_layout" type="string" value="O|SHMC"/>
    <property name="use_compositing" type="bool" value="true"/>
    <property name="show_frame_shadow" type="bool" value="true"/>
    <property name="show_popup_shadow" type="bool" value="true"/>
    <property name="show_dock_shadow" type="bool" value="true"/>
    <property name="frame_opacity" type="int" value="100"/>
    <property name="popup_opacity" type="int" value="100"/>
    <property name="inactive_opacity" type="int" value="100"/>
    <property name="move_opacity" type="int" value="100"/>
    <property name="resize_opacity" type="int" value="100"/>
  </property>
</channel>
XML

sudo chroot "$CHROOT" chown -R root:root /etc/skel/.config

# Toàn bộ khối autostart set-wallpaper-lúc-login bên dưới CHỈ cài khi thật
# sự có wallpaper.png (WALLPAPER_APPLIED=true) — trước đây script + autostart
# entry luôn được cài bất kể có wallpaper hay không (script tự thoát ở
# runtime nếu thiếu file, nhưng vẫn hardcode cài đặt "chờ sẵn" một tính năng
# không có gì để áp). Phần copy config panel/theme cho user ở CUỐI file
# không phụ thuộc wallpaper nên vẫn chạy bình thường sau khối if này.
if [ "$WALLPAPER_APPLIED" = "true" ]; then

echo "===== Script tự set wallpaper lúc login (dò đúng property monitor) ====="
cat <<'SCRIPT' | sudo tee "$CHROOT/usr/local/bin/hyggshi-set-wallpaper.sh" > /dev/null
#!/bin/bash
LOG="/tmp/hyggshi-wallpaper.log"
exec > "$LOG" 2>&1
echo "=== hyggshi-set-wallpaper.sh $(date) ==="

# Nhận đường dẫn wallpaper qua tham số dòng lệnh (dùng bởi hyggshi-welcome
# để đổi wallpaper theo theme Sáng/Tối đã chọn). Không truyền gì (trường hợp
# autostart lúc login) -> RANDOM giữa các ảnh có sẵn trong
# /usr/share/backgrounds/hyggshi/ (wallpaper.png, car-light.png...) thay vì
# luôn cố định 1 ảnh — chỉ những file THẬT SỰ tồn tại mới được đưa vào pool.
BG_DIR="/usr/share/backgrounds/hyggshi"
if [ -n "$1" ]; then
  WALL="$1"
else
  POOL=()
  for CANDIDATE in wallpaper.png car-light.png; do
    [ -f "$BG_DIR/$CANDIDATE" ] && POOL+=("$BG_DIR/$CANDIDATE")
  done
  if [ "${#POOL[@]}" -gt 0 ]; then
    WALL="${POOL[$((RANDOM % ${#POOL[@]}))]}"
    echo "Random pool (${#POOL[@]} ảnh): ${POOL[*]}"
    echo "Đã chọn: $WALL"
  else
    WALL="$BG_DIR/wallpaper.png"
  fi
fi

if [ ! -f "$WALL" ]; then
  echo "LỖI: không tìm thấy file wallpaper ($WALL), dừng."
  exit 0
fi

# ---------------------------------------------------------------------------
# Dò desktop environment đang chạy — KHÔNG hardcode XFCE. Ưu tiên biến môi
# trường chuẩn (XDG_CURRENT_DESKTOP/DESKTOP_SESSION), vì script này cũng
# được hyggshi-welcome (session của user, biến môi trường đầy đủ) gọi trực
# tiếp. Khi chạy qua hyggshi-auto-theme (systemd SYSTEM service, gọi bằng
# `sudo -u <user> DISPLAY=... DBUS_SESSION_BUS_ADDRESS=...`) các biến XDG_*
# KHÔNG được kế thừa, nên phải có fallback dò qua tiến trình phiên đồ hoạ
# (pgrep) — mỗi DE có 1 process "chủ" đặc trưng luôn chạy khi có phiên đó.
detect_de() {
  local raw="${XDG_CURRENT_DESKTOP:-}${DESKTOP_SESSION:+ $DESKTOP_SESSION}"
  raw=$(echo "$raw" | tr '[:upper:]' '[:lower:]')
  case "$raw" in
    *cinnamon*) echo "cinnamon"; return ;;
    *xfce*)     echo "xfce";     return ;;
    *gnome*)    echo "gnome";    return ;;
    *mate*)     echo "mate";     return ;;
    *lxqt*)     echo "lxqt";     return ;;
    *kde*|*plasma*) echo "kde";  return ;;
  esac
  # Không có/không nhận diện được biến môi trường -> dò qua tiến trình.
  if pgrep -x cinnamon >/dev/null 2>&1; then echo "cinnamon"; return; fi
  if pgrep -x xfdesktop >/dev/null 2>&1; then echo "xfce"; return; fi
  if pgrep -x gnome-shell >/dev/null 2>&1; then echo "gnome"; return; fi
  if pgrep -x mate-session >/dev/null 2>&1; then echo "mate"; return; fi
  if pgrep -x pcmanfm-qt >/dev/null 2>&1; then echo "lxqt"; return; fi
  if pgrep -x plasmashell >/dev/null 2>&1; then echo "kde"; return; fi
  echo "unknown"
}

# Chờ tiến trình "chủ" của DE thật sự chạy (tối đa 20s), tránh race
# condition lúc login — trước đây chỉ chờ mỗi xfdesktop.
wait_for_de_process() {
  local proc="$1"
  [ -z "$proc" ] && return 0
  for i in $(seq 1 20); do
    if pgrep -x "$proc" >/dev/null 2>&1; then
      echo "$proc đã chạy sau ${i}s"
      return 0
    fi
    sleep 1
  done
  echo "CẢNH BÁO: không thấy tiến trình $proc sau 20s — vẫn thử áp wallpaper."
}

apply_wallpaper_xfce() {
  wait_for_de_process xfdesktop

  _do_set() {
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

  _do_set
  xfdesktop --reload 2>>"$LOG"
  sleep 1
  # LUÔN restart hẳn xfdesktop (không chỉ --reload): lần đầu TẠO property
  # mới (-n), xfdesktop đang chạy thường không tự "nhìn thấy" giá trị vừa
  # tạo chỉ bằng --reload.
  killall xfdesktop 2>>"$LOG" || true
  sleep 1
  nohup xfdesktop >>"$LOG" 2>&1 &
  sleep 1

  CHECK=$(xfconf-query -c xfce4-desktop -p /backdrop -l 2>/dev/null | grep 'last-image$' | head -n1)
  if [ -n "$CHECK" ]; then
    VAL=$(xfconf-query -c xfce4-desktop -p "$CHECK" 2>/dev/null)
    echo "verify: $CHECK = $VAL"
    if [ "$VAL" != "$WALL" ]; then
      echo "Verify không khớp, retry lần 2"
      _do_set
      killall xfdesktop 2>>"$LOG" || true
      sleep 1
      nohup xfdesktop >>"$LOG" 2>&1 &
    fi
  fi
}

apply_wallpaper_cinnamon() {
  # Cinnamon dùng dconf/GSettings, không có "process reload" như xfdesktop —
  # cinnamon-settings-daemon tự áp ngay khi property đổi.
  # Login/autostart không truyền tham số -> luôn dùng wallpaper thương hiệu
  # Verdant Valley của Hyggshi OS. Khi hyggshi-welcome truyền $1 (ví dụ
  # car-light.png / car-Dark.png), giữ lựa chọn theme của user.
  if [ -z "$1" ] && [ -f "/usr/share/backgrounds/hyggshi/Verdant-Valley.png" ]; then
    gsettings set org.cinnamon.desktop.background picture-uri \
      "file:///usr/share/backgrounds/hyggshi/Verdant-Valley.png" 2>>"$LOG"
    gsettings set org.cinnamon.desktop.background picture-options 'zoom' 2>>"$LOG"
    echo "Đã set wallpaper Cinnamon mặc định Hyggshi: /usr/share/backgrounds/hyggshi/Verdant-Valley.png"
  else
    gsettings set org.cinnamon.desktop.background picture-uri "file://$WALL" 2>>"$LOG"
    gsettings set org.cinnamon.desktop.background picture-options 'zoom' 2>>"$LOG"
    echo "Đã set wallpaper Cinnamon (gsettings org.cinnamon.desktop.background) -> $WALL"
  fi
}

apply_wallpaper_gnome() {
  gsettings set org.gnome.desktop.background picture-uri "file://$WALL" 2>>"$LOG"
  gsettings set org.gnome.desktop.background picture-uri-dark "file://$WALL" 2>>"$LOG"
  gsettings set org.gnome.desktop.background picture-options 'zoom' 2>>"$LOG"
  echo "Đã set wallpaper GNOME (gsettings org.gnome.desktop.background) -> $WALL"
}

apply_wallpaper_mate() {
  gsettings set org.mate.background picture-filename "$WALL" 2>>"$LOG"
  gsettings set org.mate.background picture-options 'zoom' 2>>"$LOG"
  echo "Đã set wallpaper MATE (gsettings org.mate.background) -> $WALL"
}

apply_wallpaper_lxqt() {
  wait_for_de_process pcmanfm-qt
  if command -v pcmanfm-qt >/dev/null 2>&1; then
    pcmanfm-qt --set-wallpaper="$WALL" --wallpaper-mode=fit 2>>"$LOG"
    echo "Đã set wallpaper LXQt (pcmanfm-qt --set-wallpaper) -> $WALL"
  else
    echo "CẢNH BÁO: không tìm thấy pcmanfm-qt — bỏ qua set wallpaper LXQt." >&2
  fi
}

apply_wallpaper_kde() {
  # Plasma phải chạy hoàn chỉnh trước khi gọi plasma-apply-wallpaperimage.
  # Không dùng random pool cho KDE: wallpaper mặc định của Hyggshi là
  # Verdant-Valley.png; wallpaper.png là fallback nếu file này không có.
  wait_for_de_process plasmashell

  if [ -z "$1" ] && [ -f "/usr/share/backgrounds/hyggshi/Verdant-Valley.png" ]; then
    WALL="/usr/share/backgrounds/hyggshi/Verdant-Valley.png"
  elif [ -z "$1" ] && [ -f "/usr/share/backgrounds/hyggshi/wallpaper.png" ]; then
    WALL="/usr/share/backgrounds/hyggshi/wallpaper.png"
  fi

  if ! command -v plasma-apply-wallpaperimage >/dev/null 2>&1; then
    echo "CẢNH BÁO: thiếu plasma-apply-wallpaperimage — kiểm tra plasma-workspace." >&2
    return 0
  fi

  # Plasma 6/Wayland có thể cần thêm vài giây sau khi plasmashell xuất hiện.
  # Retry để tránh race condition khi autostart chạy rất sớm.
  for attempt in 1 2 3 4 5; do
    if plasma-apply-wallpaperimage "$WALL" >>"$LOG" 2>&1; then
      echo "Đã set wallpaper KDE Plasma -> $WALL (lần thử $attempt)"
      sleep 1
      return 0
    fi
    echo "KDE wallpaper lần thử $attempt thất bại, chờ Plasma..." >>"$LOG"
    sleep 2
  done

  echo "CẢNH BÁO: không thể áp wallpaper KDE sau 5 lần thử: $WALL" >&2
}

apply_wallpaper_fallback() {
  # DE không nhận diện được (hoặc window manager trần không có desktop
  # shell riêng) — thử feh nếu có sẵn, đây là công cụ set wallpaper X11
  # generic phổ biến nhất, không phụ thuộc DE nào.
  if command -v feh >/dev/null 2>&1; then
    DISPLAY="${DISPLAY:-:0}" feh --bg-fill "$WALL" 2>>"$LOG"
    echo "Đã set wallpaper qua feh --bg-fill (fallback, DE không xác định) -> $WALL"
  else
    echo "CẢNH BÁO: DE không xác định được và không có feh — không set được wallpaper tự động." >&2
    echo "Cài đặt thủ công wallpaper tại: $WALL" >&2
  fi
}

DE_DETECTED=$(detect_de)
echo "DE dò được: $DE_DETECTED"
case "$DE_DETECTED" in
  xfce)     apply_wallpaper_xfce ;;
  cinnamon) apply_wallpaper_cinnamon ;;
  gnome)    apply_wallpaper_gnome ;;
  mate)     apply_wallpaper_mate ;;
  lxqt)     apply_wallpaper_lxqt ;;
  kde)      apply_wallpaper_kde ;;
  *)        apply_wallpaper_fallback ;;
esac

# === HYGGSHI WELCOME AUTOSTART GUARD ===
# welcome.sh chạy trước branding.sh, build + cmake install hyggshi-welcome —
# cmake tự cài autostart entry thật vào /etc/xdg/autostart/hyggshi-welcome.desktop
# (xem packaging/hyggshi-welcome-autostart.desktop, Exec=hyggshi-welcome,
# KHÔNG có binary/wrapper tên "hyggshi-welcome-autostart" nào cả — bản guard
# cũ check nhầm tên này nên if luôn false, im lặng bỏ qua, không tự vá được
# gì). Giữ 1 guard ở bước branding cuối để đảm bảo entry autostart vẫn tồn
# tại trong rootfs sau khi toàn bộ desktop/branding (rm -rf .config, chown,
# copy skel...) đã chạy xong — chỉ TÁI TẠO nếu bị thiếu, không ghi đè source.
if [ -x "$CHROOT/usr/bin/hyggshi-welcome" ]; then
  # Cài system-wide để user live và mọi user được Calamares tạo sau này đều
  # nhận được Welcome. Đồng thời copy cùng entry vào /etc/skel để user mới
  # có cấu hình autostart ngay trong HOME; tên file giống nhau để cấu hình
  # trong HOME override entry system-wide thay vì chạy 2 lần.
  sudo mkdir -p "$CHROOT/etc/xdg/autostart" "$CHROOT/etc/skel/.config/autostart"
  cat <<'WELCOME_AUTOSTART' | sudo tee "$CHROOT/etc/xdg/autostart/hyggshi-welcome.desktop" > /dev/null
[Desktop Entry]
Type=Application
Name=Hyggshi Welcome
Name[vi]=Chào mừng Hyggshi
Comment=Tự động mở Hyggshi Welcome cho mỗi user chưa hoàn tất thiết lập lần đầu
Exec=hyggshi-welcome
TryExec=hyggshi-welcome
Icon=hyggshi-welcome
Terminal=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
X-GNOME-Autostart-Delay=4
X-KDE-autostart-after=panel
WELCOME_AUTOSTART
  sudo cp "$CHROOT/etc/xdg/autostart/hyggshi-welcome.desktop" \
    "$CHROOT/etc/skel/.config/autostart/hyggshi-welcome.desktop"
  sudo chmod 644 "$CHROOT/etc/xdg/autostart/hyggshi-welcome.desktop" \
    "$CHROOT/etc/skel/.config/autostart/hyggshi-welcome.desktop"
  echo "OK: Hyggshi Welcome autostart system-wide + /etc/skel đã được cài."
else
  echo "CẢNH BÁO: không tìm thấy hyggshi-welcome binary (WELCOME_WIZARD=false hoặc build lỗi) — bỏ qua autostart guard." >&2
fi

echo "=== xong ==="
SCRIPT
sudo chmod +x "$CHROOT/usr/local/bin/hyggshi-set-wallpaper.sh"

sudo mkdir -p "$CHROOT/etc/skel/.config/autostart"
cat <<'DESKTOP' | sudo tee "$CHROOT/etc/skel/.config/autostart/hyggshi-wallpaper.desktop" > /dev/null
[Desktop Entry]
Type=Application
Name=Hyggshi Wallpaper Setup
Name[vi]=Thiết lập hình nền Hyggshi
Comment=Áp dụng hình nền Hyggshi tự động sau khi đăng nhập
Exec=/usr/local/bin/hyggshi-set-wallpaper.sh
TryExec=/usr/local/bin/hyggshi-set-wallpaper.sh
X-GNOME-Autostart-enabled=true
X-GNOME-Autostart-Delay=8
X-KDE-autostart-after=panel
X-KDE-autostart-phase=2
OnlyShowIn=Cinnamon;GNOME;XFCE;MATE;KDE;LXQt;
NoDisplay=true
Terminal=false
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

else
  echo "===== Bỏ qua autostart set-wallpaper (không có wallpaper.png thật) ====="
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
