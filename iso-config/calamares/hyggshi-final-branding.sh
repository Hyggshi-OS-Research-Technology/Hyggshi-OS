#!/bin/sh
set -eu

# This runs INSIDE the freshly installed target, after Calamares has created
# the real user. It is the final authority for Hyggshi branding so packages
# or Calamares scripts cannot put the Debian default launcher/icon back.

ICON_SRC="/usr/share/pixmaps/hyggshi-installer.png"
WELCOME_ICON="/usr/share/icons/hicolor/256x256/apps/hyggshi-welcome.png"

# Refresh hicolor cache after installation.
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -f -t /usr/share/icons/hicolor >/dev/null 2>&1 || true
fi

# Re-create the Hyggshi Welcome desktop entry with an absolute icon path.
# Absolute path avoids icon-theme lookup falling back to a distro icon.
if command -v command >/dev/null 2>&1 || true; then :; fi
mkdir -p /usr/share/applications
cat > /usr/share/applications/hyggshi-welcome.desktop <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Hyggshi Welcome
Name[vi]=Chào mừng Hyggshi
Comment=Cấu hình nhanh Hyggshi OS lần đầu sử dụng
Exec=hyggshi-welcome
Icon=/usr/share/icons/hicolor/256x256/apps/hyggshi-welcome.png
Terminal=false
Categories=System;Settings;
DESKTOP
chmod 0644 /usr/share/applications/hyggshi-welcome.desktop

# Ensure the installer launcher, when intentionally retained, always points
# to the Hyggshi icon rather than Debian's installer icon.
for d in /usr/share/applications /usr/local/share/applications /etc/xdg/applications; do
  [ -d "$d" ] || continue
  for f in "$d"/*.desktop; do
    [ -f "$f" ] || continue
    if grep -Eiq '^Exec=.*(pkexec[[:space:]]+)?calamares([[:space:]]|$)' "$f" || \
       grep -Eiq '^Name(\[[^]]+\])?=.*(Install Debian|Debian Installer)' "$f"; then
      sed -i -E 's/^Name(\[[^]]+\])?=.*/Name=Install Hyggshi OS/' "$f"
      if grep -q '^Icon=' "$f"; then
        sed -i 's#^Icon=.*#Icon=/usr/share/pixmaps/hyggshi-installer.png#' "$f"
      else
        printf '\nIcon=/usr/share/pixmaps/hyggshi-installer.png\n' >> "$f"
      fi
    fi
  done
done

# Re-apply the same launcher to the actual Calamares-created user.
for home in /home/*; do
  [ -d "$home" ] || continue
  user=$(basename "$home")
  # Do not create a shortcut for system users.
  uid=$(id -u "$user" 2>/dev/null || echo 0)
  [ "$uid" -ge 1000 ] || continue
  mkdir -p "$home/Desktop"
  cat > "$home/Desktop/install-hyggshi-os.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Install Hyggshi OS
Comment=Cài đặt Hyggshi OS
Exec=pkexec calamares
Icon=/usr/share/pixmaps/hyggshi-installer.png
Terminal=false
Categories=System;Settings;
DESKTOP
  chmod 0755 "$home/Desktop/install-hyggshi-os.desktop"
  chown "$user:$user" "$home/Desktop/install-hyggshi-os.desktop" 2>/dev/null || true
  # Cinnamon/GNOME may require trusted metadata for a copied desktop file.
  if command -v gio >/dev/null 2>&1; then
    su - "$user" -c "gio set '$home/Desktop/install-hyggshi-os.desktop' metadata::trusted true" >/dev/null 2>&1 || true
  fi
done

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database /usr/share/applications >/dev/null 2>&1 || true
fi

exit 0
