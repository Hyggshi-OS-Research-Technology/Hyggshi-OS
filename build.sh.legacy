#!/bin/bash
# ============================================================
#  Hyggshi OS - Live ISO Build Script
#  Base: Debian Bookworm | DE: KDE Plasma | DM: SDDM
#  Bootloader: isolinux (BIOS only)
# ============================================================
set -e

# ---- Config ------------------------------------------------
OS_NAME="Hyggshi OS"
OS_VERSION="1.0"
DEFAULT_USER="hyggshi"
DEFAULT_PASS="hyggshi"
HOSTNAME="hyggshi-os"
DEBIAN_MIRROR="http://deb.debian.org/debian"
DEBIAN_SUITE="bookworm"

BUILD_DIR="/build"
CHROOT="$BUILD_DIR/chroot"
IMAGE="$BUILD_DIR/image"
OUTPUT_ISO="$BUILD_DIR/hyggshi-os.iso"

# Colors
RED='\033[0;31m'
GRN='\033[0;32m'
YEL='\033[1;33m'
BLU='\033[0;34m'
NC='\033[0m'

step() { echo -e "\n${BLU}==> ${GRN}$1${NC}"; }
warn() { echo -e "${YEL}[WARN] $1${NC}"; }
die()  { echo -e "${RED}[ERR] $1${NC}"; exit 1; }

# ---- Cleanup trap ------------------------------------------
cleanup() {
    warn "Cleaning up mounts (if any)..."
    for mp in dev/pts dev run proc sys; do
        mountpoint -q "$CHROOT/$mp" 2>/dev/null && umount "$CHROOT/$mp" || true
    done
}
trap cleanup EXIT

# ---- Pre-flight checks -------------------------------------
[ "$(id -u)" -eq 0 ] || die "Run as root (use --privileged in Docker)"
command -v debootstrap >/dev/null || die "debootstrap not found"
command -v mksquashfs  >/dev/null || die "squashfs-tools not found"
command -v xorriso     >/dev/null || die "xorriso not found"

mkdir -p "$CHROOT" "$IMAGE/live" "$IMAGE/isolinux"

# ============================================================
step "[1/6] Debootstrap Debian $DEBIAN_SUITE..."
# ============================================================
if [ -f "$CHROOT/etc/debian_version" ]; then
    warn "Chroot already exists, skipping debootstrap (delete $CHROOT to rebuild)"
else
    debootstrap --arch=amd64 "$DEBIAN_SUITE" "$CHROOT" "$DEBIAN_MIRROR"
fi

# ============================================================
step "[2/6] Mounting virtual filesystems..."
# ============================================================
mount --bind /dev      "$CHROOT/dev"
mount --bind /run      "$CHROOT/run"
mount -t proc  proc    "$CHROOT/proc"
mount -t sysfs sysfs   "$CHROOT/sys"
mount -t devpts devpts "$CHROOT/dev/pts"

# ============================================================
step "[3/6] Installing packages inside chroot..."
# ============================================================
chroot "$CHROOT" /bin/bash -c "
set -e
export DEBIAN_FRONTEND=noninteractive

apt-get update

# Kernel + live-boot
apt-get install -y \
    linux-image-amd64 \
    live-boot \
    live-boot-initramfs-tools \
    systemd-sysv \
    --no-install-recommends

# KDE Plasma (minimal)
apt-get install -y \
    kde-plasma-desktop \
    sddm \
    konsole \
    dolphin \
    kate \
    --no-install-recommends

# Networking & utilities
apt-get install -y \
    network-manager \
    network-manager-gnome \
    sudo \
    nano \
    curl \
    wget \
    bash-completion \
    --no-install-recommends

# Fonts & locale
apt-get install -y \
    locales \
    fonts-noto \
    --no-install-recommends

echo 'en_US.UTF-8 UTF-8' > /etc/locale.gen
locale-gen
update-locale LANG=en_US.UTF-8

# Create default user
useradd -m -s /bin/bash $DEFAULT_USER
echo '$DEFAULT_USER:$DEFAULT_PASS' | chpasswd
usermod -aG sudo,audio,video,netdev $DEFAULT_USER

# Auto-login with SDDM
mkdir -p /etc/sddm.conf.d
cat > /etc/sddm.conf.d/autologin.conf << 'SDDMEOF'
[Autologin]
User=$DEFAULT_USER
Session=plasma
SDDMEOF

# Hostname
echo '$HOSTNAME' > /etc/hostname
cat > /etc/hosts << 'HOSTSEOF'
127.0.0.1   localhost
127.0.1.1   $HOSTNAME
::1         localhost ip6-localhost ip6-loopback
HOSTSEOF

# Enable services
systemctl enable sddm
systemctl enable NetworkManager

# OS branding
mkdir -p /etc/hyggshi
cat > /etc/os-release << 'OSEOF'
PRETTY_NAME=\"$OS_NAME $OS_VERSION\"
NAME=\"$OS_NAME\"
VERSION_ID=\"$OS_VERSION\"
VERSION=\"$OS_VERSION (Bookworm)\"
ID=hyggshi
ID_LIKE=debian
HOME_URL=\"https://hyggshi-os-website.pages.dev\"
SUPPORT_URL=\"https://github.com/Hyggshi-OS-project-center\"
OSEOF

# Clean up
apt-get autoremove -y
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
"

# ============================================================
step "[4/6] Unmounting virtual filesystems..."
# ============================================================
umount "$CHROOT/dev/pts"
umount "$CHROOT/dev"
umount "$CHROOT/run"
umount "$CHROOT/proc"
umount "$CHROOT/sys"

# ============================================================
step "[5/6] Creating squashfs + copying kernel/initrd..."
# ============================================================
echo "  Building squashfs (this takes a while)..."
mksquashfs "$CHROOT" "$IMAGE/live/filesystem.squashfs" \
    -e boot \
    -comp xz \
    -b 1M \
    -noappend \
    -no-progress 2>/dev/null

# Pick latest kernel & initrd
KERNEL=$(ls "$CHROOT/boot/vmlinuz-"* 2>/dev/null | sort -V | tail -1)
INITRD=$(ls "$CHROOT/boot/initrd.img-"* 2>/dev/null | sort -V | tail -1)

[ -f "$KERNEL" ] || die "Kernel not found in $CHROOT/boot/"
[ -f "$INITRD" ] || die "initrd not found in $CHROOT/boot/"

cp "$KERNEL" "$IMAGE/live/vmlinuz"
cp "$INITRD" "$IMAGE/live/initrd.img"

echo "  Kernel : $KERNEL"
echo "  Initrd : $INITRD"
echo "  Squashfs: $(du -sh $IMAGE/live/filesystem.squashfs | cut -f1)"

# ============================================================
step "[6/6] Building ISO with isolinux (BIOS)..."
# ============================================================
ISOLINUX_BIN="/usr/lib/ISOLINUX/isolinux.bin"
ISOHDPFX_BIN="/usr/lib/ISOLINUX/isohdpfx.bin"
MODULES_DIR="/usr/lib/syslinux/modules/bios"

[ -f "$ISOLINUX_BIN" ] || die "isolinux.bin not found — is isolinux package installed?"
[ -f "$ISOHDPFX_BIN" ] || die "isohdpfx.bin not found"

cp "$ISOLINUX_BIN"         "$IMAGE/isolinux/"
cp "$ISOHDPFX_BIN"         "$IMAGE/isolinux/"
cp "$MODULES_DIR/ldlinux.c32"  "$IMAGE/isolinux/" 2>/dev/null || true
cp "$MODULES_DIR/libcom32.c32" "$IMAGE/isolinux/" 2>/dev/null || true
cp "$MODULES_DIR/libutil.c32"  "$IMAGE/isolinux/" 2>/dev/null || true
cp "$MODULES_DIR/menu.c32"     "$IMAGE/isolinux/" 2>/dev/null || true
cp "$MODULES_DIR/vesamenu.c32" "$IMAGE/isolinux/" 2>/dev/null || true

cat > "$IMAGE/isolinux/isolinux.cfg" << EOF
UI menu.c32
PROMPT 0
TIMEOUT 50

MENU TITLE $OS_NAME $OS_VERSION

LABEL live
  MENU LABEL Start $OS_NAME (Live)
  KERNEL /live/vmlinuz
  APPEND initrd=/live/initrd.img boot=live components quiet splash

LABEL live-debug
  MENU LABEL Start $OS_NAME (Debug / no splash)
  KERNEL /live/vmlinuz
  APPEND initrd=/live/initrd.img boot=live components

LABEL memtest
  MENU LABEL --
EOF

xorriso -as mkisofs \
    -o "$OUTPUT_ISO" \
    -isohybrid-mbr "$ISOHDPFX_BIN" \
    -c isolinux/boot.cat \
    -b isolinux/isolinux.bin \
    -no-emul-boot \
    -boot-load-size 4 \
    -boot-info-table \
    -V "HYGGSHI_OS" \
    "$IMAGE"

# ============================================================
echo ""
echo -e "${GRN}╔══════════════════════════════════════════╗${NC}"
echo -e "${GRN}║  ✅  BUILD SUCCESSFUL!                   ║${NC}"
echo -e "${GRN}╚══════════════════════════════════════════╝${NC}"
echo ""
echo "  ISO : $OUTPUT_ISO"
echo "  Size: $(du -sh $OUTPUT_ISO | cut -f1)"
echo ""
echo "  Test with QEMU:"
echo "  qemu-system-x86_64 -m 2048 -cdrom $OUTPUT_ISO -boot d -vga virtio -enable-kvm"
echo ""
