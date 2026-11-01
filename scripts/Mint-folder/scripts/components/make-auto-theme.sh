#!/bin/bash
# make-auto-theme.sh — sinh project "hyggshi-theme": bản thay thế nhẹ cho
# legacy Hyggshi theme daemon.
# Thay vì 1 daemon chạy nền liên tục link libxfconf, đây chỉ là 1 SCRIPT
# BASH được systemd TIMER gọi định kỳ (mặc định mỗi 5 phút) rồi thoát —
# không cần libxfconf-0-dev/glib2.0-dev để build (không cần build gì cả),
# RAM lúc rảnh gần như bằng 0 vì không có tiến trình nào chạy nền.
#
# Kiến trúc:
#   - hyggshi-auto-theme (bash)  -> cài vào /usr/local/bin
#   - hyggshi-auto-theme.service -> cài vào /etc/systemd/system (system-wide,
#     KHÔNG PHẢI --user, vì cần chạy được kể cả trước khi user đăng nhập —
#     xem ghi chú "sudo -u" bên trong script để hiểu vì sao chạy bằng root
#     vẫn áp được wallpaper cho đúng phiên đồ hoạ của user)
#   - hyggshi-auto-theme.timer   -> cài vào /etc/systemd/system, OnBootSec=1min
#     + OnUnitActiveSec=5min
#   - theme.conf                 -> config mặc định, cài vào /etc/hyggshi/
#     (user có thể override riêng qua ~/.config/hyggshi/theme.conf)
#
# Cách dùng:
#   ./scripts/components/make-auto-theme.sh     # chỉ sinh source vào packages/hyggshi/hyggshi-theme/
#
# Việc CÀI THẬT vào hệ thống (copy file + systemctl enable) do
# packages/hyggshi/auto-theme.sh đảm nhiệm, chạy trong chroot lúc build ISO
# (xem workflow) — script này chỉ ghi ra source, không cần root.
set -e
[ "$DEBUG_MODE" = "true" ] && set -x

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
APP_DIR="$REPO_ROOT/packages/hyggshi/hyggshi-theme"

echo "===== Tạo cây thư mục project hyggshi-theme tại: $APP_DIR ====="
mkdir -p "$APP_DIR"

# ---------------------------------------------------------------------------
# hyggshi-auto-theme — script chính, chạy 1 lần mỗi lần systemd timer bắn.
# ---------------------------------------------------------------------------
cat > "$APP_DIR/hyggshi-auto-theme" <<'SCRIPT'
#!/bin/bash
# hyggshi-auto-theme — thay thế legacy Hyggshi theme daemon bằng
# 1 script bash chạy ĐỊNH KỲ qua systemd timer (không chạy nền liên tục,
# gần như 0 RAM lúc rảnh). Mỗi lần chạy:
#   1. Đọc config (system-wide /etc/hyggshi/theme.conf, user override
#      ~/.config/hyggshi/theme.conf nếu có) để biết MODE + khung giờ.
#   2. Tính theme muốn áp (light/dark).
#   3. Nếu GIỐNG lần áp gần nhất thì thoát ngay — KHÔNG gọi lại
#      hyggshi-set-wallpaper.sh, vì script đó restart hẳn xfdesktop
#      (killall + relaunch), gọi mỗi 5 phút dù không đổi gì sẽ làm màn
#      hình giật/nháy liên tục.
#   4. Nếu khác, tự dò phiên đồ hoạ (X11/Wayland) đang active trên máy qua
#      loginctl, rồi sudo -u <user> kèm đúng DISPLAY/DBUS_SESSION_BUS_ADDRESS
#      để gọi hyggshi-set-wallpaper.sh — vì service này chạy bằng ROOT
#      (systemd SYSTEM service, không phải --user), xfconf-query cần đúng
#      D-Bus session bus của user thì mới ghi được, gọi thẳng bằng root sẽ
#      fail (không lỗi ồn ào, chỉ lặng lẽ không đổi gì).
set -u

SYS_CONF="/etc/hyggshi/theme.conf"
STATE_DIR="/var/lib/hyggshi-auto-theme"
WALLPAPER_SCRIPT="/usr/local/bin/hyggshi-set-wallpaper.sh"
LIGHT_WALL="/usr/share/backgrounds/hyggshi/car-light.png"
DARK_WALL="/usr/share/backgrounds/hyggshi/car-Dark.png"

log() { echo "[hyggshi-auto-theme] $*"; }

# Chuyển "HH:MM" -> tổng số phút trong ngày, để so sánh bằng số nguyên thay
# vì so chuỗi giờ (tránh lỗi vặt kiểu "08:00" bị bash coi là octal nếu lỡ
# dùng $((...)) trực tiếp trên chuỗi có số 0 đứng đầu).
to_minutes() {
  local hhmm="$1" h="${1%%:*}" m="${1##*:}"
  h="${h#0}"; m="${m#0}"
  [ -z "$h" ] && h=0
  [ -z "$m" ] && m=0
  echo $(( 10#$h * 60 + 10#$m ))
}

# Tính theme muốn áp (light/dark) dựa theo MODE + LIGHT_START/DARK_START đã
# nạp sẵn ra biến môi trường trước khi gọi hàm này.
decide_theme() {
  case "${MODE:-auto}" in
    light) echo "light" ;;
    dark)  echo "dark" ;;
    *)
      local now l d
      now=$(to_minutes "$(date +%H:%M)")
      l=$(to_minutes "${LIGHT_START:-06:00}")
      d=$(to_minutes "${DARK_START:-18:00}")
      if [ "$l" -le "$d" ]; then
        if [ "$now" -ge "$l" ] && [ "$now" -lt "$d" ]; then echo "light"; else echo "dark"; fi
      else
        # Trường hợp hiếm: DARK_START nhỏ hơn LIGHT_START (vd DARK_START=02:00)
        if [ "$now" -ge "$d" ] && [ "$now" -lt "$l" ]; then echo "dark"; else echo "light"; fi
      fi
      ;;
  esac
}

mkdir -p "$STATE_DIR"

# Không có phiên đồ hoạ nào -> loginctl trả rỗng, thoát êm (vd chạy trên
# server/headless, hoặc chưa ai đăng nhập lúc OnBootSec=1min kích hoạt).
SESSION_IDS=$(loginctl list-sessions --no-legend 2>/dev/null | awk '{print $1}')
if [ -z "$SESSION_IDS" ]; then
  log "khong co phien dang nhap nao dang active, bo qua lan nay"
  exit 0
fi

while IFS= read -r SID; do
  [ -z "$SID" ] && continue

  U=$(loginctl show-session "$SID" -p Name --value 2>/dev/null)
  [ -z "$U" ] && continue
  UID_N=$(id -u "$U" 2>/dev/null) || continue
  BUS="/run/user/$UID_N/bus"
  # Không có socket D-Bus user -> không phải phiên đồ hoạ thật (vd phiên
  # SSH/tty thuần), bỏ qua session này.
  [ -S "$BUS" ] || continue

  DISP=$(loginctl show-session "$SID" -p Display --value 2>/dev/null)
  [ -z "$DISP" ] && DISP=":0"

  # ---- Nạp config: mặc định -> system-wide -> user override, theo đúng
  #      thứ tự ưu tiên tăng dần (file sau ghi đè file trước). ----
  MODE="auto"; LIGHT_START="06:00"; DARK_START="18:00"
  [ -f "$SYS_CONF" ] && source "$SYS_CONF"
  USER_HOME=$(getent passwd "$U" | cut -d: -f6)
  USER_CONF="$USER_HOME/.config/hyggshi/theme.conf"
  [ -n "$USER_HOME" ] && [ -f "$USER_CONF" ] && source "$USER_CONF"

  WANT=$(decide_theme)

  STATE_FILE="$STATE_DIR/last-applied-$U"
  LAST=""
  [ -f "$STATE_FILE" ] && LAST=$(cat "$STATE_FILE" 2>/dev/null)
  if [ "$LAST" = "$WANT" ]; then
    continue
  fi

  WALL="$LIGHT_WALL"
  [ "$WANT" = "dark" ] && WALL="$DARK_WALL"
  if [ ! -f "$WALL" ]; then
    log "khong tim thay $WALL cho user $U, bo qua"
    continue
  fi

  if [ ! -x "$WALLPAPER_SCRIPT" ]; then
    log "khong tim thay $WALLPAPER_SCRIPT, bo qua"
    continue
  fi

  log "user=$U mode=$MODE -> ap theme=$WANT ($WALL)"
  sudo -u "$U" DISPLAY="$DISP" DBUS_SESSION_BUS_ADDRESS="unix:path=$BUS" \
    "$WALLPAPER_SCRIPT" "$WALL" >/dev/null 2>&1

  echo "$WANT" > "$STATE_FILE"
done <<< "$SESSION_IDS"
SCRIPT
chmod +x "$APP_DIR/hyggshi-auto-theme"

# ---------------------------------------------------------------------------
# hyggshi-auto-theme.service — systemd SYSTEM unit (không phải --user), vì
# timer cần chạy được ngay cả khi kích hoạt trước lúc user đăng nhập xong
# (OnBootSec=1min) — script bên trong tự dò + sudo -u vào đúng phiên user.
# ---------------------------------------------------------------------------
cat > "$APP_DIR/hyggshi-auto-theme.service" <<'SVCEOF'
[Unit]
Description=Hyggshi auto theme — doi wallpaper Sang/Toi theo gio (chay 1 lan roi thoat)
# Can /run/user/<uid>/bus cua phien dang nhap da san sang.
After=systemd-logind.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/hyggshi-auto-theme
SVCEOF

# ---------------------------------------------------------------------------
# hyggshi-auto-theme.timer — bắn mỗi 5 phút, Persistent=true để chạy bù
# ngay lúc boot lại nếu máy đã tắt đúng lúc lẽ ra phải chạy.
# ---------------------------------------------------------------------------
cat > "$APP_DIR/hyggshi-auto-theme.timer" <<'TIMEREOF'
[Unit]
Description=Chay hyggshi-auto-theme dinh ky (moi 5 phut)

[Timer]
OnBootSec=1min
OnUnitActiveSec=5min
Persistent=true

[Install]
WantedBy=timers.target
TIMEREOF

# ---------------------------------------------------------------------------
# theme.conf — config mặc định, cài vào /etc/hyggshi/theme.conf. User có
# thể override riêng qua ~/.config/hyggshi/theme.conf (không cần sudo).
# ---------------------------------------------------------------------------
cat > "$APP_DIR/theme.conf" <<'CONFEOF'
# Hyggshi auto theme — config
# Dat o /etc/hyggshi/theme.conf (mac dinh toan he thong) hoac
# ~/.config/hyggshi/theme.conf (rieng tung user, ghi de len /etc).
#
# MODE: auto | light | dark
#   auto  -> tu doi theo khung gio LIGHT_START / DARK_START ben duoi
#   light -> luon dung wallpaper Sang
#   dark  -> luon dung wallpaper Toi
MODE=auto

# Gio bat dau theme Sang / Toi, dinh dang 24h "HH:MM"
LIGHT_START=06:00
DARK_START=18:00
CONFEOF

cat > "$APP_DIR/README.md" <<'MDEOF'
# hyggshi-theme (bash + systemd timer)

Bản theme tự động nhẹ của Hyggshi OS, không cần daemon C++. Thay vì 1 daemon chạy nền liên
tục, đây chỉ là 1 script bash được **systemd timer** gọi mỗi 5 phút rồi
thoát — không cần build gì cả (không cần `libxfconf-0-dev`/`glib2.0-dev`),
RAM lúc rảnh gần như bằng 0.

## Cài tay (để test, không qua ISO build)

```bash
sudo cp hyggshi-auto-theme /usr/local/bin/
sudo chmod +x /usr/local/bin/hyggshi-auto-theme
sudo cp hyggshi-auto-theme.service hyggshi-auto-theme.timer /etc/systemd/system/
sudo mkdir -p /etc/hyggshi
sudo cp theme.conf /etc/hyggshi/theme.conf

sudo systemctl daemon-reload
sudo systemctl enable --now hyggshi-auto-theme.timer
```

Kiểm tra:

```bash
systemctl status hyggshi-auto-theme.timer
sudo systemctl start hyggshi-auto-theme.service   # chạy thử ngay, không đợi timer
journalctl -u hyggshi-auto-theme.service -f
```

## Cấu hình

Sửa `/etc/hyggshi/theme.conf` (toàn hệ thống) hoặc tạo riêng
`~/.config/hyggshi/theme.conf` (ghi đè cho từng user, không cần sudo):

```
MODE=auto
LIGHT_START=06:00
DARK_START=18:00
```

`MODE=light`/`dark` để ép cứng 1 theme, bỏ qua khung giờ.

## Vì sao service chạy bằng root nhưng vẫn đổi được wallpaper?

`hyggshi-auto-theme.service` là **system** service (không phải
`--user`), nên tự nó không có `DISPLAY`/`DBUS_SESSION_BUS_ADDRESS` của
phiên đồ hoạ — gọi thẳng `xfconf-query` sẽ fail âm thầm. Script
`hyggshi-auto-theme` tự dò phiên đang active qua `loginctl`, rồi
`sudo -u <user>` kèm đúng 2 biến môi trường đó để gọi lại
`/usr/local/bin/hyggshi-set-wallpaper.sh` (cài bởi `scripts/target/branding.sh`)
đúng như cách `hyggshi-welcome` đang làm.

Script cũng lưu theme đã áp gần nhất vào
`/var/lib/hyggshi-auto-theme/last-applied-<user>` để **không** gọi lại
`hyggshi-set-wallpaper.sh` (restart xfdesktop) mỗi 5 phút nếu theme chưa
đổi — tránh giật/nháy màn hình định kỳ.
MDEOF

echo "===== Đã sinh xong source code tại $APP_DIR ====="
