#!/bin/bash
# build-linuxmint.sh — bootstrap base rootfs cho Linux Mint.
# Linux Mint không có mirror debootstrap riêng — nó được build trên nền
# Ubuntu, nên ta debootstrap Ubuntu base tương ứng rồi add thêm repo Mint
# lên trên (giống cách Mint thật sự được build).
# Được `source` từ scripts/build.sh (không tự chạy độc lập) nên dùng chung
# shell/biến môi trường: MINT_VERSION, GITHUB_ENV, DEBUG_MODE...
set -e
[ "$DEBUG_MODE" = "true" ] && set -x

case "$MINT_VERSION" in
  22)   BASE_CODENAME="noble"; MINT_CODENAME="wilma" ;;
  21.3) BASE_CODENAME="jammy"; MINT_CODENAME="virginia" ;;
  21.2) BASE_CODENAME="jammy"; MINT_CODENAME="victoria" ;;
  *)    BASE_CODENAME="noble"; MINT_CODENAME="wilma" ;;
esac
MIRROR="http://archive.ubuntu.com/ubuntu/"
DISTRO_LABEL="Linux Mint ${MINT_VERSION} (${MINT_CODENAME}, nền Ubuntu ${BASE_CODENAME})"

echo "Sẽ build trên: $DISTRO_LABEL"
# Ghi ra $GITHUB_ENV để các step/script sau (desktop.sh, branding.sh, iso.sh...) đọc được
{
  echo "BASE_CODENAME=$BASE_CODENAME"
  echo "MIRROR=$MIRROR"
  echo "MINT_CODENAME=$MINT_CODENAME"
  echo "DISTRO_LABEL=$DISTRO_LABEL"
} >> "$GITHUB_ENV"

echo "===== Debootstrap Ubuntu base (nền cho Mint) ====="
sudo debootstrap --arch=amd64 --variant=minbase \
  "$BASE_CODENAME" live-build/chroot "$MIRROR"

echo "===== Mount virtual filesystems for chroot ====="
sudo mount --bind /dev live-build/chroot/dev
sudo mount --bind /run live-build/chroot/run
sudo chroot live-build/chroot mount -t proc none /proc
sudo chroot live-build/chroot mount -t sysfs none /sys

echo "===== Configure APT sources inside chroot (Ubuntu base + repo Mint) ====="
sudo tee live-build/chroot/etc/apt/sources.list > /dev/null <<EOF
deb http://archive.ubuntu.com/ubuntu ${BASE_CODENAME} main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu ${BASE_CODENAME}-updates main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu ${BASE_CODENAME}-security main restricted universe multiverse
EOF
sudo mkdir -p live-build/chroot/etc/apt/sources.list.d
sudo tee live-build/chroot/etc/apt/sources.list.d/official-package-repositories.list > /dev/null <<EOF
deb http://packages.linuxmint.com ${MINT_CODENAME} main upstream import backport
EOF
sudo cp /etc/resolv.conf live-build/chroot/etc/resolv.conf

echo "===== Import Linux Mint APT signing key ====="
# BUG CŨ: URL https://www.linuxmint.com/mint-repository-keyring/mint-archive-keyring.gpg
# không tồn tại (404) -> curl -f fail -> rơi vào fallback "chroot ... apt-key",
# nhưng gnupg/gpgv CHƯA được cài BÊN TRONG chroot (chỉ apt-get install trên HOST),
# nên apt-key luôn "command not found", bị nuốt bởi `|| true`. Kết quả: repo Mint
# không có key hợp lệ -> `apt-get update` trong desktop.sh chết với NO_PUBKEY và
# (vì desktop.sh có `set -e`) làm hỏng toàn bộ build khi chọn distro=linuxmint.
#
# Fix: cài gnupg/dirmngr NGAY BÊN TRONG chroot (base Ubuntu key đã có sẵn từ
# debootstrap nên apt-get này chạy được), rồi dùng đúng fingerprint chính thức
# của Linux Mint signing key để tải trực tiếp từ keyserver vào 1 keyring riêng,
# tham chiếu qua signed-by (không dùng apt-key/global trust đã deprecated).
# LƯU Ý: apt-get update ở đây CHỈ để có gnupg/dirmngr cài từ repo Ubuntu
# base (đã có key sẵn từ debootstrap). Lúc này repo Mint trong
# sources.list.d ĐÃ được thêm nhưng CHƯA có key -> apt update sẽ luôn báo
# lỗi NO_PUBKEY/"is not signed" cho riêng repo Mint (exit code 100) dù các
# repo Ubuntu vẫn tải thành công. Vì set -e ở đầu file, nếu không có
# `|| true` ở đây thì toàn bộ build sẽ chết ngay tại đây, không bao giờ
# chạy tới đoạn import key bên dưới -> đây chính là lỗi build.
sudo chroot live-build/chroot apt-get update || true
sudo chroot live-build/chroot apt-get install -y --no-install-recommends gnupg dirmngr

# BUG CŨ #2: `gpg --recv-keys` gọi BÊN TRONG chroot cần dirmngr mở kết nối
# mạng ra keyserver, nhưng dirmngr không khởi động được trong chroot kiểu
# này (thiếu /dev/pts -> không tạo được socket/tempfile trong
# /root/.gnupg) -> luôn lỗi "No such file or directory" / "No dirmngr",
# bất kể thử keyserver nào. Vì set -e, cả 2 lần thử đều fail thì build chết.
#
# Fix: tải key ở dạng ASCII-armor bằng `curl` NGAY TRÊN HOST (không cần
# dirmngr, không chạy trong chroot), rồi chỉ dùng `gpg --dearmor` để đổi
# định dạng armor -> binary keyring. --dearmor thuần là convert định dạng,
# KHÔNG cần agent/dirmngr/mạng nên chạy được trong chroot bình thường.
MINT_KEY_FPR="302F0738F465C1535761F965A6616109451BBBF2"

# Tạo sẵn homedir gpg với quyền đúng (0700) — trong chroot rút gọn này gpg
# đôi khi không tự tạo được /root/.gnupg, gây lỗi "failed to create
# temporary file ... No such file or directory" ngay cả với --dearmor.
sudo mkdir -p live-build/chroot/root/.gnupg
sudo chroot live-build/chroot chmod 700 /root/.gnupg

curl -fsSL "https://keyserver.ubuntu.com/pks/lookup?op=get&options=mr&search=0x${MINT_KEY_FPR}" \
  -o /tmp/mint-archive-key.asc \
|| curl -fsSL "https://keys.openpgp.org/pks/lookup?op=get&options=mr&search=0x${MINT_KEY_FPR}" \
  -o /tmp/mint-archive-key.asc

sudo cp /tmp/mint-archive-key.asc live-build/chroot/tmp/mint-archive-key.asc
sudo chroot live-build/chroot gpg --batch --yes --dearmor \
  -o /usr/share/keyrings/mint-archive-keyring.gpg \
  /tmp/mint-archive-key.asc
sudo rm -f live-build/chroot/tmp/mint-archive-key.asc

sudo sed -i 's#^deb http://packages.linuxmint.com#deb [signed-by=/usr/share/keyrings/mint-archive-keyring.gpg] http://packages.linuxmint.com#' \
  live-build/chroot/etc/apt/sources.list.d/official-package-repositories.list

echo "===== Verify: apt update trong chroot phải sạch lỗi NO_PUBKEY ====="
sudo chroot live-build/chroot apt-get update

echo "===== build-linuxmint.sh xong ====="
