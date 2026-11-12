#!/usr/bin/env bash
# Bootstrap Linux Mint into the caller's rootfs directory.
# Can be sourced by scripts/build.sh or run by Mint-folder's host builder.
set -Eeuo pipefail
[ "${DEBUG_MODE:-false}" = "true" ] && set -x

: "${MINT_VERSION:=22}"
: "${CHROOT_DIR:=live-build/chroot}"
: "${GITHUB_ENV:=live-build/build.env}"
: "${ARCH:=amd64}"
: "${MINT_MIRROR:=http://packages.linuxmint.com}"
if [ "$ARCH" = "arm64" ]; then
  : "${UBUNTU_MIRROR:=http://ports.ubuntu.com/ubuntu-ports}"
  : "${SECURITY_MIRROR:=http://ports.ubuntu.com/ubuntu-ports}"
else
  : "${UBUNTU_MIRROR:=http://archive.ubuntu.com/ubuntu}"
  : "${SECURITY_MIRROR:=http://security.ubuntu.com/ubuntu}"
fi

case "$MINT_VERSION" in
  22.3) DEFAULT_BASE_CODENAME="noble"; DEFAULT_MINT_CODENAME="zena" ;;
  22)   DEFAULT_BASE_CODENAME="noble"; DEFAULT_MINT_CODENAME="wilma" ;;
  21.3) DEFAULT_BASE_CODENAME="jammy"; DEFAULT_MINT_CODENAME="virginia" ;;
  21.2) DEFAULT_BASE_CODENAME="jammy"; DEFAULT_MINT_CODENAME="victoria" ;;
  *)
    echo "Phiên bản Linux Mint không hỗ trợ: $MINT_VERSION" >&2
    exit 1
    ;;
esac

: "${BASE_CODENAME:=$DEFAULT_BASE_CODENAME}"
: "${MINT_CODENAME:=$DEFAULT_MINT_CODENAME}"
DISTRO_LABEL="Linux Mint ${MINT_VERSION} (${MINT_CODENAME}, Ubuntu ${BASE_CODENAME})"

mkdir -p "$(dirname "$GITHUB_ENV")" "$CHROOT_DIR"
echo "===== Bootstrap $DISTRO_LABEL vào $CHROOT_DIR ====="
sudo debootstrap --arch="$ARCH" --variant=minbase \
  "$BASE_CODENAME" "$CHROOT_DIR" "$UBUNTU_MIRROR/"

sudo mkdir -p "$CHROOT_DIR/dev/pts" "$CHROOT_DIR/run" \
  "$CHROOT_DIR/sys" "$CHROOT_DIR/proc" "$CHROOT_DIR/usr/share/keyrings" \
  "$CHROOT_DIR/root/.gnupg" "$CHROOT_DIR/etc/apt/sources.list.d"
sudo chmod 0700 "$CHROOT_DIR/root/.gnupg"
mountpoint -q "$CHROOT_DIR/dev" || sudo mount --bind /dev "$CHROOT_DIR/dev"
mountpoint -q "$CHROOT_DIR/dev/pts" || sudo mount --bind /dev/pts "$CHROOT_DIR/dev/pts"
mountpoint -q "$CHROOT_DIR/run" || sudo mount --bind /run "$CHROOT_DIR/run"
sudo chroot "$CHROOT_DIR" mountpoint -q /proc || sudo chroot "$CHROOT_DIR" mount -t proc proc /proc
sudo chroot "$CHROOT_DIR" mountpoint -q /sys || sudo chroot "$CHROOT_DIR" mount -t sysfs sysfs /sys
sudo cp -L /etc/resolv.conf "$CHROOT_DIR/etc/resolv.conf"

sudo tee "$CHROOT_DIR/etc/apt/sources.list" >/dev/null <<EOF
deb ${UBUNTU_MIRROR} ${BASE_CODENAME} main restricted universe multiverse
deb ${UBUNTU_MIRROR} ${BASE_CODENAME}-updates main restricted universe multiverse
deb ${SECURITY_MIRROR} ${BASE_CODENAME}-security main restricted universe multiverse
EOF
sudo tee "$CHROOT_DIR/etc/apt/sources.list.d/official-package-repositories.list" >/dev/null <<EOF
deb [signed-by=/usr/share/keyrings/mint-archive-keyring.gpg] ${MINT_MIRROR} ${MINT_CODENAME} main upstream import backport
EOF

# The Ubuntu base has its own trusted key, so it can install GnuPG before the
# Mint archive key is added. Ignore the expected Mint NO_PUBKEY on this pass.
sudo chroot "$CHROOT_DIR" env DEBIAN_FRONTEND=noninteractive apt-get update || true
sudo chroot "$CHROOT_DIR" env DEBIAN_FRONTEND=noninteractive \
  apt-get install -y --no-install-recommends ca-certificates gnupg

MINT_KEY_FPR="302F0738F465C1535761F965A6616109451BBBF2"
MINT_KEY_ASC="$(mktemp)"
trap 'rm -f "$MINT_KEY_ASC"' EXIT
curl -fsSL "https://keyserver.ubuntu.com/pks/lookup?op=get&options=mr&search=0x${MINT_KEY_FPR}" \
  -o "$MINT_KEY_ASC" \
  || curl -fsSL "https://keys.openpgp.org/pks/lookup?op=get&options=mr&search=0x${MINT_KEY_FPR}" \
    -o "$MINT_KEY_ASC"
sudo install -m 0644 "$MINT_KEY_ASC" "$CHROOT_DIR/tmp/mint-archive-key.asc"
sudo chroot "$CHROOT_DIR" gpg --batch --yes --dearmor \
  -o /usr/share/keyrings/mint-archive-keyring.gpg /tmp/mint-archive-key.asc
sudo rm -f "$CHROOT_DIR/tmp/mint-archive-key.asc"

sudo chroot "$CHROOT_DIR" env DEBIAN_FRONTEND=noninteractive apt-get update

{
  echo "BASE_DISTRO=linuxmint"
  echo "BASE_CODENAME=$BASE_CODENAME"
  echo "MINT_VERSION=$MINT_VERSION"
  echo "MINT_CODENAME=$MINT_CODENAME"
  echo "DISTRO_LABEL=$DISTRO_LABEL"
} >> "$GITHUB_ENV"

echo "===== Linux Mint bootstrap complete ====="
