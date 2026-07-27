#!/bin/bash
# build.sh — chuẩn bị base rootfs: resolve distro, debootstrap, mount, apt sources.
# Chạy trên HOST (runner), không chạy trong chroot.
set -e
[ "$DEBUG_MODE" = "true" ] && set -x

echo "===== Free up disk space ====="
sudo rm -rf /usr/share/dotnet /usr/local/lib/android /opt/ghc /opt/hostedtoolcache
sudo apt-get clean
df -h

echo "===== Install host build dependencies ====="
sudo apt-get update
sudo apt-get install -y \
  debootstrap squashfs-tools xorriso isolinux syslinux-efi \
  grub-pc-bin grub-efi-amd64-bin grub-common mtools dosfstools \
  live-boot live-boot-doc

echo "===== Resolve base distro (codename, mirror, apt template) ====="
case "$BASE_DISTRO" in
  debian)
    BASE_CODENAME="$DEBIAN_VERSION"
    MIRROR="http://deb.debian.org/debian/"
    SOURCES_TEMPLATE="debian"
    MINT_CODENAME=""
    DISTRO_LABEL="Debian ${BASE_CODENAME}"
    ;;
  ubuntu)
    BASE_CODENAME="$UBUNTU_VERSION"
    MIRROR="http://archive.ubuntu.com/ubuntu/"
    SOURCES_TEMPLATE="ubuntu"
    MINT_CODENAME=""
    DISTRO_LABEL="Ubuntu ${BASE_CODENAME}"
    ;;
  linuxmint)
    # Linux Mint không có mirror debootstrap riêng — nó được build trên nền
    # Ubuntu, nên ta debootstrap Ubuntu base tương ứng rồi add thêm repo Mint
    # lên trên (giống cách Mint thật sự được build).
    case "$MINT_VERSION" in
      22)   BASE_CODENAME="noble"; MINT_CODENAME="wilma" ;;
      21.3) BASE_CODENAME="jammy"; MINT_CODENAME="virginia" ;;
      21.2) BASE_CODENAME="jammy"; MINT_CODENAME="victoria" ;;
      *)    BASE_CODENAME="noble"; MINT_CODENAME="wilma" ;;
    esac
    MIRROR="http://archive.ubuntu.com/ubuntu/"
    SOURCES_TEMPLATE="mint"
    DISTRO_LABEL="Linux Mint ${MINT_VERSION} (${MINT_CODENAME}, nền Ubuntu ${BASE_CODENAME})"
    ;;
  alpine)
    # Alpine dùng apk + musl, KHÔNG dùng debootstrap/apt/dpkg. Nhánh này chỉ
    # build base rootfs bằng apk-tools-static. desktop.sh/branding.sh/iso.sh
    # hiện tại gọi apt-get/dpkg/calamares/live-boot thẳng nên SẼ LỖI ở các
    # bước sau nếu chạy nguyên với distro=alpine — cần viết bản
    # alpine-desktop.sh (apk add xfce4 lightdm ...) và alpine-iso.sh (Alpine
    # dùng mkinitfs/initramfs riêng, tên kernel/initrd khác linux-image-*/
    # initrd.img-*) riêng thì mới chạy hết pipeline được. Coi đây là
    # experimental/base-rootfs-only cho tới khi có 2 script đó.
    BASE_CODENAME="${ALPINE_VERSION:-v3.20}"
    MIRROR="https://dl-cdn.alpinelinux.org/alpine"
    SOURCES_TEMPLATE="alpine"
    MINT_CODENAME=""
    DISTRO_LABEL="Alpine Linux ${BASE_CODENAME} (experimental — base rootfs only)"
    ;;
  *)
    echo "Distro không hợp lệ: $BASE_DISTRO"
    exit 1
    ;;
esac

echo "Sẽ build trên: $DISTRO_LABEL"
# Ghi ra $GITHUB_ENV để các step/script sau (branding.sh, iso.sh...) đọc được
{
  echo "BASE_CODENAME=$BASE_CODENAME"
  echo "MIRROR=$MIRROR"
  echo "SOURCES_TEMPLATE=$SOURCES_TEMPLATE"
  echo "MINT_CODENAME=$MINT_CODENAME"
  echo "DISTRO_LABEL=$DISTRO_LABEL"
} >> "$GITHUB_ENV"

echo "===== Debootstrap / apk bootstrap base system ====="
mkdir -p live-build/chroot

if [ "$BASE_DISTRO" = "alpine" ]; then
  echo "===== Bootstrap Alpine bằng apk-tools-static (không có debootstrap cho Alpine) ====="
  APK_STATIC_PKG=$(curl -fsSL "$MIRROR/${BASE_CODENAME}/main/x86_64/" \
    | grep -o 'apk-tools-static-[0-9][^"]*\.apk' | sort -V | tail -n1)
  if [ -z "$APK_STATIC_PKG" ]; then
    echo "Không tìm được gói apk-tools-static trên $MIRROR/${BASE_CODENAME}/main/x86_64/"
    exit 1
  fi
  curl -fsSL "$MIRROR/${BASE_CODENAME}/main/x86_64/$APK_STATIC_PKG" -o /tmp/apk-tools-static.apk
  mkdir -p /tmp/apk-static-extract
  tar -xzf /tmp/apk-tools-static.apk -C /tmp/apk-static-extract
  sudo /tmp/apk-static-extract/sbin/apk.static \
    -X "$MIRROR/${BASE_CODENAME}/main" -X "$MIRROR/${BASE_CODENAME}/community" \
    -U --allow-untrusted --arch x86_64 \
    --root live-build/chroot --initdb add alpine-base openrc

  sudo mkdir -p live-build/chroot/etc/apk
  cat <<EOF | sudo tee live-build/chroot/etc/apk/repositories > /dev/null
$MIRROR/${BASE_CODENAME}/main
$MIRROR/${BASE_CODENAME}/community
EOF
  echo "===== apk bootstrap xong — CHƯA có desktop/branding/iso riêng cho Alpine ====="
else
  sudo debootstrap --arch=amd64 --variant=minbase \
    "$BASE_CODENAME" live-build/chroot "$MIRROR"
fi

if [ "$BASE_DISTRO" != "alpine" ]; then

echo "===== Mount virtual filesystems for chroot ====="
sudo mount --bind /dev live-build/chroot/dev
sudo mount --bind /run live-build/chroot/run
sudo chroot live-build/chroot mount -t proc none /proc
sudo chroot live-build/chroot mount -t sysfs none /sys

echo "===== Configure APT sources inside chroot ====="
case "$SOURCES_TEMPLATE" in
  debian)
    # non-free-firmware chỉ tồn tại từ Debian 12 (bookworm) trở đi.
    # bullseye (Debian 11) không có component này -> phải bỏ ra, nếu không
    # apt update sẽ lỗi 404/"Invalid" component ngay từ đầu.
    if [ "$BASE_CODENAME" = "bullseye" ]; then
      FIRMWARE_COMPONENT=""
    else
      FIRMWARE_COMPONENT="non-free-firmware"
    fi
    sudo tee live-build/chroot/etc/apt/sources.list > /dev/null <<EOF
deb http://deb.debian.org/debian ${BASE_CODENAME} main contrib non-free ${FIRMWARE_COMPONENT}
deb http://deb.debian.org/debian ${BASE_CODENAME}-updates main contrib non-free ${FIRMWARE_COMPONENT}
deb http://security.debian.org/debian-security ${BASE_CODENAME}-security main contrib non-free ${FIRMWARE_COMPONENT}
EOF
    ;;
  ubuntu)
    sudo tee live-build/chroot/etc/apt/sources.list > /dev/null <<EOF
deb http://archive.ubuntu.com/ubuntu ${BASE_CODENAME} main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu ${BASE_CODENAME}-updates main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu ${BASE_CODENAME}-security main restricted universe multiverse
EOF
    ;;
  mint)
    # base apt sources = Ubuntu tương ứng, cộng thêm repo chính thức của Mint
    sudo tee live-build/chroot/etc/apt/sources.list > /dev/null <<EOF
deb http://archive.ubuntu.com/ubuntu ${BASE_CODENAME} main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu ${BASE_CODENAME}-updates main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu ${BASE_CODENAME}-security main restricted universe multiverse
EOF
    sudo mkdir -p live-build/chroot/etc/apt/sources.list.d
    sudo tee live-build/chroot/etc/apt/sources.list.d/official-package-repositories.list > /dev/null <<EOF
deb http://packages.linuxmint.com ${MINT_CODENAME} main upstream import backport
EOF
    ;;
esac
sudo cp /etc/resolv.conf live-build/chroot/etc/resolv.conf

if [ "$BASE_DISTRO" = "linuxmint" ]; then
  echo "===== Import Linux Mint APT signing key ====="
  sudo apt-get install -y gnupg
  curl -fsSL https://www.linuxmint.com/mint-repository-keyring/mint-archive-keyring.gpg \
    | sudo tee live-build/chroot/usr/share/keyrings/mint-archive-keyring.gpg > /dev/null || \
    sudo chroot live-build/chroot apt-key adv --keyserver keyserver.ubuntu.com \
      --recv-keys 27DE097940FC9D0FDBDCC2404E163382636958F6 || true
  sudo sed -i 's#^deb http://packages.linuxmint.com#deb [signed-by=/usr/share/keyrings/mint-archive-keyring.gpg] http://packages.linuxmint.com#' \
    live-build/chroot/etc/apt/sources.list.d/official-package-repositories.list || true
fi

fi # end if BASE_DISTRO != alpine

echo "===== build.sh xong ====="
