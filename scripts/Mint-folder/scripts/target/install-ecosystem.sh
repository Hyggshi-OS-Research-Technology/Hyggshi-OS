#!/bin/bash
# install-ecosystem-for-hyggshi.sh — cài đặt hệ sinh thái ứng dụng Hyggshi OS:
#   1) Tự động mở mọi file .zip trong packages/hyggshi/
#   2) Cài mọi file .deb tìm thấy bên trong (apt install, fallback dpkg -i)
#   3) Ghi lại config.json (logo, plugin, module) cho nexfetch
set -e
[ "$DEBUG_MODE" = "true" ] && set -x

# Cho phép chạy script từ bất kỳ đâu trong repo — tự xác định gốc repo dựa
# trên vị trí thật của chính file này (scripts/target/install-ecosystem.sh).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="${REPO_ROOT:-$DEFAULT_REPO_ROOT}"

# Bên trong chroot (chạy qua `chroot build/chroot ...`), tiến trình đã
# LÀ root và chroot debootstrap tối giản thường KHÔNG có sẵn lệnh sudo — gọi
# cứng "sudo" sẽ báo "command not found" và script chết ngay dòng đầu. Chỉ
# dùng sudo khi thật sự chưa phải root.
SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  SUDO="sudo"
fi

export DEBIAN_FRONTEND=noninteractive

# APP_DIR nhận đường dẫn TUYỆT ĐỐI trực tiếp nếu được truyền qua biến môi
# trường (xem step "[install-ecosystem-for-hyggshi.sh]" trong .github/
# workflows/build-hyggshi-os.yml — nó copy packages/hyggshi/ vào /tmp bên
# trong chroot rồi truyền thẳng path tuyệt đối), KHÔNG phụ thuộc vào
# REPO_ROOT/logic "cd" — tránh lỗi lệch version khi .yml và .sh không được
# cập nhật đồng bộ. Nếu không truyền, tự fallback theo REPO_ROOT.
APP_DIR="${APP_DIR:-$REPO_ROOT/packages/hyggshi}"

WORK_DIR="$(mktemp -d /tmp/hyggshi-ecosystem-XXXXXX)"
trap 'rm -rf "$WORK_DIR"' EXIT

echo "===== Cài đặt hệ sinh thái Hyggshi OS ====="
echo "Repo root : $REPO_ROOT"
echo "App dir   : $APP_DIR"

# ----- 0. Đảm bảo có unzip -----
if ! command -v unzip > /dev/null 2>&1; then
  echo "Không tìm thấy 'unzip', đang cài đặt..."
  $SUDO apt-get update -qq
  $SUDO apt-get install -y unzip
fi

if [ ! -d "$APP_DIR" ]; then
  echo "⚠️  Không tìm thấy thư mục '$APP_DIR' — không có gì để cài, dừng lại."
  exit 0
fi

# ----- 1. Mở mọi file .zip trong packages/hyggshi/ -----
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
  $SUDO apt-get update -qq || true
  for DEB in "${DEB_FILES[@]}"; do
    echo "📥 Cài đặt: $(basename "$DEB")"
    # apt-get install tự resolve dependency cho file .deb local (apt >= 1.1);
    # nếu không có/không hoạt động thì fallback sang dpkg -i + apt -f install
    if ! $SUDO apt-get install -y "$DEB"; then
      echo "   apt-get install thất bại, thử dpkg -i ..."
      $SUDO dpkg -i "$DEB" || true
      echo "   Sửa dependency còn thiếu (apt-get install -f) ..."
      $SUDO apt-get install -f -y
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

# Dùng logo ASCII có SẴN bên trong gói nexfetch (logos/hyggshi_OS.txt, đã
# render ANSI/truecolor block art) thay vì Logo.png ngoài repo — file này do
# chính .deb cài vào, nên KHÔNG cần copy/tính path tương đối gì thêm, luôn
# tồn tại ngay sau bước cài .deb ở trên và không phụ thuộc REPO_ROOT.
#
# LƯU Ý: gói nexfetch KHÔNG ship file tên "logo.txt" — tên file thật trong
# logos/ là "hyggshi_OS.txt" (kèm theo debian.txt, arch.txt, tux.txt, ...).
# Dò qua vài tên khả dĩ để không vỡ nếu tên file đổi giữa các bản nexfetch.
NEXFETCH_LOGO_DIR="/usr/share/nexfetch/logos"
NEXFETCH_LOGO_PATH=""
for CANDIDATE in "hyggshi_OS.txt" "hyggshi-os.txt" "logo.txt" "nexfetch.txt"; do
  if [ -f "$NEXFETCH_LOGO_DIR/$CANDIDATE" ]; then
    NEXFETCH_LOGO_PATH="$NEXFETCH_LOGO_DIR/$CANDIDATE"
    break
  fi
done
if [ -z "$NEXFETCH_LOGO_PATH" ]; then
  echo "⚠️  Không tìm thấy logo nào khớp trong $NEXFETCH_LOGO_DIR — dùng mặc định hyggshi_OS.txt."
  NEXFETCH_LOGO_PATH="$NEXFETCH_LOGO_DIR/hyggshi_OS.txt"
fi

read -r -d '' NEXFETCH_CONFIG_JSON << JSON || true
{
  "show_logo": true,
  "color_blocks": true,
  "theme": "classic",
  "logo": "$NEXFETCH_LOGO_PATH",
  "logo_width": 32,
  "background_image": "",
  "plugins": [
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
    "locale"
  ]
}
JSON

for DIR in "${NEXFETCH_CONFIG_DIRS[@]}"; do
  $SUDO mkdir -p "$DIR"
  echo "$NEXFETCH_CONFIG_JSON" | $SUDO tee "$DIR/config.json" > /dev/null
  echo "✅ Đã ghi $DIR/config.json"
done

if [ -f "$NEXFETCH_LOGO_PATH" ]; then
  echo "🖼  Logo có sẵn: $NEXFETCH_LOGO_PATH"
else
  echo "⚠️  Không thấy $NEXFETCH_LOGO_PATH — có thể gói nexfetch chưa cài thành công ở bước trên."
fi

echo "===== Hoàn tất cài đặt hệ sinh thái Hyggshi OS ====="
