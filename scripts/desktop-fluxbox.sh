#!/bin/bash
# desktop-fluxbox.sh — configure Hyggshi OS Flex Edition (Slax-style)
# Stack: Fluxbox (WM) + Tint2 (Taskbar) + PCManFM (File Manager & Desktop) + Rofi (Launcher) + Picom (Compositor) + xterm
# Runs as root inside chroot
set -e
[ "${DEBUG_MODE:-}" = "true" ] && set -x

say() { printf '===== %s =====\n' "$*"; }

say "Cấu hình Hyggshi OS Flex Edition (Slax-style)"

# 1. Dọn cấu hình xorg.conf cứng (để Xorg tự dò KMS/virtio/qxl/vesa/gpu thật)
rm -f /etc/X11/xorg.conf.d/20-hyggshi-flex.conf \
      /etc/X11/xorg.conf.d/21-hyggshi-flex-fallback.conf 2>/dev/null || true

# 2. Tạo thư mục cấu hình hệ thống
mkdir -p /etc/X11/fluxbox
mkdir -p /usr/share/fluxbox/styles
mkdir -p /etc/xdg/tint2
mkdir -p /etc/rofi
mkdir -p /etc/xdg/picom
mkdir -p /etc/xdg/pcmanfm/default
mkdir -p /usr/share/backgrounds/hyggshi
mkdir -p /usr/share/xsessions
mkdir -p /usr/share/applications

# 3. Copy cấu hình từ staged source (/tmp/hcl-filecopy-src) nếu có
FLUX_SRC="/tmp/hcl-filecopy-src/iso-config/fluxbox"
if [ -d "$FLUX_SRC" ]; then
  [ -f "$FLUX_SRC/init" ]                  && cp -f "$FLUX_SRC/init"                  /etc/X11/fluxbox/init
  [ -f "$FLUX_SRC/menu" ]                  && cp -f "$FLUX_SRC/menu"                  /etc/X11/fluxbox/fluxbox-menu
  [ -f "$FLUX_SRC/keys" ]                  && cp -f "$FLUX_SRC/keys"                  /etc/X11/fluxbox/keys
  [ -f "$FLUX_SRC/startup" ]               && cp -f "$FLUX_SRC/startup"               /etc/X11/fluxbox/startup
  [ -f "$FLUX_SRC/tint2rc" ]               && cp -f "$FLUX_SRC/tint2rc"               /etc/xdg/tint2/tint2rc
  [ -f "$FLUX_SRC/rofi.rasi" ]             && cp -f "$FLUX_SRC/rofi.rasi"             /etc/rofi/config.rasi
  [ -f "$FLUX_SRC/picom.conf" ]            && cp -f "$FLUX_SRC/picom.conf"            /etc/xdg/picom.conf
  [ -f "$FLUX_SRC/pcmanfm.conf" ]          && cp -f "$FLUX_SRC/pcmanfm.conf"          /etc/xdg/pcmanfm/default/pcmanfm.conf
  [ -f "$FLUX_SRC/desktop-items-0.conf" ]  && cp -f "$FLUX_SRC/desktop-items-0.conf"  /etc/xdg/pcmanfm/default/desktop-items-0.conf
  [ -f "$FLUX_SRC/gsimplecal.conf" ]       && { mkdir -p /etc/xdg/gsimplecal; cp -f "$FLUX_SRC/gsimplecal.conf" /etc/xdg/gsimplecal/config; }
  if [ -d "$FLUX_SRC/styles" ]; then
    cp -rf "$FLUX_SRC/styles/"* /usr/share/fluxbox/styles/ 2>/dev/null || true
  fi
fi

# Đảm bảo file cấu hình gsimplecal luôn tồn tại
if [ ! -f /etc/xdg/gsimplecal/config ]; then
  mkdir -p /etc/xdg/gsimplecal
  cat <<'EOF' > /etc/xdg/gsimplecal/config
show_calendar = 1
show_week_numbers = 1
mark_today = 1
close_on_unfocus = 1
close_on_mouseleave = 0
mainwindow_decorated = 0
mainwindow_keep_above = 1
mainwindow_sticky = 1
mainwindow_skip_taskbar = 1
mainwindow_resizable = 0
mainwindow_position = mouse
EOF
fi

# Đảm bảo startup hệ thống có quyền thực thi
[ -f /etc/X11/fluxbox/startup ] && chmod 0755 /etc/X11/fluxbox/startup

# 4. Sao chép hình nền vào hệ thống
for wp in /tmp/hcl-filecopy-src/iso-config/branding/wallpaper.png \
          /tmp/hcl-filecopy-src/iso-config/branding/Verdant-Valley.png \
          /usr/share/backgrounds/Verdant-Valley.png; do
  if [ -f "$wp" ] && [ ! -f /usr/share/backgrounds/hyggshi/wallpaper.png ]; then
    cp -f "$wp" /usr/share/backgrounds/hyggshi/wallpaper.png
    echo "OK: wallpaper sao chép từ $wp"
    break
  fi
done

# 5. Tạo desktop entry cho Rofi launcher và đảm bảo xterm.desktop / calamares.desktop cho Tint2 launcher
cat <<'EOF' > /usr/share/applications/hyggshi-rofi.desktop
[Desktop Entry]
Type=Application
Name=Applications
GenericName=Application Launcher
Comment=Open application launcher
Exec=rofi -show drun -show-icons
Icon=distributor-logo
Terminal=false
Categories=System;Utility;
StartupNotify=false
EOF
chmod 0644 /usr/share/applications/hyggshi-rofi.desktop

if [ -f /usr/share/applications/debian-xterm.desktop ] && [ ! -f /usr/share/applications/xterm.desktop ]; then
  ln -sf debian-xterm.desktop /usr/share/applications/xterm.desktop
elif [ ! -f /usr/share/applications/xterm.desktop ]; then
  cat <<'EOF' > /usr/share/applications/xterm.desktop
[Desktop Entry]
Name=XTerm
Comment=standard terminal emulator for the X Window System
Exec=xterm
Terminal=false
Type=Application
Icon=xterm-color
Categories=System;TerminalEmulator;
EOF
  chmod 0644 /usr/share/applications/xterm.desktop
fi

if [ -f /usr/share/applications/io.calamares.calamares.desktop ] && [ ! -f /usr/share/applications/calamares.desktop ]; then
  ln -sf io.calamares.calamares.desktop /usr/share/applications/calamares.desktop
fi

# 6. Cấu hình session desktop cho LightDM
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

# 7. Cấu hình LightDM
mkdir -p /etc/lightdm/lightdm.conf.d
cat <<'EOF' > /etc/lightdm/lightdm.conf.d/50-fluxbox.conf
[Seat:*]
user-session=fluxbox
greeter-session=lightdm-gtk-greeter
EOF

# 8. Cấu hình skeleton (/etc/skel) — áp dụng cho mọi user mới tạo
mkdir -p /etc/skel/.fluxbox
mkdir -p /etc/skel/.config/tint2
mkdir -p /etc/skel/.config/rofi
mkdir -p /etc/skel/.config/picom
mkdir -p /etc/skel/.config/pcmanfm/default
mkdir -p /etc/skel/.config/gsimplecal
mkdir -p /etc/skel/Desktop

# Copy các file của Fluxbox vào skel
[ -f /etc/X11/fluxbox/init ]          && cp -f /etc/X11/fluxbox/init          /etc/skel/.fluxbox/init
[ -f /etc/X11/fluxbox/fluxbox-menu ]  && cp -f /etc/X11/fluxbox/fluxbox-menu  /etc/skel/.fluxbox/menu
[ -f /etc/X11/fluxbox/menu ]          && cp -f /etc/X11/fluxbox/menu          /etc/skel/.fluxbox/menu
[ -f /etc/X11/fluxbox/keys ]          && cp -f /etc/X11/fluxbox/keys          /etc/skel/.fluxbox/keys
[ -f /etc/X11/fluxbox/startup ]       && cp -f /etc/X11/fluxbox/startup       /etc/skel/.fluxbox/startup

# Đảm bảo /etc/skel/.fluxbox/startup luôn tồn tại và có quyền thực thi
if [ ! -f /etc/skel/.fluxbox/startup ] && [ -f "$FLUX_SRC/startup" ]; then
  cp -f "$FLUX_SRC/startup" /etc/skel/.fluxbox/startup
fi
[ -f /etc/skel/.fluxbox/startup ] && chmod 0755 /etc/skel/.fluxbox/startup

# Đảm bảo /etc/skel/.fluxbox/init luôn tồn tại và tắt toolbar fluxbox mặc định
if [ ! -f /etc/skel/.fluxbox/init ]; then
  cat <<'EOF' > /etc/skel/.fluxbox/init
session.menuFile: ~/.fluxbox/menu
session.keyFile: ~/.fluxbox/keys
session.styleFile: /usr/share/fluxbox/styles/Hyggshi-Flex
session.configVersion: 13
session.screen0.toolbar.visible: false
session.screen0.toolbar.autoHide: false
session.screen0.workspaces: 4
session.screen0.workspaceNames: 1, 2, 3, 4
session.screen0.focusModel: ClickToFocus
session.screen0.window.focus.alpha: 255
session.screen0.window.unfocus.alpha: 200
session.screen0.titlebar.left: Stick
session.screen0.titlebar.right: Minimize Maximize Close
EOF
fi

# Tint2 user skeleton
[ -f /etc/xdg/tint2/tint2rc ] && cp -f /etc/xdg/tint2/tint2rc /etc/skel/.config/tint2/tint2rc

# Rofi user skeleton
[ -f /etc/rofi/config.rasi ] && cp -f /etc/rofi/config.rasi /etc/skel/.config/rofi/config.rasi

# Picom user skeleton
[ -f /etc/xdg/picom.conf ] && cp -f /etc/xdg/picom.conf /etc/skel/.config/picom/picom.conf

# PCManFM user skeleton (cấu hình desktop + wallpaper)
[ -f /etc/xdg/pcmanfm/default/pcmanfm.conf ] && \
  cp -f /etc/xdg/pcmanfm/default/pcmanfm.conf /etc/skel/.config/pcmanfm/default/pcmanfm.conf
[ -f /etc/xdg/pcmanfm/default/desktop-items-0.conf ] && \
  cp -f /etc/xdg/pcmanfm/default/desktop-items-0.conf /etc/skel/.config/pcmanfm/default/desktop-items-0.conf

# gsimplecal user skeleton (popup lịch khi click vào đồng hồ)
[ -f /etc/xdg/gsimplecal/config ] && cp -f /etc/xdg/gsimplecal/config /etc/skel/.config/gsimplecal/config

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

# Calamares Live Installer icon trên Desktop (dùng install-hyggshi-os.desktop đồng bộ với branding.sh, tránh trùng 2 icon)
rm -f /etc/skel/Desktop/calamares.desktop 2>/dev/null || true
if [ ! -f /etc/skel/Desktop/install-hyggshi-os.desktop ]; then
  cat <<'EOF' > /etc/skel/Desktop/install-hyggshi-os.desktop
[Desktop Entry]
Type=Application
Version=1.0
Name=Install Hyggshi OS
GenericName=Live Installer
Comment=Install Hyggshi OS Flex Edition to your drive
Exec=/usr/local/bin/hyggshi-launch-installer.sh
Icon=hyggshi-installer
Terminal=false
Categories=System;
EOF
fi
chmod 0755 /etc/skel/Desktop/install-hyggshi-os.desktop 2>/dev/null || true

# xinitrc fallback
cat <<'EOF' > /etc/skel/.xinitrc
#!/bin/sh
[ -f ~/.fluxbox/startup ] && exec ~/.fluxbox/startup
exec fluxbox
EOF
chmod 0755 /etc/skel/.xinitrc

# 9. Sao chép trực tiếp vào user live ($OS_USERNAME) nếu đã được tạo
if [ -n "${OS_USERNAME:-}" ] && id -u "$OS_USERNAME" >/dev/null 2>&1; then
  USER_HOME=$(getent passwd "$OS_USERNAME" | cut -d: -f6)
  if [ -d "$USER_HOME" ]; then
    mkdir -p "$USER_HOME/.fluxbox" \
             "$USER_HOME/.config/tint2" \
             "$USER_HOME/.config/rofi" \
             "$USER_HOME/.config/picom" \
             "$USER_HOME/.config/pcmanfm/default" \
             "$USER_HOME/.config/gsimplecal" \
             "$USER_HOME/Desktop"
    rm -f "$USER_HOME/Desktop/calamares.desktop" 2>/dev/null || true
    cp -rf /etc/skel/.fluxbox/. "$USER_HOME/.fluxbox/" 2>/dev/null || true
    [ -f /etc/skel/.Xresources ] && cp -f /etc/skel/.Xresources "$USER_HOME/.Xresources" 2>/dev/null || true
    [ -f /etc/skel/.xinitrc ] && cp -f /etc/skel/.xinitrc "$USER_HOME/.xinitrc" 2>/dev/null || true
    [ -f /etc/skel/.config/tint2/tint2rc ] && cp -f /etc/skel/.config/tint2/tint2rc "$USER_HOME/.config/tint2/tint2rc" 2>/dev/null || true
    [ -f /etc/skel/.config/rofi/config.rasi ] && cp -f /etc/skel/.config/rofi/config.rasi "$USER_HOME/.config/rofi/config.rasi" 2>/dev/null || true
    [ -f /etc/skel/.config/picom/picom.conf ] && cp -f /etc/skel/.config/picom/picom.conf "$USER_HOME/.config/picom/picom.conf" 2>/dev/null || true
    [ -f /etc/skel/.config/pcmanfm/default/pcmanfm.conf ] && \
      cp -f /etc/skel/.config/pcmanfm/default/pcmanfm.conf "$USER_HOME/.config/pcmanfm/default/pcmanfm.conf" 2>/dev/null || true
    [ -f /etc/skel/.config/pcmanfm/default/desktop-items-0.conf ] && \
      cp -f /etc/skel/.config/pcmanfm/default/desktop-items-0.conf "$USER_HOME/.config/pcmanfm/default/desktop-items-0.conf" 2>/dev/null || true
    [ -f /etc/skel/.config/gsimplecal/config ] && \
      cp -f /etc/skel/.config/gsimplecal/config "$USER_HOME/.config/gsimplecal/config" 2>/dev/null || true
    [ -f /etc/skel/Desktop/install-hyggshi-os.desktop ] && \
      cp -f /etc/skel/Desktop/install-hyggshi-os.desktop "$USER_HOME/Desktop/" 2>/dev/null || true
    
    [ -f "$USER_HOME/.fluxbox/startup" ] && chmod 0755 "$USER_HOME/.fluxbox/startup"
    [ -f "$USER_HOME/Desktop/install-hyggshi-os.desktop" ] && chmod 0755 "$USER_HOME/Desktop/install-hyggshi-os.desktop"
    
    chown -R "$OS_USERNAME:$OS_USERNAME" \
      "$USER_HOME/.fluxbox" \
      "$USER_HOME/.config" \
      "$USER_HOME/Desktop" \
      "$USER_HOME/.Xresources" \
      "$USER_HOME/.xinitrc" 2>/dev/null || true
    echo "OK: đã sao chép cấu hình Fluxbox/Tint2/PCManFM vào $USER_HOME"
  fi
fi

say "Hyggshi OS Flex Edition (Slax-style) hoàn tất cài đặt cấu hình!"
