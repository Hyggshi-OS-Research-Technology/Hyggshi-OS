#!/bin/bash
# desktop-fluxbox.sh — configure Hyggshi OS Flex Edition (Slax-style)
# Stack: Fluxbox (WM) + Tint2 (Taskbar) + PCManFM (File Manager) + Rofi (Launcher) + Picom (Compositor) + xterm
# Runs as root inside chroot
set -e
[ "${DEBUG_MODE:-}" = "true" ] && set -x

say() { printf '===== %s =====\n' "$*"; }

say "Cấu hình Hyggshi OS Flex Edition (Slax-style)"

# 1. Tạo thư mục cấu hình hệ thống
mkdir -p /etc/X11/fluxbox
mkdir -p /usr/share/fluxbox/styles
mkdir -p /etc/xdg/tint2
mkdir -p /etc/rofi
mkdir -p /etc/xdg/picom
mkdir -p /etc/xdg/pcmanfm/default
mkdir -p /usr/share/backgrounds/hyggshi

# 2. Copy cấu hình từ staged source (/tmp/hcl-filecopy-src) nếu có
FLUX_SRC="/tmp/hcl-filecopy-src/iso-config/fluxbox"
if [ -d "$FLUX_SRC" ]; then
  [ -f "$FLUX_SRC/init" ] && cp -f "$FLUX_SRC/init" /etc/X11/fluxbox/init
  [ -f "$FLUX_SRC/menu" ] && cp -f "$FLUX_SRC/menu" /etc/X11/fluxbox/fluxbox-menu
  [ -f "$FLUX_SRC/keys" ] && cp -f "$FLUX_SRC/keys" /etc/X11/fluxbox/keys
  [ -f "$FLUX_SRC/startup" ] && cp -f "$FLUX_SRC/startup" /etc/X11/fluxbox/startup
  [ -f "$FLUX_SRC/tint2rc" ] && cp -f "$FLUX_SRC/tint2rc" /etc/xdg/tint2/tint2rc
  [ -f "$FLUX_SRC/rofi.rasi" ] && cp -f "$FLUX_SRC/rofi.rasi" /etc/rofi/config.rasi
  [ -f "$FLUX_SRC/picom.conf" ] && cp -f "$FLUX_SRC/picom.conf" /etc/xdg/picom.conf
  [ -f "$FLUX_SRC/pcmanfm.conf" ] && cp -f "$FLUX_SRC/pcmanfm.conf" /etc/xdg/pcmanfm/default/pcmanfm.conf
  if [ -d "$FLUX_SRC/styles" ]; then
    cp -rf "$FLUX_SRC/styles/"* /usr/share/fluxbox/styles/ 2>/dev/null || true
  fi
fi

# Đảm bảo startup có quyền thực thi
[ -f /etc/X11/fluxbox/startup ] && chmod 0755 /etc/X11/fluxbox/startup

# 3. Tạo desktop entry cho Rofi để launcher trên Tint2 hoạt động
mkdir -p /usr/share/applications
cat <<'EOF' > /usr/share/applications/hyggshi-rofi.desktop
[Desktop Entry]
Type=Application
Name=Applications
GenericName=Application Launcher
Comment=Open application launcher
Exec=rofi -show drun -show-icons
Icon=start-here
Terminal=false
Categories=System;Utility;
StartupNotify=false
EOF
chmod 0644 /usr/share/applications/hyggshi-rofi.desktop

# 4. Sao chép hình nền vào hệ thống
for wp in /tmp/hcl-filecopy-src/iso-config/branding/wallpaper.png \
          /tmp/hcl-filecopy-src/iso-config/branding/Verdant-Valley.png \
          /usr/share/backgrounds/Verdant-Valley.png; do
  if [ -f "$wp" ] && [ ! -f /usr/share/backgrounds/hyggshi/wallpaper.png ]; then
    cp -f "$wp" /usr/share/backgrounds/hyggshi/wallpaper.png
    break
  fi
done

# 5. Cấu hình session desktop cho display manager (LightDM)
mkdir -p /usr/share/xsessions
cat <<'EOF' > /usr/share/xsessions/fluxbox.desktop
[Desktop Entry]
Name=Fluxbox
Comment=Hyggshi OS Flex Edition (Slax-style Window Manager)
Exec=startfluxbox
Terminal=false
TryExec=fluxbox
Type=Application
[Window Manager]
SessionManaged=true
EOF
chmod 0644 /usr/share/xsessions/fluxbox.desktop

# 6. Cấu hình skeleton (/etc/skel)
mkdir -p /etc/skel/.fluxbox
for f in init menu keys startup; do
  if [ -f "/etc/X11/fluxbox/$f" ]; then
    cp -f "/etc/X11/fluxbox/$f" "/etc/skel/.fluxbox/$f"
  elif [ -f "/etc/X11/fluxbox/fluxbox-$f" ]; then
    cp -f "/etc/X11/fluxbox/fluxbox-$f" "/etc/skel/.fluxbox/$f"
  fi
done
[ -f /etc/skel/.fluxbox/startup ] && chmod 0755 /etc/skel/.fluxbox/startup

# Tint2 user skeleton
mkdir -p /etc/skel/.config/tint2
[ -f /etc/xdg/tint2/tint2rc ] && cp -f /etc/xdg/tint2/tint2rc /etc/skel/.config/tint2/tint2rc

# Rofi user skeleton
mkdir -p /etc/skel/.config/rofi
[ -f /etc/rofi/config.rasi ] && cp -f /etc/rofi/config.rasi /etc/skel/.config/rofi/config.rasi

# Picom user skeleton
mkdir -p /etc/skel/.config/picom
[ -f /etc/xdg/picom.conf ] && cp -f /etc/xdg/picom.conf /etc/skel/.config/picom/picom.conf

# PCManFM user skeleton
mkdir -p /etc/skel/.config/pcmanfm/default
[ -f /etc/xdg/pcmanfm/default/pcmanfm.conf ] && cp -f /etc/xdg/pcmanfm/default/pcmanfm.conf /etc/skel/.config/pcmanfm/default/pcmanfm.conf

# xterm user skeleton (.Xresources)
cat <<'EOF' > /etc/skel/.Xresources
! Hyggshi OS Flex — xterm color configuration (Hyggshi Dark)
xterm*faceName: Monospace
xterm*faceSize: 11
xterm*utf8: 1
xterm*locale: true
xterm*saveLines: 4096
xterm*background: #1a1b26
xterm*foreground: #c0caf5
xterm*cursorColor: #7aa2f7
xterm*color0: #15161e
xterm*color1: #f7768e
xterm*color2: #9ece6a
xterm*color3: #e0af68
xterm*color4: #7aa2f7
xterm*color5: #bb9af7
xterm*color6: #7dcfff
xterm*color7: #a9b1d6
xterm*color8: #414868
xterm*color9: #f7768e
xterm*color10: #9ece6a
xterm*color11: #e0af68
xterm*color12: #7aa2f7
xterm*color13: #bb9af7
xterm*color14: #7dcfff
xterm*color15: #c0caf5
EOF
mkdir -p /etc/X11/app-defaults
cp -f /etc/skel/.Xresources /etc/X11/app-defaults/XTerm-color 2>/dev/null || true

# 7. Desktop icon cho Calamares Live Installer
mkdir -p /etc/skel/Desktop
cat <<'EOF' > /etc/skel/Desktop/calamares.desktop
[Desktop Entry]
Type=Application
Version=1.0
Name=Install Hyggshi OS
GenericName=Live Installer
Comment=Install Hyggshi OS Flex Edition to your drive
Exec=pkexec calamares
Icon=calamares
Terminal=false
Categories=System;
EOF
chmod 0755 /etc/skel/Desktop/calamares.desktop

# 8. Sao chép vào user live hiện tại nếu đã tạo
if [ -n "${OS_USERNAME:-}" ] && id -u "$OS_USERNAME" >/dev/null 2>&1; then
  USER_HOME=$(getent passwd "$OS_USERNAME" | cut -d: -f6)
  if [ -d "$USER_HOME" ]; then
    mkdir -p "$USER_HOME/.fluxbox" \
             "$USER_HOME/.config/tint2" \
             "$USER_HOME/.config/rofi" \
             "$USER_HOME/.config/picom" \
             "$USER_HOME/.config/pcmanfm/default" \
             "$USER_HOME/Desktop"
    cp -rf /etc/skel/.fluxbox/* "$USER_HOME/.fluxbox/" 2>/dev/null || true
    cp -f /etc/skel/.Xresources "$USER_HOME/.Xresources" 2>/dev/null || true
    cp -f /etc/skel/.config/tint2/* "$USER_HOME/.config/tint2/" 2>/dev/null || true
    cp -f /etc/skel/.config/rofi/* "$USER_HOME/.config/rofi/" 2>/dev/null || true
    cp -f /etc/skel/.config/picom/* "$USER_HOME/.config/picom/" 2>/dev/null || true
    cp -f /etc/skel/.config/pcmanfm/default/* "$USER_HOME/.config/pcmanfm/default/" 2>/dev/null || true
    cp -f /etc/skel/Desktop/* "$USER_HOME/Desktop/" 2>/dev/null || true
    chown -R "$OS_USERNAME:$OS_USERNAME" "$USER_HOME/.fluxbox" "$USER_HOME/.config" "$USER_HOME/Desktop" "$USER_HOME/.Xresources" 2>/dev/null || true
  fi
fi

say "Hyggshi OS Flex Edition (Slax-style) hoàn tất cài đặt cấu hình!"
