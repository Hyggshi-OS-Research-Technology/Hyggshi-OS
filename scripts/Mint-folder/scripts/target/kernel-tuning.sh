#!/bin/bash
# kernel-tuning.sh — profile "Edition" dùng chung cho Debian (desktop.sh,
# chạy trong chroot)
# Được `source`, KHÔNG tự chạy độc lập.
#
# EDITION hợp lệ: normal | developer | server | lite
#   - normal      : Desktop mặc định, không chỉnh gì đặc biệt.
#   - developer   : swappiness thấp, inotify watch cao (build/watch nhiều file),
#                   thêm build-essential/git/docker.
#   - server      : swappiness thấp, tối ưu network backlog, tắt hiệu ứng boot,
#                   thêm openssh-server.
#   - lite        : tối ưu cho máy yếu, package tối giản, boot bớt log.
#
# LƯU Ý: đây là kernel *runtime* parameter qua sysctl + boot cmdline, không
# phải compile-time kernel config (CONFIG_PREEMPT, CONFIG_HZ...) — muốn đổi
# loại đó phải tự build kernel riêng, sysctl/cmdline không làm được việc đó.

# In ra nội dung /etc/sysctl.d/99-hyggshi-tuning.conf theo edition.
hyggshi_sysctl_conf() {
  local edition="${1:-normal}"
  case "$edition" in
    developer)
      cat <<EOF
# Hyggshi OS — Edition: Developer
vm.swappiness = 10
vm.vfs_cache_pressure = 50
fs.inotify.max_user_watches = 524288
fs.file-max = 2097152
kernel.nmi_watchdog = 0
EOF
      ;;
    server)
      cat <<EOF
# Hyggshi OS — Edition: Server
vm.swappiness = 10
vm.vfs_cache_pressure = 50
fs.file-max = 2097152
net.core.somaxconn = 4096
net.ipv4.tcp_max_syn_backlog = 4096
kernel.nmi_watchdog = 0
EOF
      ;;
    lite)
      cat <<EOF
# Hyggshi OS — Edition: Lite
# Dùng chung với zram (xem hyggshi_edition_packages_apt) — swap là RAM nén,
# không phải disk, nên swappiness CAO (80) là đúng: đẩy trang ít dùng vào
# zram sớm để giải phóng RAM thật cho máy yếu, khác hẳn logic "swappiness
# thấp = tốt" áp dụng cho swap trên đĩa (developer/server ở trên).
vm.swappiness = 80
vm.vfs_cache_pressure = 50
vm.watermark_scale_factor = 200
kernel.nmi_watchdog = 0
EOF
      ;;
    *)
      cat <<EOF
# Hyggshi OS — Edition: Normal/Desktop
vm.swappiness = 60
vm.vfs_cache_pressure = 100
EOF
      ;;
  esac
}

# Gói apt thêm theo edition (Debian/Ubuntu/Mint) — cách nhau bằng dấu cách.
hyggshi_edition_packages_apt() {
  local edition="${1:-normal}"
  case "$edition" in
    developer) echo "build-essential git curl docker.io htop" ;;
    server)    echo "openssh-server htop" ;;
    lite)      echo "zram-tools" ;;
    *)         echo "" ;;
  esac
}

# /etc/default/zramswap cho edition lite — chỉ có ý nghĩa khi zram-tools đã
# được cài ở trên. ALGO=lz4 vì máy yếu thường CPU cũng yếu — lz4 nén/giải
# nén nhanh hơn zstd, đổi lấy tỉ lệ nén thấp hơn một chút (đúng hướng đánh
# đổi cho "lite"; normal/server mạnh hơn có thể chọn zstd để nén tốt hơn).
hyggshi_zram_conf() {
  local edition="${1:-normal}"
  case "$edition" in
    lite)
      cat <<EOF
ALGO=lz4
PERCENT=50
PRIORITY=100
EOF
      ;;
  esac
}

# Service systemd nên mask cho edition — giảm RAM nền + thời gian boot trên
# máy yếu. CHỈ áp dụng cho lite: developer/server có thể vẫn cần các service
# này cho việc khác, "mất tính năng để đổi lấy tốc độ" chỉ đúng mục tiêu lite.
hyggshi_edition_services_mask() {
  local edition="${1:-normal}"
  case "$edition" in
    lite) printf '%s\n' bluetooth.service ModemManager.service avahi-daemon.service cups.service ;;
    *)    : ;;
  esac
}

# Gói pacman thêm theo edition (Arch) — MỖI GÓI 1 DÒNG (packages.x86_64).
hyggshi_edition_packages_pacman() {
  local edition="${1:-normal}"
  case "$edition" in
    developer) printf '%s\n' base-devel git docker htop ;;
    server)    printf '%s\n' openssh htop ;;
    *)         : ;;
  esac
}

# Gói apk thêm theo edition (Alpine) — cách nhau bằng dấu cách.
hyggshi_edition_packages_apk() {
  local edition="${1:-normal}"
  case "$edition" in
    developer) echo "build-base git curl docker htop" ;;
    server)    echo "openssh htop" ;;
    *)         echo "" ;;
  esac
}

# Gói dnf thêm theo edition (Fedora) — cách nhau bằng dấu cách.
hyggshi_edition_packages_dnf() {
  local edition="${1:-normal}"
  case "$edition" in
    developer) echo "@development-tools git curl docker htop" ;;
    server)    echo "openssh-server htop" ;;
    lite)      echo "zram-generator" ;;
    *)         echo "" ;;
  esac
}

# Kernel boot cmdline (GRUB) thêm theo edition — kernel parameter thật sự,
# khác sysctl runtime ở trên.
hyggshi_kernel_cmdline_extra() {
  local edition="${1:-normal}"
  case "$edition" in
    server)    echo "quiet loglevel=3 systemd.show_status=0" ;;
    lite)      echo "quiet loglevel=1" ;;
    developer) echo "loglevel=7" ;;
    *)         echo "quiet splash" ;;
  esac
}
