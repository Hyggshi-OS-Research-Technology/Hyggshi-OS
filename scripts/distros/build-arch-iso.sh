#!/bin/bash
# build-arch-iso.sh — build ISO Arch Linux (bootable) bằng `mkarchiso`
# sử dụng profile và công cụ từ thư mục Arch-folder ($ARCH_FOLDER, mặc định scripts/Arch-folder)
# được cấu hình trong [Arch-build] của iso-config/config/config.ini.
set -e
: "${HYGGSHI_VERSION_ID:=1.4.2}"
[ "$DEBUG_MODE" = "true" ] && set -x

: "${DISTRO_NAME:=Hyggshi OS}"
: "${OS_HOSTNAME:=hyggshi-os}"
: "${OS_TIMEZONE:=Asia/Ho_Chi_Minh}"
: "${OS_USERNAME:=hyggshi}"
: "${OS_PASSWORD:=hyggshi}"
: "${DE:=kde}"
: "${ICON_THEME:=papirus}"
: "${INCLUDE_BROWSER:=false}"
: "${INCLUDE_OFFICE:=false}"
: "${EDITION:=normal}"
: "${ISO_FILENAME:=hyggshi-os-kde-v1.4.2-arch.iso}"
: "${WALLPAPER_URL:=}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

DISTRO_LABEL="Arch Linux"
echo "===== Biến build đang dùng ====="
echo "DISTRO_NAME=$DISTRO_NAME | DISTRO_LABEL=$DISTRO_LABEL"
echo "EDITION=$EDITION | DE=$DE | ISO_FILENAME=$ISO_FILENAME"

# 1. Khởi tạo pacman keyring và cài đặt công cụ cần thiết
echo "===== Khởi tạo pacman keyring và cài archiso + build tools ====="
pacman-key --init
pacman-key --populate archlinux
pacman -Sy --noconfirm archlinux-keyring
pacman -Syu --noconfirm --needed archiso base-devel git grub dosfstools edk2-ovmf mtools libisoburn squashfs-tools sbsigntools openssl sudo rsync

# 2. Định vị thư mục Arch-folder
RAW_ARCH_FOLDER="${HCL_ARCH_FOLDER:-${ARCH_FOLDER:-scripts/Arch-folder}}"
CLEAN_ARCH_FOLDER="${RAW_ARCH_FOLDER#./}"
ARCH_FOLDER_PATH="$REPO_ROOT/$CLEAN_ARCH_FOLDER"

echo "===== Sử dụng cấu hình Arch từ $ARCH_FOLDER_PATH ====="
if [ ! -d "$ARCH_FOLDER_PATH/profile" ]; then
  echo "LỖI: Không tìm thấy profile archiso tại $ARCH_FOLDER_PATH/profile!" >&2
  exit 1
fi

PROFILE_DIR="$REPO_ROOT/archlive"
rm -rf "$PROFILE_DIR" work out
mkdir -p "$PROFILE_DIR"
cp -r "$ARCH_FOLDER_PATH/profile/"* "$PROFILE_DIR/"

# 3. Tạo user builder để biên dịch package bằng makepkg (không chạy được dưới quyền root)
id -u builder >/dev/null 2>&1 || useradd -m -s /bin/bash builder
echo 'builder ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/builder
chmod 0440 /etc/sudoers.d/builder

mkdir -p /opt/localrepo
chmod -R 777 /opt/localrepo

# 4. Biên dịch các gói Hyggshi nội bộ từ $ARCH_FOLDER_PATH/pkgs nếu có
if [ -d "$ARCH_FOLDER_PATH/pkgs" ]; then
  echo "===== Biên dịch các gói Hyggshi nội bộ từ $ARCH_FOLDER_PATH/pkgs ====="
  chown -R builder:builder "$ARCH_FOLDER_PATH/pkgs" 2>/dev/null || true
  for pkg in "$ARCH_FOLDER_PATH/pkgs"/*; do
    if [ -f "$pkg/PKGBUILD" ]; then
      pkgname=$(basename "$pkg")
      echo "==> Đang build: $pkgname..."
      (
        cd "$pkg"
        sudo -u builder makepkg -s -f --noconfirm --needed 2>&1 || true
        cp -f ./*.pkg.tar.zst /opt/localrepo/ 2>/dev/null || true
      )
    fi
  done
fi

# 5. Build Calamares từ AUR nếu có trong packages.x86_64
if grep -q "^calamares$" "$PROFILE_DIR/packages.x86_64" 2>/dev/null; then
  echo "===== Build Calamares (AUR) vào /opt/localrepo ====="
  sudo -u builder bash -c '
    rm -rf /home/builder/calamares
    git clone --depth 1 --branch calamares --single-branch https://github.com/archlinux/aur.git /home/builder/calamares 2>/dev/null || \
    git clone --depth 1 https://aur.archlinux.org/calamares.git /home/builder/calamares
    cd /home/builder/calamares
    makepkg -s -f --noconfirm --needed
  ' 2>&1 || echo "⚠️ Build Calamares AUR không thành công, sẽ bỏ qua nếu thiếu package."
  cp -f /home/builder/calamares/*.pkg.tar.zst /opt/localrepo/ 2>/dev/null || true
fi

rm -f /opt/localrepo/*-debug-*.pkg.tar.zst 2>/dev/null || true

# 6. Cập nhật database /opt/localrepo nếu có package
if ls /opt/localrepo/*.pkg.tar.zst >/dev/null 2>&1; then
  echo "===== Cập nhật database hyggshi.db cho /opt/localrepo ====="
  repo-add -n -R /opt/localrepo/hyggshi.db.tar.gz /opt/localrepo/*.pkg.tar.zst
  ln -sf hyggshi.db.tar.gz /opt/localrepo/hyggshi-local.db.tar.gz
  [ -f /opt/localrepo/hyggshi.files.tar.gz ] && ln -sf hyggshi.files.tar.gz /opt/localrepo/hyggshi-local.files.tar.gz || true
  ls -lh /opt/localrepo
else
  echo "⚠️ Không có package nào trong /opt/localrepo — tắt repo [hyggshi] và bỏ calamares khỏi packages.x86_64"
  sed -i '/^\[hyggshi\]/,+4d' "$PROFILE_DIR/pacman.conf" 2>/dev/null || true
  sed -i '/^calamares$/d' "$PROFILE_DIR/packages.x86_64" 2>/dev/null || true
fi

# 7. Lọc và chuẩn hóa packages.x86_64: chỉ giữ lại các gói thực sự có trên repo
echo "===== Kiểm tra và chuẩn hoá manifest packages.x86_64 ====="
pacman -Sql | sort -u > /tmp/available_pkgs.txt

CLEAN_PKGS="$PROFILE_DIR/packages.x86_64.clean"
> "$CLEAN_PKGS"
while IFS= read -r line || [ -n "$line" ]; do
  trimmed=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  if [ -z "$trimmed" ] || [[ "$trimmed" =~ ^# ]]; then
    echo "$line" >> "$CLEAN_PKGS"
    continue
  fi
  if grep -Fxq "$trimmed" /tmp/available_pkgs.txt; then
    echo "$trimmed" >> "$CLEAN_PKGS"
  else
    echo "⚠️  Gói '$trimmed' không tồn tại trong repository — bỏ qua để tránh lỗi pacstrap."
  fi
done < "$PROFILE_DIR/packages.x86_64"
mv "$CLEAN_PKGS" "$PROFILE_DIR/packages.x86_64"

# 8. Đảm bảo các file trong file_permissions (profiledef.sh) tồn tại
if [ ! -f "$PROFILE_DIR/airootfs/usr/local/bin/hyggshi-icons" ]; then
  mkdir -p "$PROFILE_DIR/airootfs/usr/local/bin"
  cat <<'EOF' > "$PROFILE_DIR/airootfs/usr/local/bin/hyggshi-icons"
#!/bin/sh
exit 0
EOF
  chmod +x "$PROFILE_DIR/airootfs/usr/local/bin/hyggshi-icons"
fi

# 9. Branding wallpaper từ iso-config nếu có
WALLPAPER_FILE=$(find "$REPO_ROOT/iso-config/branding" -maxdepth 1 -iname "wallpaper.*" \
  \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" \) 2>/dev/null | head -n1)
if [ -n "$WALLPAPER_FILE" ]; then
  mkdir -p "$PROFILE_DIR/airootfs/usr/share/backgrounds/hyggshi"
  cp -f "$WALLPAPER_FILE" "$PROFILE_DIR/airootfs/usr/share/backgrounds/hyggshi/wallpaper.png" 2>/dev/null || true
fi

# 10. Chạy mkarchiso để build ISO
echo "===== Chạy mkarchiso để build ISO Hyggshi OS Arch Edition ====="
mkarchiso -v -w "$REPO_ROOT/work" -o "$REPO_ROOT/out" "$PROFILE_DIR"

OUT_ISO=$(find "$REPO_ROOT/out" -maxdepth 1 -iname "*.iso" | head -n1)
if [ -z "$OUT_ISO" ]; then
  echo "LỖI: mkarchiso báo xong nhưng không thấy file .iso nào trong out/." >&2
  ls -la "$REPO_ROOT/out" >&2 || true
  exit 1
fi

mv "$OUT_ISO" "$REPO_ROOT/$ISO_FILENAME"
sha256sum "$REPO_ROOT/$ISO_FILENAME" > "$REPO_ROOT/$ISO_FILENAME.sha256"
ls -lh "$REPO_ROOT/$ISO_FILENAME" "$REPO_ROOT/$ISO_FILENAME.sha256"

echo "===== build-arch-iso.sh xong: ISO được tạo thành công từ $ARCH_FOLDER_PATH ====="
