#!/bin/bash
# build-nexwm.sh — clone + build (make) + cài NexWM TỪ SOURCE, và tạo đúng
# X11 session (/usr/share/xsessions/nexwm.desktop) để LightDM/SDDM/GDM nhận
# diện NexDE như một session chọn được ở màn hình đăng nhập.
#
# Chạy BÊN TRONG chroot (giống desktop.sh / welcome.sh /
# install-ecosystem-for-hyggshi.sh) vì binary + session file cần nằm trong
# rootfs của ISO cuối cùng, không phải máy runner CI.
#
# Biến môi trường (đều có default, workflow có thể override):
#   NEXWM_REPO_URL  - URL git repo NexWM (mặc định: org Hyggshi-OS-Research-Technology)
#   NEXWM_REF       - branch/tag/commit để checkout (mặc định: main)
#   SRC_DIR         - nơi clone source vào (mặc định: /tmp/nexwm-src)
#   PREFIX          - install prefix (mặc định: /usr, khớp các gói .deb khác trong ISO)
#
# LƯU Ý QUAN TRỌNG (bug đã gặp thực tế, xem lịch sử sửa nexwm.desktop):
#   - File .desktop cho display manager PHẢI là Type=XSession, KHÔNG PHẢI
#     Type=Application — sai type khiến LightDM/SDDM/GDM không hiện hoặc từ
#     chối chạy session này ("không cho chạy").
#   - Exec/TryExec PHẢI là đường dẫn TUYỆT ĐỐI — display manager chạy với
#     PATH bị giới hạn, thường KHÔNG có /usr/local/bin.
#   Vì không chắc chắn source trên git đã có bản vá 2 lỗi này hay chưa (có
#   thể lệch phiên bản với lần audit trước), script này LUÔN LUÔN tự ghi đè
#   nexwm.desktop + start-nexde bằng nội dung đã biết là đúng SAU BƯỚC
#   `make install`, thay vì tin tưởng hoàn toàn vào file trong repo.
set -e
[ "$DEBUG_MODE" = "true" ] && set -x
export DEBIAN_FRONTEND=noninteractive

: "${NEXWM_REPO_URL:=https://github.com/Hyggshi-OS-Research-Technology/NexWM.git}"
: "${NEXWM_REF:=main}"
: "${SRC_DIR:=/tmp/nexwm-src}"
: "${PREFIX:=/usr}"

echo "===== Cài build dependency cho NexWM (xcb/X11 dev headers) ====="
apt-get update
apt-get install -y --no-install-recommends \
  git build-essential pkg-config \
  libx11-dev libxcb1-dev libxcb-util-dev libxcb-util0-dev \
  libxcb-randr0-dev libxcb-ewmh-dev libxcb-icccm4-dev libxcb-keysyms1-dev \
  qt6-base-dev qt6-base-dev-tools

echo "===== Clone NexWM (${NEXWM_REPO_URL} @ ${NEXWM_REF}) ====="
rm -rf "$SRC_DIR"
if ! git clone --branch "$NEXWM_REF" --depth=1 "$NEXWM_REPO_URL" "$SRC_DIR"; then
  echo "LỖI: clone thất bại (URL/branch sai, hoặc mất mạng/rate-limit)." >&2
  echo "Kiểm tra lại NEXWM_REPO_URL='$NEXWM_REPO_URL' NEXWM_REF='$NEXWM_REF'." >&2
  exit 1
fi

echo "===== make (WM + nexwmctl + toàn bộ component desktop suite) ====="
make -C "$SRC_DIR" -j"$(nproc)" all

echo "===== Kiểm tra binary đã build thực sự có mặt trước khi install ====="
# Giống bug "exit 0 nhưng thiếu file" đã gặp ở desktop.sh (kernel image):
# `make` có thể trả về 0 dù 1 target lỗi ngầm tuỳ Makefile — kiểm tra thẳng
# file thay vì tin exit code.
MISSING=0
for bin in nexwm nexwmctl nex-panel nex-launcher nex-wallpaper nex-desktop nex-notify nex-settings; do
  if [ ! -x "$SRC_DIR/bin/$bin" ]; then
    echo "LỖI: thiếu $SRC_DIR/bin/$bin sau khi make." >&2
    MISSING=1
  fi
done
if [ "$MISSING" = "1" ]; then
  echo "LỖI NGHIÊM TRỌNG: build NexWM không đầy đủ, dừng lại." >&2
  exit 1
fi

echo "===== make install (PREFIX=$PREFIX) ====="
make -C "$SRC_DIR" install PREFIX="$PREFIX"

BINDIR="$PREFIX/bin"

echo "===== Ghi đè /usr/share/xsessions/nexwm.desktop (Type=XSession, absolute path) ====="
mkdir -p /usr/share/xsessions
cat <<EOF > /usr/share/xsessions/nexwm.desktop
[Desktop Entry]
Name=Nex Desktop Environment
Comment=Modern, lightweight X11 window manager and desktop suite
Exec=$BINDIR/start-nexde
TryExec=$BINDIR/nexwm
Type=XSession
DesktopNames=NexDE
EOF

echo "===== Ghi đè $BINDIR/start-nexde (absolute path cho mọi component) ====="
cat <<EOF > "$BINDIR/start-nexde"
#!/bin/sh
# start-nexde — Session launcher for Nex Desktop Environment
# Display manager chạy script này với PATH bị giới hạn (thường không có
# $BINDIR nếu khác /usr/bin), nên gọi mọi component bằng đường dẫn tuyệt đối.
BINDIR=$BINDIR

"\$BINDIR/nex-wallpaper" --restore 2>/dev/null || "\$BINDIR/nex-wallpaper" --color 0x1a1a2e &
"\$BINDIR/nex-desktop" &
"\$BINDIR/nex-panel" &
"\$BINDIR/nex-notify" "NexDE" "Welcome to Nex Desktop Environment" 3000 &
exec "\$BINDIR/nexwm"
EOF
chmod +x "$BINDIR/start-nexde"

echo "===== Kiểm tra session đã cài đúng vị trí ====="
if [ -x "$BINDIR/nexwm" ] && [ -f /usr/share/xsessions/nexwm.desktop ]; then
  echo "OK: NexWM đã cài tại $BINDIR/nexwm, session tại /usr/share/xsessions/nexwm.desktop"
else
  echo "LỖI: thiếu binary hoặc session file sau install." >&2
  exit 1
fi

echo "===== Dọn công cụ build (giảm dung lượng ISO) ====="
apt-get purge -y --autoremove build-essential 2>/dev/null || true
rm -rf "$SRC_DIR"

echo "===== build-nexwm.sh xong ====="
