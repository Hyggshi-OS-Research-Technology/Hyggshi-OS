#!/bin/bash
set -e
[ "$DEBUG_MODE" = "true" ] && set -x
CHROOT=live-build/chroot

echo "===== Copy branding assets ====="
sudo mkdir -p "$CHROOT/usr/share/backgrounds/hyggshi"

# Copy car wallpapers
for CAR_FILE in car-light.png car-Dark.png car-auto.png; do
  if [ -f "iso-config/branding/$CAR_FILE" ]; then
    sudo cp "iso-config/branding/$CAR_FILE" "$CHROOT/usr/share/backgrounds/hyggshi/$CAR_FILE"
  fi
done

# Wallpaper chính (ưu tiên Wallpaper1.png từ ảnh bạn upload)
WALLPAPER_FILE=""
if [ -f "iso-config/branding/Wallpaper1.png" ]; then
  WALLPAPER_FILE="iso-config/branding/Wallpaper1.png"
elif [ -f "iso-config/branding/wallpaper.png" ]; then
  WALLPAPER_FILE="iso-config/branding/wallpaper.png"
elif [ -n "$WALLPAPER_URL" ]; then
  curl -fsSL "$WALLPAPER_URL" -o /tmp/wallpaper-remote.png && [ -s /tmp/wallpaper-remote.png ] && WALLPAPER_FILE=/tmp/wallpaper-remote.png
fi

WALLPAPER_APPLIED=false
if [ -n "$WALLPAPER_FILE" ]; then
  sudo cp "$WALLPAPER_FILE" "$CHROOT/usr/share/backgrounds/hyggshi/wallpaper.png"
  WALLPAPER_APPLIED=true
else
  sudo apt-get install -y imagemagick >/dev/null 2>&1 || true
  if command -v convert >/dev/null 2>&1; then
    convert -size 1920x1080 gradient:'#1a2a4a-#0d1220' /tmp/wallpaper.png
    sudo cp /tmp/wallpaper.png "$CHROOT/usr/share/backgrounds/hyggshi/wallpaper.png"
    WALLPAPER_APPLIED=true
  fi
fi

if [ "$WALLPAPER_APPLIED" = "true" ]; then
  for LINK in "$CHROOT/etc/alternatives/desktop-background" \
              "$CHROOT/usr/share/backgrounds/desktop-background" \
              "$CHROOT/usr/share/images/desktop-base/desktop-background"; do
    if [ -e "$LINK" ] || [ -L "$LINK" ]; then
      sudo rm -f "$LINK"
      sudo ln -sf /usr/share/backgrounds/hyggshi/wallpaper.png "$LINK"
    fi
  done
  if sudo chroot "$CHROOT" bash -c 'command -v update-alternatives' >/dev/null 2>&1; then
    sudo chroot "$CHROOT" update-alternatives --install \
      /usr/share/images/desktop-base/desktop-background desktop-background \
      /usr/share/backgrounds/hyggshi/wallpaper.png 100 2>&1 || true
    sudo chroot "$CHROOT" update-alternatives --set \
      desktop-background /usr/share/backgrounds/hyggshi/wallpaper.png 2>&1 || true
  fi

  # Patch xfce4-desktop.xml gốc
  FOUND_XMLS=$(sudo find "$CHROOT/etc/xdg" "$CHROOT/usr/share" -name "xfce4-desktop.xml" 2>/dev/null || true)
  for f in $FOUND_XMLS; do
    sudo sed -i -E \
      -e 's#(<property name="last-image" type="string" value=")[^"]*(")#\1/usr/share/backgrounds/hyggshi/wallpaper.png\2#g' \
      -e 's#(<property name="image-style" type="int" value=")[0-9]+(")#\g<1>5\2#g' \
      "$f" 2>/dev/null || true
  done
fi

echo "===== Rebrand os-release ====="
sudo rm -f "$CHROOT/etc/os-release" "$CHROOT/usr/lib/os-release"
ID_LIKE_VALUE="debian"
[ "$BASE_DISTRO" != "debian" ] && ID_LIKE_VALUE="ubuntu debian"

cat <<EOF | sudo tee "$CHROOT/usr/lib/os-release" >/dev/null
PRETTY_NAME="$DISTRO_NAME 1.0 (dựa trên $DISTRO_LABEL)"
NAME="$DISTRO_NAME"
VERSION_ID="1.0"
VERSION="1.0 ($DISTRO_LABEL)"
VERSION_CODENAME=$BASE_CODENAME
ID=hyggshios
ID_LIKE=$ID_LIKE_VALUE
HOME_URL="https://github.com/Hyggshi-OS-Research-Technology"
SUPPORT_URL="https://github.com/Hyggshi-OS-Research-Technology/Hyggshi-OS/issues"
BUG_REPORT_URL="https://github.com/Hyggshi-OS-Research-Technology/Hyggshi-OS/issues"
LOGO=distributor-logo
EOF
sudo ln -sf ../usr/lib/os-release "$CHROOT/etc/os-release"

cat <<EOF | sudo tee "$CHROOT/etc/lsb-release" >/dev/null
DISTRIB_ID=HyggshiOS
DISTRIB_RELEASE=1.0
DISTRIB_CODENAME=$BASE_CODENAME
DISTRIB_DESCRIPTION="$DISTRO_NAME 1.0 ($DISTRO_LABEL)"
EOF

printf "%s \\n \\l\n\n" "$DISTRO_NAME" | sudo tee "$CHROOT/etc/issue" >/dev/null
echo "Welcome to $DISTRO_NAME — built on $DISTRO_LABEL" | sudo tee "$CHROOT/etc/motd" >/dev/null

echo "===== Distributor logo ====="
LOGO_FILE=$(find iso-config/branding -maxdepth 1 -iname "logo.*" \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" \) 2>/dev/null | head -n1)
if [ -z "$LOGO_FILE" ] && [ -n "$LOGO_URL" ]; then
  curl -fsSL "$LOGO_URL" -o /tmp/logo-remote.png && [ -s /tmp/logo-remote.png ] && LOGO_FILE=/tmp/logo-remote.png
fi

if [ -n "$LOGO_FILE" ]; then
  sudo apt-get install -y imagemagick >/dev/null 2>&1 || true
  if command -v convert >/dev/null 2>&1; then
    for size in 16 22 24 32 48 64 128 192 256; do
      DEST="$CHROOT/usr/share/icons/hicolor/${size}x${size}/apps"
      sudo mkdir -p "$DEST"
      convert "$LOGO_FILE" -resize ${size}x${size} "/tmp/logo-$size.png"
      sudo cp "/tmp/logo-$size.png" "$DEST/distributor-logo.png"
    done
    sudo chroot "$CHROOT" gtk-update-icon-cache -f /usr/share/icons/hicolor 2>/dev/null || true
  fi
fi

echo "===== Calamares branding ====="
CALAMARES_SETTINGS="$CHROOT/etc/calamares/settings.conf"
if [ -n "$LOGO_FILE" ] && [ -f "$CALAMARES_SETTINGS" ]; then
  if command -v convert >/dev/null 2>&1; then
    BRANDING_COMPONENT=$(sudo grep -E '^\s*branding\s*:' "$CALAMARES_SETTINGS" | head -n1 | sed -E 's/^[^:]*:[[:space:]]*//' | tr -d "\"'" | tr -d $'\r')
    [ -z "$BRANDING_COMPONENT" ] && BRANDING_COMPONENT="debian"
    BRANDING_DIR="$CHROOT/etc/calamares/branding/$BRANDING_COMPONENT"
    BRANDING_DESC="$BRANDING_DIR/branding.desc"
    if [ -f "$BRANDING_DESC" ]; then
      LOGO_IMG_NAME=$(sudo grep -E '^\s*productLogo\s*:' "$BRANDING_DESC" | head -n1 | sed -E 's/^[^:]*:[[:space:]]*//' | tr -d "\"'" | tr -d $'\r')
      [ -z "$LOGO_IMG_NAME" ] && LOGO_IMG_NAME="logo.png"
      convert "$LOGO_FILE" -resize 256x256 -background none -gravity center -extent 256x256 /tmp/calamares-sidebar-logo.png
      sudo cp /tmp/calamares-sidebar-logo.png "$BRANDING_DIR/$LOGO_IMG_NAME"
      ICON_IMG_NAME=$(sudo grep -E '^\s*productIcon\s*:' "$BRANDING_DESC" | head -n1 | sed -E 's/^[^:]*:[[:space:]]*//' | tr -d "\"'" | tr -d $'\r')
      if [ -n "$ICON_IMG_NAME" ] && [ "$ICON_IMG_NAME" != "$LOGO_IMG_NAME" ]; then
        sudo cp /tmp/calamares-sidebar-logo.png "$BRANDING_DIR/$ICON_IMG_NAME"
      fi
    fi
  fi
fi

echo "===== Plymouth ====="
PLYMOUTH_LOGO_FILE=$(find iso-config/branding -maxdepth 1 -iname "plymouth-logo.*" \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" \) 2>/dev/null | head -n1)
if [ -z "$PLYMOUTH_LOGO_FILE" ] && [ -n "$PLYMOUTH_LOGO_URL" ]; then
  curl -fsSL "$PLYMOUTH_LOGO_URL" -o /tmp/plymouth-logo-remote.png && [ -s /tmp/plymouth-logo-remote.png ] && PLYMOUTH_LOGO_FILE=/tmp/plymouth-logo-remote.png
fi
[ -z "$PLYMOUTH_LOGO_FILE" ] && [ -n "$LOGO_FILE" ] && PLYMOUTH_LOGO_FILE="$LOGO_FILE"

if [ -n "$PLYMOUTH_LOGO_FILE" ]; then
  THEME_DIR="$CHROOT/usr/share/plymouth/themes/hyggshi-boot"
  sudo mkdir -p "$THEME_DIR"
  DISTRO_NAME_SAFE="${DISTRO_NAME//\"/}"
  sudo apt-get install -y imagemagick >/dev/null 2>&1 || true
  if command -v convert >/dev/null 2>&1; then
    convert "$PLYMOUTH_LOGO_FILE" -resize 256x256 /tmp/plymouth-logo.png
  else
    cp "$PLYMOUTH_LOGO_FILE" /tmp/plymouth-logo.png
  fi
  sudo cp /tmp/plymouth-logo.png "$THEME_DIR/logo.png"

  # Dot-wave spinner
  DOTS_COUNT=5; DOT_RADIUS=6; DOT_GAP=26; SPINNER_FRAMES=30
  DOT_ROW_WIDTH=$(( (DOTS_COUNT - 1) * DOT_GAP ))
  SPINNER_CANVAS_W=$(( DOT_ROW_WIDTH + DOT_RADIUS * 2 + 20 ))
  SPINNER_CANVAS_H=$(( DOT_RADIUS * 2 + 20 ))
  DOT_CY=$(( SPINNER_CANVAS_H / 2 ))
  if command -v convert >/dev/null 2>&1; then
    for i in $(seq 0 $((SPINNER_FRAMES - 1))); do
      read -ra DOT_COLORS <<< "$(awk -v frame="$i" -v frames="$SPINNER_FRAMES" -v dots="$DOTS_COUNT" 'BEGIN{
        pi=3.14159265; base_r=38; base_g=38; base_b=38; hi_r=255; hi_g=255; hi_b=255;
        for(j=0;j<dots;j++){phase=2*pi*frame/frames-j*(2*pi/dots);val=(sin(phase)+1)/2;
        r=base_r+(hi_r-base_r)*val;g=base_g+(hi_g-base_g)*val;b=base_b+(hi_b-base_b)*val;
        printf "#%02x%02x%02x ",r,g,b}}')"
      DRAW_STR=""
      for j in $(seq 0 $((DOTS_COUNT - 1))); do
        DOT_CX=$(( DOT_RADIUS + 10 + j * DOT_GAP ))
        DRAW_STR="$DRAW_STR fill \"${DOT_COLORS[$j]}\" circle $DOT_CX,$DOT_CY $((DOT_CX + DOT_RADIUS)),$DOT_CY"
      done
      FRAME_NAME=$(printf "spinner-%02d.png" "$i")
      convert -size ${SPINNER_CANVAS_W}x${SPINNER_CANVAS_H} xc:none -draw "$DRAW_STR" "/tmp/$FRAME_NAME"
      sudo cp "/tmp/$FRAME_NAME" "$THEME_DIR/$FRAME_NAME"
    done
  else
    SPINNER_FRAMES=0
  fi

  cat <<PLYMOUTHEOF | sudo tee "$THEME_DIR/hyggshi-boot.plymouth" >/dev/null
[Plymouth Theme]
Name=Hyggshi Boot
Description=$DISTRO_NAME_SAFE boot splash
ModuleName=script

[script]
ImageDir=/usr/share/plymouth/themes/hyggshi-boot
ScriptFile=/usr/share/plymouth/themes/hyggshi-boot/hyggshi-boot.script
PLYMOUTHEOF

  cat <<SCRIPTEOF | sudo tee "$THEME_DIR/hyggshi-boot.script" >/dev/null
Window.SetBackgroundTopColor(0, 0, 0);
Window.SetBackgroundBottomColor(0, 0, 0);
window_width = Window.GetWidth();
window_height = Window.GetHeight();
logo.image = Image("logo.png");
logo.sprite = Sprite(logo.image);
logo_x = window_width / 2 - logo.image.GetWidth() / 2;
logo_y = window_height / 2 - logo.image.GetHeight() / 2 - 40;
logo.sprite.SetX(logo_x);
logo.sprite.SetY(logo_y);
logo.sprite.SetZ(10);
spinner_frame_count = $SPINNER_FRAMES;
spinner_y = logo_y + logo.image.GetHeight() + 30;
if (spinner_frame_count > 0) {
  spinner_images[0] = Image("spinner-00.png");
  spinner_sprite = Sprite(spinner_images[0]);
  spinner_sprite.SetX(window_width / 2 - spinner_images[0].GetWidth() / 2);
  spinner_sprite.SetY(spinner_y);
  spinner_sprite.SetZ(10);
  i = 1;
  while (i < spinner_frame_count) {
    if (i < 10) { frame_suffix = "0" + i; } else { frame_suffix = "" + i; }
    spinner_images[i] = Image("spinner-" + frame_suffix + ".png");
    i++;
  }
  spinner_tick = 0; spinner_index = 0; SPINNER_TICKS = 3;
  fun refresh_callback() {
    spinner_tick++;
    if (spinner_tick >= SPINNER_TICKS) {
      spinner_tick = 0; spinner_index++;
      if (spinner_index >= spinner_frame_count) { spinner_index = 0; }
      spinner_sprite.SetImage(spinner_images[spinner_index]);
      spinner_sprite.SetX(window_width / 2 - spinner_images[spinner_index].GetWidth() / 2);
      spinner_sprite.SetY(spinner_y);
    }
  }
  Plymouth.SetRefreshFunction(refresh_callback);
}
SCRIPTEOF

  if sudo chroot "$CHROOT" bash -c 'command -v plymouth-set-default-theme' >/dev/null 2>&1; then
    sudo chroot "$CHROOT" plymouth-set-default-theme -R hyggshi-boot 2>&1 || {
      sudo chroot "$CHROOT" plymouth-set-default-theme hyggshi-boot || true
      sudo chroot "$CHROOT" update-initramfs -u || true
    }
  fi
fi

echo "===== Fastfetch logo ====="
FASTFETCH_LOGO_TXT=$(find iso-config/branding -maxdepth 1 -iname "logo.txt" 2>/dev/null | head -n1)
FASTFETCH_LOGO_PNG=$(find iso-config/branding -maxdepth 1 -iname "logo.png" 2>/dev/null | head -n1)
LOGO_DEST_DIR="$CHROOT/usr/share/hyggshi/branding"
LOGO_JSON=""

if [ -n "$FASTFETCH_LOGO_TXT" ]; then
  sudo mkdir -p "$LOGO_DEST_DIR"
  sudo cp "$FASTFETCH_LOGO_TXT" "$LOGO_DEST_DIR/logo.txt"
  LOGO_JSON='  "logo": { "type": "file", "source": "/usr/share/hyggshi/branding/logo.txt" },'
elif [ -n "$FASTFETCH_LOGO_PNG" ]; then
  sudo mkdir -p "$LOGO_DEST_DIR"
  sudo cp "$FASTFETCH_LOGO_PNG" "$LOGO_DEST_DIR/logo.png"
  LOGO_JSON='  "logo": { "type": "kitty", "source": "/usr/share/hyggshi/branding/logo.png", "height": 15 },'
fi

if [ -n "$LOGO_JSON" ]; then
  sudo mkdir -p "$CHROOT/etc/xdg/fastfetch" "$CHROOT/etc/skel/.config/fastfetch"
  cat <<FFCFG | sudo tee "$CHROOT/etc/xdg/fastfetch/config.jsonc" >/dev/null
{
  "\$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
$LOGO_JSON
  "display": { "separator": " " },
  "modules": [
    "title", "separator",
    { "type": "os", "key": "OS" }, { "type": "host", "key": "May" },
    { "type": "kernel", "key": "Kernel" }, { "type": "uptime", "key": "Uptime" },
    { "type": "packages", "key": "Packages" }, { "type": "shell", "key": "Shell" },
    { "type": "de", "key": "DE" }, { "type": "wm", "key": "WM" },
    { "type": "display", "key": "Man hinh" }, { "type": "theme", "key": "Theme" },
    { "type": "icons", "key": "Icons" }, { "type": "terminal", "key": "Terminal" },
    "break",
    { "type": "cpu", "key": "CPU" }, { "type": "gpu", "key": "GPU" },
    { "type": "memory", "key": "RAM" }, { "type": "swap", "key": "Swap" },
    { "type": "disk", "key": "Disk" }, { "type": "localip", "key": "IP" },
    "break", "colors"
  ]
}
FFCFG
  sudo cp "$CHROOT/etc/xdg/fastfetch/config.jsonc" "$CHROOT/etc/skel/.config/fastfetch/config.jsonc"
  FF_USER_HOME="$CHROOT/home/$OS_USERNAME"
  if [ -d "$FF_USER_HOME" ]; then
    sudo mkdir -p "$FF_USER_HOME/.config/fastfetch"
    sudo cp "$CHROOT/etc/xdg/fastfetch/config.jsonc" "$FF_USER_HOME/.config/fastfetch/config.jsonc"
    sudo chroot "$CHROOT" chown -R "$OS_USERNAME:$OS_USERNAME" "/home/$OS_USERNAME/.config"
    for RC in "$CHROOT/etc/skel/.bashrc" "$FF_USER_HOME/.bashrc"; do
      if [ -f "$RC" ] && ! sudo grep -q "^command -v fastfetch" "$RC" 2>/dev/null; then
        printf '\ncommand -v fastfetch >/dev/null 2>&1 && fastfetch\n' | sudo tee -a "$RC" >/dev/null
      fi
    done
  fi
fi

if [ "$DE" != "xfce" ]; then
  echo "DE=$DE, bỏ qua XFCE config."
  echo "===== branding.sh xong ====="
  exit 0
fi

echo "===== XFCE skel config ====="
SKEL="$CHROOT/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml"
sudo mkdir -p "$SKEL"

case "$ICON_THEME" in
  numix)   ICON_NAME="Numix" ;;
  breeze)  ICON_NAME="breeze" ;;
  adwaita) ICON_NAME="Adwaita" ;;
  *)       ICON_NAME="Papirus" ;;
esac

if [ "$PANEL_STYLE" = "windows10" ]; then
cat <<XML | sudo tee "$SKEL/xfce4-panel.xml" >/dev/null
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-panel" version="1.0">
  <property name="configver" type="int" value="2"/>
  <property name="panels" type="array">
    <value type="int" value="1"/>
    <property name="panel-1" type="empty">
      <property name="position" type="string" value="p=8;x=0;y=0"/>
      <property name="length" type="uint" value="100"/>
      <property name="length-adjust" type="bool" value="true"/>
      <property name="position-locked" type="bool" value="true"/>
      <property name="size" type="uint" value="34"/>
      <property name="mode" type="uint" value="0"/>
      <property name="autohide-behavior" type="uint" value="0"/>
      <property name="plugin-ids" type="array">
        <value type="int" value="1"/><value type="int" value="2"/>
        <value type="int" value="3"/><value type="int" value="4"/>
        <value type="int" value="5"/>
      </property>
    </property>
  </property>
  <property name="plugins" type="empty">
    <property name="plugin-1" type="string" value="whiskermenu">
      <property name="button-title" type="string" value=""/>
      <property name="button-icon" type="string" value="start-here"/>
      <property name="show-button-title" type="bool" value="false"/>
    </property>
    <property name="plugin-2" type="string" value="tasklist">
      <property name="grouping" type="uint" value="1"/>
      <property name="show-labels" type="bool" value="false"/>
      <property name="show-handle" type="bool" value="false"/>
    </property>
    <property name="plugin-3" type="string" value="separator">
      <property name="expand" type="bool" value="true"/>
      <property name="style" type="uint" value="0"/>
    </property>
    <property name="plugin-4" type="string" value="systray"/>
    <property name="plugin-5" type="string" value="clock">
      <property name="digital-format" type="string" value="%H:%M  %d/%m/%Y"/>
      <property name="digital-layout" type="uint" value="2"/>
    </property>
  </property>
</channel>
XML
fi

if [ "$WALLPAPER_APPLIED" = "true" ]; then
cat <<XML | sudo tee "$SKEL/xfce4-desktop.xml" >/dev/null
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-desktop" version="1.0">
  <property name="backdrop" type="empty">
    <property name="screen0" type="empty">
      <property name="monitor0" type="empty">
        <property name="workspace0" type="empty">
          <property name="last-image" type="string" value="/usr/share/backgrounds/hyggshi/wallpaper.png"/>
          <property name="image-style" type="int" value="5"/>
        </property>
      </property>
    </property>
  </property>
</channel>
XML
fi

cat <<XML | sudo tee "$SKEL/xsettings.xml" >/dev/null
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xsettings" version="1.0">
  <property name="Net" type="empty">
    <property name="IconThemeName" type="string" value="$ICON_NAME"/>
    <property name="ThemeName" type="string" value="Windows-10"/>
  </property>
</channel>
XML

cat <<XML | sudo tee "$SKEL/xfwm4.xml" >/dev/null
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="theme" type="string" value="Windows-10"/>
    <property name="button_layout" type="string" value="O|SHMC"/>
  </property>
</channel>
XML

sudo chroot "$CHROOT" chown -R root:root /etc/skel/.config

if [ "$WALLPAPER_APPLIED" = "true" ]; then
echo "===== Wallpaper autostart script ====="
cat <<'SCRIPT' | sudo tee "$CHROOT/usr/local/bin/hyggshi-set-wallpaper.sh" >/dev/null
#!/bin/bash
LOG="/tmp/hyggshi-wallpaper.log"
exec > "$LOG" 2>&1
echo "=== $(date) ==="
WALL="${1:-/usr/share/backgrounds/hyggshi/wallpaper.png}"
[ ! -f "$WALL" ] && { echo "Thieu wallpaper"; exit 0; }

for i in $(seq 1 20); do
  pgrep -x xfdesktop >/dev/null && { echo "xfdesktop chay sau ${i}s"; break; }
  sleep 1
done

PROPS=""
for i in $(seq 1 20); do
  PROPS=$(xfconf-query -c xfce4-desktop -p /backdrop -l 2>/dev/null | grep 'last-image$')
  [ -n "$PROPS" ] && { echo "Tim thay property sau ${i}s"; break; }
  sleep 1
done

apply_wallpaper() {
  PROPS=$(xfconf-query -c xfce4-desktop -p /backdrop -l 2>/dev/null | grep 'last-image$')
  if [ -z "$PROPS" ]; then
    REAL_MONITORS=$(xrandr --query 2>/dev/null | awk '/ connected/{print $1}')
    PROPS="/backdrop/screen0/monitor0/workspace0/last-image"
    for m in $REAL_MONITORS; do
      PROPS="$PROPS
/backdrop/screen0/monitor${m}/workspace0/last-image"
    done
  fi
  while read -r PROP; do
    [ -z "$PROP" ] && continue
    STYLE="${PROP%last-image}image-style"
    xfconf-query -c xfce4-desktop -p "$PROP" -n -t string -s "$WALL" 2>>"$LOG" || xfconf-query -c xfce4-desktop -p "$PROP" -s "$WALL" 2>>"$LOG"
    xfconf-query -c xfce4-desktop -p "$STYLE" -n -t int -s 5 2>>"$LOG" || xfconf-query -c xfce4-desktop -p "$STYLE" -s 5 2>>"$LOG"
    echo "Set $PROP -> $WALL"
  done <<< "$PROPS"
}

apply_wallpaper
xfdesktop --reload 2>>"$LOG"
sleep 1
killall xfdesktop 2>>"$LOG" || true
sleep 1
nohup xfdesktop >>"$LOG" 2>&1 &
sleep 1

CHECK=$(xfconf-query -c xfce4-desktop -p /backdrop -l 2>/dev/null | grep 'last-image$' | head -n1)
if [ -n "$CHECK" ]; then
  VAL=$(xfconf-query -c xfce4-desktop -p "$CHECK" 2>/dev/null)
  echo "verify: $CHECK = $VAL"
  if [ "$VAL" != "$WALL" ]; then
    echo "Retry lan 2"
    apply_wallpaper
    killall xfdesktop 2>>"$LOG" || true
    sleep 1
    nohup xfdesktop >>"$LOG" 2>&1 &
  fi
fi
echo "=== xong ==="
SCRIPT
sudo chmod +x "$CHROOT/usr/local/bin/hyggshi-set-wallpaper.sh"

sudo mkdir -p "$CHROOT/etc/skel/.config/autostart" "$CHROOT/etc/xdg/autostart"
cat <<'DESKTOP' | sudo tee "$CHROOT/etc/xdg/autostart/hyggshi-wallpaper.desktop" >/dev/null
[Desktop Entry]
Type=Application
Name=Hyggshi Wallpaper Setup
Exec=/usr/local/bin/hyggshi-set-wallpaper.sh
X-GNOME-Autostart-enabled=true
NoDisplay=true
DESKTOP
sudo cp "$CHROOT/etc/xdg/autostart/hyggshi-wallpaper.desktop" "$CHROOT/etc/skel/.config/autostart/"
fi

USER_HOME="$CHROOT/home/$OS_USERNAME"
if [ -d "$USER_HOME" ]; then
  sudo rm -rf "$USER_HOME/.config/xfce4" "$USER_HOME/.cache"
  sudo mkdir -p "$USER_HOME/.config"
  sudo cp -r "$CHROOT/etc/skel/.config/xfce4" "$USER_HOME/.config/xfce4" || true
  sudo chroot "$CHROOT" chown -R "$OS_USERNAME:$OS_USERNAME" "/home/$OS_USERNAME/.config"
fi

echo "===== branding.sh xong ====="
