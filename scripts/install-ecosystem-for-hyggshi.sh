#!/bin/bash
# install-ecosystem-for-hyggshi.sh — cài đặt hệ sinh thái ứng dụng Hyggshi OS:
#   1) Tự động mở mọi file .zip trong app-for-hyggshi/
#   2) Cài mọi file .deb tìm thấy bên trong (apt install, fallback dpkg -i)
#   3) Ghi lại config.json (logo, plugin, module) cho nexfetch
set -e
[ "$DEBUG_MODE" = "true" ] && set -x

# Cho phép chạy script từ bất kỳ đâu trong repo — tự xác định gốc repo dựa
# trên vị trí thật của chính file này (scripts/install-ecosystem-for-hyggshi.sh)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

APP_DIR="${APP_DIR:-app-for-hyggshi}"
WORK_DIR="$(mktemp -d /tmp/hyggshi-ecosystem-XXXXXX)"
trap 'rm -rf "$WORK_DIR"' EXIT

echo "===== Cài đặt hệ sinh thái Hyggshi OS ====="
echo "Repo root : $REPO_ROOT"
echo "App dir   : $APP_DIR"

# ----- 0. Đảm bảo có unzip -----
if ! command -v unzip > /dev/null 2>&1; then
  echo "Không tìm thấy 'unzip', đang cài đặt..."
  sudo apt-get update -qq
  sudo apt-get install -y unzip
fi

if [ ! -d "$APP_DIR" ]; then
  echo "⚠️  Không tìm thấy thư mục '$APP_DIR' — không có gì để cài, dừng lại."
  exit 0
fi

# ----- 1. Mở mọi file .zip trong app-for-hyggshi/ -----
ZIP_COUNT=0
DEB_FILES=()

shopt -s nullglob
for ZIP in "$APP_DIR"/*.zip; do
  ZIP_COUNT=$((ZIP_COUNT + 1))
  BASENAME="$(basename "$ZIP" .zip)"
  DEST="$WORK_DIR/$BASENAME"
  mkdir -p "$DEST"
  echo "📦 Giải nén: $ZIP -> $DEST"
  unzip -oq "$ZIP" -d "$DEST"

  while IFS= read -r -d '' DEB; do
    DEB_FILES+=("$DEB")
  done < <(find "$DEST" -type f -iname "*.deb" -print0)
done
shopt -u nullglob

if [ "$ZIP_COUNT" -eq 0 ]; then
  echo "⚠️  Không tìm thấy file .zip nào trong '$APP_DIR'."
fi

# ----- 2. Cài mọi file .deb tìm được -----
if [ "${#DEB_FILES[@]}" -eq 0 ]; then
  echo "⚠️  Không tìm thấy file .deb nào sau khi giải nén — bỏ qua bước cài gói."
else
  echo "===== Cài đặt ${#DEB_FILES[@]} gói .deb tìm thấy ====="
  sudo apt-get update -qq || true
  for DEB in "${DEB_FILES[@]}"; do
    echo "📥 Cài đặt: $(basename "$DEB")"
    # apt-get install tự resolve dependency cho file .deb local (apt >= 1.1);
    # nếu không có/không hoạt động thì fallback sang dpkg -i + apt -f install
    if ! sudo apt-get install -y "$DEB"; then
      echo "   apt-get install thất bại, thử dpkg -i ..."
      sudo dpkg -i "$DEB" || true
      echo "   Sửa dependency còn thiếu (apt-get install -f) ..."
      sudo apt-get install -f -y
    fi
  done
fi

# ----- 3. Cấu hình logo + module cho nexfetch -----
echo "===== Cấu hình config.json (logo, plugin, module) cho nexfetch ====="

# nexfetch đọc config từ /etc/nexfetch/config.json (conffile của gói .deb)
# và có bản mặc định ở /usr/share/nexfetch/config/config.json — ghi cả hai
# để chắc chắn logo/module áp dụng dù bản nào được nexfetch dùng.
NEXFETCH_CONFIG_DIRS=(
  "/etc/nexfetch"
  "/usr/share/nexfetch/config"
)

LOGO_REL_PATH=".iso-config/branding/Logo.png"
SRC_LOGO="$REPO_ROOT/iso-config/branding/Logo.png"

read -r -d '' NEXFETCH_CONFIG_JSON << 'JSON' || true
{
  "show_logo": true,
  "color_blocks": true,
  "theme": "classic",
  "logo": ".iso-config/branding/Logo.png",
  "logo_width": 32,
  "background_image": "",
  "plugins": [
    "plugins/my_plugin.so",
    "plugins/docker.so",
    "plugins/vision.so",
    "plugins/vision_nexfetch.so"
  ],
  "modules": [
    "os",
    "kernel",
    "host",
    "uptime",
    "packages",
    "display",
    "shell",
    "de",
    "wm",
    "terminal",
    "cpu",
    "gpu",
    "memory",
    "disk",
    "swap",
    "battery",
    "network",
    "theme",
    "icons",
    "font",
    "locale",
    "mymodule",
    "vision_docker",
    "visioncamera",
    "vision_nexfetch"
  ]
}
JSON

for DIR in "${NEXFETCH_CONFIG_DIRS[@]}"; do
  sudo mkdir -p "$DIR"
  echo "$NEXFETCH_CONFIG_JSON" | sudo tee "$DIR/config.json" > /dev/null
  echo "✅ Đã ghi $DIR/config.json"

  # Copy Logo.png vào đúng đường dẫn tương đối mà "logo" trong config.json
  # trỏ tới (.iso-config/branding/Logo.png), để resolve được ngay cả khi
  # nexfetch chạy với cwd = $DIR
  if [ -f "$SRC_LOGO" ]; then
    sudo mkdir -p "$DIR/$(dirname "$LOGO_REL_PATH")"
    sudo cp "$SRC_LOGO" "$DIR/$LOGO_REL_PATH"
    echo "🖼  Đã copy logo -> $DIR/$LOGO_REL_PATH"
  else
    echo "⚠️  Không tìm thấy $SRC_LOGO — logo trong config.json sẽ không hiển thị."
  fi
done

echo "===== Hoàn tất cài đặt hệ sinh thái Hyggshi OS ====="
