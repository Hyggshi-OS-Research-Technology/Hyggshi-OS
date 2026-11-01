#!/bin/bash
# theme-daemon.sh — build (cmake) + cài hyggshi-theme-daemon (daemon C++
# đổi wallpaper Sáng/Tối, xem scripts/components/make-theme-daemon.sh) TỪ SOURCE đã
# được workflow copy vào $SRC_DIR. Chạy BÊN TRONG chroot (giống welcome.sh/
# desktop.sh) vì app cần nằm trong rootfs của ISO, không phải máy runner CI.
#
# Nguồn được sinh sẵn ở HOST bằng `scripts/components/make-theme-daemon.sh` (chỉ ghi
# file .cpp/CMakeLists/.service/.preset, không cần libxfconf trên runner)
# rồi workflow copy nguyên cây packages/hyggshi/hyggshi-theme-daemon/ vào
# $SRC_DIR — script này chỉ lo phần build + install THẬT bên trong chroot,
# đúng glibc/xfconf của ISO cuối cùng.
set -e
[ "$DEBUG_MODE" = "true" ] && set -x
export DEBIAN_FRONTEND=noninteractive
: "${SRC_DIR:=/tmp/hyggshi-theme-daemon-src}"

if [ ! -f "$SRC_DIR/CMakeLists.txt" ]; then
  echo "LỖI: không thấy $SRC_DIR/CMakeLists.txt — theme-daemon.sh cần source" >&2
  echo "đã được sinh bằng scripts/components/make-theme-daemon.sh và copy vào chroot trước." >&2
  exit 1
fi

echo "===== Cài công cụ build cho Hyggshi Theme Daemon (xfconf + glib) ====="
apt-get update
apt-get install -y cmake build-essential libxfconf-0-dev libglib2.0-dev pkg-config

echo "===== cmake configure + build (Release) ====="
# CMAKE_INSTALL_PREFIX=/usr để binary + systemd --user unit + preset nằm
# đúng chỗ chuẩn (/usr/bin, /usr/lib/systemd/user...), giống cách welcome.sh
# cài hyggshi-welcome.
cmake -S "$SRC_DIR" -B "$SRC_DIR/build" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr
cmake --build "$SRC_DIR/build" -j"$(nproc)"

echo "===== cmake install (binary + systemd --user unit + preset) ====="
cmake --install "$SRC_DIR/build"

echo "===== Giữ lại thư viện runtime (libxfconf/glib) trước khi purge công cụ build ====="
# Giống lý do trong welcome.sh: binary build từ source không có Depends khai
# báo cho apt, nên autoremove có thể dọn nhầm libxfconf-0/libglib2.0-0 nếu
# không apt-mark manual trước. Quét ldd rồi resolve qua dpkg -S (dùng
# realpath để tránh lệch /lib vs /usr/lib do usrmerge).
DAEMON_BIN=$(command -v hyggshi-theme-daemon || echo /usr/bin/hyggshi-theme-daemon)
if [ -x "$DAEMON_BIN" ]; then
  for so in $(ldd "$DAEMON_BIN" 2>/dev/null | awk '{print $3}' | grep -E '^/'); do
    real_so=$(realpath "$so" 2>/dev/null || echo "$so")
    pkg=$(dpkg -S "$real_so" 2>/dev/null | head -n1 | cut -d: -f1)
    if [ -n "$pkg" ]; then
      apt-mark manual "$pkg" > /dev/null 2>&1 || true
    fi
  done
else
  echo "⚠️  Không tìm thấy binary hyggshi-theme-daemon sau khi cài — bỏ qua bước giữ lib runtime." >&2
fi

echo "===== Dọn công cụ build (giảm dung lượng ISO) ====="
apt-get purge -y --autoremove cmake build-essential libxfconf-0-dev libglib2.0-dev pkg-config 2>/dev/null || true
rm -rf "$SRC_DIR/build"

echo "===== Xong: hyggshi-theme-daemon đã cài + preset tự enable tại /usr/lib/systemd/user-preset ====="
