#!/bin/bash
# branding.sh — wallpaper, distributor logo, rebrand os-release/lsb-release,
# panel style + icon theme XFCE, autostart. Chạy trên HOST, ghi thẳng vào
# thư mục chroot (không cần chroot exec, trừ gtk-update-icon-cache).
set -e
[ "$DEBUG_MODE" = "true" ] && set -x
CHROOT=live-build/chroot

# ===== Hyggshi OS Codename =====
# Codename RIÊNG của Hyggshi OS (kiểu Ubuntu "Jammy Jellyfish"), KHÔNG phải
# codename của base distro ($BASE_CODENAME, vd "bookworm"/"noble" — cái đó
# vẫn được giữ nguyên, chỉ đổi vai trò sang HYGGSHI_BASE_CODENAME trong
# os-release). Không thêm workflow input mới (đã chạm giới hạn 25 input của
# workflow_dispatch — xem ghi chú trong Build-Hyggshi-OS-ISO.yml), nên chọn
# theo VERSION_ID hiện có, có thể override bằng biến môi trường
# HYGGSHI_CODENAME nếu build script nào đó (local-build.sh...) muốn set tay.
HYGGSHI_VERSION_ID="1.0"
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
if [ -d "iso-config/branding" ]; then
  sudo cp -r iso-config/branding/* "$CHROOT/usr/share/plymouth/themes/" 2>/dev/null || true
fi

echo "===== Wallpaper ====="
sudo mkdir -p "$CHROOT/usr/share/backgrounds/hyggshi"

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
      -e 's#(<property name="image-style" type="int" value=")[0-9]+(")#\g<1>5\2#g' \
      "$f" 2>/dev/null || true
  done
else
  echo "===== Bỏ qua update-alternatives / patch xfce4-desktop.xml (không có wallpaper.png thật) ====="
fi

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
PRETTY_NAME="$DISTRO_NAME 1.0 \"$HYGGSHI_CODENAME\" (dựa trên $DISTRO_LABEL)"
NAME="$DISTRO_NAME"
VERSION_ID="1.0"
VERSION="1.0 ($HYGGSHI_CODENAME) ($DISTRO_LABEL)"
VERSION_CODENAME="$HYGGSHI_CODENAME"
HYGGSHI_BASE_CODENAME=$BASE_CODENAME
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
DISTRIB_CODENAME="$HYGGSHI_CODENAME"
DISTRIB_DESCRIPTION="$DISTRO_NAME 1.0 \"$HYGGSHI_CODENAME\" ($DISTRO_LABEL)"
EOF

printf "%s \"%s\" \\n \\l\n\n" "$DISTRO_NAME" "$HYGGSHI_CODENAME" | sudo tee "$CHROOT/etc/issue" > /dev/null
echo "Welcome to $DISTRO_NAME \"$HYGGSHI_CODENAME\" — built on $DISTRO_LABEL" | sudo tee "$CHROOT/etc/motd" > /dev/null

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

  # Nhiều tool "System Info" (cinnamon-control-center info panel, mintinfo,
  # hardinfo, gnome-system-monitor...) KHÔNG tra icon theme hicolor như trên,
  # mà đọc thẳng 1 file cố định tại /usr/share/pixmaps/distributor-logo.png
  # (quy ước lâu đời từ Debian/Ubuntu). Thiếu file này là lý do logo không
  # hiện ra trong "System Settings" dù icon hicolor đã cài đủ ở trên.
  sudo mkdir -p "$CHROOT/usr/share/pixmaps"
  convert "$LOGO_FILE" -resize 256x256 "/tmp/logo-pixmap.png"
  sudo cp "/tmp/logo-pixmap.png" "$CHROOT/usr/share/pixmaps/distributor-logo.png"

  echo "Đã áp logo custom: $LOGO_FILE"
  fi
else
  echo "⚠️  Không thấy file logo trong iso-config/branding/ — vẫn giữ logo mặc định của distro gốc."
  echo "    Thêm file logo.png (khuyến nghị 256x256, nền trong suốt) vào iso-config/branding/ để đổi logo."
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
#   3) Không có gì cả — bỏ qua, fastfetch tự dùng logo nhận diện distro mặc định.
FASTFETCH_LOGO_TXT=$(find iso-config/branding -maxdepth 1 -iname "logo.txt" 2>/dev/null | head -n1)
FASTFETCH_LOGO_PNG=$(find iso-config/branding -maxdepth 1 -iname "logo.png" 2>/dev/null | head -n1)

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
  echo "Không thấy logo.txt hoặc Logo.png trong iso-config/branding/ — fastfetch dùng logo tự nhận diện distro mặc định."
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
