#!/bin/bash
# build-fedora.sh — bootstrap + build ISO Fedora (bootable) bằng `dnf
# --installroot` (không cần debootstrap/pacstrap), chạy trong container
# fedora:latest --privileged (cần mount /proc /sys /dev để chroot: rpm %post
# scriptlet của systemd/glibc/kernel và dracut đều cần /proc để chạy đúng).
#
# THIẾT KẾ (khác Alpine, giống Debian hơn):
#   - Alpine dùng apk --root và tránh chroot vì apk hầu như không có %post
#     phức tạp. RPM/dnf thì ngược lại — %post của glibc, systemd, kernel...
#     thường cần /proc, /dev thật để chạy (ldconfig, systemd-machine-id-setup,
#     kernel-install...) nên ở đây PHẢI mount --bind + chroot như
#     build-debian.sh, không thể làm kiểu "cài thẳng vào --root" đơn thuần.
#   - LIVE-BOOT: Fedora có sẵn cơ chế chính chủ cho việc này — dracut với
#     module "dmsquash-live" (đúng công nghệ Fedora Live/Workstation ISO thật
#     dùng). Không cần tự viết initramfs bằng busybox như build-alpine.sh —
#     chỉ cần cài package "dracut-live" rồi generate lại initramfs với
#     --add "dmsquash-live pollcdrom" bên trong chroot.
set -e
[ "$DEBUG_MODE" = "true" ] && set -x

: "${DISTRO_NAME:=Hyggshi OS}"
: "${FEDORA_VERSION:=41}"
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
# shellcheck source=/dev/null
source "$SCRIPT_DIR/../kernel-tuning.sh"

DISTRO_LABEL="Fedora ${FEDORA_VERSION}"
echo "===== Biến build đang dùng ====="
echo "DISTRO_NAME=$DISTRO_NAME | DISTRO_LABEL=$DISTRO_LABEL"
echo "EDITION=$EDITION | DE=$DE | ISO_FILENAME=$ISO_FILENAME"

rm -rf live-build
mkdir -p live-build/chroot
# --installroot yêu cầu đường dẫn TUYỆT ĐỐI (dnf báo lỗi "Only absolute paths
# allowed" nếu truyền đường dẫn tương đối) — resolve bằng $(pwd) trước khi
# gán, không thể để "live-build/chroot" tương đối như các script apt/apk khác.
ROOTFS="$(pwd)/live-build/chroot"

echo "===== rpm --initdb: khởi tạo RPM DB trống trong rootfs đích ====="
rpm --root "$ROOTFS" --initdb

# --nogpgcheck: tránh dnf dừng lại chờ xác nhận import GPG key khi chạy
# non-interactive trong CI (giống tinh thần --allow-untrusted của
# build-alpine.sh) — đánh đổi hợp lý cho ISO build tự động, không phải cho
# hệ thống production cần verify chữ ký gói.
#
# --use-host-config: dnf5 (mặc định trên container fedora:41) đổi hành vi so
# với dnf4 — với --installroot vào 1 thư mục MỚI TINH (chưa có
# /etc/yum.repos.d riêng), nó không tự lấy repo của host nữa, báo thẳng
# "No matching repositories for *, *" thay vì fallback êm như dnf4. Phải
# truyền cờ này tường minh để dùng repo đã cấu hình sẵn của container host
# (image fedora:41 gốc) làm nguồn cài cho $ROOTFS.
DNF_TARGET() {
  dnf -y --use-host-config --releasever="$FEDORA_VERSION" --installroot="$ROOTFS" \
    --setopt=install_weak_deps=False --nogpgcheck "$@"
}

echo "===== dnf --installroot: bootstrap base rootfs + kernel + dracut-live ====="
# util-linux: cần cho dracut nói chung (logger — xem cảnh báo bên dưới).
# device-mapper: cung cấp dmsetup — dmsquash-live-root.sh (chạy lúc live-boot
# thật) gọi thẳng "dmsetup create live-rw", và module-setup.sh của
# dmsquash-live tự kiểm tra dmsetup có mặt trong rootfs TRƯỚC khi cho phép
# cài module — thiếu gói này là lý do thật sự đằng sau "Module 'dmsquash-live'
# cannot be installed." (dòng cảnh báo "/dev/log or logger" ngay phía trên nó
# trong log CHỈ là warning vô hại của chính dracut-logger, không phải nguyên
# nhân — xem dracut-logger.c, đã xác nhận qua nhiều báo lỗi tương tự trên
# GitHub/Bugzilla dùng dmsquash-live).
DNF_TARGET install glibc-minimal-langpack systemd systemd-udev passwd sudo \
  util-linux device-mapper NetworkManager kernel kernel-core dracut dracut-live \
  grub2-pc grub2-efi-x64 shim-x64 squashfs-tools

echo "===== Kiểm tra kernel image đã thực sự có trong /boot và /lib/modules ====="
KVER=$(basename "$(ls -d "$ROOTFS"/lib/modules/*/ 2>/dev/null | head -n1)")
if [ -z "$KVER" ] || ! ls "$ROOTFS"/boot/vmlinuz-* >/dev/null 2>&1; then
  echo "LỖI: dnf install kernel báo 'thành công' nhưng không thấy /boot/vmlinuz-* hoặc /lib/modules/<ver> trong rootfs." >&2
  echo "Nội dung /boot:" >&2
  ls -la "$ROOTFS/boot" >&2 || true
  exit 1
fi
echo "OK: kernel $KVER — $(ls "$ROOTFS"/boot/vmlinuz-* | head -n1)"

echo "===== Mount virtual filesystems cho chroot (rpm %post + dracut cần /proc /dev) ====="
mount --bind /dev "$ROOTFS/dev"
mount --bind /run "$ROOTFS/run"
mount -t proc  proc  "$ROOTFS/proc"
mount -t sysfs sysfs "$ROOTFS/sys"
# BẮT BUỘC: unmount trước khi mksquashfs, nếu không squashfs sẽ đóng luôn
# /proc /sys /dev /run THẬT của container host vào trong ảnh — file hệ thống
# đó không thuộc về ISO và có thể làm ISO không boot được hoặc phình dung
# lượng vô lý.
cleanup_mounts() {
  umount -R "$ROOTFS/dev" 2>/dev/null || true
  umount -R "$ROOTFS/run" 2>/dev/null || true
  umount "$ROOTFS/proc"   2>/dev/null || true
  umount "$ROOTFS/sys"    2>/dev/null || true
}
trap cleanup_mounts EXIT

# calamares — MỌI base phải có installer, giống Debian/Alpine. Có thể không
# có sẵn trong repo Fedora chính thức tuỳ version — không để lỗi ở đây làm
# hỏng cả build.
echo "===== Cài calamares (installer) ====="
DNF_TARGET install calamares || echo "CẢNH BÁO: gói calamares không có sẵn cho Fedora $FEDORA_VERSION — bỏ qua, ISO sẽ không có installer."

echo "===== Desktop environment: $DE (1 trong 6: xfce/kde/lxqt/gnome/mate/cinnamon) ====="
DISPLAY_MANAGER="lightdm"
case "$DE" in
  kde)
    DNF_TARGET install @kde-desktop-environment sddm konsole dolphin
    DISPLAY_MANAGER="sddm"
    ;;
  lxqt)
    DNF_TARGET install @lxqt-desktop-environment sddm pcmanfm-qt xterm
    DISPLAY_MANAGER="sddm"
    ;;
  gnome)
    DNF_TARGET install @gnome-desktop gdm gnome-terminal nautilus
    DISPLAY_MANAGER="gdm"
    ;;
  mate)
    DNF_TARGET install @mate-desktop-environment lightdm lightdm-gtk
    DISPLAY_MANAGER="lightdm"
    ;;
  cinnamon)
    DNF_TARGET install @cinnamon-desktop lightdm lightdm-gtk || \
      echo "CẢNH BÁO: cinnamon có thể chưa đóng gói đầy đủ trên Fedora $FEDORA_VERSION — kiểm tra lại."
    DISPLAY_MANAGER="lightdm"
    ;;
  *)
    DNF_TARGET install @xfce-desktop-environment xfce4-terminal lightdm lightdm-gtk
    DISPLAY_MANAGER="lightdm"
    ;;
esac

case "$ICON_THEME" in
  numix)   DNF_TARGET install numix-icon-theme-circle || true ;;
  breeze)  DNF_TARGET install breeze-icon-theme        || true ;;
  adwaita) DNF_TARGET install adwaita-icon-theme        || true ;;
  *)       DNF_TARGET install papirus-icon-theme        || true ;;
esac

[ "$INCLUDE_BROWSER" = "true" ] && { DNF_TARGET install firefox     || echo "CẢNH BÁO: cài firefox thất bại — bỏ qua."; }
[ "$INCLUDE_OFFICE" = "true" ]  && { DNF_TARGET install libreoffice  || echo "CẢNH BÁO: cài libreoffice thất bại — bỏ qua."; }

echo "===== Edition=$EDITION (kernel sysctl tuning + gói thêm — xem kernel-tuning.sh) ====="
mkdir -p "$ROOTFS/etc/sysctl.d"
hyggshi_sysctl_conf "$EDITION" > "$ROOTFS/etc/sysctl.d/99-hyggshi-tuning.conf"
EDITION_PKGS=$(hyggshi_edition_packages_dnf "$EDITION")
if [ -n "$EDITION_PKGS" ]; then
  echo "Gói thêm cho edition '$EDITION': $EDITION_PKGS"
  DNF_TARGET install $EDITION_PKGS || true
fi
# zram-generator (Fedora) dùng format ini khác hẳn /etc/default/zramswap của
# Debian (zram-tools) nên viết trực tiếp ở đây thay vì tái dùng
# hyggshi_zram_conf — cùng lý do lz4 cho máy yếu như bản Debian đã giải thích.
if [ "$EDITION" = "lite" ]; then
  mkdir -p "$ROOTFS/etc/systemd"
  cat <<EOF > "$ROOTFS/etc/systemd/zram-generator.conf"
[zram0]
zram-size = min(ram / 2, 4096)
compression-algorithm = lz4
EOF
fi

# Mask service nền không cần cho lite (đồng bộ với desktop.sh bên Debian).
for svc in $(hyggshi_edition_services_mask "$EDITION"); do
  echo "Mask service '$svc' cho edition '$EDITION'"
  chroot "$ROOTFS" systemctl mask "$svc" 2>/dev/null || true
done

echo "===== hostname / timezone ====="
echo "$OS_HOSTNAME" > "$ROOTFS/etc/hostname"
echo "127.0.1.1 $OS_HOSTNAME" >> "$ROOTFS/etc/hosts"
chroot "$ROOTFS" ln -sf "/usr/share/zoneinfo/$OS_TIMEZONE" /etc/localtime

echo "===== Tạo user mặc định cho live session (chroot thật, có /proc nên useradd/chpasswd chạy bình thường) ====="
chroot "$ROOTFS" useradd -m -G wheel -s /bin/bash "$OS_USERNAME" || true
# Pass credentials through stdin instead of interpolating them into a shell
# command. This accepts punctuation in a password without executing it.
{ set +x; } 2>/dev/null
printf '%s:%s\n' "$OS_USERNAME" "$OS_PASSWORD" | chroot "$ROOTFS" chpasswd
[ "$DEBUG_MODE" = "true" ] && set -x

echo "===== Bật service khởi động cùng hệ thống ====="
chroot "$ROOTFS" systemctl enable NetworkManager "$DISPLAY_MANAGER" || true

echo "===== Autologin cho live session ====="
case "$DE" in
  kde|lxqt)
    mkdir -p "$ROOTFS/etc/sddm.conf.d"
    cat <<EOF > "$ROOTFS/etc/sddm.conf.d/hyggshi-autologin.conf"
[Autologin]
User=$OS_USERNAME
Session=$([ "$DE" = "kde" ] && echo plasma || echo lxqt)
EOF
    ;;
  gnome)
    mkdir -p "$ROOTFS/etc/gdm"
    cat <<EOF > "$ROOTFS/etc/gdm/custom.conf"
[daemon]
AutomaticLoginEnable = true
AutomaticLogin = $OS_USERNAME
EOF
    ;;
  *)
    mkdir -p "$ROOTFS/etc/lightdm/lightdm.conf.d"
    cat <<EOF > "$ROOTFS/etc/lightdm/lightdm.conf.d/50-hyggshi-autologin.conf"
[Seat:*]
autologin-user=$OS_USERNAME
autologin-user-timeout=0
autologin-session=$DE
EOF
    ;;
esac

echo "===== Branding: wallpaper + rebrand os-release ====="
mkdir -p "$ROOTFS/usr/share/backgrounds/hyggshi"
WALLPAPER_FILE=$(find iso-config/branding -maxdepth 1 -iname "wallpaper.*" \
  \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" \) 2>/dev/null | head -n1)
if [ -z "$WALLPAPER_FILE" ] && [ -n "$WALLPAPER_URL" ]; then
  if curl -fsSL "$WALLPAPER_URL" -o /tmp/wallpaper-remote.png 2>/dev/null && [ -s /tmp/wallpaper-remote.png ]; then
    WALLPAPER_FILE=/tmp/wallpaper-remote.png
  fi
fi
if [ -n "$WALLPAPER_FILE" ]; then
  cp "$WALLPAPER_FILE" "$ROOTFS/usr/share/backgrounds/hyggshi/wallpaper.png"
else
  echo "⚠️  Không lấy được wallpaper — bỏ qua, giữ nền mặc định của DE."
fi

rm -f "$ROOTFS/etc/os-release"
cat <<EOF > "$ROOTFS/etc/os-release"
PRETTY_NAME="$DISTRO_NAME 1.0 (dựa trên $DISTRO_LABEL)"
NAME="$DISTRO_NAME"
VERSION_ID="1.0"
VERSION="1.0 ($DISTRO_LABEL)"
ID=hyggshios
ID_LIKE=fedora
HOME_URL="https://github.com/Hyggshi-OS-Research-Technology"
SUPPORT_URL="https://github.com/Hyggshi-OS-Research-Technology/Hyggshi-OS/issues"
BUG_REPORT_URL="https://github.com/Hyggshi-OS-Research-Technology/Hyggshi-OS/issues"
EOF
echo "Welcome to $DISTRO_NAME — built on $DISTRO_LABEL" > "$ROOTFS/etc/motd"

echo "===== dracut: generate initramfs live (dmsquash-live) ====="
chroot "$ROOTFS" dracut -v --force --add "dmsquash-live pollcdrom" \
  "/boot/initramfs-live-$KVER.img" "$KVER"

echo "===== Unmount /proc /sys /dev /run trước khi đóng gói squashfs ====="
cleanup_mounts
trap - EXIT

echo "===== Đóng gói rootfs thành squashfs ====="
mkdir -p live-build/image/live
mksquashfs "$ROOTFS" live-build/image/live/filesystem.squashfs -comp xz -e boot

VMLINUX_FILE=$(find "$ROOTFS/boot" -maxdepth 1 -type f -name 'vmlinuz-*' -printf '%T@ %p\n' \
  | sort -nr | head -n1 | cut -d' ' -f2-)
if [ -z "$VMLINUX_FILE" ]; then
  echo "LỖI: không tìm thấy kernel vmlinuz trong $ROOTFS/boot." >&2
  exit 1
fi
cp "$VMLINUX_FILE" live-build/image/live/vmlinuz
cp "$ROOTFS/boot/initramfs-live-$KVER.img" live-build/image/live/initrd

echo "===== Build bootable ISO with grub (dmsquash-live cmdline) ====="
KERNEL_CMDLINE_EXTRA=$(hyggshi_kernel_cmdline_extra "$EDITION")
mkdir -p live-build/image/boot/grub
cat <<EOF > live-build/image/boot/grub/grub.cfg
set timeout=10
set default=0
menuentry "$DISTRO_NAME Live" {
  linux /live/vmlinuz root=live:CDLABEL=HYGGSHI_OS rd.live.image $KERNEL_CMDLINE_EXTRA
  initrd /live/initrd
}
EOF

grub2-mkrescue -o "$ISO_FILENAME" live-build/image --compress=xz -- -volid "HYGGSHI_OS"
ls -lh "$ISO_FILENAME"

echo "===== build-fedora.sh xong ====="
echo "LƯU Ý: dùng dmsquash-live (dracut) — cùng công nghệ Fedora Live chính"
echo "chủ dùng, nên đáng tin hơn initramfs tự viết của build-alpine.sh, nhưng"
echo "VẪN CHƯA test trên phần cứng/VM thật — nếu ISO không boot vào desktop,"
echo "thêm 'rd.debug' vào kernel cmdline ở trên để xem log dracut chi tiết."
