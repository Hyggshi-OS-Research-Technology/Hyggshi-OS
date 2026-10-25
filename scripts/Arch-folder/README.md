# Hyggshi OS — Arch Edition

Arch-based live + installer ISO built with [archiso](https://wiki.archlinux.org/title/Archiso) featuring a customized KDE Plasma desktop, full UEFI Secure Boot signing chain, modern post-installer cleanup, and hardware diagnostics.

- **Desktop:** KDE Plasma 6 + SDDM (Tokyo Night aesthetic, Hyggshi Dark / Light themes)
- **Live session:** autologin as `liveuser` (password `liveuser`, passwordless sudo)
- **Installer:** [Calamares](https://calamares.io) — "Install Hyggshi OS" on the desktop, or `sudo calamares`
- **Welcome Center:** `hyggshi-welcome` — quick access to system info, updates, drivers, software, and docs
- **Hardware Diagnostics:** `hyggshi-hardware` — automated CPU microcode, GPU, audio, and network detection
- **Secure Boot:** Full Shim + MOK signing chain with verification and QEMU test harness

---

## Architecture & Layout

```
├── .github/workflows/
│   └── build.yml               # Multi-stage CI/CD: build -> sign -> verify -> artifacts
├── pkgs/                       # PKGBUILDs for Hyggshi OS components
│   ├── hyggshi-branding/       # Wallpapers, splash, color schemes, look-and-feel
│   ├── hyggshi-os-release/     # /etc/os-release and /etc/hyggshi-* metadata
│   ├── hyggshi-tools/          # Diagnostic and post-install binaries
│   └── hyggshi-welcome/        # Hyggshi Welcome Center
├── profile/
│   ├── airootfs/               # Overlay root filesystem for the live image
│   │   ├── etc/
│   │   │   ├── calamares/      # Calamares branding and installation modules
│   │   │   ├── fastfetch/      # Hyggshi fastfetch preset
│   │   │   └── skel/.config/   # KDE defaults (kdeglobals, ksplashrc, autostart)
│   │   └── usr/
│   │       ├── local/bin/      # hyggshi-hardware, hyggshi-welcome, hyggshi-post-install
│   │       └── share/          # Wallpapers, colors, plymouth, icons, plasma look-and-feel
│   ├── packages.x86_64         # Categorized package manifest (Core, Hardware, KDE, etc.)
│   ├── pacman.conf             # Pacman configuration with [hyggshi] repository
│   └── profiledef.sh           # Archiso profile definition
└── tools/
    ├── build-packages.sh       # Compiles pkgs/ PKGBUILDs and generates local repo database
    ├── publish-to-hrac.sh      # Deploys packages and db to Hyggshi-OS-Foundation/HRAC
    ├── gen-secureboot-keys.sh  # Generates RSA 2048-bit Secure Boot keypair
    ├── secureboot-iso.sh       # Signs kernel/GRUB, injects Shim + MOK, rebuilds ISO
    ├── verify-secureboot.sh    # Automated inspection & verification of the Secure Boot chain
    ├── inspect-iso.sh          # Inspects internal layout, partition table, and boot headers
    └── test-secureboot-qemu.sh # Launches ISO in QEMU with UEFI Secure Boot (OVMF)
```

---

## Building Locally

To build the ISO locally on an Arch Linux system:

```bash
# 1. Install prerequisites
sudo pacman -S archiso base-devel git grub dosfstools edk2-ovmf mtools libisoburn squashfs-tools sbsigntool openssl

# 2. Build Calamares (AUR) into a local repository
git clone https://github.com/archlinux/aur.git --branch calamares --single-branch /tmp/calamares
(cd /tmp/calamares && makepkg -s --noconfirm)
sudo mkdir -p /opt/localrepo
sudo cp /tmp/calamares/*.pkg.tar.zst /opt/localrepo/
sudo repo-add /opt/localrepo/hyggshi.db.tar.gz /opt/localrepo/*.pkg.tar.zst

# 3. Build the ISO
sudo mkarchiso -v -w work/ -o out/ profile/
```

---

## Hyggshi Package Repository (HRAC)

Community and official Hyggshi packages are managed in [Hyggshi-OS-Foundation/HRAC](https://github.com/Hyggshi-OS-Foundation/HRAC):

- To build all internal PKGBUILDs (`pkgs/*`) into `/opt/localrepo`:
  ```bash
  ./tools/build-packages.sh
  ```
- To publish packages and updated database to HRAC:
  ```bash
  ./tools/publish-to-hrac.sh /opt/localrepo
  ```
- When published, the remote repository line in `profile/pacman.conf` can be activated:
  ```ini
  Server = https://raw.githubusercontent.com/Hyggshi-OS-Foundation/HRAC/main/$arch
  ```

---

## Secure Boot Pipeline

1. **Generate Keys (or use existing repository secrets):**
   ```bash
   tools/gen-secureboot-keys.sh keys/
   ```

2. **Sign the Raw ISO:**
   ```bash
   tools/secureboot-iso.sh out/hyggshi-os-arch-*.iso out/Hyggshi-OS-Arch-KDE-x86_64.iso keys/sb.key keys/sb.crt
   ```

3. **Verify the Signed ISO:**
   ```bash
   tools/verify-secureboot.sh out/Hyggshi-OS-Arch-KDE-x86_64.iso keys/sb.crt
   ```

4. **Test in QEMU with UEFI Secure Boot:**
   ```bash
   tools/test-secureboot-qemu.sh --secure-boot out/Hyggshi-OS-Arch-KDE-x86_64.iso
   ```

---

## Look & Feel Customization

- **Themes:** `Hyggshi Dark` (`HyggshiDark.colors`) & `Hyggshi Light` (`HyggshiLight.colors`) in `/usr/share/color-schemes/`
- **Panel & Splash:** `/usr/share/plasma/look-and-feel/org.hyggshi.desktop/`
- **Boot Splash (Plymouth):** `/usr/share/plymouth/themes/hyggshi/`
- **SDDM Background:** `/usr/share/sddm/themes/breeze/theme.conf.user`
- **Wallpaper:** `/usr/share/wallpapers/Hyggshi`
