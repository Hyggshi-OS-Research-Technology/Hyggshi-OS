#!/bin/bash
# Hyggshi OS — make Cinnamon Tela icon theme survive Calamares installation.
# Run inside chroot during image build.
set -e

install -d /usr/local/bin /etc/xdg/autostart

cat > /usr/local/bin/hyggshi-apply-cinnamon-defaults <<'SCRIPT'
#!/bin/bash
# Apply Hyggshi's Cinnamon defaults once for each newly-created user.
# Calamares may create a user's dconf database from the live session; that
# user-level database can override /etc/dconf/db/local.  Applying the default
# once after the first graphical login makes Tela persistent on the installed
# system without forcing it again after the user changes themes later.
set -u

[ "${XDG_CURRENT_DESKTOP:-}" = "X-Cinnamon" ] || {
    case "${XDG_CURRENT_DESKTOP:-}" in
      *Cinnamon*) : ;;
      *) exit 0 ;;
    esac
}

MARKER="$HOME/.config/hyggshi/.cinnamon-defaults-applied"
[ -e "$MARKER" ] && exit 0

mkdir -p "$(dirname "$MARKER")"

# Do not fail the login if a particular key is unavailable during session
# startup; Cinnamon will load the values on its next settings refresh.
gsettings set org.cinnamon.desktop.interface icon-theme 'Tela' 2>/dev/null || true
gsettings set org.cinnamon.desktop.interface gtk-theme 'Orchis' 2>/dev/null || true
gsettings set org.cinnamon.desktop.interface cursor-theme 'Bibata-Modern-Classic' 2>/dev/null || true
gsettings set org.cinnamon.theme name 'Orchis' 2>/dev/null || true
gsettings set org.cinnamon.desktop.wm.preferences theme 'Orchis' 2>/dev/null || true

touch "$MARKER"
exit 0
SCRIPT
chmod 0755 /usr/local/bin/hyggshi-apply-cinnamon-defaults

cat > /etc/xdg/autostart/hyggshi-cinnamon-defaults.desktop <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Hyggshi Cinnamon Defaults
Comment=Apply Hyggshi OS Cinnamon icon and theme defaults after installation
Exec=/usr/local/bin/hyggshi-apply-cinnamon-defaults
OnlyShowIn=Cinnamon;
X-GNOME-Autostart-enabled=true
NoDisplay=true
DESKTOP
chmod 0644 /etc/xdg/autostart/hyggshi-cinnamon-defaults.desktop

# Also place the helper in /etc/skel so users created by Calamares receive it
# even if the installer copies/overrides /etc/xdg/autostart entries.
install -d /etc/skel/.config/autostart
cp /etc/xdg/autostart/hyggshi-cinnamon-defaults.desktop /etc/skel/.config/autostart/

# Keep the system dconf default as a second layer of protection.
install -d /etc/dconf/profile /etc/dconf/db/local.d
cat > /etc/dconf/profile/user <<'PROFILE'
user-db:user
system-db:local
PROFILE
cat > /etc/dconf/db/local.d/01-hyggshi-cinnamon-theme <<'DCONF'
[org/cinnamon/desktop/interface]
icon-theme='Tela'
gtk-theme='Orchis'
cursor-theme='Bibata-Modern-Classic'

[org/cinnamon/desktop/wm/preferences]
theme='Orchis'

[org/cinnamon/theme]
name='Orchis'
DCONF
command -v dconf >/dev/null 2>&1 && dconf update || true

echo "OK: Cinnamon Tela persistence guard installed."
