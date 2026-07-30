#!/bin/bash
# desktop.sh — cài package cơ bản, DE (xfce/kde/lxqt/gnome/mate/cinnamon),
# user, hostname/timezone, Edition (kernel tuning, chỉ Debian).
# Chạy BÊN TRONG chroot (được gọi qua `chroot ... env ... /tmp/desktop.sh`).
set -e
[ "$DEBUG_MODE" = "true" ] && set -x
export DEBIAN_FRONTEND=noninteractive

# kernel-tuning.sh (profile Edition) được yml copy vào /tmp cùng lúc với
# desktop.sh, vì script này chạy BÊN TRONG chroot — chỉ /tmp là tồn tại,
# không có đường dẫn gốc scripts/ của repo trên host.
# shellcheck source=/dev/null
source /tmp/kernel-tuning.sh
: "${EDITION:=normal}"

if [ "$BASE_DISTRO" = "alpine" ]; then
  echo "LỖI: desktop.sh này chỉ hỗ trợ apt/dpkg (Debian/Ubuntu/Mint)."
  echo "Alpine dùng apk + OpenRC nên cần một alpine-desktop.sh riêng (apk add xfce4 lightdm ...)."
  echo "Nhánh build.sh cho alpine hiện mới chỉ dựng base rootfs, dừng ở đây là đúng."
  exit 1
fi

apt-get update

echo "===== Cài kernel + base system (fallback giữa generic/amd64) ====="
apt-get install -y linux-image-generic live-boot systemd-sysv \
  plymouth plymouth-themes network-manager sudo locales tzdata \
  lsb-release || \
apt-get install -y linux-image-amd64 live-boot systemd-sysv \
  plymouth plymouth-themes network-manager sudo locales tzdata \
  lsb-release

echo "===== Cài GRUB + công cụ cho Calamares (partition/bootloader module) ====="
# BUG: khác với build-fedora.sh (gói "grub2-pc grub2-efi-x64 shim-x64" được
# cài THẲNG vào --installroot trước khi cài calamares), desktop.sh trước đây
# KHÔNG cài bất kỳ gói grub nào vào trong chroot này. grub-pc-bin/
# grub-efi-amd64-bin/grub-common ở build.sh chỉ cài trên HOST (runner) để
# grub-mkrescue đóng gói ISO — đó là GRUB của riêng ISO live, khác hoàn toàn
# với GRUB cần có SẴN bên trong squashfs/chroot này (chroot này chính là
# rootfs được Calamares unpack ra đĩa rồi chroot vào để chạy grub-install/
# update-grub cho hệ thống ĐÃ CÀI). Thiếu gói ở đây khiến bootloader module
# của Calamares fail vì "grub-install: command not found" ngay trong target
# vừa cài — đúng triệu chứng "install/partition/bootloader step fails".
# FIX (đúng nguyên nhân lỗi "grub-pc has no installation candidate" /
# "Package grub-pc is not available... following packages replace it:
# grub-common" thấy trong Calamares khi cài đặt thật):
#
# 1) apt-get install nhận NHIỀU gói trong 1 lệnh là MỘT giao dịch: nếu chỉ
#    một gói "no installation candidate" (vd "grub-pc" — gói meta hay bị
#    transition tạm thời trên Debian testing/sid, đúng như log lỗi), CẢ
#    LỆNH thất bại và KHÔNG gói nào trong danh sách được cài — kể cả
#    grub-common/efibootmgr/parted/dosfstools vốn dĩ cài bình thường được.
#    Trước đây lỗi này chỉ in CẢNH BÁO rồi build tiếp tục "thành công",
#    đóng gói ISO thiếu sạch cả 6 gói này, nên Calamares luôn fail ở bước
#    bootloader/partition khi cài đặt thật. Fix: cài TỪNG gói một để 1 gói
#    lỗi không kéo các gói còn lại theo.
# 2) "grub-pc"/"grub-efi-amd64" là gói META dùng debconf để hỏi ổ đĩa và tự
#    chạy grub-install (thiết kế cho debian-installer tương tác) — không
#    cần trong chroot này vì Calamares tự quản lý việc gọi grub-install qua
#    module bootloader riêng của nó. Cái thực sự cần là gói BINARY chứa
#    grub-install: grub-pc-bin (target i386-pc) + grub-efi-amd64-bin (target
#    x86_64-efi) — đúng cặp gói build.sh đã dùng cho HOST khi grub-mkrescue
#    đóng ISO (xem grep grub trong build.sh) nên đổi sang đây cho nhất quán,
#    đồng thời tránh phụ thuộc vào gói meta "grub-pc" hay bị lỗi tạm thời.
# efibootmgr cần cho nhánh UEFI ghi boot entry vào NVRAM; parted/dosfstools
# cần cho module partition (tạo/format phân vùng ESP/root).
GRUB_INSTALL_FAILED=0
for pkg in grub-pc-bin grub-efi-amd64-bin grub-common efibootmgr parted dosfstools; do
  if ! apt-get install -y "$pkg"; then
    echo "LỖI: cài gói '$pkg' thất bại (xem log apt ở trên để biết lý do — hết mạng, gói bị transition tạm thời, v.v.)." >&2
    GRUB_INSTALL_FAILED=1
  fi
done
if [ "$GRUB_INSTALL_FAILED" = "1" ]; then
  echo "LỖI NGHIÊM TRỌNG: thiếu ít nhất 1 gói GRUB/partition ở trên." >&2
  echo "Calamares bootloader/partition module CHẮC CHẮN sẽ lỗi khi cài đặt" >&2
  echo "thật nếu tiếp tục đóng ISO với chroot thiếu gói này. Dừng build ở" >&2
  echo "đây (thay vì chỉ cảnh báo rồi đóng ISO hỏng) để phát hiện sớm." >&2
  exit 1
fi

echo "===== Cài Calamares (installer) — optional, không làm fail cả build ====="
# calamares-settings-debian cung cấp cấu hình module cài đặt (partition, unpackfs,
# bootloader...) cho mọi distro Debian-based. Thử cài cả hai; nếu settings không
# có thì vẫn giữ calamares core; nếu cả hai đều không có thì ISO boot live được
# nhưng không có graphical installer (không fatal).
apt-get install -y calamares calamares-settings-debian || \
apt-get install -y calamares || \
echo "CẢNH BÁO: không cài được calamares/calamares-settings-debian — ISO sẽ không có graphical installer hoặc installer chưa được cấu hình."

if command -v calamares >/dev/null 2>&1; then
    echo "OK: calamares đã cài tại $(command -v calamares)"
else
    echo "CẢNH BÁO: calamares không có trong PATH — installer sẽ không khả dụng."
fi

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

  gnome)
    # gnome-session cần cho phiên GNOME thật (không chỉ gnome-shell trần);
    # gdm3 là display manager mặc định của GNOME (autologin cấu hình riêng bên dưới).
    apt-get install -y gnome-session gnome-shell gdm3 gnome-terminal \
      nautilus gnome-tweaks
    ;;

  mate)
    apt-get install -y mate-desktop-environment lightdm lightdm-gtk-greeter
    ;;

  cinnamon)
    apt-get install -y cinnamon-desktop-environment lightdm lightdm-gtk-greeter
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
  # một số gói (task-xfce-desktop, ...) có thể kéo
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
  read -r -a EXTRA_PACKAGE_LIST <<< "$EXTRA_PACKAGES"
  apt-get install -y "${EXTRA_PACKAGE_LIST[@]}" || true
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
elif [ "$DE" = "gnome" ]; then
  # GNOME dùng gdm3, không phải lightdm/sddm — cấu hình autologin riêng theo
  # đúng cú pháp custom.conf của gdm3, khác hẳn 2 nhánh trên.
  mkdir -p /etc/gdm3
  if [ -f /etc/gdm3/custom.conf ]; then
    sed -i '/^\[daemon\]/,/^\[/ s/^#\?AutomaticLoginEnable *=.*/AutomaticLoginEnable = true/' /etc/gdm3/custom.conf
    sed -i "/^\[daemon\]/,/^\[/ s/^#\?AutomaticLogin *=.*/AutomaticLogin = $OS_USERNAME/" /etc/gdm3/custom.conf
  else
    cat <<EOF > /etc/gdm3/custom.conf
[daemon]
AutomaticLoginEnable = true
AutomaticLogin = $OS_USERNAME
EOF
  fi
elif [ "$DE" = "mate" ]; then
  mkdir -p /etc/lightdm/lightdm.conf.d
  cat <<EOF > /etc/lightdm/lightdm.conf.d/50-hyggshi-autologin.conf
[Seat:*]
autologin-user=$OS_USERNAME
autologin-user-timeout=0
autologin-session=mate
EOF
elif [ "$DE" = "cinnamon" ]; then
  mkdir -p /etc/lightdm/lightdm.conf.d
  cat <<EOF > /etc/lightdm/lightdm.conf.d/50-hyggshi-autologin.conf
[Seat:*]
autologin-user=$OS_USERNAME
autologin-user-timeout=0
autologin-session=cinnamon
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

# ============================================================
# Edition (kernel tuning) — CHỈ áp dụng cho Debian, theo đúng yêu cầu
# ("arch và debian thêm tuỳ chọn chỉnh thông số kernel"). Ubuntu/Mint chạy
# chung script này nhưng không áp dụng, để không đổi hành vi đã ổn định.
# ============================================================
if [ "$BASE_DISTRO" = "debian" ]; then
  echo "===== Áp dụng Edition=$EDITION (kernel sysctl tuning) ====="
  mkdir -p /etc/sysctl.d
  hyggshi_sysctl_conf "$EDITION" > /etc/sysctl.d/99-hyggshi-tuning.conf

  EDITION_PKGS=$(hyggshi_edition_packages_apt "$EDITION")
  if [ -n "$EDITION_PKGS" ]; then
    echo "Gói thêm cho edition '$EDITION': $EDITION_PKGS"
    apt-get install -y $EDITION_PKGS || true
  fi

  # zram (lite): ghi /etc/default/zramswap SAU KHI zram-tools đã cài ở trên,
  # nếu không package sẽ tự tạo file mặc định rồi đè lên config của mình.
  ZRAM_CONF=$(hyggshi_zram_conf "$EDITION")
  if [ -n "$ZRAM_CONF" ]; then
    echo "Áp dụng zram config cho edition '$EDITION'"
    echo "$ZRAM_CONF" > /etc/default/zramswap
  fi

  # Mask service nền không cần cho lite — dùng `systemctl mask` (không phải
  # disable) để không service nào, kể cả do gói khác kéo vào sau, tự bật lại.
  # `|| true`: service chưa cài (chưa có unit) không được làm fail cả build.
  for svc in $(hyggshi_edition_services_mask "$EDITION"); do
    echo "Mask service '$svc' cho edition '$EDITION'"
    systemctl mask "$svc" 2>/dev/null || true
  done
fi

apt-get clean
rm -rf /var/lib/apt/lists/*

echo "Checkpoint kernel CUỐI desktop.sh: $(ls /boot/vmlinuz-* 2>/dev/null || echo 'KHÔNG CÓ FILE')"
echo "===== desktop.sh xong ====="
