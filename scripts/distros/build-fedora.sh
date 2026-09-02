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
: "${HYGGSHI_VERSION_ID:=1.0}"
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

# calamares (installer) — thường không có sẵn trong repo Fedora chính thức.
# Không để lỗi ở đây làm hỏng cả build — nếu thiếu thì ISO boot live được
# nhưng không có graphical installer.
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
    DNF_TARGET install @lxqt-desktop-environment sddm pcmanfm-qt qterminal featherpad lximage-qt lxqt-archiver pavucontrol-qt qps screengrab openbox obconf-qt || \
    DNF_TARGET install @lxqt-desktop-environment sddm pcmanfm-qt qterminal featherpad lximage-qt openbox
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
SWAP_MODE_VAL="${HCL_SWAP_MODE:-${SWAP_MODE:-fixed}}"
SWAP_MB_VAL="${HCL_SWAP_MB:-${SWAP_MB:-0}}"
if [ "$SWAP_MODE_VAL" != "off" ] || [ "$EDITION" = "lite" ]; then
  mkdir -p "$ROOTFS/etc/systemd" "$ROOTFS/etc/modules-load.d"
  echo "zram" > "$ROOTFS/etc/modules-load.d/zram.conf"
  ZRAM_SIZE_SPEC="${SWAP_MB_VAL:-1024}"
  [ "$ZRAM_SIZE_SPEC" = "0" ] && ZRAM_SIZE_SPEC="min(ram / 2, 4096)"
  ZRAM_ALGO="zstd"
  [ "$EDITION" = "lite" ] && ZRAM_ALGO="lz4"
  cat <<EOF > "$ROOTFS/etc/systemd/zram-generator.conf"
[zram0]
zram-size = $ZRAM_SIZE_SPEC
compression-algorithm = $ZRAM_ALGO
swap-priority = 100
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
PRETTY_NAME="$DISTRO_NAME $HYGGSHI_VERSION_ID (dựa trên $DISTRO_LABEL)"
NAME="$DISTRO_NAME"
VERSION_ID="$HYGGSHI_VERSION_ID"
VERSION="$HYGGSHI_VERSION_ID ($DISTRO_LABEL)"
ID=hyggshios
ID_LIKE=fedora
HOME_URL="https://github.com/Hyggshi-OS-Research-Technology"
SUPPORT_URL="https://github.com/Hyggshi-OS-Research-Technology/Hyggshi-OS/issues"
BUG_REPORT_URL="https://github.com/Hyggshi-OS-Research-Technology/Hyggshi-OS/issues"
EOF
echo "Welcome to $DISTRO_NAME — built on $DISTRO_LABEL" > "$ROOTFS/etc/motd"

echo "===== dracut: generate initramfs live (dmsquash-live) ====="
# BUG: gói "dracut" trên Fedora tự cài sẵn /usr/lib/dracut/dracut.conf.d/
# 99-hostonly.conf với nội dung "[[ $hostonly ]] || hostonly=yes" — nghĩa là
# MẶC ĐỊNH hostonly=yes trên mọi hệ Fedora, kể cả rootfs vừa dựng bằng
# --installroot ở trên. module-setup.sh của chính "90dmsquash-live" (dracut
# upstream) có check(): "[[ $hostonly ]] && return 1" — cố tình LOẠI BỎ
# module này khi hostonly đang bật (comment gốc: "a live host-only image
# doesn't really make a lot of sense"). Đây chính là nguyên nhân thật của
# "dracut[E]: Module 'dmsquash-live' cannot be installed." — không phải do
# thiếu dmsetup/device-mapper (đã cài đủ ở trên). Phải truyền --no-hostonly
# tường minh để dracut build một initramfs live tổng quát (không khoá theo
# phần cứng của container build), đúng như hướng dẫn build livecd chính
# thức của Fedora.
chroot "$ROOTFS" dracut -v --force --no-hostonly --add "dmsquash-live pollcdrom" \
  "/boot/initramfs-live-$KVER.img" "$KVER"

echo "===== Unmount /proc /sys /dev /run trước khi đóng gói squashfs ====="
cleanup_mounts
trap - EXIT

echo "===== Dọn sạch rác, cache và build artifacts trong rootfs trước khi đóng gói squashfs ====="
sudo rm -rf "$ROOTFS/tmp/"* "$ROOTFS/tmp/".[!.]* 2>/dev/null || true
sudo rm -rf "$ROOTFS/var/tmp/"* 2>/dev/null || true
sudo rm -rf "$ROOTFS/var/cache/dnf/"* "$ROOTFS/var/cache/yum/"* 2>/dev/null || true
sudo find "$ROOTFS/var/log" -type f -exec truncate -s 0 {} \; 2>/dev/null || true
sudo rm -rf "$ROOTFS/root/.cache/"* "$ROOTFS/home/"*/.cache/* 2>/dev/null || true

echo "===== Đóng gói rootfs thành squashfs ====="
mkdir -p live-build/image/live
# BUG (giống hệt bug đã fix ở iso.sh cho nhánh Debian): KHÔNG được loại trừ
# /boot khỏi squashfs bằng "-e boot". ISO live vẫn boot được nếu loại trừ (vì
# GRUB nạp /live/vmlinuz + /live/initrd trực tiếp từ ISO, không qua squashfs)
# — NHƯNG sau khi Calamares cài đặt (unpackfs chép squashfs này vào đĩa) thì
# /boot của hệ thống ĐÃ CÀI sẽ trống rỗng (không có vmlinuz-*/initramfs-*),
# khiến bootloader module của Calamares fail với kiểu lỗi "grub2-pc has no
# installation candidate" / thiếu file khi chạy grub2-mkconfig trong target.
# Giữ nguyên /boot trong squashfs để hệ thống sau khi cài có đủ file cho
# grub2-install/grub2-mkconfig.
MAX_COMP="${HCL_SQUASHFS_MAX_COMPRESSION:-${SQUASHFS_MAX_COMPRESSION:-}}"
if [ -z "$MAX_COMP" ] || [ "$MAX_COMP" = "false" ]; then
  if [ -f iso-config/config/config.ini ]; then
    MAX_COMP=$(grep -E '^[[:space:]]*squashfs-max-compression[[:space:]]*=' iso-config/config/config.ini 2>/dev/null | tail -n1 | tr -d ' "' | cut -d'=' -f2 | tr '[:upper:]' '[:lower:]' || echo "false")
  fi
fi
EXCLUDE_OPTS=(-wildcards -e "tmp/*" -e "tmp/.*" -e "var/tmp/*" -e "var/cache/dnf/*" -e "var/cache/yum/*" -e "root/.cache/*" -e "home/*/.cache/*")
if [ "${MAX_COMP:-false}" = "true" ]; then
  echo "squashfs-max-compression=true -> xz tối đa"
  mksquashfs "$ROOTFS" live-build/image/live/filesystem.squashfs -comp xz -b 1M -Xdict-size 100% -Xbcj x86 -processors "$(nproc)" "${EXCLUDE_OPTS[@]}"
else
  mksquashfs "$ROOTFS" live-build/image/live/filesystem.squashfs -comp xz -b 1M -Xdict-size 100% "${EXCLUDE_OPTS[@]}"
fi

VMLINUX_FILE=$(find "$ROOTFS/boot" -maxdepth 1 -type f -name 'vmlinuz-*' -printf '%T@ %p\n' \
  | sort -nr | head -n1 | cut -d' ' -f2-)
if [ -z "$VMLINUX_FILE" ]; then
  echo "LỖI: không tìm thấy kernel vmlinuz trong $ROOTFS/boot." >&2
  exit 1
fi
cp "$VMLINUX_FILE" live-build/image/live/vmlinuz
cp "$ROOTFS/boot/initramfs-live-$KVER.img" live-build/image/live/initrd

echo "===== Build bootable ISO with grub (dmsquash-live cmdline) ====="
# BUG: dracut's dmsquash-live-root.sh mặc định chỉ tìm squashfs tại
# "/LiveOS/squashfs.img" trên thiết bị boot (rd.live.dir mặc định "LiveOS",
# rd.live.squashimg mặc định "squashfs.img") — xem module-setup.sh của
# 90dmsquash-live upstream. Build này lại đóng gói squashfs ở
# "/live/filesystem.squashfs" (theo convention live-boot của Debian, không
# phải Fedora). Thiếu 2 tham số rd.live.dir/rd.live.squashimg bên dưới,
# dracut không bao giờ tìm thấy ảnh squashfs thật, cứ lặp lại chờ (initqueue
# poll) tới khi hết timeout — biểu hiện là hệ thống "đứng hình" ở
# "Job dev-mapper-live\x2drw.device/start running" cho tới khi hit timeout
# 50min (root_delay/rd.retry mặc định của dracut), không hề crash hay báo
# lỗi rõ ràng nào khác.
#
# BUG 2: rootfs dựng bằng "dnf --installroot" KHÔNG cài selinux-policy/
# selinux-policy-targeted (chỉ cài các gói tối thiểu ở trên), nhưng kernel
# Fedora vẫn bật SELinux mặc định lúc boot. Không có policy nào được nạp,
# mọi lệnh setxattr(security.selinux, ...) của systemd lên /dev đều bị
# kernel từ chối ("Unable to fix SELinux security context ... Permission
# denied") — dồn lại tới mức PID 1 không tạo nổi /dev cần thiết, dẫn tới
# "Failed to allocate manager object: Permission denied" và
# "Freezing execution." (boot chết cứng). Cách đúng đắn là cài
# selinux-policy-targeted + relabel, nhưng cho ISO live/test thế này, tắt
# hẳn SELinux bằng "selinux=0" ở kernel cmdline là đủ và đơn giản hơn nhiều.
KERNEL_CMDLINE_EXTRA=$(hyggshi_kernel_cmdline_extra "$EDITION")
mkdir -p live-build/image/boot/grub
cat <<EOF > live-build/image/boot/grub/grub.cfg
set timeout=10
set default=0
menuentry "$DISTRO_NAME Live" {
  linux /live/vmlinuz root=live:CDLABEL=HYGGSHI_OS rd.live.image rd.live.dir=live rd.live.squashimg=filesystem.squashfs selinux=0 $KERNEL_CMDLINE_EXTRA
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
