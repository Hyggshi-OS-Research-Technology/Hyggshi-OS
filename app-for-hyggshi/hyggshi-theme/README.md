# hyggshi-theme (bash + systemd timer)

Bản thay thế nhẹ cho `hyggshi-theme-daemon` (C++/libxfconf, xem
`app-for-hyggshi/hyggshi-theme-daemon/`). Thay vì 1 daemon chạy nền liên
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
`/usr/local/bin/hyggshi-set-wallpaper.sh` (cài bởi `scripts/branding.sh`)
đúng như cách `hyggshi-welcome` đang làm.

Script cũng lưu theme đã áp gần nhất vào
`/var/lib/hyggshi-auto-theme/last-applied-<user>` để **không** gọi lại
`hyggshi-set-wallpaper.sh` (restart xfdesktop) mỗi 5 phút nếu theme chưa
đổi — tránh giật/nháy màn hình định kỳ.
