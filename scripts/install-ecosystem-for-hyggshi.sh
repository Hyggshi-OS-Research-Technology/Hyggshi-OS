#!/bin/bash
# install-ecosystem-for-hyggshi.sh — cài đặt hệ sinh thái ứng dụng Hyggshi OS:
#   1) Tự động cài mọi file .deb trong app-for-hyggshi/ (nexcode, nexfetch...)
#   2) Tự động mở mọi file .zip trong app-for-hyggshi/, cài .deb và binary (nexwm, nex-panel...)
#   3) Tải và cài đặt mọi app khai báo qua URL/fileinstall() từ config.ini (HCL_APP_INSTALLS)
#   4) Ghi lại config.json (logo, plugin, module) cho nexfetch
set -e
[ "$DEBUG_MODE" = "true" ] && set -x

# Cho phép chạy script từ bất kỳ đâu trong repo — tự xác định gốc repo dựa
# trên vị trí thật của chính file này (scripts/install-ecosystem-for-hyggshi.sh).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="${REPO_ROOT:-$DEFAULT_REPO_ROOT}"

# Bên trong chroot (chạy qua `chroot live-build/chroot ...`), tiến trình đã
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
# workflows/Build-Hyggshi-OS-ISO.yml — nó copy app-for-hyggshi/ vào /tmp bên
# trong chroot rồi truyền thẳng path tuyệt đối), KHÔNG phụ thuộc vào
# REPO_ROOT/logic "cd" — tránh lỗi lệch version khi .yml và .sh không được
# cập nhật đồng bộ. Nếu không truyền, tự fallback theo REPO_ROOT.
APP_DIR="${APP_DIR:-$REPO_ROOT/app-for-hyggshi}"

WORK_DIR="$(mktemp -d /tmp/hyggshi-ecosystem-XXXXXX)"
trap 'rm -rf "$WORK_DIR"' EXIT

echo "===== Cài đặt hệ sinh thái Hyggshi OS ====="
echo "Repo root : $REPO_ROOT"
echo "App dir   : $APP_DIR"

# ----- 0. Đảm bảo có các công cụ cần thiết (unzip, curl, file) -----
MISSING_TOOLS=()
for tool in unzip curl file; do
  if ! command -v "$tool" > /dev/null 2>&1; then
    MISSING_TOOLS+=("$tool")
  fi
done

if [ "${#MISSING_TOOLS[@]}" -gt 0 ]; then
  echo "Đang cài đặt các công cụ còn thiếu: ${MISSING_TOOLS[*]}..."
  $SUDO apt-get update -qq || true
  $SUDO apt-get install -y "${MISSING_TOOLS[@]}" || true
fi

DEB_FILES=()
BIN_FILES=()

# Helper: thêm gói .deb vào danh sách nếu chưa có
add_deb() {
  local f="$1"
  [ -f "$f" ] || return 0
  for existing in "${DEB_FILES[@]}"; do
    if [ "$existing" = "$f" ]; then
      return 0
    fi
  done
  DEB_FILES+=("$f")
}

# Helper: cài đặt file binary ELF vào /usr/local/bin
install_binary() {
  local bin="$1"
  local name
  name="$(basename "$bin")"
  echo "⚙️  Cài binary vào /usr/local/bin: $name"
  $SUDO cp "$bin" "/usr/local/bin/$name"
  $SUDO chmod 755 "/usr/local/bin/$name"
}

# ----- 1. Quét và thu thập các file .deb trực tiếp trong APP_DIR -----
if [ -d "$APP_DIR" ]; then
  shopt -s nullglob
  for DEB in "$APP_DIR"/*.deb; do
    echo "📦 Tìm thấy gói .deb trực tiếp: $(basename "$DEB")"
    add_deb "$DEB"
  done

  # ----- 2. Mở mọi file .zip trong app-for-hyggshi/ -----
  ZIP_COUNT=0
  for ZIP in "$APP_DIR"/*.zip; do
    ZIP_COUNT=$((ZIP_COUNT + 1))
    BASENAME="$(basename "$ZIP" .zip)"
    DEST="$WORK_DIR/$BASENAME"
    mkdir -p "$DEST"
    echo "📦 Giải nén: $ZIP -> $DEST"
    unzip -oq "$ZIP" -d "$DEST"

    # Thu thập file .deb bên trong zip
    while IFS= read -r -d '' DEB; do
      add_deb "$DEB"
    done < <(find "$DEST" -type f -iname "*.deb" -print0)

    # Thu thập binary ELF thực thi bên trong zip (như nexwm, nex-panel, nex-launcher...)
    while IFS= read -r -d '' BIN; do
      if [ -f "$BIN" ] && file "$BIN" 2>/dev/null | grep -q "ELF.*executable"; then
        install_binary "$BIN"
      fi
    done < <(find "$DEST" -type f -print0)
  done
  shopt -u nullglob

  if [ "$ZIP_COUNT" -eq 0 ]; then
    echo "ℹ️  Không có file .zip nào trong '$APP_DIR'."
  fi
fi

# ----- 3. Tải và xử lý các app khai báo qua HCL_APP_INSTALLS / fileinstall() -----
# HCL_APP_INSTALLS chứa danh sách file path hoặc URL (http/https)
if [ -n "${HCL_APP_INSTALLS:-}" ]; then
  echo "===== Xử lý ứng dụng từ config.ini (HCL_APP_INSTALLS) ====="
  DOWNLOAD_DIR="$WORK_DIR/downloads"
  mkdir -p "$DOWNLOAD_DIR"

  for ITEM in $HCL_APP_INSTALLS; do
    # Bỏ qua nếu item rỗng
    [ -z "$ITEM" ] && continue

    if [[ "$ITEM" =~ ^https?:// ]]; then
      echo "🌐 Tải ứng dụng từ URL: $ITEM"
      URL_BASENAME="$(basename "${ITEM%%\?*}")"
      [ -z "$URL_BASENAME" ] && URL_BASENAME="downloaded_app_$(date +%s)"
      TARGET_FILE="$DOWNLOAD_DIR/$URL_BASENAME"

      if command -v curl > /dev/null 2>&1; then
        curl -fsSL "$ITEM" -o "$TARGET_FILE" || echo "⚠️  Tải thất bại: $ITEM"
      elif command -v wget > /dev/null 2>&1; then
        wget -q "$ITEM" -O "$TARGET_FILE" || echo "⚠️  Tải thất bại: $ITEM"
      fi

      if [ -f "$TARGET_FILE" ]; then
        MIME_TYPE="$(file -b --mime-type "$TARGET_FILE" 2>/dev/null || true)"
        if [[ "$TARGET_FILE" == *.deb ]] || [ "$MIME_TYPE" = "application/vnd.debian.binary-package" ]; then
          add_deb "$TARGET_FILE"
        elif [[ "$TARGET_FILE" == *.zip ]] || [ "$MIME_TYPE" = "application/zip" ]; then
          UNZIP_DEST="$DOWNLOAD_DIR/unpacked_${URL_BASENAME}"
          mkdir -p "$UNZIP_DEST"
          unzip -oq "$TARGET_FILE" -d "$UNZIP_DEST"
          while IFS= read -r -d '' DEB; do add_deb "$DEB"; done < <(find "$UNZIP_DEST" -type f -iname "*.deb" -print0)
          while IFS= read -r -d '' BIN; do
            if [ -f "$BIN" ] && file "$BIN" 2>/dev/null | grep -q "ELF.*executable"; then
              install_binary "$BIN"
            fi
          done < <(find "$UNZIP_DEST" -type f -print0)
        elif [[ "$TARGET_FILE" == *.tar.gz ]] || [[ "$TARGET_FILE" == *.tgz ]]; then
          TAR_DEST="$DOWNLOAD_DIR/unpacked_${URL_BASENAME}"
          mkdir -p "$TAR_DEST"
          tar -xzf "$TARGET_FILE" -C "$TAR_DEST" || true
          while IFS= read -r -d '' DEB; do add_deb "$DEB"; done < <(find "$TAR_DEST" -type f -iname "*.deb" -print0)
        elif file "$TARGET_FILE" 2>/dev/null | grep -q "ELF.*executable"; then
          install_binary "$TARGET_FILE"
        fi
      fi
    else
      # Đường dẫn file local (ví dụ ./app-for-hyggshi/nexcode... hoặc /tmp/app-for-hyggshi/...)
      LOCAL_CANDIDATE=""
      BASE_NAME="$(basename "$ITEM")"
      if [ -f "$ITEM" ]; then
        LOCAL_CANDIDATE="$ITEM"
      elif [ -f "$APP_DIR/$BASE_NAME" ]; then
        LOCAL_CANDIDATE="$APP_DIR/$BASE_NAME"
      elif [ -f "$REPO_ROOT/$ITEM" ]; then
        LOCAL_CANDIDATE="$REPO_ROOT/$ITEM"
      fi

      if [ -n "$LOCAL_CANDIDATE" ]; then
        if [[ "$LOCAL_CANDIDATE" == *.deb ]]; then
          add_deb "$LOCAL_CANDIDATE"
        fi
      fi
    fi
  done
fi

# ----- 3.5. Lọc bỏ .deb SAI kiến trúc so với chroot đang cài (vd .deb
# amd64-only như nexfetch/nexcode hiện tại — xem app-for-hyggshi/*.deb —
# đưa vào chroot arm64) TRƯỚC khi cài, thay vì để apt-get/dpkg -i fail giữa
# chừng rồi kéo `apt-get install -f -y` (không có "|| true") fail theo do
# `set -e`, sập cả script chỉ vì 1 .deb không tương thích. "all" (gói
# arch-independent, vd .deb chỉ chứa script/asset) luôn được giữ.
CHROOT_ARCH="$(dpkg --print-architecture 2>/dev/null || echo unknown)"
COMPATIBLE_DEB_FILES=()
for DEB in "${DEB_FILES[@]}"; do
  DEB_ARCH="$(dpkg-deb -f "$DEB" Architecture 2>/dev/null || echo unknown)"
  if [ "$DEB_ARCH" = "all" ] || [ "$DEB_ARCH" = "$CHROOT_ARCH" ] || [ "$CHROOT_ARCH" = "unknown" ]; then
    COMPATIBLE_DEB_FILES+=("$DEB")
  else
    echo "⚠️  Bỏ qua $(basename "$DEB") — gói build cho '$DEB_ARCH', chroot này là '$CHROOT_ARCH' (không tương thích)." >&2
  fi
done
DEB_FILES=("${COMPATIBLE_DEB_FILES[@]}")

# ----- 4. Cài mọi file .deb tìm được -----
if [ "${#DEB_FILES[@]}" -eq 0 ]; then
  echo "⚠️  Không tìm thấy file .deb nào tương thích — bỏ qua bước cài gói deb."
else
  echo "===== Cài đặt ${#DEB_FILES[@]} gói .deb ====="
  $SUDO apt-get update -qq || true
  for DEB in "${DEB_FILES[@]}"; do
    echo "📥 Cài đặt: $(basename "$DEB")"
    if ! $SUDO apt-get install -y "$DEB"; then
      echo "   apt-get install thất bại, thử dpkg -i ..."
      $SUDO dpkg -i "$DEB" || true
      echo "   Sửa dependency còn thiếu (apt-get install -f) ..."
      $SUDO apt-get install -f -y
    fi
  done
fi

# ----- 5. Cấu hình logo + module cho nexfetch -----
echo "===== Cấu hình config.json (logo, plugin, module) cho nexfetch ====="

NEXFETCH_CONFIG_DIRS=(
  "/etc/nexfetch"
  "/usr/share/nexfetch/config"
)

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
