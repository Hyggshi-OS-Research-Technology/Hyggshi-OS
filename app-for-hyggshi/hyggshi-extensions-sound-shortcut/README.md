# hyggshi-extensions-sound-shortcut

**Daemon C++ xử lý phím tắt âm thanh cho Hyggshi OS / XFCE.**

Bắt phím `Fn+Volume Up/Down/Mute` toàn cục (XGrabKey), điều khiển âm lượng, và hiện OSD popup dark-theme giống macOS/Windows.

---

## Tính năng

| Tính năng | Mô tả |
|-----------|-------|
| 🎹 Global hotkey | Bắt `XF86AudioRaiseVolume`, `XF86AudioLowerVolume`, `XF86AudioMute` qua XGrabKey |
| 🔊 Multi-backend | Auto-detect PipeWire (`wpctl`) → PulseAudio (`pactl`) → ALSA (`amixer`) |
| 🪟 OSD Popup | Qt popup dark-theme, fade-in/out, tự ẩn sau 1.5 giây |
| 🔒 Single-instance | `flock` lock — không mở 2 daemon cùng lúc |
| 🚀 XFCE autostart | Cài vào `/etc/xdg/autostart/` — tự chạy cùng session |

## Dependencies

```
libqt6-dev (hoặc libqt5-dev)
libx11-dev
libxtst-dev    ← XGrabKey
```

Cài trên Debian/Ubuntu:
```bash
sudo apt-get install -y qtbase5-dev libx11-dev libxtst-dev cmake gcc g++
# Hoặc cho Qt6:
sudo apt-get install -y qt6-base-dev libx11-dev libxtst-dev cmake gcc g++
```

## Build

```bash
cd app-for-hyggshi/hyggshi-extensions-sound-shortcut
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j$(nproc)
sudo make install   # cài vào /usr/local/bin/ + /etc/xdg/autostart/
```

## Chạy thử

```bash
./build/hyggshi-sound-shortcut
# Bấm Fn+Vol+ trên bàn phím → OSD popup hiện ở góc phải dưới màn hình
```

## Cấu trúc source

```
src/
  main.cpp           — entry point, single-instance guard, kết nối signals
  KeyGrabber.h/.cpp  — XGrabKey global hotkey listener
  AudioController.h/.cpp — PipeWire/PulseAudio/ALSA backend
  OsdWindow.h/.cpp   — Qt OSD popup với animation
resources/
  hyggshi-sound-shortcut.qrc
  icons/{volume-high,volume-low,volume-muted}.png
packaging/
  *-autostart.desktop → /etc/xdg/autostart/
  *-app.desktop       → /usr/share/applications/
```

## Tích hợp vào Hyggshi OS ISO

Binary được pre-build bởi CI và stage vào `/tmp/hyggshi-sound-shortcut` trước khi
`desktop.sh` chạy trong chroot. `desktop.sh` copy binary + ghi autostart.

Xem phần `===== Hyggshi Sound Shortcut =====` trong `scripts/desktop.sh`.
