# Hyggshi OS

A custom Debian-based Linux distribution built with a `debootstrap` +
`mksquashfs` + `xorriso` pipeline (no `live-build`).

## Build Requirements
- Linux host (or the supplied `Dockerfile` for a containerized build)
- root / sudo
- ~5GB free disk space

## Build

```bash
sudo bash scripts/local-build.sh
```

Configuration is passed via environment variables (see the defaults at the
top of `scripts/local-build.sh`), e.g.:

`HYGGSHI_VERSION_ID` is the **Hyggshi OS version riêng**, independent of the
base distro version. In GitHub Actions it is editable directly through the
`hyggshi_version` input; locally it defaults to `1.0`.


```bash
BASE_DISTRO=debian DEBIAN_VERSION=trixie DE=xfce \
sudo -E bash scripts/local-build.sh
```

GitHub Actions builds the same pipeline (`scripts/build.sh` +
`scripts/desktop.sh` + `scripts/iso.sh`) for `debian`, `ubuntu`, and
`linuxmint` base distros — see `.github/workflows`.

## Stack
- Base: Debian Trixie (13) by default — Ubuntu Noble and Linux Mint 22 also supported via `BASE_DISTRO`
- Desktop: XFCE (default; `kde`, `lxqt`, `gnome`, `mate`, `cinnamon` also selectable via `DE`)
- Display/Login Manager: LightDM (autologin on the live session only — see "Autologin" below)
- Installer: Calamares
- Architecture: amd64

## Autologin: Live vs Installed
The live ISO session autologs into LightDM/XFCE so the user lands on the
desktop immediately. Once Calamares finishes installing to disk, a
`shellprocess@removeautologin` job strips the live-session autologin config
from the installed system, so the real machine boots to a LightDM login
prompt (username + password).

## Links
- Website: https://hyggshi-os-website.pages.dev

## GRUB background branding

Để áp dụng nền GRUB riêng, đặt hai file branding tại đúng đường dẫn:

- `iso-config/branding/desktop-grub.png` — file được GRUB render làm background.
- `iso-config/branding/desktop-grub.svg` — bản vector được đóng gói kèm làm source branding.

`./scripts/iso.sh` sẽ tự copy hai file vào ISO và dùng `desktop-grub.png` làm nền GRUB. Nếu thiếu PNG, ISO vẫn build và GRUB dùng nền mặc định.
