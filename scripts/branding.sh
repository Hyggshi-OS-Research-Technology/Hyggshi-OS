#!/bin/bash
# branding.sh — wallpaper, distributor logo, rebrand os-release/lsb-release,
# panel style + icon theme XFCE, autostart. Chạy trên HOST, ghi thẳng vào
# thư mục chroot (không cần chroot exec, trừ gtk-update-icon-cache).
set -e
[ "$DEBUG_MODE" = "true" ] && set -x
CHROOT=live-build/chroot

# ===== HCL: đọc config.ini làm nguồn version/codename =====
# TRƯỚC ĐÂY: HYGGSHI_VERSION_ID/HYGGSHI_CODENAME chỉ tới từ input
# workflow_dispatch (hoặc mặc định "1.0" + bảng HYGGSHI_CODENAMES cứng ở
# dưới) — [my-version-os-base] Version/codename trong config.ini CHƯA BAO
# GIỜ được đọc, dù file đó có sẵn 2 field y hệt mục đích này (đây chính là
# lỗi bị phát hiện: script không hề gọi .ini để lấy data).
#
# Giờ nếu tồn tại config.ini + tools/hcl_parser.py, resolve nó và LẤY LÀM
# NGUỒN CHÍNH — ghi đè lên input/mặc định. Tắt bằng HCL_CONFIG_OVERRIDE=false
# nếu muốn quay lại hành vi cũ (chỉ dùng input thủ công của workflow).
HCL_CONFIG_FILE="${HCL_CONFIG_FILE:-iso-config/config/config.ini}"
HCL_PARSER="${HCL_PARSER:-tools/hcl_parser.py}"
: "${HCL_CONFIG_OVERRIDE:=true}"

if [ "$HCL_CONFIG_OVERRIDE" = "true" ] && [ -f "$HCL_CONFIG_FILE" ] && [ -f "$HCL_PARSER" ]; then
  echo "===== HCL: resolve $HCL_CONFIG_FILE ====="
  HCL_JSON="$(mktemp)"
  if python3 "$HCL_PARSER" "$HCL_CONFIG_FILE" --root . --emit-json "$HCL_JSON" --strict; then
    HCL_CFG_VERSION="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['base_profile'].get('version') or '')" "$HCL_JSON" 2>/dev/null || true)"
    HCL_CFG_CODENAME="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['base_profile'].get('codename') or '')" "$HCL_JSON" 2>/dev/null || true)"
    HCL_CFG_GREETER_SRC="$(python3 -c "import json,sys
d = json.load(open(sys.argv[1]))
for fc in d.get('file_copies', []):
    if 'gtk.css' in fc.get('source', '') or 'gtk.css' in (fc.get('rename') or '') or 'Hyggshi-Greeter' in (fc.get('target') or ''):
        print(fc.get('source') or '')
        break
custom = d.get('customization', {})
for k in ('linkgreetercss', 'linkthemegreeter', 'linkgreetergtk'):
    if k in custom:
        print(custom[k].get('arg') or custom[k].get('path') or '')
        break
" "$HCL_JSON" 2>/dev/null | head -n1 || true)"
    HCL_CFG_GREETER_TGT="$(python3 -c "import json,sys
d = json.load(open(sys.argv[1]))
for fc in d.get('file_copies', []):
    if 'gtk.css' in fc.get('source', '') or 'gtk.css' in (fc.get('rename') or '') or 'Hyggshi-Greeter' in (fc.get('target') or ''):
        print(fc.get('resolved_target') or fc.get('target') or '')
        break
" "$HCL_JSON" 2>/dev/null | head -n1 || true)"
    if [ -n "$HCL_CFG_VERSION" ]; then
      HYGGSHI_VERSION_ID="$HCL_CFG_VERSION"
      echo "  -> HYGGSHI_VERSION_ID lấy từ config.ini: $HYGGSHI_VERSION_ID"
    fi
    if [ -n "$HCL_CFG_CODENAME" ]; then
      HYGGSHI_CODENAME="$HCL_CFG_CODENAME"
      echo "  -> HYGGSHI_CODENAME lấy từ config.ini: $HYGGSHI_CODENAME"
    fi
    if [ -n "$HCL_CFG_GREETER_SRC" ]; then
      echo "  -> LightDM Greeter GTK CSS lấy từ config.ini: $HCL_CFG_GREETER_SRC -> ${HCL_CFG_GREETER_TGT:-$GREETER_THEME_DIR/gtk.css}"
    fi
  else
    echo "!! HCL: config.ini có lỗi validate (xem log ở trên) — bỏ qua, dùng input/mặc định như cũ." >&2
  fi
  rm -f "$HCL_JSON"
else
  echo "===== HCL: bỏ qua config.ini (không thấy $HCL_CONFIG_FILE / $HCL_PARSER, hoặc HCL_CONFIG_OVERRIDE=false) — dùng input/mặc định như cũ ====="
fi

# ===== Hyggshi OS Codename =====
# Codename RIÊNG của Hyggshi OS (kiểu Ubuntu "Jammy Jellyfish"), KHÔNG phải
# codename của base distro ($BASE_CODENAME, vd "bookworm"/"noble" — cái đó
# vẫn được giữ nguyên, chỉ đổi vai trò sang HYGGSHI_BASE_CODENAME trong
# os-release). Đây là fallback nếu HCL ở trên không set được (config.ini
# không tồn tại, hoặc HCL_CONFIG_OVERRIDE=false) — giữ nguyên hành vi cũ:
# chọn theo VERSION_ID hoặc override bằng HYGGSHI_CODENAME thủ công.
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

# Plymouth branding đã được tách sang scripts/plymouth.sh

echo "===== GRUB/Desktop-base branding ====="
# Luôn ghi đè file desktop-base bằng branding riêng của Hyggshi OS.
# Nguồn repo: ./iso-config/branding/desktop-grub.png và desktop-grub.svg
# Đây là file mà desktop-base/GRUB của hệ thống dùng tại:
#   /usr/share/images/desktop-base/desktop-grub.png
GRUB_BRANDING_DIR="$CHROOT/usr/share/images/desktop-base"
sudo mkdir -p "$GRUB_BRANDING_DIR"
if [ -f "iso-config/branding/desktop-grub.png" ]; then
  sudo install -m 0644 "iso-config/branding/desktop-grub.png" \
    "$GRUB_BRANDING_DIR/desktop-grub.png"
  echo "OK: ghi đè $GRUB_BRANDING_DIR/desktop-grub.png"
else
  echo "WARNING: thiếu iso-config/branding/desktop-grub.png — không ghi đè desktop-base background."
fi
if [ -f "iso-config/branding/desktop-grub.svg" ]; then
  sudo install -m 0644 "iso-config/branding/desktop-grub.svg" \
    "$GRUB_BRANDING_DIR/desktop-grub.svg"
  echo "OK: copy $GRUB_BRANDING_DIR/desktop-grub.svg"
fi

echo "===== Wallpaper ====="
sudo mkdir -p "$CHROOT/usr/share/backgrounds/hyggshi"

# Wallpaper mặc định riêng cho Cinnamon/Hyggshi OS. File này được copy vào
# đúng đường dẫn mà lệnh GSettings lúc login sử dụng.
if [ -f "iso-config/branding/Verdant-Valley.png" ]; then
  sudo install -m 0644 "iso-config/branding/Verdant-Valley.png" \
    "$CHROOT/usr/share/backgrounds/hyggshi/Verdant-Valley.png"
  echo "Đã copy Verdant-Valley.png vào /usr/share/backgrounds/hyggshi/"
else
  echo "⚠️ Không thấy iso-config/branding/Verdant-Valley.png — Cinnamon sẽ dùng wallpaper fallback hiện có."
fi

# car-light.png / car-Dark.png: wallpaper riêng cho theme Sáng/Tối, được
# hyggshi-welcome (make-welcome.sh) áp tự động khi user chọn theme ở trang
# "Chọn giao diện". Copy sẵn vào đây (không phụ thuộc cmake install của app)
# để có mặt ngay cả khi app hyggshi-welcome chưa từng được build/cài riêng.
for CAR_FILE in car-light.png car-Dark.png car-auto.png; do
  if [ -f "iso-config/branding/$CAR_FILE" ]; then
    sudo cp "iso-config/branding/$CAR_FILE" "$CHROOT/usr/share/backgrounds/hyggshi/$CAR_FILE"
    echo "Đã copy $CAR_FILE vào /usr/share/backgrounds/hyggshi/"
  else
    echo "⚠️  Không thấy iso-config/branding/$CAR_FILE — hyggshi-welcome sẽ bỏ qua đổi wallpaper cho theme tương ứng."
  fi
done

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
      -e 's#<property name="image-style" type="int" value="[0-9]+"#<property name="image-style" type="int" value="5"#g' \
      "$f" 2>/dev/null || true
  done
else
  echo "===== Bỏ qua update-alternatives / patch xfce4-desktop.xml (không có wallpaper.png thật) ====="
fi

echo "===== Custom màn hình đăng nhập (LightDM GTK Greeter) ====="
# Mặc định lightdm-gtk-greeter dùng theme GTK gốc của hệ thống -> ra cái hộp
# thoại trắng vuông vức, avatar xám xịt như ảnh mô tả trong issue. Ở đây ta
# áp GTK3 theme riêng CHỈ áp cho greeter (không đụng tới GTK theme
# của desktop bên trong phiên đăng nhập), lấy từ iso-config/branding/gtk.css
# (khai báo qua linkgreetercss = filecustom(...) trong config.ini).
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

# Nguồn và đích gtk.css cho greeter: ưu tiên từ lệnh copy() trong config.ini, fallback về ./iso-config/branding/gtk.css
GREETER_CSS_SRC=""
GREETER_CSS_DEST=""

if [ -n "$HCL_CFG_GREETER_SRC" ] && [ -f "$HCL_CFG_GREETER_SRC" ]; then
  GREETER_CSS_SRC="$HCL_CFG_GREETER_SRC"
  [ -n "$HCL_CFG_GREETER_TGT" ] && GREETER_CSS_DEST="$CHROOT/${HCL_CFG_GREETER_TGT#/}"
elif [ -f /tmp/hcl-resolved.json ]; then
  RESOLVED_INFO="$(python3 -c "import json
try:
    d = json.load(open('/tmp/hcl-resolved.json'))
    for fc in d.get('file_copies', []):
        if 'gtk.css' in fc.get('source', '') or 'gtk.css' in (fc.get('rename') or '') or 'Hyggshi-Greeter' in (fc.get('target') or ''):
            src = fc.get('source', '')
            tgt = fc.get('resolved_target') or fc.get('target', '')
            print(f\"{src}\t{tgt}\")
            break
    custom = d.get('customization', {})
    for k in ('linkgreetercss', 'linkthemegreeter', 'linkgreetergtk'):
        if k in custom:
            val = custom[k].get('arg') or custom[k].get('path') or ''
            if val:
                print(f\"{val}\t\")
                break
except Exception:
    pass
" 2>/dev/null | head -n1 || true)"
  SRC_PART="$(echo "$RESOLVED_INFO" | cut -f1)"
  TGT_PART="$(echo "$RESOLVED_INFO" | cut -f2)"
  if [ -n "$SRC_PART" ] && [ -f "$SRC_PART" ]; then
    GREETER_CSS_SRC="$SRC_PART"
    if [ -n "$TGT_PART" ]; then
      GREETER_CSS_DEST="$CHROOT/${TGT_PART#/}"
    fi
  fi
fi

if [ -z "$GREETER_CSS_SRC" ] && [ -f "iso-config/branding/gtk.css" ]; then
  GREETER_CSS_SRC="iso-config/branding/gtk.css"
fi

if [ -z "$GREETER_CSS_DEST" ]; then
  GREETER_CSS_DEST="$GREETER_THEME_DIR/gtk.css"
fi

if [ -n "$GREETER_CSS_SRC" ] && [ -f "$GREETER_CSS_SRC" ]; then
  sudo mkdir -p "$(dirname "$GREETER_CSS_DEST")"
  sudo install -m 0644 "$GREETER_CSS_SRC" "$GREETER_CSS_DEST"
  echo "Đã copy [HCL copy] $GREETER_CSS_SRC -> $GREETER_CSS_DEST"
else
  echo "⚠️ Không thấy $GREETER_CSS_SRC (hoặc iso-config/branding/gtk.css) — greeter sẽ dùng theme GTK mặc định." >&2
fi

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

if [ "$BASE_DISTRO" = "debian" ]; then
  ID_LIKE_VALUE="debian"
else
  ID_LIKE_VALUE="ubuntu debian"
fi

# Tránh lặp lại version/codename nếu DISTRO_NAME đã chứa sẵn (ví dụ load từ config.ini)
if [[ "$DISTRO_NAME" == *"$HYGGSHI_VERSION_ID"* ]] || [[ -n "$HYGGSHI_CODENAME" && "$DISTRO_NAME" == *"$HYGGSHI_CODENAME"* ]]; then
  PRETTY_NAME="$DISTRO_NAME"
  DISTRIB_DESCRIPTION="$DISTRO_NAME ($DISTRO_LABEL)"
  ISSUE_TITLE="$DISTRO_NAME"
  MOTD_TITLE="$DISTRO_NAME"
else
  PRETTY_NAME="$DISTRO_NAME $HYGGSHI_VERSION_ID $HYGGSHI_CODENAME"
  DISTRIB_DESCRIPTION="$DISTRO_NAME $HYGGSHI_VERSION_ID \"$HYGGSHI_CODENAME\" ($DISTRO_LABEL)"
  ISSUE_TITLE="$DISTRO_NAME \"$HYGGSHI_CODENAME\""
  MOTD_TITLE="$DISTRO_NAME \"$HYGGSHI_CODENAME\""
fi

cat <<EOF | sudo tee "$CHROOT/usr/lib/os-release" > /dev/null
PRETTY_NAME="$PRETTY_NAME"
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
DISTRIB_DESCRIPTION="$DISTRIB_DESCRIPTION"
EOF

printf "%s \\n \\l\n\n" "$ISSUE_TITLE" | sudo tee "$CHROOT/etc/issue" > /dev/null
echo "Welcome to $MOTD_TITLE — built on $DISTRO_LABEL" | sudo tee "$CHROOT/etc/motd" > /dev/null

echo "===== Distributor logo (GNOME, XFCE, Cinnamon, system info, pixmaps) ====="
# 1. Ưu tiên file logo có sẵn trong repo (checkout local, không phân biệt hoa/thường)
LOGO_FILE=$(find iso-config/branding -maxdepth 1 -iname "logo.*" \
  \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.svg" \) 2>/dev/null | head -n1)
LOGO_SVG_FILE=$(find iso-config/branding -maxdepth 1 -iname "logo.svg" 2>/dev/null | head -n1)

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
    echo "Tạo bộ icon nhiều kích thước từ: $LOGO_FILE"
    for size in 16 22 24 32 48 64 128 192 256 512; do
      convert "$LOGO_FILE" -resize ${size}x${size} "/tmp/logo-$size.png"
    done

    # 1. Cài vào theme mặc định hicolor (cho cả distributor-logo lẫn debian-logo)
    for size in 16 22 24 32 48 64 128 192 256; do
      DEST="$CHROOT/usr/share/icons/hicolor/${size}x${size}/apps"
      sudo mkdir -p "$DEST"
      for name in distributor-logo distributor-logo-debian debian-logo hyggshi-logo; do
        sudo rm -f "$DEST/${name}.png" 2>/dev/null || true
        sudo cp --remove-destination -f "/tmp/logo-$size.png" "$DEST/${name}.png" 2>/dev/null || true
      done
    done
    if [ -n "$LOGO_SVG_FILE" ] && [ -f "$LOGO_SVG_FILE" ]; then
      sudo mkdir -p "$CHROOT/usr/share/icons/hicolor/scalable/apps"
      for name in distributor-logo distributor-logo-debian debian-logo hyggshi-logo; do
        sudo rm -f "$CHROOT/usr/share/icons/hicolor/scalable/apps/${name}.svg" 2>/dev/null || true
        sudo cp --remove-destination -f "$LOGO_SVG_FILE" "$CHROOT/usr/share/icons/hicolor/scalable/apps/${name}.svg" 2>/dev/null || true
      done
    fi

    # 2. GHI ĐÈ VÀO CÁC ICON THEME ĐÃ CÀI (Papirus, Adwaita, Tela...)
    # GNOME/GTK luôn tìm trong icon theme active (như Papirus) TRƯỚC khi fallback về hicolor.
    # Dùng rm -f và --remove-destination để không bao giờ bị lỗi "dangling symlink".
    for theme_dir in "$CHROOT/usr/share/icons"/*; do
      [ -d "$theme_dir" ] || continue
      theme_name="$(basename "$theme_dir")"
      [ "$theme_name" = "hicolor" ] && continue
      [ "$theme_name" = "default" ] && continue
      [ "$theme_name" = "locolor" ] && continue

      # Tìm và ghi đè mọi icon distributor-logo* và debian-logo* có trong theme
      find "$theme_dir" \( -name "distributor-logo*" -o -name "debian-logo*" \) 2>/dev/null | while read -r match_file; do
        match_dir="$(dirname "$match_file")"
        ext="${match_file##*.}"
        sudo rm -f "$match_file" 2>/dev/null || true
        if [ "$ext" = "svg" ]; then
          if [ -n "$LOGO_SVG_FILE" ] && [ -f "$LOGO_SVG_FILE" ]; then
            sudo cp --remove-destination -f "$LOGO_SVG_FILE" "$match_file" 2>/dev/null || true
          else
            sudo cp --remove-destination -f "/tmp/logo-256.png" "${match_file%.*}.png" 2>/dev/null || true
          fi
        else
          dir_size=$(echo "$match_dir" | grep -oE '[0-9]+x[0-9]+' | cut -d'x' -f1 || true)
          if [ -n "$dir_size" ] && [ -f "/tmp/logo-$dir_size.png" ]; then
            sudo cp --remove-destination -f "/tmp/logo-$dir_size.png" "$match_file" 2>/dev/null || true
          else
            sudo cp --remove-destination -f "/tmp/logo-256.png" "$match_file" 2>/dev/null || true
          fi
        fi
      done

      # Đảm bảo các thư mục apps/places phổ biến của theme luôn có distributor-logo
      for sub in "scalable/apps" "scalable/places" "64x64/apps" "48x48/apps" "32x32/apps"; do
        if [ -d "$theme_dir/$sub" ]; then
          for icon_name in distributor-logo distributor-logo-debian debian-logo; do
            if [ -n "$LOGO_SVG_FILE" ] && [ -f "$LOGO_SVG_FILE" ]; then
              sudo rm -f "$theme_dir/$sub/${icon_name}.svg" 2>/dev/null || true
              sudo cp --remove-destination -f "$LOGO_SVG_FILE" "$theme_dir/$sub/${icon_name}.svg" 2>/dev/null || true
            fi
            if [ -f "/tmp/logo-64.png" ]; then
              sudo rm -f "$theme_dir/$sub/${icon_name}.png" 2>/dev/null || true
              sudo cp --remove-destination -f "/tmp/logo-64.png" "$theme_dir/$sub/${icon_name}.png" 2>/dev/null || true
            fi
          done
        fi
      done
      sudo chroot "$CHROOT" gtk-update-icon-cache -f -q "/usr/share/icons/$theme_name" 2>/dev/null || true
    done

    # 3. Ghi đè vào /usr/share/pixmaps (nơi GNOME System Monitor, Hardinfo, Settings fallback tìm)
    sudo mkdir -p "$CHROOT/usr/share/pixmaps"
    for p_name in distributor-logo debian-logo hyggshi-logo; do
      sudo rm -f "$CHROOT/usr/share/pixmaps/${p_name}.png" "$CHROOT/usr/share/pixmaps/${p_name}.svg" 2>/dev/null || true
      sudo cp --remove-destination -f "/tmp/logo-256.png" "$CHROOT/usr/share/pixmaps/${p_name}.png" 2>/dev/null || true
      if [ -n "$LOGO_SVG_FILE" ] && [ -f "$LOGO_SVG_FILE" ]; then
        sudo cp --remove-destination -f "$LOGO_SVG_FILE" "$CHROOT/usr/share/pixmaps/${p_name}.svg" 2>/dev/null || true
      fi
    done

    # 4. Ghi đè thư mục debian-logos do gói desktop-base của Debian cung cấp (nếu có)
    DEBIAN_LOGOS_DIR="$CHROOT/usr/share/desktop-base/debian-logos"
    if [ -d "$DEBIAN_LOGOS_DIR" ]; then
      for size in 64 128 256 512; do
        [ -f "/tmp/logo-$size.png" ] || continue
        sudo rm -f "$DEBIAN_LOGOS_DIR/logo-$size.png" "$DEBIAN_LOGOS_DIR/logo-text-version-$size.png" 2>/dev/null || true
        sudo cp --remove-destination -f "/tmp/logo-$size.png" "$DEBIAN_LOGOS_DIR/logo-$size.png" 2>/dev/null || true
        sudo cp --remove-destination -f "/tmp/logo-$size.png" "$DEBIAN_LOGOS_DIR/logo-text-version-$size.png" 2>/dev/null || true
      done
      echo "Đã ghi đè logo Hyggshi vào $DEBIAN_LOGOS_DIR"
    fi

    sudo chroot "$CHROOT" gtk-update-icon-cache -f /usr/share/icons/hicolor 2>/dev/null || true
    echo "Đã áp logo custom vào hicolor, active icon themes, pixmaps và desktop-base: $LOGO_FILE"
  fi
else
  echo "⚠️  Không thấy file logo trong iso-config/branding/ — vẫn giữ logo mặc định của distro gốc."
  echo "    Thêm file logo.png (khuyến nghị 256x256, nền trong suốt) vào iso-config/branding/ để đổi logo."
fi

# ===== Persist Hyggshi icons/installer shortcut into the installed system =====
# branding.sh runs after the live user has been created and after Calamares has
# been installed. Put the same launcher/icon into /etc/skel so a user created
# by Calamares after installation does not receive the Debian default icon.
if [ -f "iso-config/branding/Hyggshi-OS-Installer.png" ]; then
  echo "===== Persist Install Hyggshi OS icon + desktop entry ====="
  INSTALLER_ICON="$CHROOT/usr/share/icons/hicolor/256x256/apps/hyggshi-installer.png"
  sudo mkdir -p "$(dirname "$INSTALLER_ICON")" "$CHROOT/usr/share/pixmaps" "$CHROOT/etc/skel/Desktop"
  sudo install -m 0644 "iso-config/branding/Hyggshi-OS-Installer.png" "$INSTALLER_ICON"
  sudo install -m 0644 "iso-config/branding/Hyggshi-OS-Installer.png" "$CHROOT/usr/share/pixmaps/hyggshi-installer.png"
  sudo tee "$CHROOT/etc/skel/Desktop/install-hyggshi-os.desktop" > /dev/null <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Install Hyggshi OS
Comment=Cài đặt Hyggshi OS
Exec=/usr/local/bin/hyggshi-launch-installer.sh
Icon=hyggshi-installer
Terminal=false
Categories=System;Settings;
DESKTOP
  sudo chmod 0644 "$CHROOT/etc/skel/Desktop/install-hyggshi-os.desktop"

  # Also refresh the live user's shortcut if one exists.
  # BUG ĐÃ SỬA: "$CHROOT/home/*/Desktop" nằm trong DẤU NHÁY KÉP nên "*"
  # KHÔNG được shell glob — vòng lặp trước đây chỉ thử đúng 2 chuỗi literal
  # (không tồn tại) + "$CHROOT/root/Desktop", nên [ -d ... ] luôn false với
  # nhánh /home/* và desktop entry của user live không bao giờ được refresh
  # qua đường này (mọi user live thực ra vẫn có icon đúng, nhưng là NHỜ
  # useradd -m copy từ /etc/skel LÚC TẠO USER trong desktop.sh — bug này
  # chỉ ảnh hưởng nếu re-run branding.sh trên user đã tồn tại từ trước).
  # Bỏ quote quanh phần chứa "*" để glob hoạt động; giữ quote quanh phần
  # còn lại của path. Không dùng set -f nên glob mặc định được bật.
  for user_desktop in $CHROOT/home/*/Desktop "$CHROOT/root/Desktop"; do
    [ -d "$user_desktop" ] || continue
    sudo cp "$CHROOT/etc/skel/Desktop/install-hyggshi-os.desktop" "$user_desktop/install-hyggshi-os.desktop" 2>/dev/null || true
  done
fi

# Make the Welcome icon robust against icon-theme/cache changes after install.
WELCOME_ICON_SRC="app-for-hyggshi/hyggshi-welcome/resources/icons/logo.png"
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
    [ -z "$BRANDING_COMPONENT" ] && BRANDING_COMPONENT="debian"

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
  echo "Bỏ qua đổi logo sidebar Calamares (thiếu file logo trong iso-config/branding/, hoặc chưa có /etc/calamares/settings.conf)."
fi

# Plymouth boot splash đã được tách sang scripts/plymouth.sh (linkplymouth trong config.ini)

echo "===== Fastfetch: gắn logo custom (logo.txt ưu tiên, Logo.png dự phòng) ====="
# ĐẶT TRƯỚC nhánh "if DE != xfce -> exit 0" bên dưới để áp dụng cho MỌI DE
# (KDE/LXQt/GNOME/MATE/Cinnamon), không chỉ riêng XFCE.
#
# Thứ tự ưu tiên:
#   1) iso-config/branding/logo.txt  — ASCII/ANSI-art ĐÃ CÓ SẴN mã màu
#      (\033[38;2;r;g;bm...) -> dùng "type": "file", fastfetch IN THẲNG nội
#      dung, giữ nguyên escape sequence màu, KHÔNG cần imagemagick/chafa,
#      chạy đúng trên MỌI terminal (kể cả terminal không hỗ trợ image protocol).
#   2) iso-config/branding/Logo.png  — fallback nếu không có logo.txt, dùng
#      "type": "kitty" (image protocol) — CHỈ hiển thị đúng trên terminal hỗ
#      trợ kitty graphics protocol (Kitty, WezTerm, Konsole mới...). Terminal
#      không hỗ trợ sẽ không hiện logo (chỉ hiện info bên phải), không lỗi.
#   3) /usr/share/nexfetch/logos/hyggshi_OS.txt BÊN TRONG CHROOT — nguồn dự
#      phòng cho các bản build không có logo.txt/Logo.png trong repo. Gói
#      nexfetch (cài ở bước install-ecosystem-for-hyggshi.sh, CHẠY TRƯỚC
#      branding.sh trong cả workflow lẫn local-build.sh) mang sẵn logo ASCII
#      Hyggshi tại đường dẫn này (nội dung y hệt iso-config/branding/logo.txt).
#   4) KHÔNG còn fallback "fastfetch tự nhận diện distro" như bản cũ — với
#      /etc/os-release có ID=hyggshios + ID_LIKE=debian, fastfetch auto-detect
#      KHÔNG biết "hyggshios" nên rơi về ID_LIKE và in logo DEBIAN mỗi lần mở
#      terminal. Để tránh logo Debian lọt vào terminal, luôn phải trỏ config
#      vào 1 file logo Hyggshi THẬT SỰ tồn tại; chỉ bỏ qua khi tuyệt đối không
#      có nguồn logo nào (kèm cảnh báo rõ thay vì im lặng đổ về Debian).
FASTFETCH_LOGO_TXT=$(find iso-config/branding -maxdepth 1 -iname "logo.txt" 2>/dev/null | head -n1)
FASTFETCH_LOGO_PNG=$(find iso-config/branding -maxdepth 1 -iname "logo.png" 2>/dev/null | head -n1)
# Logo Hyggshi đi kèm gói nexfetch .deb đã cài vào chroot ở bước ecosystem
# (chạy trước branding.sh) — dùng làm nguồn dự phòng nếu repo không có logo.
NEXFETCH_LOGO_SRC="$CHROOT/usr/share/nexfetch/logos/hyggshi_OS.txt"

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

elif [ -f "$NEXFETCH_LOGO_SRC" ]; then
  # Nguồn dự phòng: logo Hyggshi trong gói nexfetch .deb. KHÔNG để fastfetch
  # rơi về auto-detect — auto-detect sẽ in logo Debian (ID_LIKE=debian).
  sudo mkdir -p "$LOGO_DEST_DIR"
  sudo cp "$NEXFETCH_LOGO_SRC" "$LOGO_DEST_DIR/logo.txt"
  LOGO_JSON='  "logo": {
    "type": "file",
    "source": "/usr/share/hyggshi/branding/logo.txt"
  },'
  echo "Không có logo.txt/Logo.png trong repo — dùng logo Hyggshi từ gói nexfetch ($NEXFETCH_LOGO_SRC) làm logo fastfetch."

else
  echo "⚠️  Không tìm thấy bất kỳ logo Hyggshi nào (repo lẫn gói nexfetch) — KHÔNG ghi config fastfetch." >&2
  echo "    Nếu ghi config mà thiếu file logo, fastfetch auto-detect sẽ in logo DEBIAN (ID_LIKE=debian)." >&2
  echo "    Thêm iso-config/branding/logo.txt để terminal hiện đúng logo Hyggshi." >&2
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
# của gói xfwm4 trên distro nền (thường TẮT trên môi trường live-build) ->
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

# Đã gỡ apply_wallpaper_xfce() (auto-apply wallpaper lúc login cho XFCE qua
# xfconf-query + restart xfdesktop). XFCE giờ rơi vào apply_wallpaper_fallback
# ở dispatch case bên dưới — không tự set wallpaper lúc login nữa, chỉ giữ
# wallpaper mặc định đã patch sẵn vào xfce4-desktop.xml lúc build (skel).

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
  xfce)     echo "XFCE: bỏ qua auto-apply wallpaper lúc login (tính năng đã bị gỡ), giữ wallpaper mặc định lúc build." ;;
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
OnlyShowIn=Cinnamon;GNOME;MATE;KDE;LXQt;
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
