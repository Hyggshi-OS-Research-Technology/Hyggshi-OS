#!/bin/bash
# build-arch.sh — bootstrap base rootfs cho Arch Linux (pacman, rolling release).
# Được `source` từ scripts/build.sh (không tự chạy độc lập) nên dùng chung
# shell/biến môi trường: ENABLE_KERNEL_TUNING, GITHUB_ENV, DEBUG_MODE...
#
# EXPERIMENTAL: Arch dùng pacman, KHÔNG dùng debootstrap/apt/dpkg — giống
# tình trạng của Alpine (xem build-alpine.sh). Nhánh này chỉ dựng base rootfs
# bằng bootstrap tarball chính thức của Arch. desktop.sh/branding.sh/iso.sh
# hiện tại gọi apt-get/dpkg/calamares/live-boot thẳng nên SẼ LỖI ở các bước
# sau nếu chạy nguyên pipeline với distro=arch — cần viết một bản
# arch-desktop.sh (pacman -S xfce4 lightdm ...) và arch-iso.sh (Arch dùng
# mkinitcpio thay vì update-initramfs, tên kernel/initrd khác
# linux-image-*/initrd.img-*, và archiso/grub thay vì live-boot) riêng thì
# mới chạy hết pipeline được. Coi đây là experimental/base-rootfs-only cho
# tới khi có 2 script đó.
set -e
[ "$DEBUG_MODE" = "true" ] && set -x

# Arch là rolling release, không có "version" như Debian/Ubuntu/Mint — chỉ có
# ngày snapshot của bootstrap tarball. Dùng "latest" trên mirror chính thức.
BASE_CODENAME="rolling"
MIRROR="https://geo.mirror.pkgbuild.com"
DISTRO_LABEL="Arch Linux (rolling, experimental — base rootfs only)"

echo "Sẽ build trên: $DISTRO_LABEL"
# Ghi ra $GITHUB_ENV để các step/script sau đọc được (dù desktop/branding/iso
# chưa hỗ trợ Arch, giữ cùng convention với các distro khác)
{
  echo "BASE_CODENAME=$BASE_CODENAME"
  echo "MIRROR=$MIRROR"
  echo "DISTRO_LABEL=$DISTRO_LABEL"
} >> "$GITHUB_ENV"

echo "===== Tải bootstrap tarball chính thức của Arch ====="
BOOTSTRAP_URL="$MIRROR/iso/latest/archlinux-bootstrap-x86_64.tar.zst"
curl -fsSL "$BOOTSTRAP_URL" -o /tmp/archlinux-bootstrap.tar.zst \
  || { echo "Tải bootstrap tarball thất bại: $BOOTSTRAP_URL"; exit 1; }

echo "===== Giải nén vào live-build/chroot ====="
# Tarball chính thức luôn có 1 thư mục gốc "root.x86_64/" bọc ngoài — dùng
# --strip-components=1 để nội dung đổ thẳng vào live-build/chroot, không lồng
# thêm 1 cấp thư mục con.
mkdir -p live-build/chroot
sudo tar --use-compress-program=unzstd --strip-components=1 \
  -xf /tmp/archlinux-bootstrap.tar.zst -C live-build/chroot

echo "===== Cấu hình mirrorlist + resolv.conf trong chroot ====="
cat <<EOF | sudo tee live-build/chroot/etc/pacman.d/mirrorlist > /dev/null
Server = $MIRROR/\$repo/os/\$arch
EOF
sudo cp /etc/resolv.conf live-build/chroot/etc/resolv.conf

echo "===== Tắt CheckSpace trong pacman.conf ====="
# BUG: pacman dùng statvfs để check dung lượng trống trước khi cài, nhưng
# trên overlayfs (chính là root filesystem của GitHub Actions runner khi
# chạy trong chroot) nó không xác định đúng được mount point của
# /var/cache/pacman/pkg -> báo nhầm "could not determine cachedir mount
# point" / "not enough free disk space" dù ổ đĩa runner còn hàng chục GB
# trống. Đây là vấn đề đã biết của pacman khi chạy trong container/chroot
# trên overlayfs, không phải do thật sự hết dung lượng. Tắt CheckSpace là
# cách khắc phục chuẩn (đánh đổi: mất cảnh báo sớm nếu THẬT SỰ hết đĩa —
# chấp nhận được vì runner luôn có >100GB trống).
sudo sed -i 's/^CheckSpace/#CheckSpace/' live-build/chroot/etc/pacman.conf

echo "===== Mount virtual filesystems for chroot ====="
sudo mount --bind /dev live-build/chroot/dev
sudo mount --bind /run live-build/chroot/run
sudo chroot live-build/chroot mount -t proc none /proc
sudo chroot live-build/chroot mount -t sysfs none /sys

echo "===== Khởi tạo pacman keyring + cài base/linux ====="
# BUG CŨ (Alpine) từng gặp: dirmngr không chạy được trong chroot rút gọn vì
# thiếu /dev/pts -> áp dụng luôn bài học đó ở đây: pacman-key cần gpg agent,
# nên phải chắc /dev đã bind-mount (đã làm ở trên) trước khi init keyring,
# nếu không sẽ lỗi kiểu "no such file or directory" ngầm khó hiểu.
sudo chroot live-build/chroot pacman-key --init
sudo chroot live-build/chroot pacman-key --populate archlinux

# LƯU Ý: chỉ định rõ "mkinitcpio" trong danh sách gói cài, KHÔNG để trống.
# "base"+"linux" cần một gói cung cấp initramfs (mkinitcpio/booster/dracut)
# nhưng đây là "virtual package" có nhiều provider -> nếu không chỉ định rõ,
# pacman sẽ dừng lại hỏi "Enter a number (default=1):" để chọn provider.
# --noconfirm tự trả lời prompt "Proceed with installation? [Y/n]" nhưng
# KHÔNG tự trả lời prompt chọn provider này -> build treo/chờ input vô thời
# hạn trên CI (không có TTY để gõ). Ghi rõ "mkinitcpio" loại bỏ luôn việc
# phải chọn.
sudo chroot live-build/chroot pacman -Sy --noconfirm --needed base linux linux-firmware mkinitcpio

echo "===== Unmount virtual filesystems ====="
sudo chroot live-build/chroot umount /proc || true
sudo chroot live-build/chroot umount /sys || true
sudo umount live-build/chroot/run || true
sudo umount live-build/chroot/dev || true

# ============================================================
# Tuỳ chỉnh thông số kernel (sysctl) — TÙY CHỌN, chỉ áp dụng khi
# ENABLE_KERNEL_TUNING=true. Đây là các giá trị mặc định hợp lý cho một live/
# desktop system (giảm swappiness, giảm cache pressure, tắt NMI watchdog để
# đỡ tốn 1 core lúc idle). KHÔNG đụng tới các thông số ảnh hưởng bảo mật
# (vd kernel.kptr_restrict, kernel.dmesg_restrict) — nếu cần siết bảo mật thì
# nên làm ở một file/step riêng, không trộn chung với tuning hiệu năng ở đây.
# ============================================================
if [ "$ENABLE_KERNEL_TUNING" = "true" ]; then
  echo "===== Ghi /etc/sysctl.d/99-hyggshi-tuning.conf (tuỳ chỉnh thông số kernel) ====="
  sudo mkdir -p live-build/chroot/etc/sysctl.d
  cat <<EOF | sudo tee live-build/chroot/etc/sysctl.d/99-hyggshi-tuning.conf > /dev/null
# Hyggshi OS — kernel tuning cho live/desktop system (áp dụng lúc boot qua
# systemd-sysctl). Đây chỉ là điểm khởi đầu hợp lý, không phải benchmark cho
# mọi phần cứng — chỉnh lại nếu chạy trên máy chủ/server workload khác.

# Ít ưu tiên swap hơn RAM cache khi còn RAM trống (mặc định 60, desktop
# thường mượt hơn ở mức thấp hơn vì tránh swap sớm khi vẫn còn RAM rảnh)
vm.swappiness = 10

# Giữ lại inode/dentry cache lâu hơn thay vì reclaim aggressive (mặc định
# 100), giúp thao tác file lặp lại (build, git...) nhanh hơn
vm.vfs_cache_pressure = 50

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
