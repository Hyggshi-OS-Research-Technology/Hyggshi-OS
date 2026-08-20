#!/bin/bash
# build-arch-iso.sh — build ISO Arch Linux thật (bootable) bằng mkarchiso,
# công cụ chính chủ của archlinux.org (chính là công cụ họ dùng để build ISO
# live/rescue gốc của Arch). Thay thế hoàn toàn cách tự pacstrap+chroot+mount
# tay của build-arch.sh cũ — mkarchiso tự lo debootstrap-tương-đương
# (pacstrap), mkinitcpio với hook archiso, squashfs, bootloader (syslinux +
# GRUB EFI) và không cần ta tự mount /proc /sys /dev như trước.
#
# CHẠY BÊN TRONG CONTAINER archlinux:latest với --privileged (mkarchiso vẫn
# cần mount/overlayfs y hệt pacstrap để build airootfs).
set -e
: "${HYGGSHI_VERSION_ID:=1.0}"
[ "$DEBUG_MODE" = "true" ] && set -x
: "${EDITION:=normal}"

# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../kernel-tuning.sh"

echo "===== Cài archiso ====="
pacman -Sy --noconfirm --needed archiso

PROFILE_DIR="arch-iso-profile"
WORK_DIR="arch-iso-work"
OUT_DIR="arch-iso-out"
rm -rf "$PROFILE_DIR" "$WORK_DIR" "$OUT_DIR"

echo "===== Copy profile 'releng' gốc của archiso làm nền ====="
# releng là profile chính chủ Arch dùng để build ISO live/rescue của họ —
# đã giải quyết sẵn bootloader/mkinitcpio-archiso/squashfs, ta chỉ cần
# customize thêm DE + branding lên trên.
cp -r /usr/share/archiso/configs/releng/ "$PROFILE_DIR"

echo "===== Tuỳ chỉnh profiledef.sh (tên/nhãn ISO) ====="
sed -i \
  -e "s/^iso_name=.*/iso_name=\"hyggshi-os\"/" \
  -e "s/^iso_label=.*/iso_label=\"HYGGSHIOS_\$(date +%Y%m)\"/" \
  -e "s#^iso_publisher=.*#iso_publisher=\"Hyggshi OS Research \& Technology <https://github.com/Hyggshi-OS-Research-Technology>\"#" \
  -e "s/^iso_application=.*/iso_application=\"$DISTRO_NAME Live\"/" \
  -e "s/^install_dir=.*/install_dir=\"hyggshi\"/" \
  "$PROFILE_DIR/profiledef.sh"

echo "===== Bổ sung gói vào packages.x86_64 (DE + tuỳ chọn người dùng) ====="
# packages.x86_64 của releng đã có sẵn base/linux/mkinitcpio-archiso/... —
# nhưng KHÔNG có networkmanager (releng mặc định dùng iwd/systemd-networkd),
# nên phải thêm tường minh, không được giả định gói này đã có sẵn.
{
  echo ""
  echo "# ===== Hyggshi OS: DE + tuỳ chọn ($DE, edition=$EDITION, browser=$INCLUDE_BROWSER, office=$INCLUDE_OFFICE) ====="
  echo networkmanager

  # calamares — KHÔNG có sẵn trong repo chính thức của Arch Linux (chỉ có
  # trên AUR). mkarchiso chỉ dùng repo chính thức nên không thể cài trực
  # tiếp. Nếu cần installer trên Arch, phải tự build calamares từ AUR
  # hoặc dùng công cụ cài đặt khác (arch-install-scripts).
  # printf '%s\n' calamares

  case "$DE" in
    kde)
      printf '%s\n' plasma-desktop sddm konsole dolphin
      ;;
    lxqt)
      printf '%s\n' lxqt sddm pcmanfm-qt xterm
      ;;
    gnome)
      printf '%s\n' gnome gnome-tweaks gdm
      ;;
    mate)
      printf '%s\n' mate mate-extra lightdm lightdm-gtk-greeter
      ;;
    cinnamon)
      printf '%s\n' cinnamon lightdm lightdm-gtk-greeter
      ;;
    *)
      printf '%s\n' xfce4 xfce4-goodies lightdm lightdm-gtk-greeter
      ;;
  esac

  # gói thêm theo Edition (developer/server) — xem kernel-tuning.sh
  hyggshi_edition_packages_pacman "$EDITION"

  case "$ICON_THEME" in
    numix)   echo numix-icon-theme ;;
    breeze)  echo breeze-icons ;;
    adwaita) echo adwaita-icon-theme ;;
    *)       echo papirus-icon-theme ;;
  esac

  [ "$INCLUDE_BROWSER" = "true" ] && echo firefox
  [ "$INCLUDE_OFFICE" = "true" ] && echo libreoffice-fresh

  # gói thêm do người dùng chỉ định, mỗi gói 1 dòng (packages.x86_64 là
  # danh sách 1-gói-1-dòng, không phải chuỗi cách nhau bằng dấu cách như apt)
  if [ -n "$EXTRA_PACKAGES" ]; then
    for pkg in $EXTRA_PACKAGES; do echo "$pkg"; done
  fi
} >> "$PROFILE_DIR/packages.x86_64"

AIROOTFS="$PROFILE_DIR/airootfs"

echo "===== Branding: wallpaper ====="
mkdir -p "$AIROOTFS/usr/share/backgrounds/hyggshi"
WALLPAPER_FILE=$(find iso-config/branding -maxdepth 1 -iname "wallpaper.*" \
  \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" \) 2>/dev/null | head -n1)
if [ -z "$WALLPAPER_FILE" ]; then
  echo "Không thấy wallpaper trong repo local, tải trực tiếp từ GitHub..."
  if curl -fsSL "$WALLPAPER_URL" -o /tmp/wallpaper-remote.png 2>/dev/null && [ -s /tmp/wallpaper-remote.png ]; then
    WALLPAPER_FILE=/tmp/wallpaper-remote.png
  fi
fi
if [ -n "$WALLPAPER_FILE" ]; then
  cp "$WALLPAPER_FILE" "$AIROOTFS/usr/share/backgrounds/hyggshi/wallpaper.png"
  echo "Đã dùng wallpaper: $WALLPAPER_FILE"
else
  echo "⚠️  Không lấy được wallpaper — bỏ qua, giữ nền mặc định của DE."
fi

if [ "$DE" = "xfce" ]; then
  echo "===== XFCE panel style + icon theme + wallpaper (skel profile) ====="
  SKEL="$AIROOTFS/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml"
  mkdir -p "$SKEL"

  case "$ICON_THEME" in
    numix)   ICON_NAME="Numix" ;;
    breeze)  ICON_NAME="Breeze" ;;
    adwaita) ICON_NAME="Adwaita" ;;
    *)       ICON_NAME="Papirus" ;;
  esac

  if [ "$PANEL_STYLE" = "windows10" ]; then
  cat <<XML > "$SKEL/xfce4-panel.xml"
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
        <value type="int" value="1"/>
        <value type="int" value="2"/>
        <value type="int" value="3"/>
        <value type="int" value="4"/>
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

  cat <<XML > "$SKEL/xfce4-desktop.xml"
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

  cat <<XML > "$SKEL/xsettings.xml"
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xsettings" version="1.0">
  <property name="Net" type="empty">
    <property name="IconThemeName" type="string" value="$ICON_NAME"/>
  </property>
</channel>
XML
fi

echo "===== customize_airootfs.sh (chạy TỰ ĐỘNG bên trong chroot lúc mkarchiso build) ====="
# archiso tự thực thi airootfs/root/customize_airootfs.sh bên trong chroot
# của airootfs trong lúc build rồi tự xoá file này khỏi ISO cuối cùng — nên
# KHÔNG cần ta tự mount /proc /sys /dev + chroot tay như build-arch.sh cũ.
mkdir -p "$AIROOTFS/root"
CUSTOMIZE="$AIROOTFS/root/customize_airootfs.sh"
cat <<CUSTOMEOF > "$CUSTOMIZE"
#!/usr/bin/env bash
set -e -u

echo "$OS_HOSTNAME" > /etc/hostname
ln -sf "/usr/share/zoneinfo/$OS_TIMEZONE" /etc/localtime

useradd -m -s /bin/bash -G wheel "$OS_USERNAME" || true
echo "$OS_USERNAME:$OS_PASSWORD" | chpasswd

# LƯU Ý: dùng "|| echo ..." thay vì để lỗi thẳng — script này chạy dưới
# set -e, và đã có 1 lần networkmanager.service không tồn tại (thiếu gói
# trong packages.x86_64) làm chết TOÀN BỘ customize_airootfs.sh giữa chừng,
# kể cả các bước rebrand os-release phía dưới chưa kịp chạy. Không để 1 gói
# thiếu/service enable lỗi kéo sập cả script.
systemctl enable NetworkManager || echo "CẢNH BÁO: NetworkManager.service không tồn tại — kiểm tra packages.x86_64"

CUSTOMEOF

case "$DE" in
  kde)
    cat <<CUSTOMEOF >> "$CUSTOMIZE"
systemctl enable sddm || echo "CẢNH BÁO: sddm.service không tồn tại — kiểm tra packages.x86_64"
mkdir -p /etc/sddm.conf.d
cat <<SDDMEOF > /etc/sddm.conf.d/hyggshi-autologin.conf
[Autologin]
User=$OS_USERNAME
Session=plasma
SDDMEOF
CUSTOMEOF
    ;;
  lxqt)
    cat <<CUSTOMEOF >> "$CUSTOMIZE"
systemctl enable sddm || echo "CẢNH BÁO: sddm.service không tồn tại — kiểm tra packages.x86_64"
mkdir -p /etc/sddm.conf.d
cat <<SDDMEOF > /etc/sddm.conf.d/hyggshi-autologin.conf
[Autologin]
User=$OS_USERNAME
Session=lxqt
SDDMEOF
CUSTOMEOF
    ;;
  gnome)
    cat <<CUSTOMEOF >> "$CUSTOMIZE"
systemctl enable gdm || echo "CẢNH BÁO: gdm.service không tồn tại — kiểm tra packages.x86_64"
mkdir -p /etc/gdm
cat <<GDMEOF > /etc/gdm/custom.conf
[daemon]
AutomaticLoginEnable = true
AutomaticLogin = $OS_USERNAME
GDMEOF
CUSTOMEOF
    ;;
  mate)
    cat <<CUSTOMEOF >> "$CUSTOMIZE"
systemctl enable lightdm || echo "CẢNH BÁO: lightdm.service không tồn tại — kiểm tra packages.x86_64"
mkdir -p /etc/lightdm/lightdm.conf.d
cat <<LIGHTDMEOF > /etc/lightdm/lightdm.conf.d/50-hyggshi-autologin.conf
[Seat:*]
autologin-user=$OS_USERNAME
autologin-user-timeout=0
autologin-session=mate
LIGHTDMEOF
CUSTOMEOF
    ;;
  cinnamon)
    cat <<CUSTOMEOF >> "$CUSTOMIZE"
systemctl enable lightdm || echo "CẢNH BÁO: lightdm.service không tồn tại — kiểm tra packages.x86_64"
mkdir -p /etc/lightdm/lightdm.conf.d
cat <<LIGHTDMEOF > /etc/lightdm/lightdm.conf.d/50-hyggshi-autologin.conf
[Seat:*]
autologin-user=$OS_USERNAME
autologin-user-timeout=0
autologin-session=cinnamon
LIGHTDMEOF
CUSTOMEOF
    ;;
  *)
    cat <<CUSTOMEOF >> "$CUSTOMIZE"
systemctl enable lightdm || echo "CẢNH BÁO: lightdm.service không tồn tại — kiểm tra packages.x86_64"
mkdir -p /etc/lightdm/lightdm.conf.d
cat <<LIGHTDMEOF > /etc/lightdm/lightdm.conf.d/50-hyggshi-autologin.conf
[Seat:*]
autologin-user=$OS_USERNAME
autologin-user-timeout=0
autologin-session=xfce
LIGHTDMEOF
CUSTOMEOF
    ;;
esac

cat <<CUSTOMEOF >> "$CUSTOMIZE"

# Rebrand os-release
rm -f /etc/os-release
cat <<OSEOF > /etc/os-release
PRETTY_NAME="$DISTRO_NAME $HYGGSHI_VERSION_ID (dựa trên $DISTRO_LABEL)"
NAME="$DISTRO_NAME"
VERSION_ID="$HYGGSHI_VERSION_ID"
VERSION="$HYGGSHI_VERSION_ID ($DISTRO_LABEL)"
ID=hyggshios
ID_LIKE=arch
HOME_URL="https://github.com/Hyggshi-OS-Research-Technology"
SUPPORT_URL="https://github.com/Hyggshi-OS-Research-Technology/Hyggshi-OS/issues"
BUG_REPORT_URL="https://github.com/Hyggshi-OS-Research-Technology/Hyggshi-OS/issues"
OSEOF
CUSTOMEOF

chmod +x "$CUSTOMIZE"

# ============================================================
# Edition (kernel tuning qua sysctl) — normal | developer | server | lite.
# Ghi thẳng vào overlay (không cần chạy lệnh gì trong customize_airootfs.sh)
# vì đây chỉ là 1 file cấu hình tĩnh, áp dụng lúc boot qua systemd-sysctl.
# Runtime kernel parameter, KHÔNG phải compile-time kernel config
# (CONFIG_PREEMPT, CONFIG_HZ, CONFIG_BTRFS_FS...) — muốn đổi loại đó phải tự
# build kernel riêng, sysctl không làm được. Hàm dùng chung với Debian, xem
# scripts/kernel-tuning.sh.
# ============================================================
echo "===== Ghi /etc/sysctl.d/99-hyggshi-tuning.conf theo Edition=$EDITION ====="
mkdir -p "$AIROOTFS/etc/sysctl.d"
hyggshi_sysctl_conf "$EDITION" > "$AIROOTFS/etc/sysctl.d/99-hyggshi-tuning.conf"

echo "===== mkarchiso build (có thể mất vài phút) ====="
mkarchiso -v -w "$WORK_DIR" -o "$OUT_DIR" "$PROFILE_DIR"

echo "===== Đổi tên file ISO output thành \$ISO_FILENAME ====="
BUILT_ISO=$(find "$OUT_DIR" -maxdepth 1 -name "*.iso" | head -n1)
if [ -z "$BUILT_ISO" ]; then
  echo "LỖI: mkarchiso chạy xong (exit 0) nhưng không tìm thấy file .iso nào trong $OUT_DIR" >&2
  ls -la "$OUT_DIR" >&2 || true
  exit 1
fi
cp "$BUILT_ISO" "$ISO_FILENAME"
ls -lh "$ISO_FILENAME"

echo "===== build-arch-iso.sh xong ====="
