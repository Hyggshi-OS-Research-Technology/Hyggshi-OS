#!/bin/bash
# desktop.sh — cài package cơ bản, DE (xfce/kde), user, hostname/timezone.
# Chạy BÊN TRONG chroot (được gọi qua `chroot ... env ... /tmp/desktop.sh`).
set -e
[ "$DEBUG_MODE" = "true" ] && set -x
export DEBIAN_FRONTEND=noninteractive

if [ "$BASE_DISTRO" = "alpine" ]; then
  echo "LỖI: desktop.sh này chỉ hỗ trợ apt/dpkg (Debian/Ubuntu/Mint)."
  echo "Alpine dùng apk + OpenRC nên cần một alpine-desktop.sh riêng (apk add xfce4 lightdm ...)."
  echo "Nhánh build.sh cho alpine hiện mới chỉ dựng base rootfs, dừng ở đây là đúng."
  exit 1
fi

apt-get update
apt-get install -y linux-image-generic live-boot systemd-sysv \
  plymouth plymouth-themes network-manager sudo locales tzdata \
  lsb-release calamares || \
apt-get install -y linux-image-amd64 live-boot systemd-sysv \
  plymouth plymouth-themes network-manager sudo locales tzdata \
  lsb-release calamares

# BUG CŨ: dòng apt-get install ở trên đôi khi trả về exit code 0 ("thành
# công") nhưng KHÔNG thực sự để lại /boot/vmlinuz-*  và /boot/initrd.img-*
# (ví dụ do postinst của gói kernel lỗi ngầm trong chroot, hoặc bị package
# khác purge/động tới sau đó). Vì desktop.sh set -e không bắt được trường
# hợp "exit 0 nhưng thiếu file", lỗi chỉ lộ ra rất trễ ở iso.sh (khi
# `sudo ls -t .../vmlinuz-*` trả rỗng) với thông báo cryptic
# "cp: cannot stat ''" — lúc đó DE/toàn bộ rootfs đã cài xong, tốn hết thời
# gian build mới biết. Kiểm tra ngay tại đây, fail sớm kèm thông tin debug
# đầy đủ, để biết chính xác nguyên nhân (mất mạng giữa chừng, hết dung
# lượng đĩa, tên gói kernel sai cho distro/version này...).
echo "===== Kiểm tra kernel image đã thực sự có trong /boot ====="
if ! ls /boot/vmlinuz-* >/dev/null 2>&1 || ! ls /boot/initrd.img-* >/dev/null 2>&1; then
  echo "LỖI: apt-get install kernel báo 'thành công' nhưng /boot không có" >&2
  echo "vmlinuz-*/initrd.img-* — ISO sẽ không boot được nếu tiếp tục." >&2
  echo "--- Debug info ---" >&2
  echo "Dung lượng đĩa còn lại:" >&2
  df -h / >&2
  echo "Các gói linux-image* đã cài (dpkg):" >&2
  dpkg -l 'linux-image*' 2>&1 >&2 || true
  echo "Nội dung /boot:" >&2
  ls -la /boot >&2 || true
  exit 1
fi
echo "OK: tìm thấy $(ls /boot/vmlinuz-* | head -n1) và $(ls /boot/initrd.img-* | head -n1)"

# Khóa gói kernel thật sự (linux-image-X.Y.Z-generic, linux-modules-*,
# thường bị apt đánh dấu "auto-installed" vì chỉ là dependency của
# metapackage linux-image-generic) để KHÔNG BAO GIỜ bị autoremove động tới.
#
# BUG CŨ: bản trước dùng `dpkg -l 'pattern1' 'pattern2' | awk` — nếu MỘT
# trong hai pattern không khớp gói nào (vd hệ chỉ có "-generic", không có
# "-amd64"), `dpkg -l` trả về exit code khác 0 cho toàn bộ lệnh, có thể làm
# mất luôn phần output của pattern còn lại tuỳ phiên bản dpkg -> apt-mark
# nhận danh sách rỗng -> KHÔNG bảo vệ được gì -> autoremove xoá mất kernel
# thật (đúng triệu chứng: /boot rỗng dù build.sh/desktop.sh không báo lỗi).
# Fix: dùng `dpkg-query -W` (ổn định hơn, không bị lỗi kiểu này) để liệt kê
# TOÀN BỘ gói liên quan tới kernel đang cài (image/modules/headers), và
# dùng `apt-mark hold` thay vì chỉ `manual` — hold là mức bảo vệ mạnh nhất,
# apt sẽ không bao giờ remove/upgrade gói đã hold bất kể lý do gì.
KERNEL_PKGS=$(dpkg-query -W -f='${Package}\n' 2>/dev/null \
  | grep -E '^linux-(image|modules|headers)-' || true)
if [ -n "$KERNEL_PKGS" ]; then
  echo "Khóa các gói kernel sau khỏi autoremove/upgrade (apt-mark hold):"
  echo "$KERNEL_PKGS"
  echo "$KERNEL_PKGS" | xargs apt-mark hold
else
  echo "CẢNH BÁO: không tìm thấy gói linux-image-*/linux-modules-*/linux-headers-* nào đã cài — kiểm tra lại bước cài kernel ở trên." >&2
fi

# calamares-settings-debian chỉ có trên Debian — cài trên Ubuntu/Mint sẽ
# lỗi "Unable to locate package" và (vì nằm chung 1 lệnh apt-get) làm hỏng
# luôn cả việc cài kernel/DE ở trên. Tách riêng và chỉ cài khi BASE_DISTRO=debian.
if [ "$BASE_DISTRO" = "debian" ]; then
  apt-get install -y calamares-settings-debian || true
fi

echo "===== Firmware / driver phần cứng (wifi, GPU...) ====="
# Tên gói khác nhau giữa Debian và Ubuntu/Mint (nền Ubuntu) nên phải tách
# riêng, y như phần kernel ở trên. Thiếu firmware là lý do phổ biến khiến
# live USB không bắt được wifi hoặc không lên được giao diện đồ hoạ trên
# máy thật (dù chạy tốt trên VM vì QEMU/VirtualBox không cần firmware này).
if [ "$BASE_DISTRO" = "debian" ]; then
  apt-get install -y firmware-linux-free firmware-misc-nonfree \
    firmware-realtek firmware-iwlwifi firmware-atheros \
    os-prober pciutils usbutils || true
else
  apt-get install -y linux-firmware os-prober pciutils usbutils || true
fi

# hostname
echo "$OS_HOSTNAME" > /etc/hostname
echo "127.0.1.1 $OS_HOSTNAME" >> /etc/hosts

# timezone
ln -sf "/usr/share/zoneinfo/$OS_TIMEZONE" /etc/localtime
dpkg-reconfigure -f noninteractive tzdata || true

case "$DE" in
  kde)
    apt-get install -y kde-plasma-desktop sddm
    ;;

  lxqt)
    # sddm dùng chung cơ chế autologin session=lxqt bên dưới, đồng bộ với KDE.
    # lxqt-config cần cho phần icon/theme setting qua GUI (không bắt buộc lúc
    # build nhưng nên có để user chỉnh lại sau khi cài).
    apt-get install -y lxqt sddm lxqt-config lxqt-panel lxqt-session \
      pcmanfm-qt xterm

    # icon theme theo lựa chọn — LXQt vẫn dùng icon theme GTK/Qt chung như XFCE
    case "$ICON_THEME" in
      numix)   apt-get install -y numix-icon-theme ;;
      breeze)  apt-get install -y breeze-icon-theme ;;
      adwaita) apt-get install -y adwaita-icon-theme ;;
      *)       apt-get install -y papirus-icon-theme ;;
    esac
    ;;

  *)
    # mặc định: xfce
    apt-get install -y task-xfce-desktop lightdm lightdm-gtk-greeter \
      xfce4-whiskermenu-plugin git libgtk-3-bin x11-xserver-utils

    # icon theme theo lựa chọn
    case "$ICON_THEME" in
      numix)   apt-get install -y numix-icon-theme ;;
      breeze)  apt-get install -y breeze-icon-theme ;;
      adwaita) apt-get install -y adwaita-icon-theme ;;
      *)       apt-get install -y papirus-icon-theme ;;
    esac

    # GTK theme cho khung cửa sổ/taskbar kiểu Windows 10 (B00merang-Project, open source)
    # BUG CŨ: clone không có fallback -> nếu GitHub rate-limit/timeout, `set -e`
    # sẽ abort NGUYÊN build ở bước này (dù DE/package chính đã cài xong).
    if ! git clone --depth=1 https://github.com/B00merang-Project/Windows-10 \
        /usr/share/themes/Windows-10; then
      echo "⚠️  Clone theme Windows-10 thất bại (mạng/rate-limit) — bỏ qua, giữ GTK theme mặc định."
    fi
    ;;
esac

# trình duyệt / office (tùy chọn)
if [ "$INCLUDE_BROWSER" = "true" ]; then
  apt-get install -y firefox-esr || apt-get install -y firefox
fi

if [ "$INCLUDE_OFFICE" = "true" ]; then
  apt-get install -y libreoffice
else
  # một số gói (task-xfce-desktop, calamares-settings-debian...) có thể kéo
  # theo libreoffice qua "Recommends" dù ta không apt-get install nó trực
  # tiếp. Purge tường minh ở đây để đảm bảo đúng lựa chọn của người dùng.
  echo "INCLUDE_OFFICE=false — kiểm tra và gỡ LibreOffice nếu bị cài kèm theo Recommends"
  echo "Checkpoint kernel TRƯỚC autoremove: $(ls /boot/vmlinuz-* 2>/dev/null || echo 'KHÔNG CÓ FILE')"
  apt-get purge -y 'libreoffice*' 2>/dev/null || true
  apt-get autoremove -y 2>/dev/null || true
  echo "Checkpoint kernel SAU autoremove: $(ls /boot/vmlinuz-* 2>/dev/null || echo 'KHÔNG CÓ FILE — autoremove chính là thủ phạm')"
fi

# gói thêm do người dùng chỉ định
if [ -n "$EXTRA_PACKAGES" ]; then
  apt-get install -y $EXTRA_PACKAGES || true
fi

# user mặc định cho live session
useradd -m -s /bin/bash -G sudo "$OS_USERNAME" || true
# BUG CŨ: khi DEBUG_MODE=true (set -x ở đầu file), lệnh chpasswd bên dưới
# sẽ bị xtrace in thẳng "OS_USERNAME:OS_PASSWORD" ra install-debug.log —
# log này được upload làm artifact (retention 14 ngày) -> lộ mật khẩu
# plaintext. Tắt xtrace tạm thời quanh đúng 1 dòng nhạy cảm này.
{ set +x; } 2>/dev/null
echo "$OS_USERNAME:$OS_PASSWORD" | chpasswd
[ "$DEBUG_MODE" = "true" ] && set -x

echo "===== Autologin cho live session ====="
# QUAN TRỌNG: nếu không bật autologin, live ISO sẽ dừng ở màn hình đăng
# nhập LightDM/SDDM. Không ai chạm tới thì KHÔNG session desktop nào được
# tạo, nghĩa là autostart script set-wallpaper trong branding.sh (chỉ chạy
# lúc có phiên desktop) không bao giờ được thực thi -> nhìn như "hình nền
# không tự apply", dù bản thân script set-wallpaper hoàn toàn không có lỗi.
if [ "$DE" = "kde" ]; then
  mkdir -p /etc/sddm.conf.d
  cat <<EOF > /etc/sddm.conf.d/hyggshi-autologin.conf
[Autologin]
User=$OS_USERNAME
Session=plasma
EOF
elif [ "$DE" = "lxqt" ]; then
  # BUG CŨ: nếu để rơi vào nhánh else (lightdm + Session=xfce) như trước khi
  # thêm case này, live ISO chọn LXQt sẽ autologin vào 1 session "xfce" chưa
  # từng được cài (chỉ cài lxqt ở trên) -> đăng nhập xong màn hình đen/lỗi.
  mkdir -p /etc/sddm.conf.d
  cat <<EOF > /etc/sddm.conf.d/hyggshi-autologin.conf
[Autologin]
User=$OS_USERNAME
Session=lxqt
EOF
else
  mkdir -p /etc/lightdm/lightdm.conf.d
  cat <<EOF > /etc/lightdm/lightdm.conf.d/50-hyggshi-autologin.conf
[Seat:*]
autologin-user=$OS_USERNAME
autologin-user-timeout=0
autologin-session=xfce
EOF
fi

apt-get clean
rm -rf /var/lib/apt/lists/*

echo "Checkpoint kernel CUỐI desktop.sh: $(ls /boot/vmlinuz-* 2>/dev/null || echo 'KHÔNG CÓ FILE')"
echo "===== desktop.sh xong ====="
