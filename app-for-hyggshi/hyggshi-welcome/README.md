# Hyggshi Welcome

Hyggshi Welcome is the first-run onboarding wizard for Hyggshi OS. It is a native Qt application with Qt 6/Qt 5 fallback support.

## Setup flow

1. Welcome
2. Language and keyboard
3. Network status
4. Appearance
5. Accessibility
6. System check
7. Update check
8. Hyggshi OS features
9. Ready

## Persistence

User preferences are stored in:

```text
~/.config/hyggshi/welcome.conf
~/.config/hyggshi/theme.conf
```

The first-run marker is:

```text
~/.config/hyggshi/welcome-shown
```

Set `HYGGSHI_WELCOME_FORCE=1` to run the wizard again without deleting the marker.

## Build

Requirements:

- CMake 3.16+
- C++17 compiler
- Qt 6 Widgets, or Qt 5 Widgets

Build:

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j$(nproc)
sudo cmake --install build
```

The update page only checks package availability and never installs packages or asks for administrator privileges. Network setup is delegated to the desktop's existing network tools.


## Tự động mở cho user mới

Hyggshi Welcome được cài vào `/etc/xdg/autostart/hyggshi-welcome.desktop` và đồng thời vào `/etc/skel/.config/autostart/`. Vì vậy user live và user mới tạo sau khi cài OS đều tự mở Welcome ở lần đăng nhập đầu tiên.

Ứng dụng lưu marker tại `~/.config/hyggshi/welcome-shown` sau khi người dùng chọn hoàn tất thiết lập. Nếu marker đã tồn tại, chương trình tự thoát và không hiện lại. Có thể test lại bằng:

```bash
HYGGSHI_WELCOME_FORCE=1 hyggshi-welcome
```
