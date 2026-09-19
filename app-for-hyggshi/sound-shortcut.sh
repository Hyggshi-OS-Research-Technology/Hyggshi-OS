#!/bin/bash
# sound-shortcut.sh — build + install Hyggshi Sound Shortcut từ source đã commit
# tại app-for-hyggshi/hyggshi-extensions-sound-shortcut/.
# Chạy BÊN TRONG chroot để binary được build bằng đúng glibc/Qt của ISO cuối cùng,
# sau đó install vào rootfs (/usr/bin, /etc/xdg/autostart, icons...).
set -e
[ "$DEBUG_MODE" = "true" ] && set -x
export DEBIAN_FRONTEND=noninteractive
: "${SRC_DIR:=/tmp/hyggshi-extensions-sound-shortcut}"

if [ ! -f "$SRC_DIR/CMakeLists.txt" ]; then
  echo "LỖI: không thấy $SRC_DIR/CMakeLists.txt — sound-shortcut.sh cần source" >&2
  echo "đã commit tại app-for-hyggshi/hyggshi-extensions-sound-shortcut/ và được copy vào chroot." >&2
  exit 1
fi

echo "===== Cài công cụ build cho Hyggshi Sound Shortcut (X11 + Qt6/Qt5) ====="
apt-get update
if ! apt-get install -y cmake build-essential libx11-dev qt6-base-dev; then
  echo "qt6-base-dev không có sẵn — fallback sang Qt5."
  apt-get install -y cmake build-essential libx11-dev qtbase5-dev qt5-qmake
fi

echo "===== cmake configure + build (Release) ====="
cmake -S "$SRC_DIR" -B "$SRC_DIR/build" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr
cmake --build "$SRC_DIR/build" -j"$(nproc)"

echo "===== cmake install (binary + desktop entry + autostart + icons) ====="
cmake --install "$SRC_DIR/build"

# Đồng thời cài autostart vào /etc/skel/.config/autostart cho user mới
mkdir -p /etc/xdg/autostart /etc/skel/.config/autostart
if [ -f "$SRC_DIR/packaging/hyggshi-sound-shortcut-autostart.desktop" ]; then
  install -m 0644 "$SRC_DIR/packaging/hyggshi-sound-shortcut-autostart.desktop" \
    /etc/xdg/autostart/hyggshi-sound-shortcut.desktop
  install -m 0644 "$SRC_DIR/packaging/hyggshi-sound-shortcut-autostart.desktop" \
    /etc/skel/.config/autostart/hyggshi-sound-shortcut.desktop
fi

echo "===== Giữ lại thư viện runtime Qt & X11 trước khi purge công cụ build ====="
SOUND_BIN=$(command -v hyggshi-sound-shortcut || echo /usr/bin/hyggshi-sound-shortcut)
if [ -x "$SOUND_BIN" ]; then
  for so in $(ldd "$SOUND_BIN" 2>/dev/null | awk '{print $3}' | grep -E '^/'); do
    real_so=$(realpath "$so" 2>/dev/null || echo "$so")
    pkg=$(dpkg -S "$real_so" 2>/dev/null | head -n1 | cut -d: -f1)
    if [ -n "$pkg" ]; then
      apt-mark manual "$pkg" > /dev/null 2>&1 || true
    fi
  done
else
  echo "⚠️  Không tìm thấy binary hyggshi-sound-shortcut sau khi cài — bỏ qua bước giữ lib runtime." >&2
fi

echo "===== Dọn công cụ build (giảm dung lượng ISO) ====="
apt-get purge -y --autoremove cmake build-essential libx11-dev qt6-base-dev qtbase5-dev qt5-qmake 2>/dev/null || true
rm -rf "$SRC_DIR/build"

echo "===== Xong: hyggshi-sound-shortcut đã cài + autostart tại /etc/xdg/autostart ====="
