#!/bin/bash
# build-alpine.sh — bootstrap + build ISO Alpine Linux (bootable) bằng
# `apk --root` (không cần debootstrap/pacstrap/mkarchiso), chạy NATIVE trong
# container alpine:latest (không cần chroot/qemu vì cùng kiến trúc amd64).
#
# BẢN CŨ: do lỗi copy-paste, file này từng chứa nguyên logic của
# build-arch-iso.sh (pacman/mkarchiso) — không chạy được trên container
# alpine vì không có pacman, và job build-alpine trước đây chỉ dừng ở bootstrap
# rootfs rồi đóng gói tarball (không có DE/calamares/ISO thật cho Alpine).
# Viết lại hoàn toàn từ đây.
#
# THIẾT KẾ:
#   - Cài package thẳng vào $ROOTFS bằng `apk add --root` — apk (khác apt/
#     debootstrap) không cần chroot để chạy postinst vì hầu hết gói Alpine
#     không có script cài đặt phức tạp phụ thuộc "đang chạy trong hệ thống
#     đích". Nhờ vậy KHÔNG cần mount --bind /dev /proc /sys + chroot như
#     build-debian.sh, cũng không cần container --privileged như build-arch.
#   - adduser/passwd/rc-update lẽ ra cần chạy "thật" bên trong rootfs đích,
#     nhưng ở đây ghi thẳng vào /etc/passwd,/etc/shadow,/etc/group và tạo
#     symlink runlevel thủ công (đó chính xác là những gì các lệnh đó làm
#     bên dưới) — tránh phải chroot, giữ job đơn giản, không cần --privileged.
#   - LIVE-BOOT: Alpine không có gói kiểu "live-boot" (Debian) hay archiso
#     (Arch) đóng gói sẵn cơ chế "boot 1 squashfs làm root + overlay tmpfs".
#     Ở đây tự dựng 1 initramfs tối giản bằng busybox-static + overlayfs,
#     mô phỏng cơ chế mà live-boot làm cho Debian. Phần init tự viết này
#     CHƯA test trên phần cứng/VM thật — coi là EXPERIMENTAL (xem cuối file).
set -e
: "${HYGGSHI_VERSION_ID:=1.0}"
[ "$DEBUG_MODE" = "true" ] && set -x

# ============================================================
# FIX: fallback default cho các biến bắt buộc, giống các script build-*.sh
# khác trong repo — không để rỗng lọt vào os-release/hostname/username...
# ============================================================
: "${DISTRO_NAME:=Hyggshi OS}"
: "${ALPINE_VERSION:=v3.20}"
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

DISTRO_LABEL="Alpine Linux ${ALPINE_VERSION}"
echo "===== Biến build đang dùng ====="
echo "DISTRO_NAME=$DISTRO_NAME | DISTRO_LABEL=$DISTRO_LABEL"
echo "EDITION=$EDITION | DE=$DE | ISO_FILENAME=$ISO_FILENAME"

ROOTFS="live-build/chroot"
rm -rf live-build alpine-initrd
mkdir -p "$ROOTFS/etc/apk"

case "$ALPINE_VERSION" in
  edge) REPO_TAG="edge" ;;
  *)    REPO_TAG="$ALPINE_VERSION" ;;
esac
MIRROR="https://dl-cdn.alpinelinux.org/alpine"
MAIN_REPO="$MIRROR/$REPO_TAG/main"
COMMUNITY_REPO="$MIRROR/$REPO_TAG/community"

cat <<EOF > "$ROOTFS/etc/apk/repositories"
$MAIN_REPO
$COMMUNITY_REPO
EOF

# apk_target — helper cài gói vào $ROOTFS, tránh lặp lại 4 tham số ở mọi
# lệnh cài gói bên dưới.
apk_target() {
  apk add --root "$ROOTFS" --initdb -U \
    --repository "$MAIN_REPO" --repository "$COMMUNITY_REPO" \
    --allow-untrusted "$@"
}

echo "===== apk --initdb: bootstrap base rootfs (native, không cần chroot) ====="
apk_target alpine-base linux-lts linux-firmware-none \
  openrc alpine-conf busybox-suid busybox-static shadow sudo doas \
  networkmanager wpa_supplicant tzdata eudev udev-init-scripts kmod \
  squashfs-tools

echo "===== Kiểm tra kernel image đã thực sự có trong /boot và /lib/modules ====="
KVER=$(basename "$(ls -d "$ROOTFS"/lib/modules/*/ 2>/dev/null | head -n1)")
if [ -z "$KVER" ] || ! ls "$ROOTFS"/boot/vmlinuz-lts >/dev/null 2>&1; then
  echo "LỖI: apk add linux-lts báo 'thành công' nhưng không thấy /boot/vmlinuz-lts hoặc /lib/modules/<ver> trong rootfs." >&2
  echo "Nội dung /boot:" >&2
  ls -la "$ROOTFS/boot" >&2 || true
  exit 1
fi
echo "OK: kernel $KVER — $(ls "$ROOTFS"/boot/vmlinuz-lts)"

# calamares (installer) — gói này thường không có sẵn trong repo Alpine
# (không được build sẵn cho mọi phiên bản). Không để lỗi ở đây làm hỏng
# cả build — nếu thiếu thì ISO sẽ boot live được nhưng không có graphical installer.
echo "===== Cài calamares (installer) ====="
apk_target calamares || echo "CẢNH BÁO: gói calamares không có sẵn cho $ALPINE_VERSION/community — bỏ qua, ISO sẽ không có installer."

echo "===== Desktop environment: $DE (1 trong 6: xfce/kde/lxqt/gnome/mate/cinnamon) ====="
DISPLAY_MANAGER="lightdm"
case "$DE" in
  kde)
    apk_target plasma-desktop sddm konsole dolphin
    DISPLAY_MANAGER="sddm"
    ;;
  lxqt)
    apk_target lxqt sddm pcmanfm-qt qterminal featherpad lximage-qt lxqt-archiver pavucontrol-qt qps screengrab openbox || \
    apk_target lxqt sddm pcmanfm-qt qterminal featherpad lximage-qt openbox
    DISPLAY_MANAGER="sddm"
    ;;
  gnome)
    apk_target gnome gdm gnome-terminal nautilus || \
      echo "CẢNH BÁO: 1 số gói gnome có thể không có/đổi tên trên $ALPINE_VERSION — kiểm tra lại."
    DISPLAY_MANAGER="gdm"
    ;;
  mate)
    apk_target mate mate-extra lightdm lightdm-gtk-greeter
    DISPLAY_MANAGER="lightdm"
    ;;
  cinnamon)
    apk_target cinnamon lightdm lightdm-gtk-greeter || \
      echo "CẢNH BÁO: cinnamon có thể chưa đóng gói đầy đủ trên Alpine — kiểm tra lại."
    DISPLAY_MANAGER="lightdm"
    ;;
  *)
    apk_target xfce4 xfce4-terminal lightdm lightdm-gtk-greeter
    DISPLAY_MANAGER="lightdm"
    ;;
esac

case "$ICON_THEME" in
  numix)   apk_target numix-icon-theme    || true ;;
  breeze)  apk_target breeze-icons        || true ;;
  adwaita) apk_target adwaita-icon-theme  || true ;;
  *)       apk_target papirus-icon-theme  || true ;;
esac

[ "$INCLUDE_BROWSER" = "true" ] && { apk_target firefox     || echo "CẢNH BÁO: cài firefox thất bại — bỏ qua."; }
[ "$INCLUDE_OFFICE" = "true" ]  && { apk_target libreoffice  || echo "CẢNH BÁO: cài libreoffice thất bại — bỏ qua."; }

echo "===== Edition=$EDITION (kernel sysctl tuning + gói thêm — xem kernel-tuning.sh) ====="
mkdir -p "$ROOTFS/etc/sysctl.d"
hyggshi_sysctl_conf "$EDITION" > "$ROOTFS/etc/sysctl.d/99-hyggshi-tuning.conf"
EDITION_PKGS=$(hyggshi_edition_packages_apk "$EDITION")
if [ -n "$EDITION_PKGS" ]; then
  echo "Gói thêm cho edition '$EDITION': $EDITION_PKGS"
  apk_target $EDITION_PKGS || true
fi

SWAP_MODE_VAL="${HCL_SWAP_MODE:-${SWAP_MODE:-fixed}}"
SWAP_MB_VAL="${HCL_SWAP_MB:-${SWAP_MB:-0}}"
if [ "$SWAP_MODE_VAL" != "off" ] || [ "$EDITION" = "lite" ]; then
  apk_target zram-init || true
  mkdir -p "$ROOTFS/etc/modules-load.d"
  echo "zram" > "$ROOTFS/etc/modules-load.d/zram.conf"
fi

echo "===== hostname / timezone ====="
echo "$OS_HOSTNAME" > "$ROOTFS/etc/hostname"
echo "127.0.1.1 $OS_HOSTNAME" >> "$ROOTFS/etc/hosts"
ln -sf "/usr/share/zoneinfo/$OS_TIMEZONE" "$ROOTFS/etc/localtime"
echo "$OS_TIMEZONE" > "$ROOTFS/etc/timezone"

echo "===== Tạo user mặc định cho live session (ghi thẳng passwd/shadow/group, không chroot) ====="
# LƯU Ý: không dùng `adduser`/`chpasswd` vì các lệnh đó thao tác trên
# /etc/passwd của HOST container, không hỗ trợ --root trỏ sang rootfs đích
# — phải tự ghi đúng định dạng dòng passwd/shadow/group. Mật khẩu băm bằng
# `openssl passwd -6` chạy trên HOST (không đụng tới rootfs đích), an toàn.
UID_NEW=1000
GID_NEW=1000
grep -q "^$OS_USERNAME:" "$ROOTFS/etc/passwd" 2>/dev/null || \
  echo "$OS_USERNAME:x:$UID_NEW:$GID_NEW:$OS_USERNAME:/home/$OS_USERNAME:/bin/ash" >> "$ROOTFS/etc/passwd"
grep -q "^$OS_USERNAME:" "$ROOTFS/etc/group" 2>/dev/null || \
  echo "$OS_USERNAME:x:$GID_NEW:" >> "$ROOTFS/etc/group"
sed -i "s/^wheel:x:10:.*/wheel:x:10:$OS_USERNAME/" "$ROOTFS/etc/group" 2>/dev/null || true

PASS_HASH=$(openssl passwd -6 "$OS_PASSWORD" 2>/dev/null || true)
if [ -n "$PASS_HASH" ]; then
  # xoá dòng shadow cũ của user này (nếu có, từ lần build trước) trước khi ghi lại
  sed -i "/^$OS_USERNAME:/d" "$ROOTFS/etc/shadow" 2>/dev/null || true
  echo "$OS_USERNAME:$PASS_HASH:19000:0:99999:7:::" >> "$ROOTFS/etc/shadow"
else
  echo "CẢNH BÁO: không tạo được password hash (thiếu 'openssl' trên host runner) — user sẽ không có mật khẩu; chỉ vào được qua autologin." >&2
fi
mkdir -p "$ROOTFS/home/$OS_USERNAME"
chown -R "$UID_NEW:$GID_NEW" "$ROOTFS/home/$OS_USERNAME" 2>/dev/null || true

echo "===== Bật service ở default/boot runlevel (symlink thủ công, tương đương rc-update add) ====="
mkdir -p "$ROOTFS/etc/runlevels/default" "$ROOTFS/etc/runlevels/boot" "$ROOTFS/etc/runlevels/sysinit"
enable_service() {
  local svc="$1" level="${2:-default}"
  if [ -e "$ROOTFS/etc/init.d/$svc" ]; then
    ln -sf "/etc/init.d/$svc" "$ROOTFS/etc/runlevels/$level/$svc"
  else
    echo "CẢNH BÁO: không thấy /etc/init.d/$svc trong rootfs — bỏ qua enable, kiểm tra lại tên gói/service." >&2
  fi
}
enable_service devfs sysinit
enable_service dmesg sysinit
enable_service hwdrivers sysinit
enable_service hostname boot
enable_service networking boot
enable_service networkmanager default
enable_service "$DISPLAY_MANAGER" default

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
ID_LIKE=alpine
HOME_URL="https://github.com/Hyggshi-OS-Research-Technology"
SUPPORT_URL="https://github.com/Hyggshi-OS-Research-Technology/Hyggshi-OS/issues"
BUG_REPORT_URL="https://github.com/Hyggshi-OS-Research-Technology/Hyggshi-OS/issues"
EOF
printf "%s \\n \\l\n\n" "$DISTRO_NAME" > "$ROOTFS/etc/issue"
echo "Welcome to $DISTRO_NAME — built on $DISTRO_LABEL" > "$ROOTFS/etc/motd"

echo "===== Dọn sạch rác, cache và build artifacts trong rootfs trước khi đóng gói squashfs ====="
sudo rm -rf "$ROOTFS/tmp/"* "$ROOTFS/tmp/".[!.]* 2>/dev/null || true
sudo rm -rf "$ROOTFS/var/tmp/"* 2>/dev/null || true
sudo rm -rf "$ROOTFS/var/cache/apk/"* 2>/dev/null || true
sudo find "$ROOTFS/var/log" -type f -exec truncate -s 0 {} \; 2>/dev/null || true
sudo rm -rf "$ROOTFS/root/.cache/"* "$ROOTFS/home/"*/.cache/* 2>/dev/null || true

echo "===== Đóng gói rootfs thành squashfs ====="
mkdir -p live-build/image/live
MAX_COMP="${HCL_SQUASHFS_MAX_COMPRESSION:-${SQUASHFS_MAX_COMPRESSION:-}}"
if [ -z "$MAX_COMP" ] || [ "$MAX_COMP" = "false" ]; then
  if [ -f iso-config/config/config.ini ]; then
    MAX_COMP=$(grep -E '^[[:space:]]*squashfs-max-compression[[:space:]]*=' iso-config/config/config.ini 2>/dev/null | tail -n1 | tr -d ' "' | cut -d'=' -f2 | tr '[:upper:]' '[:lower:]' || echo "false")
  fi
fi
EXCLUDE_OPTS=(-wildcards -e "tmp/*" -e "tmp/.*" -e "var/tmp/*" -e "var/cache/apk/*" -e "root/.cache/*" -e "home/*/.cache/*")
if [ "${MAX_COMP:-false}" = "true" ]; then
  echo "squashfs-max-compression=true -> xz tối đa"
  mksquashfs "$ROOTFS" live-build/image/live/filesystem.squashfs -comp xz -b 1M -Xdict-size 100% -Xbcj x86 -processors "$(nproc)" "${EXCLUDE_OPTS[@]}"
else
  mksquashfs "$ROOTFS" live-build/image/live/filesystem.squashfs -comp xz -b 1M -Xdict-size 100% "${EXCLUDE_OPTS[@]}"
fi

cp "$ROOTFS/boot/vmlinuz-lts" live-build/image/live/vmlinuz

# ============================================================
# EXPERIMENTAL: initramfs tự dựng (busybox-static + overlayfs) để boot
# squashfs ở trên làm live root — Alpine không có sẵn cơ chế kiểu
# "live-boot" (Debian)/archiso (Arch) cho việc này. CHƯA test trên phần
# cứng/VM thật. Nếu boot lỗi, đây là nơi đầu tiên cần soi log (thêm
# "debug" vào kernel cmdline để rớt vào shell cứu hộ nếu cần — busybox sh
# sẽ chạy được vì đã có trong initramfs).
# ============================================================
echo "===== Build initramfs tối giản (busybox + overlayfs, EXPERIMENTAL) ====="
INITRD_DIR="alpine-initrd"
mkdir -p "$INITRD_DIR"/bin "$INITRD_DIR"/dev "$INITRD_DIR"/proc "$INITRD_DIR"/sys \
  "$INITRD_DIR"/mnt/cdrom "$INITRD_DIR"/mnt/squash "$INITRD_DIR"/mnt/overlay \
  "$INITRD_DIR"/newroot "$INITRD_DIR"/lib/modules

cp "$ROOTFS/bin/busybox.static" "$INITRD_DIR/bin/busybox" 2>/dev/null || \
  cp "$ROOTFS/bin/busybox" "$INITRD_DIR/bin/busybox"
chmod +x "$INITRD_DIR/bin/busybox"
# FIX: `./bin/busybox --install` bị busybox từ chối với lỗi "is not an
# absolute path" — nó đòi hỏi cả binary lẫn thư mục đích đều là đường dẫn
# tuyệt đối, không chấp nhận đường dẫn tương đối dù đã `cd` đúng chỗ.
INITRD_ABS="$(cd "$INITRD_DIR" && pwd)"
"$INITRD_ABS/bin/busybox" --install -s "$INITRD_ABS/bin"

# Gom module (squashfs/overlay/isofs/loop) + phụ thuộc bằng modprobe --show-depends
# (không cần boot đúng kernel đó, modprobe hỗ trợ -d rootdir -S kver để "khô chạy").
for mod in loop isofs squashfs overlay; do
  DEPS=$(modprobe -d "$ROOTFS" -S "$KVER" --show-depends "$mod" 2>/dev/null | awk '{print $2}')
  for dep in $DEPS; do
    rel="${dep#/}"
    mkdir -p "$INITRD_DIR/$(dirname "$rel")"
    cp "$ROOTFS/$rel" "$INITRD_DIR/$rel" 2>/dev/null || \
      echo "CẢNH BÁO: không copy được module $rel vào initramfs — kiểm tra lại (boot có thể thiếu module này)."
  done
done

cat <<'INITEOF' > "$INITRD_DIR/init"
#!/bin/busybox sh
/bin/busybox mount -t proc none /proc
/bin/busybox mount -t sysfs none /sys
/bin/busybox mount -t devtmpfs none /dev 2>/dev/null || /bin/busybox mount -t tmpfs none /dev

for m in loop isofs squashfs overlay; do
  for f in $(/bin/busybox find /lib/modules -name "${m}.ko*" 2>/dev/null); do
    /bin/busybox insmod "$f" 2>/dev/null
  done
done

# Tìm thiết bị CD-ROM/USB chứa /live/filesystem.squashfs
for dev in /dev/sr0 /dev/sr1 /dev/sda1 /dev/sdb1 /dev/sdc1 /dev/vda1 /dev/vdb1; do
  [ -b "$dev" ] || continue
  /bin/busybox mount -o ro "$dev" /mnt/cdrom 2>/dev/null || continue
  [ -f /mnt/cdrom/live/filesystem.squashfs ] && break
  /bin/busybox umount /mnt/cdrom 2>/dev/null
done

if [ ! -f /mnt/cdrom/live/filesystem.squashfs ]; then
  echo "LỖI: không tìm thấy /live/filesystem.squashfs trên bất kỳ thiết bị nào." >/dev/console
  exec /bin/busybox sh
fi

/bin/busybox mount -t squashfs -o loop,ro /mnt/cdrom/live/filesystem.squashfs /mnt/squash
/bin/busybox mount -t tmpfs tmpfs /mnt/overlay
/bin/busybox mkdir -p /mnt/overlay/upper /mnt/overlay/work
/bin/busybox mount -t overlay overlay \
  -o lowerdir=/mnt/squash,upperdir=/mnt/overlay/upper,workdir=/mnt/overlay/work /newroot

/bin/busybox mount --move /proc /newroot/proc
/bin/busybox mount --move /sys /newroot/sys
/bin/busybox mount --move /dev /newroot/dev

exec /bin/busybox switch_root /newroot /sbin/init
INITEOF
chmod +x "$INITRD_DIR/init"

( cd "$INITRD_DIR" && find . | cpio -o -H newc 2>/dev/null | gzip -9 ) > live-build/image/live/initrd

echo "===== Build bootable ISO with grub ====="
KERNEL_CMDLINE_EXTRA=$(hyggshi_kernel_cmdline_extra "$EDITION")
mkdir -p live-build/image/boot/grub
cat <<EOF > live-build/image/boot/grub/grub.cfg
set timeout=10
set default=0
menuentry "$DISTRO_NAME Live" {
  linux /live/vmlinuz $KERNEL_CMDLINE_EXTRA
  initrd /live/initrd
}
EOF

grub-mkrescue -o "$ISO_FILENAME" live-build/image --compress=xz -- -volid "HYGGSHI_OS"
ls -lh "$ISO_FILENAME"

echo "===== build-alpine.sh xong ====="
echo "LƯU Ý: phần initramfs live-boot (busybox+overlayfs) là tự viết, CHƯA"
echo "được kiểm chứng trên phần cứng/VM thật — nếu ISO không boot được vào"
echo "desktop, thêm 'debug' vào kernel cmdline (grub.cfg ở trên) để rớt vào"
echo "busybox sh cứu hộ và kiểm tra log trước khi báo lỗi."
