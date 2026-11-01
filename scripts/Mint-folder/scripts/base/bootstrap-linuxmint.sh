#!/usr/bin/env bash
# Bootstrap the Hyggshi OS root filesystem from Linux Mint 22.3 Zena.
# Mint 22.3 is Ubuntu Noble based.
set -Eeuo pipefail
[ "${DEBUG_MODE:-false}" = "true" ] && set -x

: "${MINT_VERSION:=22.3}"
: "${MINT_CODENAME:=zena}"
: "${BASE_CODENAME:=noble}"
: "${MINT_MIRROR:=http://packages.linuxmint.com}"
: "${UBUNTU_MIRROR:=http://archive.ubuntu.com/ubuntu}"
: "${SECURITY_MIRROR:=http://security.ubuntu.com/ubuntu}"
: "${CHROOT_DIR:=build/chroot}"

mkdir -p "$CHROOT_DIR"

echo "===== Hyggshi OS base: Linux Mint ${MINT_VERSION} (${MINT_CODENAME}) ====="
echo "===== Ubuntu base: ${BASE_CODENAME} ====="

# Start from the Ubuntu base that Linux Mint 22.3 uses, then add Mint repositories.
sudo debootstrap --arch=amd64 --variant=minbase       "$BASE_CODENAME" "$CHROOT_DIR" "$UBUNTU_MIRROR/"

sudo mkdir -p "$CHROOT_DIR/dev/pts" "$CHROOT_DIR/run" "$CHROOT_DIR/sys" "$CHROOT_DIR/proc"
sudo mount --bind /dev "$CHROOT_DIR/dev"
sudo mount --bind /dev/pts "$CHROOT_DIR/dev/pts" || true
sudo mount --bind /run "$CHROOT_DIR/run"
sudo mount -t proc proc "$CHROOT_DIR/proc"
sudo mount -t sysfs sysfs "$CHROOT_DIR/sys"

sudo cp -L /etc/resolv.conf "$CHROOT_DIR/etc/resolv.conf"

sudo tee "$CHROOT_DIR/etc/apt/sources.list" >/dev/null <<EOF
deb ${UBUNTU_MIRROR} ${BASE_CODENAME} main restricted universe multiverse
deb ${UBUNTU_MIRROR} ${BASE_CODENAME}-updates main restricted universe multiverse
deb ${SECURITY_MIRROR} ${BASE_CODENAME}-security main restricted universe multiverse
EOF

sudo mkdir -p "$CHROOT_DIR/etc/apt/sources.list.d" "/tmp/hyggshi-mint-key"
sudo tee "$CHROOT_DIR/etc/apt/sources.list.d/official-package-repositories.list" >/dev/null <<EOF
deb [signed-by=/usr/share/keyrings/mint-archive-keyring.gpg] ${MINT_MIRROR} ${MINT_CODENAME} main upstream import backport
EOF

sudo chroot "$CHROOT_DIR" env DEBIAN_FRONTEND=noninteractive apt-get update || true
sudo chroot "$CHROOT_DIR" env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ca-certificates curl gnupg dirmngr

MINT_KEY_FPR="302F0738F465C1535761F965A6616109451BBBF2"
curl -fsSL "https://keyserver.ubuntu.com/pks/lookup?op=get&options=mr&search=0x${MINT_KEY_FPR}"       -o /tmp/mint-archive-key.asc
sudo cp /tmp/mint-archive-key.asc "$CHROOT_DIR/tmp/mint-archive-key.asc"
sudo mkdir -p "$CHROOT_DIR/usr/share/keyrings" "$CHROOT_DIR/root/.gnupg"
sudo chroot "$CHROOT_DIR" gpg --batch --yes --dearmor       -o /usr/share/keyrings/mint-archive-keyring.gpg       /tmp/mint-archive-key.asc
sudo rm -f "$CHROOT_DIR/tmp/mint-archive-key.asc" /tmp/mint-archive-key.asc

sudo chroot "$CHROOT_DIR" env DEBIAN_FRONTEND=noninteractive apt-get update

{
  echo "BASE_CODENAME=${BASE_CODENAME}"
  echo "BASE_DISTRO=linuxmint"
  echo "MINT_VERSION=${MINT_VERSION}"
  echo "MINT_CODENAME=${MINT_CODENAME}"
  echo "DISTRO_LABEL=Linux Mint ${MINT_VERSION} (${MINT_CODENAME})"
} >> "${GITHUB_ENV:-build/build.env}"

echo "===== Linux Mint rootfs ready ====="
