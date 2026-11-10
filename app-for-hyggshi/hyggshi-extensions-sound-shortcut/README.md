# hyggshi-extensions-sound-shortcut

**C++ daemon for global audio hotkeys on Hyggshi OS / XFCE.**

Captures `Fn+Volume Up/Down/Mute` system-wide via `XGrabKey`, controls audio levels, and displays a modern dark-themed OSD popup similar to macOS/Windows.

---

## Features

| Feature | Description |
|---------|-------------|
| 🎹 Global Hotkey | Captures `XF86AudioRaiseVolume`, `XF86AudioLowerVolume`, `XF86AudioMute` via `XGrabKey` |
| 🔊 Multi-backend | Auto-detects PipeWire (`wpctl`) → PulseAudio (`pactl`) → ALSA (`amixer`) |
| 🪟 OSD Popup | Qt dark-themed popup, fade-in/out animations, auto-hides after 1.5 seconds |
| 🔒 Single-instance | Enforces single instance via `flock` |
| 🚀 XFCE Autostart | Installs to `/etc/xdg/autostart/` to start with user sessions |

## Dependencies

```text
libqt6-base-dev (or qtbase5-dev)
libx11-dev
libxtst-dev    <-- XGrabKey
```

Installation on Debian/Ubuntu:
```bash
# For Qt6:
sudo apt-get install -y qt6-base-dev libx11-dev libxtst-dev cmake gcc g++

# Or for Qt5:
sudo apt-get install -y qtbase5-dev libx11-dev libxtst-dev cmake gcc g++
```

## Build

```bash
cd app-for-hyggshi/hyggshi-extensions-sound-shortcut
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j$(nproc)
sudo make install   # Installs to /usr/local/bin/ and /etc/xdg/autostart/
```

## Testing

```bash
./build/hyggshi-sound-shortcut
# Press Fn+Vol+ / Fn+Vol- on your keyboard -> OSD popup appears at bottom-right
```

## Source Structure

```text
src/
  main.cpp           - Entry point, single-instance guard, signal connections
  KeyGrabber.h/.cpp  - XGrabKey global hotkey listener
  AudioController.h/.cpp - PipeWire/PulseAudio/ALSA backend controller
  OsdWindow.h/.cpp   - Qt OSD popup window with animation
resources/
  hyggshi-sound-shortcut.qrc
  icons/{volume-high,volume-low,volume-muted}.png
packaging/
  *-autostart.desktop -> /etc/xdg/autostart/
  *-app.desktop       -> /usr/share/applications/
```

## Integration into Hyggshi OS ISO

The binary is pre-built by CI and staged into `/tmp/hyggshi-sound-shortcut` before `desktop.sh` runs inside the chroot. `desktop.sh` installs the binary and configures autostart.

See the `===== Hyggshi Sound Shortcut =====` section in `scripts/desktop.sh`.
