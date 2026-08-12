#!/bin/bash
hyggshi_sysctl_conf() {
  local edition="${1:-normal}"
  case "$edition" in
    developer)
      cat <<EOF
# Hyggshi OS — Developer
vm.swappiness = 10
vm.vfs_cache_pressure = 50
fs.inotify.max_user_watches = 524288
fs.file-max = 2097152
kernel.nmi_watchdog = 0
EOF
      ;;
    server)
      cat <<EOF
# Hyggshi OS — Server
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
# Hyggshi OS — Lite
vm.swappiness = 80
vm.vfs_cache_pressure = 50
vm.watermark_scale_factor = 200
kernel.nmi_watchdog = 0
EOF
      ;;
    *)
      cat <<EOF
# Hyggshi OS — Normal
vm.swappiness = 60
vm.vfs_cache_pressure = 100
EOF
      ;;
  esac
}

hyggshi_edition_packages_apt() {
  local edition="${1:-normal}"
  case "$edition" in
    developer) echo "build-essential git curl docker.io htop" ;;
    server)    echo "openssh-server htop" ;;
    lite)      echo "zram-tools" ;;
    *)         echo "" ;;
  esac
}

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

hyggshi_edition_services_mask() {
  local edition="${1:-normal}"
  case "$edition" in
    lite) printf '%s\n' bluetooth.service ModemManager.service avahi-daemon.service cups.service ;;
    *)    : ;;
  esac
}

hyggshi_kernel_cmdline_extra() {
  local edition="${1:-normal}"
  case "$edition" in
    server)    echo "quiet loglevel=3 systemd.show_status=0" ;;
    lite)      echo "quiet loglevel=1" ;;
    developer) echo "loglevel=7" ;;
    *)         echo "quiet splash" ;;
  esac
}
