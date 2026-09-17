#!/bin/bash
# plymouth.sh — Plymouth boot splash (logo + dot-wave spinner animation),
# cấu hình theme hyggshi-boot và đóng gói vào initramfs qua hook initramfs-tools.
# Chạy trên HOST, thao tác trực tiếp vào thư mục chroot ($CHROOT).
set -e
[ "$DEBUG_MODE" = "true" ] && set -x
CHROOT="${CHROOT:-${CHROOT_DIR:-live-build/chroot}}"

echo "===== Plymouth boot splash: bắt đầu cấu hình ====="

# ===== HCL: đọc config.ini làm nguồn version / codename / distro name =====
HCL_CONFIG_FILE="${HCL_CONFIG_FILE:-iso-config/config/config.ini}"
HCL_PARSER="${HCL_PARSER:-tools/hcl_parser.py}"
: "${HCL_CONFIG_OVERRIDE:=true}"

HCL_CFG_LOGO=""
if [ "$HCL_CONFIG_OVERRIDE" = "true" ] && [ -f "$HCL_CONFIG_FILE" ] && [ -f "$HCL_PARSER" ]; then
  echo "===== HCL: resolve $HCL_CONFIG_FILE ====="
  HCL_JSON="$(mktemp)"
  if python3 "$HCL_PARSER" "$HCL_CONFIG_FILE" --root . --emit-json "$HCL_JSON" --strict; then
    HCL_CFG_VERSION="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['base_profile'].get('version') or '')" "$HCL_JSON" 2>/dev/null || true)"
    HCL_CFG_CODENAME="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['base_profile'].get('codename') or '')" "$HCL_JSON" 2>/dev/null || true)"
    HCL_CFG_NAME="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['base_profile'].get('name') or '')" "$HCL_JSON" 2>/dev/null || true)"
    HCL_CFG_LOGO="$(python3 -c "import json,sys
d = json.load(open(sys.argv[1]))
custom = d.get('customization', {})
if 'linkimagelogo' in custom:
    print(custom['linkimagelogo'].get('path') or custom['linkimagelogo'].get('url') or '')
" "$HCL_JSON" 2>/dev/null || true)"

    if [ -n "$HCL_CFG_VERSION" ]; then
      HYGGSHI_VERSION_ID="$HCL_CFG_VERSION"
      echo "  -> HYGGSHI_VERSION_ID lấy từ config.ini: $HYGGSHI_VERSION_ID"
    fi
    if [ -n "$HCL_CFG_CODENAME" ]; then
      HYGGSHI_CODENAME="$HCL_CFG_CODENAME"
      echo "  -> HYGGSHI_CODENAME lấy từ config.ini: $HYGGSHI_CODENAME"
    fi
    if [ -n "$HCL_CFG_NAME" ] && [ -z "$DISTRO_NAME" ]; then
      DISTRO_NAME="$HCL_CFG_NAME"
      echo "  -> DISTRO_NAME lấy từ config.ini: $DISTRO_NAME"
    fi
  else
    echo "!! HCL: config.ini có lỗi validate — dùng input/mặc định." >&2
  fi
  rm -f "$HCL_JSON"
fi

# ===== Fallback Codename & Distro Name =====
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
: "${DISTRO_NAME:=Hyggshi OS}"

echo "===== Copy Plymouth branding (nếu có) ====="
if [ -d "iso-config/branding/plymouth" ]; then
  sudo mkdir -p "$CHROOT/usr/share/plymouth/themes"
  sudo cp -r iso-config/branding/plymouth/* "$CHROOT/usr/share/plymouth/themes/" 2>/dev/null || true
fi
if [ -d "iso-config/branding" ]; then
  sudo mkdir -p "$CHROOT/usr/share/plymouth/themes"
  sudo cp -r iso-config/branding/* "$CHROOT/usr/share/plymouth/themes/" 2>/dev/null || true
fi

echo "===== Plymouth boot splash (logo + spinner tròn xoay) ====="
# Theme riêng "hyggshi-boot" dùng module "script" của Plymouth — logo tự
# dán qua link (PLYMOUTH_LOGO_URL), không phụ thuộc theme có sẵn trong
# plymouth-themes. Chạy TRƯỚC bất kỳ desktop environment nào lúc boot nên
# áp dụng chung cho mọi DE.

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

# 3. Dùng file logo từ cấu hình HCL config.ini (linkimagelogo) nếu có
if [ -z "$PLYMOUTH_LOGO_FILE" ] && [ -n "$HCL_CFG_LOGO" ] && [ -f "$HCL_CFG_LOGO" ]; then
  PLYMOUTH_LOGO_FILE="$HCL_CFG_LOGO"
  echo "Dùng logo từ config.ini cho Plymouth: $PLYMOUTH_LOGO_FILE"
fi

# 4. Nếu có $LOGO_FILE từ step trước hoặc biến môi trường
if [ -z "$PLYMOUTH_LOGO_FILE" ] && [ -n "$LOGO_FILE" ] && [ -f "$LOGO_FILE" ]; then
  PLYMOUTH_LOGO_FILE="$LOGO_FILE"
  echo "Dùng chung logo distributor cho Plymouth: $LOGO_FILE"
fi

# 5. Tìm logo distributor chung trong iso-config/branding
if [ -z "$PLYMOUTH_LOGO_FILE" ]; then
  COMMON_LOGO=$(find iso-config/branding -maxdepth 1 -iname "logo.*" \
    \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.svg" \) 2>/dev/null | head -n1)
  if [ -n "$COMMON_LOGO" ]; then
    PLYMOUTH_LOGO_FILE="$COMMON_LOGO"
    echo "Dùng logo chung từ iso-config/branding cho Plymouth: $PLYMOUTH_LOGO_FILE"
  elif [ -n "$LOGO_URL" ]; then
    echo "Tải logo distributor từ \$LOGO_URL cho Plymouth..."
    if curl -fsSL "$LOGO_URL" -o /tmp/logo-remote.png && [ -s /tmp/logo-remote.png ]; then
      PLYMOUTH_LOGO_FILE=/tmp/logo-remote.png
      echo "Tải thành công: $LOGO_URL"
    fi
  elif [ -f "iso-config/branding/Logo.png" ]; then
    PLYMOUTH_LOGO_FILE="iso-config/branding/Logo.png"
    echo "Dùng Logo.png mặc định cho Plymouth: $PLYMOUTH_LOGO_FILE"
  fi
fi

if [ -z "$PLYMOUTH_LOGO_FILE" ]; then
  echo "⚠️  Không có logo nào cho Plymouth (thiếu file local, PLYMOUTH_LOGO_URL và LOGO_URL đều trống/tải lỗi) — bỏ qua, giữ Plymouth theme mặc định của distro gốc."
else
  THEME_DIR="$CHROOT/usr/share/plymouth/themes/hyggshi-boot"
  sudo mkdir -p "$THEME_DIR"
  if [[ -n "$HYGGSHI_CODENAME" && "$DISTRO_NAME" == *"$HYGGSHI_CODENAME"* ]]; then
    DISTRO_NAME_SAFE="${DISTRO_NAME//\"/}"
  else
    DISTRO_NAME_SAFE="${DISTRO_NAME//\"/} ${HYGGSHI_CODENAME}"
  fi

  sudo apt-get install -y imagemagick > /dev/null 2>&1 || true
  if command -v convert > /dev/null 2>&1; then
    convert "$PLYMOUTH_LOGO_FILE" -resize 256x256 /tmp/plymouth-logo.png
  else
    cp "$PLYMOUTH_LOGO_FILE" /tmp/plymouth-logo.png
  fi
  sudo cp /tmp/plymouth-logo.png "$THEME_DIR/logo.png"

  # Copy hyggshi-logo-text.png vào theme (logo chữ gắn đáy màn hình, giống Fedora/Manjaro)
  LOGO_TEXT_FILE=$(find iso-config/branding -maxdepth 1 -iname "hyggshi-logo-text.*" \
    \( -iname "*.png" -o -iname "*.jpg" \) 2>/dev/null | head -n1)
  HAVE_LOGO_TEXT=0
  if [ -n "$LOGO_TEXT_FILE" ]; then
    if command -v convert > /dev/null 2>&1; then
      convert "$LOGO_TEXT_FILE" -resize x60 /tmp/hyggshi-logo-text.png
    else
      cp "$LOGO_TEXT_FILE" /tmp/hyggshi-logo-text.png
    fi
    sudo cp /tmp/hyggshi-logo-text.png "$THEME_DIR/hyggshi-logo-text.png"
    HAVE_LOGO_TEXT=1
    echo "OK: đã copy hyggshi-logo-text.png vào $THEME_DIR"
  else
    echo "⚠️  Không thấy iso-config/branding/hyggshi-logo-text.png — bỏ qua logo text ở đáy."
  fi

  echo "----- Vẽ frame dot-wave 3 chấm kiểu Fedora/Manjaro (ImageMagick) -----"
  # 3 chấm nhỏ nằm ngang, sáng dần theo pha sóng — giống spinner của Manjaro.
  DOTS_COUNT=3
  DOT_RADIUS=5
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
# Hyggshi OS Plymouth Boot Splash
# Layout: nền đen, logo giữa màn hình, spinner 3 chấm bên dưới logo,
# hyggshi-logo-text.png ghim ở đáy — giống Fedora / Manjaro.
Window.SetBackgroundTopColor(0, 0, 0);
Window.SetBackgroundBottomColor(0, 0, 0);

window_width  = Window.GetWidth();
window_height = Window.GetHeight();

# ---- Logo chính ở giữa màn hình ----
logo.image  = Image("logo.png");
logo.sprite = Sprite(logo.image);
logo_x = window_width  / 2 - logo.image.GetWidth()  / 2;
logo_y = window_height / 2 - logo.image.GetHeight() / 2;
logo.sprite.SetX(logo_x);
logo.sprite.SetY(logo_y);
logo.sprite.SetZ(10);

# ---- Hyggshi logo text ghim ở đáy màn hình ----
if ($HAVE_LOGO_TEXT == 1) {
  hyggshi_image  = Image("hyggshi-logo-text.png");
  hyggshi_sprite = Sprite();
  hyggshi_sprite.SetImage(hyggshi_image);
  hyggshi_sprite.SetX(
    Window.GetX() +
    (Window.GetWidth() / 2 - hyggshi_image.GetWidth() / 2)
  );
  hyggshi_sprite.SetY(
    Window.GetHeight() - hyggshi_image.GetHeight() - 50
  );
  hyggshi_sprite.SetZ(10);
}

# ---- Spinner: 3 chấm dot-wave bên dưới logo ----
spinner_frame_count = $SPINNER_FRAMES;
spinner_y = logo_y + logo.image.GetHeight() + 24;

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

  spinner_tick  = 0;
  spinner_index = 0;
  SPINNER_TICKS = 2; # đổi frame mỗi 2 lần refresh (~50Hz) → sóng 3 chấm chạy hết 1 vòng ~1.2s

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

echo "===== Plymouth boot splash: hoàn tất ====="
