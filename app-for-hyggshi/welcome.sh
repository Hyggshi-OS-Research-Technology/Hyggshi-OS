#!/bin/bash
# welcome.sh — build (cmake) + cài hyggshi-welcome (Qt wizard chào mừng lần
# đầu, xem scripts/make-welcome.sh) TỪ SOURCE đã được workflow copy vào
# $SRC_DIR. Chạy BÊN TRONG chroot (giống desktop.sh/
# install-ecosystem-for-hyggshi.sh) vì app cần nằm trong rootfs của ISO,
# không phải máy runner CI.
#
# Nguồn được sinh sẵn ở HOST bằng `scripts/make-welcome.sh` (không cần Qt
# trên runner, chỉ ghi file .cpp/.h/CMakeLists) rồi workflow copy nguyên cây
# app-for-hyggshi/hyggshi-welcome/ vào $SRC_DIR — script này chỉ lo phần
# build + install THẬT bên trong chroot, đúng glibc/Qt của ISO cuối cùng.
set -e
[ "$DEBUG_MODE" = "true" ] && set -x
export DEBIAN_FRONTEND=noninteractive
: "${SRC_DIR:=/tmp/hyggshi-welcome-src}"

if [ ! -f "$SRC_DIR/CMakeLists.txt" ]; then
  echo "LỖI: không thấy $SRC_DIR/CMakeLists.txt — welcome.sh cần source đã" >&2
  echo "được sinh bằng scripts/make-welcome.sh và copy vào chroot trước." >&2
  exit 1
fi

echo "===== Cài công cụ build cho Hyggshi Welcome (ưu tiên Qt6, fallback Qt5) ====="
apt-get update
if ! apt-get install -y cmake build-essential qt6-base-dev; then
  echo "qt6-base-dev không có sẵn (base distro/codename cũ) — fallback sang Qt5."
  apt-get install -y cmake build-essential qtbase5-dev qt5-qmake
fi

echo "===== cmake configure + build (Release) ====="
# CMAKE_INSTALL_PREFIX=/usr (mặc định của cmake là /usr/local) để binary +
# desktop entry nằm đúng chỗ chuẩn của package hệ thống (/usr/bin,
# /usr/share/applications), giống các gói .deb khác trong ISO.
cmake -S "$SRC_DIR" -B "$SRC_DIR/build" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr
cmake --build "$SRC_DIR/build" -j"$(nproc)"

echo "===== cmake install (binary + desktop entry + autostart) ====="
cmake --install "$SRC_DIR/build"

echo "===== Giữ lại thư viện runtime Qt trước khi purge công cụ build ====="
# apt không biết binary hyggshi-welcome (build từ source, không phải .deb có
# khai báo Depends) cần các thư viện .so runtime này, nên nếu chỉ chạy
# "apt-get purge --autoremove" cho -dev/cmake/build-essential thì autoremove
# CÓ THỂ dọn nhầm luôn libQt6Widgets.so.* v.v vì tưởng không còn ai cần.
# Quét ldd trên binary vừa build rồi apt-mark manual đúng gói sở hữu từng
# .so để giữ chúng lại an toàn — không cần đoán tên gói theo từng distro/
# codename (bookworm/trixie/noble... đặt tên khác nhau, có/không hậu tố t64).
WELCOME_BIN=$(command -v hyggshi-welcome || echo /usr/bin/hyggshi-welcome)
if [ -x "$WELCOME_BIN" ]; then
  for so in $(ldd "$WELCOME_BIN" 2>/dev/null | awk '{print $3}' | grep -E '^/'); do
    # QUAN TRỌNG: trên Debian/Ubuntu hiện đại /lib là SYMLINK sang /usr/lib
    # (usrmerge). ldd trả đường dẫn qua /lib/..., nhưng dpkg liệt kê file
    # đã cài dưới /usr/lib/... trong .list — nên `dpkg -S "$so"` với path
    # còn nguyên /lib/... SẼ KHÔNG khớp gì cả (không lỗi, chỉ lặng lẽ trả
    # rỗng), khiến vòng lặp này tưởng chạy được nhưng thực ra không
    # apt-mark manual được gói nào, và purge bên dưới xoá mất
    # libQt6Widgets.so.* làm hyggshi-welcome hết chạy được. Resolve qua
    # realpath trước để luôn tra đúng theo path thật /usr/lib/... mà dpkg
    # biết.
    real_so=$(realpath "$so" 2>/dev/null || echo "$so")
    pkg=$(dpkg -S "$real_so" 2>/dev/null | head -n1 | cut -d: -f1)
    if [ -n "$pkg" ]; then
      apt-mark manual "$pkg" > /dev/null 2>&1 || true
    fi
  done
else
  echo "⚠️  Không tìm thấy binary hyggshi-welcome sau khi cài — bỏ qua bước giữ lib runtime." >&2
fi

echo "===== Dọn công cụ build (giảm dung lượng ISO) ====="
apt-get purge -y --autoremove cmake build-essential qt6-base-dev qtbase5-dev qt5-qmake 2>/dev/null || true
rm -rf "$SRC_DIR/build"

echo "===== Xong: hyggshi-welcome đã cài + autostart tại /etc/xdg/autostart ====="
