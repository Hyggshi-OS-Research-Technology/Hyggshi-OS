#!/bin/bash
# auto-theme.sh — cài "hyggshi-theme" (bash + systemd timer, xem
# scripts/components/make-auto-theme.sh) TỪ SOURCE đã được workflow copy vào $SRC_DIR.
# Chạy BÊN TRONG chroot (giống welcome.sh) vì systemd unit
# + script cần nằm trong rootfs của ISO, không phải máy runner CI.
#
# KHÔNG CẦN BUILD (không cmake, không compile) — khác hẳn welcome.sh/
# auto-theme.sh, đây chỉ là copy file + enable timer, nên script này
# ngắn hơn nhiều và không cần cài/purge công cụ build gì cả.
set -e
[ "$DEBUG_MODE" = "true" ] && set -x
: "${SRC_DIR:=/tmp/hyggshi-theme-src}"

if [ ! -f "$SRC_DIR/hyggshi-auto-theme" ]; then
  echo "LỖI: không thấy $SRC_DIR/hyggshi-auto-theme — auto-theme.sh cần" >&2
  echo "source đã được sinh bằng scripts/components/make-auto-theme.sh và copy vào" >&2
  echo "chroot trước." >&2
  exit 1
fi

echo "===== Cài hyggshi-auto-theme vào /usr/local/bin ====="
install -m 755 "$SRC_DIR/hyggshi-auto-theme" /usr/local/bin/hyggshi-auto-theme

echo "===== Cài systemd unit (service + timer) vào /etc/systemd/system ====="
install -m 644 "$SRC_DIR/hyggshi-auto-theme.service" /etc/systemd/system/hyggshi-auto-theme.service
install -m 644 "$SRC_DIR/hyggshi-auto-theme.timer" /etc/systemd/system/hyggshi-auto-theme.timer

echo "===== Cài config mặc định vào /etc/hyggshi/theme.conf ====="
# Không ghi đè nếu ISO build lại trên chroot đã có sẵn config cũ (idempotent
# giữa các lần build lại cùng chroot) — chỉ tạo mới khi chưa tồn tại.
mkdir -p /etc/hyggshi
if [ ! -f /etc/hyggshi/theme.conf ]; then
  install -m 644 "$SRC_DIR/theme.conf" /etc/hyggshi/theme.conf
else
  echo "/etc/hyggshi/theme.conf đã tồn tại — giữ nguyên, không ghi đè."
fi

echo "===== Enable hyggshi-auto-theme.timer (tự chạy từ lúc boot) ====="
# systemctl enable trong chroot (chưa boot, không có PID 1 thật chạy) chỉ
# tạo symlink, không thật sự start — daemon-reload/start thật sẽ xảy ra ở
# lần boot đầu tiên của ISO/máy cài xong. Dùng --now vẫn an toàn: nó bỏ qua
# phần "start ngay" khi phát hiện đang chạy trong chroot (không có systemd
# PID 1), chỉ phần "enable" (tạo symlink) thực sự có tác dụng ở đây.
systemctl enable hyggshi-auto-theme.timer 2>&1 || {
  echo "⚠️  systemctl enable thất bại qua cách thường — tự tạo symlink thủ công." >&2
  mkdir -p /etc/systemd/system/timers.target.wants
  ln -sf /etc/systemd/system/hyggshi-auto-theme.timer \
    /etc/systemd/system/timers.target.wants/hyggshi-auto-theme.timer
}

echo "===== Xong: hyggshi-auto-theme đã cài + timer enable (chạy mỗi 5 phút từ lúc boot) ====="
