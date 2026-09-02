#!/bin/bash
# build-arch-iso.sh — build ISO Arch Linux (bootable) bằng `mkarchiso`
# (công cụ chính chủ archlinux.org, gói `archiso`), chạy NATIVE trong
# container archlinux:latest --privileged (mkarchiso tự mount --bind
# /proc /sys /dev vào work dir để pacstrap/chroot chạy %post của
# systemd/glibc/kernel — giống lý do build-fedora.sh cần --privileged).
#
# BUG ĐÃ SỬA: file này trước đây (do lỗi copy-paste ngược — xem comment
# đầu build-alpine.sh kể lại đúng sự cố tương tự nhưng theo chiều ngược
# lại) chứa nhầm nội dung của scripts/arch.sh (helper kiến trúc CPU
# amd64/arm64 dùng cho build-debian.sh/desktop.sh) — hoàn toàn không có
# lệnh mkarchiso nào, khiến job build-arch không build ra ISO gì cả.
# Nội dung đúng của scripts/arch.sh đã được tách ra file riêng
# (scripts/arch.sh) — file này viết lại từ đầu, đúng vai trò của nó.
#
# THIẾT KẾ:
#   - archiso dùng PROFILE (thư mục packages.x86_64 + profiledef.sh +
#     airootfs/) — ở đây copy profile "releng" gốc của archiso làm nền,
#     rồi ghi đè packages.x86_64/profiledef.sh/airootfs theo DE/branding
#     của Hyggshi OS, giống cách build-alpine.sh/build-fedora.sh tuỳ biến
#     rootfs riêng cho từng distro.
#   - USER/SERVICE: dùng airootfs/root/customize_airootfs.sh (script chạy
#     1 lần qua arch-chroot ngay sau khi mkarchiso pacstrap xong, trước
#     khi đóng gói squashfs) để tạo user + enable service — đây là cách
#     CHÍNH THỐNG theo tài liệu archiso (README.profile.rst) dù mkarchiso
#     có cảnh báo "customize_airootfs.sh is deprecated" (chưa bị gỡ, vẫn
#     hoạt động — xem archlinux/archiso trên GitHub, nhánh master).
#   - VIETNAMESE INPUT (fcitx5-unikey) + calamares: CẢ HAI đều chỉ có trên
#     AUR, không có trong repo chính thức (core/extra) — mkarchiso không
#     tự cài AUR. Bỏ qua 2 gói này cho job Arch (giống cách build-alpine.sh
#     thành thật báo "bỏ qua" khi calamares không có sẵn cho Alpine), ISO
#     vẫn boot live được nhưng KHÔNG có graphical installer/gõ tiếng Việt.
set -e
: "${HYGGSHI_VERSION_ID:=1.0}"
[ "$DEBUG_MODE" = "true" ] && set -x

: "${DISTRO_NAME:=Hyggshi OS}"
: "${OS_HOSTNAME:=hyggshi-os}"
: "${OS_TIMEZONE:=Asia/Ho_Chi_Minh}"
: "${OS_USERNAME:=hyggshi}"
: "${OS_PASSWORD:=hyggshi}"
: "${DE:=xfce}"
: "${ICON_THEME:=papirus}"
: "${INCLUDE_BROWSER:=false}"
: "${INCLUDE_OFFICE:=false}"
: "${EDITION:=normal}"
: "${ISO_FILENAME:=hyggshi-os.iso}"
: "${WALLPAPER_URL:=}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/../kernel-tuning.sh"

DISTRO_LABEL="Arch Linux"
echo "===== Biến build đang dùng ====="
echo "DISTRO_NAME=$DISTRO_NAME | DISTRO_LABEL=$DISTRO_LABEL"
echo "EDITION=$EDITION | DE=$DE | ISO_FILENAME=$ISO_FILENAME"

echo "===== Cài archiso + công cụ build trên container archlinux:latest ====="
pacman -Sy --noconfirm --needed archiso git openssl >/dev/null

echo "===== Copy profile 'releng' gốc của archiso làm nền ====="
PROFILE_DIR="$REPO_ROOT/archlive"
rm -rf "$PROFILE_DIR" work out
cp -r /usr/share/archiso/configs/releng/ "$PROFILE_DIR"

echo "===== packages.x86_64: thêm gói theo DE/edition/branding ====="
# Gói base của releng đã có: base linux linux-firmware, mkinitcpio-archiso,
# networkmanager, grub, efibootmgr, dosfstools, squashfs-tools... — chỉ cần
# APPEND thêm, không ghi đè để không mất phần archiso cần cho live-boot.
{
  echo ""
  echo "# ===== Hyggshi OS: gói thêm theo DE/edition (build-arch-iso.sh) ====="
  case "$DE" in
    kde)
      printf '%s\n' plasma-desktop sddm konsole dolphin
      DISPLAY_MANAGER="sddm"
      ;;
    lxqt)
      printf '%s\n' lxqt sddm pcmanfm-qt qterminal featherpad lximage-qt lxqt-archiver pavucontrol-qt qps screengrab openbox obconf-qt
      DISPLAY_MANAGER="sddm"
      ;;
    gnome)
      printf '%s\n' gnome gdm gnome-terminal nautilus
      DISPLAY_MANAGER="gdm"
      ;;
    mate)
      printf '%s\n' mate mate-extra lightdm lightdm-gtk-greeter
      DISPLAY_MANAGER="lightdm"
      ;;
    cinnamon)
      printf '%s\n' cinnamon lightdm lightdm-gtk-greeter
      DISPLAY_MANAGER="lightdm"
      ;;
    *)
      printf '%s\n' xfce4 xfce4-goodies xfce4-terminal lightdm lightdm-gtk-greeter
      DISPLAY_MANAGER="lightdm"
      ;;
  esac

  case "$ICON_THEME" in
    numix)   echo "numix-icon-theme" ;;
    breeze)  echo "breeze-icons" ;;
    adwaita) echo "adwaita-icon-theme" ;;
    *)       echo "papirus-icon-theme" ;;
  esac

  [ "$INCLUDE_BROWSER" = "true" ] && echo "firefox"
  [ "$INCLUDE_OFFICE" = "true" ] && echo "libreoffice-fresh"

  SWAP_MODE_VAL="${HCL_SWAP_MODE:-${SWAP_MODE:-fixed}}"
  SWAP_MB_VAL="${HCL_SWAP_MB:-${SWAP_MB:-0}}"
  if [ "$SWAP_MODE_VAL" != "off" ] || [ "$EDITION" = "lite" ]; then
    echo "zram-generator"
  fi

  hyggshi_edition_packages_pacman "$EDITION"
} >> "$PROFILE_DIR/packages.x86_64"

SWAP_MODE_VAL="${HCL_SWAP_MODE:-${SWAP_MODE:-fixed}}"
SWAP_MB_VAL="${HCL_SWAP_MB:-${SWAP_MB:-0}}"
if [ "$SWAP_MODE_VAL" != "off" ] || [ "$EDITION" = "lite" ]; then
  mkdir -p "$PROFILE_DIR/airootfs/etc/systemd" "$PROFILE_DIR/airootfs/etc/modules-load.d"
  echo "zram" > "$PROFILE_DIR/airootfs/etc/modules-load.d/zram.conf"
  ZRAM_SIZE_SPEC="${SWAP_MB_VAL:-1024}"
  [ "$ZRAM_SIZE_SPEC" = "0" ] && ZRAM_SIZE_SPEC="min(ram / 2, 4096)"
  cat <<EOF > "$PROFILE_DIR/airootfs/etc/systemd/zram-generator.conf"
[zram0]
zram-size = $ZRAM_SIZE_SPEC
compression-algorithm = zstd
swap-priority = 100
EOF
fi

# Lưu DISPLAY_MANAGER ra file tạm để customize_airootfs.sh (chạy trong
# chroot riêng, không thấy biến shell của script này) đọc lại được.
echo "$DISPLAY_MANAGER" > "$PROFILE_DIR/airootfs/root/.hyggshi-display-manager"

echo "===== profiledef.sh: rebrand tên/label ISO ====="
sed -i "s/^iso_name=.*/iso_name=\"hyggshi-os\"/" "$PROFILE_DIR/profiledef.sh"
sed -i "s/^iso_label=.*/iso_label=\"HYGGSHI_OS\"/" "$PROFILE_DIR/profiledef.sh"
sed -i "s/^iso_publisher=.*/iso_publisher=\"$DISTRO_NAME <https:\/\/github.com\/Hyggshi-OS-Research-Technology>\"/" "$PROFILE_DIR/profiledef.sh"
sed -i "s/^iso_application=.*/iso_application=\"$DISTRO_NAME Live\/Rescue CD\"/" "$PROFILE_DIR/profiledef.sh"
sed -i "s/^install_dir=.*/install_dir=\"hyggshi\"/" "$PROFILE_DIR/profiledef.sh"

echo "===== Branding: wallpaper + rebrand os-release trong airootfs ====="
mkdir -p "$PROFILE_DIR/airootfs/usr/share/backgrounds/hyggshi"
WALLPAPER_FILE=$(find "$REPO_ROOT/iso-config/branding" -maxdepth 1 -iname "wallpaper.*" \
  \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" \) 2>/dev/null | head -n1)
if [ -z "$WALLPAPER_FILE" ] && [ -n "$WALLPAPER_URL" ]; then
  if curl -fsSL "$WALLPAPER_URL" -o /tmp/wallpaper-remote.png 2>/dev/null && [ -s /tmp/wallpaper-remote.png ]; then
    WALLPAPER_FILE=/tmp/wallpaper-remote.png
  fi
fi
if [ -n "$WALLPAPER_FILE" ]; then
  cp "$WALLPAPER_FILE" "$PROFILE_DIR/airootfs/usr/share/backgrounds/hyggshi/wallpaper.png"
else
  echo "⚠️  Không lấy được wallpaper — bỏ qua, giữ nền mặc định của DE."
fi

mkdir -p "$PROFILE_DIR/airootfs/etc"
cat <<EOF > "$PROFILE_DIR/airootfs/etc/os-release"
PRETTY_NAME="$DISTRO_NAME $HYGGSHI_VERSION_ID (dựa trên $DISTRO_LABEL)"
NAME="$DISTRO_NAME"
VERSION_ID="$HYGGSHI_VERSION_ID"
VERSION="$HYGGSHI_VERSION_ID ($DISTRO_LABEL)"
ID=hyggshios
ID_LIKE=arch
HOME_URL="https://github.com/Hyggshi-OS-Research-Technology"
SUPPORT_URL="https://github.com/Hyggshi-OS-Research-Technology/Hyggshi-OS/issues"
BUG_REPORT_URL="https://github.com/Hyggshi-OS-Research-Technology/Hyggshi-OS/issues"
EOF
printf "%s \\\\n \\\\l\n\n" "$DISTRO_NAME" > "$PROFILE_DIR/airootfs/etc/issue"
echo "Welcome to $DISTRO_NAME — built on $DISTRO_LABEL" > "$PROFILE_DIR/airootfs/etc/motd"
echo "$OS_HOSTNAME" > "$PROFILE_DIR/airootfs/etc/hostname"

echo "===== sysctl tuning theo edition (xem kernel-tuning.sh) ====="
mkdir -p "$PROFILE_DIR/airootfs/etc/sysctl.d"
hyggshi_sysctl_conf "$EDITION" > "$PROFILE_DIR/airootfs/etc/sysctl.d/99-hyggshi-tuning.conf"

echo "===== customize_airootfs.sh: user/timezone/service/autologin ====="
# Chạy 1 lần qua arch-chroot NGAY SAU pacstrap (trước khi mkarchiso đóng
# gói squashfs) — đây là chỗ duy nhất có đủ môi trường chroot thật để chạy
# useradd/systemctl enable (không thể làm bằng cách ghi file tĩnh như
# build-alpine.sh vì Arch cần systemctl preset đúng cách qua chroot).
cat <<CUSTOMEOF > "$PROFILE_DIR/airootfs/root/customize_airootfs.sh"
#!/usr/bin/env bash
set -e -u

DISPLAY_MANAGER="\$(cat /root/.hyggshi-display-manager 2>/dev/null || echo lightdm)"
rm -f /root/.hyggshi-display-manager

ln -sf "/usr/share/zoneinfo/$OS_TIMEZONE" /etc/localtime

echo "===== Tạo user mặc định cho live session ====="
useradd -m -G wheel,storage,power,network -s /bin/bash "$OS_USERNAME"
echo "$OS_USERNAME:$OS_PASSWORD" | chpasswd
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

echo "===== Bật NetworkManager + display manager ====="
systemctl enable NetworkManager.service
systemctl enable "\${DISPLAY_MANAGER}.service"

echo "===== Autologin cho live session ====="
case "\$DISPLAY_MANAGER" in
  sddm)
    mkdir -p /etc/sddm.conf.d
    cat <<EOF > /etc/sddm.conf.d/hyggshi-autologin.conf
[Autologin]
User=$OS_USERNAME
Session=$([ "$DE" = "kde" ] && echo plasma || echo lxqt)
EOF
    ;;
  gdm)
    mkdir -p /etc/gdm
    cat <<EOF > /etc/gdm/custom.conf
[daemon]
AutomaticLoginEnable = true
AutomaticLogin = $OS_USERNAME
EOF
    ;;
  *)
    mkdir -p /etc/lightdm/lightdm.conf.d
    cat <<EOF > /etc/lightdm/lightdm.conf.d/50-hyggshi-autologin.conf
[Seat:*]
autologin-user=$OS_USERNAME
autologin-user-timeout=0
autologin-session=$DE
EOF
    ;;
esac

echo "customize_airootfs.sh xong."
CUSTOMEOF
chmod +x "$PROFILE_DIR/airootfs/root/customize_airootfs.sh"

echo "===== mkarchiso: build ISO thật (native, không cần QEMU vì amd64) ====="
mkarchiso -v -w "$REPO_ROOT/work" -o "$REPO_ROOT/out" "$PROFILE_DIR"

OUT_ISO=$(find "$REPO_ROOT/out" -maxdepth 1 -iname "*.iso" | head -n1)
if [ -z "$OUT_ISO" ]; then
  echo "LỖI: mkarchiso báo xong nhưng không thấy file .iso nào trong out/." >&2
  ls -la "$REPO_ROOT/out" >&2 || true
  exit 1
fi
mv "$OUT_ISO" "$REPO_ROOT/$ISO_FILENAME"
ls -lh "$REPO_ROOT/$ISO_FILENAME"

echo "===== build-arch-iso.sh xong ====="
echo "LƯU Ý: bỏ qua fcitx5-unikey (gõ tiếng Việt) và calamares (graphical"
echo "installer) — cả 2 chỉ có trên AUR, mkarchiso không tự cài AUR package."
echo "ISO boot live được nhưng không có 2 tính năng này."
