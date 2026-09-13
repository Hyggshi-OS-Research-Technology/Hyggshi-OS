# Hyggshi Welcome

Hyggshi Welcome is the first-run onboarding wizard for Hyggshi OS. It is a native Qt application with Qt 6/Qt 5 fallback support.

## Setup flow

1. Welcome
2. Profile (display name + custom avatar)
3. Network status
4. Appearance
5. Accessibility
6. System check
7. Update check
8. Hyggshi OS features
9. Ready

There is deliberately **no Language & Keyboard step**: language and keyboard
layout are system-managed settings that follow one consistent path — the
Calamares installer applies locale + keyboard layout at install time
(`locale`/`keyboard` modules), and users change them afterwards in the
desktop's Region & Language / Input Sources settings. Welcome does not offer
its own selector and never overwrites the system's `input-sources`.

## Profile page

The Profile step sets the account's display name and avatar for the current
user (the login name is shown read-only and is not renamed by Welcome):

- The display name is pre-filled from the GECOS field and applied with
  `chfn` on finish (through `pkexec`; skipped silently without it).
- A custom avatar is any PNG/JPG/... image chosen from disk; without one, a
  deterministic colored "letter avatar" (initial of the display name) is
  used. The square-cropped image is written to `~/.face` / `~/.face.icon`
  and registered in `/var/lib/AccountsService/users/<name>` (`Icon=`,
  `SystemAccount=false`, merged without dropping other keys), which is what
  the login screen and user menus read.

## Persistence

User preferences are stored in:

```text
~/.config/hyggshi/welcome.conf
~/.config/hyggshi/theme.conf
```

The profile selection lives in `welcome.conf` under `profile/full_name` and
`profile/avatar`.

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
