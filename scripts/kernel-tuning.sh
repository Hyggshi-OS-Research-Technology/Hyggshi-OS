#!/bin/bash
# kernel-tuning.sh — profile "Edition" dùng chung cho Debian (desktop.sh,
# chạy trong chroot) và Arch (build-arch-iso.sh, ghi thẳng vào airootfs).
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
vm.swappiness = 20
vm.vfs_cache_pressure = 75
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
    *)         echo "" ;;
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
