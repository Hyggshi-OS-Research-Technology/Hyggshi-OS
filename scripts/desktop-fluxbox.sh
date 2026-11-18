#!/bin/bash
# desktop-fluxbox.sh — configure Hyggshi OS Flex Edition (Fluxbox + PCManFM + xterm)
# Runs as root inside chroot
set -e
[ "${DEBUG_MODE:-}" = "true" ] && set -x

say() { printf '===== %s =====\n' "$*"; }

say "Cấu hình Hyggshi OS Flex Edition (Fluxbox + PCManFM + xterm)"

# 1. Tạo thư mục cấu hình hệ thống cho Fluxbox
mkdir -p /etc/X11/fluxbox
mkdir -p /usr/share/fluxbox/styles

# Copy từ assets nếu đã staged vào /tmp/hcl-filecopy-src hoặc /tmp/
if [ -d /tmp/hcl-filecopy-src/iso-config/fluxbox ]; then
  cp -rf /tmp/hcl-filecopy-src/iso-config/fluxbox/* /etc/X11/fluxbox/ 2>/dev/null || true
  if [ -d /tmp/hcl-filecopy-src/iso-config/fluxbox/styles ]; then
    cp -rf /tmp/hcl-filecopy-src/iso-config/fluxbox/styles/* /usr/share/fluxbox/styles/ 2>/dev/null || true
  fi
fi

# Đảm bảo startup có quyền thực thi
[ -f /etc/X11/fluxbox/startup ] && chmod 0755 /etc/X11/fluxbox/startup

# 2. Cấu hình session desktop cho display manager (LightDM)
mkdir -p /usr/share/xsessions
cat <<'EOF' > /usr/share/xsessions/fluxbox.desktop
[Desktop Entry]
Name=Fluxbox
Comment=Hyggshi OS Flex Edition (Fluxbox Window Manager)
Exec=startfluxbox
Terminal=false
TryExec=fluxbox
Type=Application
[Window Manager]
SessionManaged=true
EOF
chmod 0644 /usr/share/xsessions/fluxbox.desktop

# 3. Cấu hình skeleton (/etc/skel/.fluxbox) để mọi user mới có cấu hình chuẩn
mkdir -p /etc/skel/.fluxbox
for f in init menu keys startup; do
  if [ -f "/etc/X11/fluxbox/$f" ]; then
    cp -f "/etc/X11/fluxbox/$f" "/etc/skel/.fluxbox/$f"
  elif [ -f "/etc/X11/fluxbox/fluxbox-$f" ]; then
    cp -f "/etc/X11/fluxbox/fluxbox-$f" "/etc/skel/.fluxbox/$f"
  fi
done
[ -f /etc/skel/.fluxbox/startup ] && chmod 0755 /etc/skel/.fluxbox/startup

# 4. Cấu hình PCManFM cho desktop management
mkdir -p /etc/xdg/pcmanfm/default
if [ -f /tmp/hcl-filecopy-src/iso-config/fluxbox/pcmanfm.conf ]; then
  cp -f /tmp/hcl-filecopy-src/iso-config/fluxbox/pcmanfm.conf /etc/xdg/pcmanfm/default/pcmanfm.conf
fi
mkdir -p /etc/skel/.config/pcmanfm/default
[ -f /etc/xdg/pcmanfm/default/pcmanfm.conf ] && cp -f /etc/xdg/pcmanfm/default/pcmanfm.conf /etc/skel/.config/pcmanfm/default/pcmanfm.conf

# 5. Cấu hình xterm (.Xresources)
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

# 6. Desktop icons (Calamares installer)
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

# 7. Sao chép sang user live hiện tại nếu đã tạo
if [ -n "${OS_USERNAME:-}" ] && id -u "$OS_USERNAME" >/dev/null 2>&1; then
  USER_HOME=$(getent passwd "$OS_USERNAME" | cut -d: -f6)
  if [ -d "$USER_HOME" ]; then
    mkdir -p "$USER_HOME/.fluxbox" "$USER_HOME/.config/pcmanfm/default" "$USER_HOME/Desktop"
    cp -rf /etc/skel/.fluxbox/* "$USER_HOME/.fluxbox/" 2>/dev/null || true
    cp -f /etc/skel/.Xresources "$USER_HOME/.Xresources" 2>/dev/null || true
    cp -f /etc/skel/.config/pcmanfm/default/* "$USER_HOME/.config/pcmanfm/default/" 2>/dev/null || true
    cp -f /etc/skel/Desktop/* "$USER_HOME/Desktop/" 2>/dev/null || true
    chown -R "$OS_USERNAME:$OS_USERNAME" "$USER_HOME/.fluxbox" "$USER_HOME/.config" "$USER_HOME/Desktop" "$USER_HOME/.Xresources" 2>/dev/null || true
  fi
fi

say "Hyggshi OS Flex Edition hoàn tất cài đặt cấu hình!"
