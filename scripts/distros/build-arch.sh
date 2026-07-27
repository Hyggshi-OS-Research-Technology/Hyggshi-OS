#!/bin/bash
# build-arch.sh — bootstrap base rootfs cho Arch Linux (pacman, rolling release).
# CHẠY BÊN TRONG CONTAINER `archlinux:latest` (xem job build-arch trong
# .github/workflows/Build-Hyggshi-OS-ISO.yml), KHÔNG chạy trên ubuntu-latest
# runner trần. Image archlinux:latest đã có sẵn pacman + keyring được
# populate lúc build image -> KHÔNG cần tự tải bootstrap tarball hay tự
# `pacman-key --init/--populate` như bản cũ. Job chạy trong container nên
# tiến trình đã là root sẵn, không cần `sudo`.
#
# EXPERIMENTAL: chỉ dựng base rootfs. desktop.sh/branding.sh/iso.sh hiện tại
# viết cho apt-get/dpkg (Debian/Ubuntu/Mint) nên SẼ LỖI nếu chạy tiếp sau
# bước này — cần arch-desktop.sh (pacman -S xfce4 lightdm ...) và
# arch-iso.sh (Arch dùng mkinitcpio thay vì update-initramfs, và cần hook
# archiso để boot từ squashfs/ISO — xem gói mkinitcpio-archiso) riêng thì
# mới chạy hết pipeline được.
set -e
[ "$DEBUG_MODE" = "true" ] && set -x

# Arch là rolling release, không có "version" như Debian/Ubuntu/Mint.
BASE_CODENAME="rolling"
DISTRO_LABEL="Arch Linux (rolling, native container build — experimental, base rootfs only)"

echo "Sẽ build trên: $DISTRO_LABEL"
{
  echo "BASE_CODENAME=$BASE_CODENAME"
  echo "DISTRO_LABEL=$DISTRO_LABEL"
} >> "$GITHUB_ENV"

echo "===== Tắt CheckSpace trong pacman.conf ====="
# Container vẫn chạy trên storage driver dạng overlay của Docker/runner, nên
# vẫn có thể dính bug cũ: pacman statvfs sai mount point của
# /var/cache/pacman/pkg -> báo nhầm "not enough free disk space". Tắt
# CheckSpace phòng ngừa trước, không đợi build fail rồi mới biết.
sed -i 's/^CheckSpace/#CheckSpace/' /etc/pacman.conf

echo "===== Cài arch-install-scripts (cung cấp pacstrap) ====="
pacman -Sy --noconfirm --needed arch-install-scripts

echo "===== Dựng base rootfs vào live-build/chroot bằng pacstrap ====="
# -c: dùng cache pacman của container (host) thay vì tạo cache riêng trong
# target -> khỏi tải lại gói nếu chạy lại nhiều lần trong cùng job.
# Chỉ định rõ "mkinitcpio" (không để pacman tự hỏi chọn provider initramfs
# giữa mkinitcpio/booster/dracut).
mkdir -p live-build/chroot
pacstrap -c live-build/chroot base linux linux-firmware mkinitcpio

# ============================================================
# Tuỳ chỉnh thông số kernel (sysctl) — TÙY CHỌN, chỉ áp dụng khi
# ENABLE_KERNEL_TUNING=true. Đây là các giá trị mặc định hợp lý cho một live/
# desktop system (giảm swappiness, giảm cache pressure, tắt NMI watchdog để
# đỡ tốn 1 core lúc idle). Đây là runtime kernel parameter qua sysctl, KHÔNG
# phải compile-time kernel config (CONFIG_PREEMPT, CONFIG_HZ, CONFIG_MODULES,
# CONFIG_BTRFS_FS...) — muốn đổi loại đó phải tự build/configure kernel
# riêng, sysctl không làm được. KHÔNG đụng tới các thông số ảnh hưởng bảo mật
# (vd kernel.kptr_restrict, kernel.dmesg_restrict) — nếu cần siết bảo mật thì
# nên làm ở một file/step riêng, không trộn chung với tuning hiệu năng ở đây.
# ============================================================
if [ "$ENABLE_KERNEL_TUNING" = "true" ]; then
  echo "===== Ghi /etc/sysctl.d/99-hyggshi-tuning.conf (tuỳ chỉnh thông số kernel) ====="
  mkdir -p live-build/chroot/etc/sysctl.d
  cat <<EOF > live-build/chroot/etc/sysctl.d/99-hyggshi-tuning.conf
# Hyggshi OS — kernel tuning cho live/desktop system (áp dụng lúc boot qua
# systemd-sysctl). Đây chỉ là điểm khởi đầu hợp lý, không phải benchmark cho
# mọi phần cứng — chỉnh lại nếu chạy trên máy chủ/server workload khác.

# Ít ưu tiên swap hơn RAM cache khi còn RAM trống (mặc định 60, desktop
# thường mượt hơn ở mức thấp hơn vì tránh swap sớm khi vẫn còn RAM rảnh)
vm.swappiness = 10

# Giữ lại inode/dentry cache lâu hơn thay vì reclaim aggressive (mặc định
# 100), giúp thao tác file lặp lại (build, git...) nhanh hơn
vm.vfs_cache_pressure = 50

# Tăng giới hạn inotify watches — mặc định 8192 hay không đủ cho IDE/editor
# theo dõi cây thư mục project lớn (VS Code, webpack watch...)
fs.inotify.max_user_watches = 524288

# Tắt NMI watchdog: tiết kiệm 1 core cho việc watchdog polling định kỳ,
# đánh đổi là mất khả năng NMI watchdog phát hiện hang cứng — chấp nhận được
# cho live/desktop ISO, KHÔNG khuyến khích cho server production.
kernel.nmi_watchdog = 0
EOF
  echo "Đã bật kernel tuning (ENABLE_KERNEL_TUNING=true)"
else
  echo "ENABLE_KERNEL_TUNING != true — bỏ qua bước tuỳ chỉnh thông số kernel."
fi

echo "===== pacstrap xong — CHƯA có desktop/branding/iso riêng cho Arch ====="
echo "===== build-arch.sh xong ====="
