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
: "${AUTOLOGIN:=true}"
: "${AUTOSCALE_DISPLAY:=true}"

if [ "$BASE_DISTRO" = "alpine" ]; then
  echo "LỖI: desktop.sh này chỉ hỗ trợ apt/dpkg (Debian/Ubuntu/Mint)."
  echo "Alpine dùng apk + OpenRC nên cần một alpine-desktop.sh riêng (apk add xfce4 lightdm ...)."
  echo "Nhánh build.sh cho alpine hiện mới chỉ dựng base rootfs, dừng ở đây là đúng."
  exit 1
fi

apt-get update

echo "===== Giảm kích thước ISO: chặn cài doc/man/info ngay từ gói ĐẦU TIÊN ====="
# Kỹ thuật chuẩn của các base image Debian/Ubuntu tối giản (Docker
# debian:slim dùng chính cách này): dpkg hỗ trợ path-exclude NGAY TỪ LÚC
# GIẢI NÉN gói — không phải xoá SAU khi đã cài (chậm hơn, và một số file có
# thể đã bị hardlink/dùng bởi postinst script). Đặt file này TRƯỚC MỌI
# apt-get install trong script để mọi gói cài từ đây trở đi (kernel, DE,
# LibreOffice, Firefox...) đều không unpack doc/man — đây là phần chiếm
# dung lượng lớn nhất trong 1 desktop ISO đầy đủ.
#
# Giữ lại /usr/share/doc/*/copyright: Debian Policy §12.5 yêu cầu MỌI gói
# phải có file copyright — xoá hết sẽ vi phạm yêu cầu ghi nhận bản quyền
# của các package đi kèm.
#
# Đánh đổi: hệ thống cài xong sẽ KHÔNG có `man <lệnh>` / doc offline. Muốn
# tắt tối ưu này (giữ đầy đủ doc/man) thì xoá file
# /etc/dpkg/dpkg.cfg.d/01-hyggshi-nodoc trước khi build.
mkdir -p /etc/dpkg/dpkg.cfg.d
cat > /etc/dpkg/dpkg.cfg.d/01-hyggshi-nodoc <<'DPKGCFGEOF'
path-exclude=/usr/share/doc/*
path-include=/usr/share/doc/*/copyright
path-exclude=/usr/share/man/*
path-exclude=/usr/share/groff/*
path-exclude=/usr/share/info/*
path-exclude=/usr/share/lintian/*
path-exclude=/usr/share/linda/*
DPKGCFGEOF

echo "===== Cài kernel + base system (fallback giữa generic/amd64) ====="
apt-get install -y linux-image-generic live-boot systemd-sysv \
  plymouth plymouth-themes network-manager sudo locales tzdata \
  lsb-release || \
apt-get install -y linux-image-amd64 live-boot systemd-sysv \
  plymouth plymouth-themes network-manager sudo locales tzdata \
  lsb-release

echo "===== Cài GRUB + công cụ cho Calamares (partition/bootloader module) ====="
# Calamares (calamares-settings-debian) mặc định yêu cầu gói "grub-pc" có
# sẵn trong target để bootloader module chạy update-grub sau khi cài đặt
# thật (xem lỗi "Package 'grub-pc' has no installation candidate" +
# "update-grub: No such file or directory" khi thiếu). Vì vậy phải cài
# thẳng grub-pc vào chroot này (không chỉ grub-pc-bin).
#
# grub-pc là gói META có bước debconf hỏi "cài GRUB vào (những) ổ đĩa nào"
# (grub-pc/install_devices). Trong chroot lúc build không có ổ đĩa thật
# (/dev/sdX) để chọn, nên PHẢI preseed debconf trước khi apt-get install,
# nếu không: dù đã export DEBIAN_FRONTEND=noninteractive, câu hỏi
# install_devices vẫn có thể làm postinst lỗi/fail (không phải hang chờ
# input, mà debconf trả rỗng rồi grub-probe/grub-install trong postinst
# báo lỗi vì không có device nào được chọn).
echo "grub-pc grub-pc/install_devices_empty boolean true" | debconf-set-selections
echo "grub-pc grub-pc/install_devices multiselect" | debconf-set-selections
echo "grub-pc grub-pc/install_devices_disks_changed multiselect" | debconf-set-selections

# apt-get install nhận NHIỀU gói trong 1 lệnh là MỘT giao dịch: nếu chỉ một
# gói lỗi, CẢ LỆNH thất bại và KHÔNG gói nào được cài — kể cả các gói còn
# lại vốn dĩ cài bình thường được. Cài TỪNG gói một để 1 gói lỗi không kéo
# các gói còn lại theo, và để biết chính xác gói nào fail.
#
# efibootmgr cần cho nhánh UEFI ghi boot entry vào NVRAM; parted/dosfstools
# cần cho module partition (tạo/format phân vùng ESP/root).
GRUB_INSTALL_FAILED=0
for pkg in grub-pc grub-pc-bin grub-efi-amd64-bin grub-common efibootmgr parted dosfstools; do
  if ! apt-get install -y "$pkg"; then
    echo "LỖI: cài gói '$pkg' thất bại (xem log apt ở trên để biết lý do — hết mạng, gói bị transition tạm thời, debconf chưa preseed đúng, v.v.)." >&2
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
    echo "OK: đã cài calamares tại $(command -v calamares)"
else
    echo "CẢNH BÁO: calamares không có trong PATH — installer sẽ không khả dụng."
fi

echo "===== Polkit: cho phép user live mở Calamares KHÔNG cần nhập mật khẩu ====="
# Icon "Install Debian/Hyggshi OS" trên desktop live gọi launcher của
# calamares-settings-debian, mặc định Exec=pkexec calamares — pkexec luôn
# hỏi xác thực qua polkit trước khi cho chạy quyền root, kể cả với user
# trong nhóm sudo (khác hẳn lệnh "sudo" thường, polkit không tự suy ra
# quyền từ nhóm sudo). Kết quả: user live thấy dialog "Authentication
# Required" mỗi lần bấm "Install" dù chính họ đang ngồi trước máy — không
# cần thiết cho live session (không có gì bí mật để bảo vệ ở đây).
#
# Fix: thêm 1 polkit JS rule (polkit >= 0.106, dùng /etc/polkit-1/rules.d/,
# format .pkla cũ đã deprecated) cho phép ĐÚNG user live ($OS_USERNAME)
# chạy calamares qua pkexec mà không cần mật khẩu. Match theo 2 điều kiện
# (không hardcode 1 action id cụ thể, vì action id chính xác của calamares
# khác nhau tuỳ gói: org.debian.pkexec.calamares, org.calamares.pkexec...):
#   1. action.id chứa "calamares" -> khớp mọi action id riêng do
#      calamares-settings-debian/calamares đăng ký.
#   2. action.id là action pkexec chung "org.freedesktop.policykit.exec" VÀ
#      chương trình được exec có chứa "calamares" -> khớp trường hợp không
#      có action riêng nào được đăng ký, pkexec rơi về action mặc định.
# Chỉ áp dụng cho ĐÚNG username live, không phải "mọi user trong nhóm sudo"
# — phạm vi hẹp nhất có thể để không mở rộng bypass mật khẩu sang việc khác.
if command -v pkexec >/dev/null 2>&1; then
  mkdir -p /etc/polkit-1/rules.d
  cat <<EOF > /etc/polkit-1/rules.d/45-hyggshi-calamares-noauth.rules
// Cho phép user live "$OS_USERNAME" mở Calamares (installer) qua pkexec mà
// không cần nhập mật khẩu — sinh tự động bởi scripts/desktop.sh.
polkit.addRule(function(action, subject) {
    if (subject.user != "$OS_USERNAME") {
        return polkit.Result.NOT_HANDLED;
    }
    if (action.id.indexOf("calamares") !== -1) {
        return polkit.Result.YES;
    }
    if (action.id == "org.freedesktop.policykit.exec") {
        var program = action.lookup("program");
        if (program && program.indexOf("calamares") !== -1) {
            return polkit.Result.YES;
        }
    }
    return polkit.Result.NOT_HANDLED;
});
EOF
  chmod 644 /etc/polkit-1/rules.d/45-hyggshi-calamares-noauth.rules
  echo "OK: đã ghi /etc/polkit-1/rules.d/45-hyggshi-calamares-noauth.rules (chỉ áp dụng cho user '$OS_USERNAME')."
else
  echo "CẢNH BÁO: không tìm thấy pkexec — bỏ qua bước ghi polkit rule (không nên xảy ra nếu calamares cài thành công, vì polkitd là dependency)." >&2
fi

echo "===== Ghi đè packages.conf (Calamares) để khớp gói THỰC SỰ có trong chroot ====="
# BUG (đã sửa SAI ở lần trước — file đúng KHÔNG PHẢI removelivepackages.conf,
# file đó không tồn tại và Calamares không đọc nó): module thật sự chạy job
# gỡ gói live-* ở bước Finish tên là "packages", đọc config tại
# /etc/calamares/modules/packages.conf (nguồn gốc:
# calamares-settings-debian, xem calamares/modules/packages.conf trong repo
# đó). Nội dung mặc định:
#   backend: apt
#   operations:
#     - remove:
#         - live-boot
#         - live-boot-doc
#         - live-config
#         - live-config-doc
#         - live-config-systemd
#         - live-tools
#         - live-task-localisation
#         - live-task-recommended
#         - calamares-settings-debian
# Danh sách này giả định build bằng live-build (debian-live) đầy đủ. Build
# này KHÔNG dùng live-build, desktop.sh chỉ cài "live-boot" ở trên nên phần
# lớn gói trong danh sách mặc định KHÔNG tồn tại trong chroot.
#
# Ở bước Finish, Calamares chạy `apt-get -q -y --purge remove <TOÀN BỘ danh
# sách>` trong 1 GIAO DỊCH DUY NHẤT — chỉ cần 1 gói "Unable to locate
# package" là CẢ LỆNH trả về exit code 100. Đây chính xác là lỗi "Package
# Manager error" / "Installation Failed" ở bước Finish.
#
# Fix: dò đúng gói nào đang THỰC SỰ cài trong chroot (dpkg-query -W), chỉ
# ghi các gói đó vào operations[0].remove — giữ nguyên "backend: apt" và
# cấu trúc "operations:" để module packages vẫn nhận diện đúng job.
mkdir -p /etc/calamares/modules
CANDIDATE_LIVE_PKGS="live-boot live-boot-doc live-config live-config-doc live-config-systemd live-tools live-task-localisation live-task-recommended calamares calamares-settings-debian"
INSTALLED_LIVE_PKGS=""
for p in $CANDIDATE_LIVE_PKGS; do
  if dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q "^install ok installed$"; then
    INSTALLED_LIVE_PKGS="$INSTALLED_LIVE_PKGS $p"
  fi
done

{
  echo "backend: apt"
  echo ""
  echo "operations:"
  if [ -n "$INSTALLED_LIVE_PKGS" ]; then
    echo "  - remove:"
    for p in $INSTALLED_LIVE_PKGS; do
      echo "      - '$p'"
    done
  else
    echo "  []"
  fi
} > /etc/calamares/modules/packages.conf

echo "packages.conf (Calamares) sẽ purge:${INSTALLED_LIVE_PKGS:-  (không gói nào — operations rỗng)}"
cat /etc/calamares/modules/packages.conf

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

    echo "===== Theme Cinnamon: GTK/Shell Orchis, Icons Tela, Cursor Bibata ====="
    apt-get install -y git curl sassc libglib2.0-dev-bin > /dev/null 2>&1 || true

    # Orchis: cùng 1 repo cài cả GTK theme lẫn Cinnamon shell theme (--tweaks
    # compact chỉ để bớt bo góc quá to trên panel nhỏ, có thể bỏ nếu không thích).
    if git clone --depth=1 https://github.com/vinceliuice/Orchis-theme.git /tmp/Orchis-theme; then
      /tmp/Orchis-theme/install.sh --tweaks compact -d /usr/share/themes \
        || echo "⚠️  Cài Orchis theme thất bại — giữ theme mặc định."
      rm -rf /tmp/Orchis-theme
    else
      echo "⚠️  Clone Orchis-theme thất bại (mạng/rate-limit) — bỏ qua, giữ theme mặc định."
    fi

    # Tela icon theme
    if git clone --depth=1 https://github.com/vinceliuice/Tela-icon-theme.git /tmp/Tela-icon-theme; then
      /tmp/Tela-icon-theme/install.sh -d /usr/share/icons \
        || echo "⚠️  Cài Tela icon theme thất bại — giữ icon mặc định."
      rm -rf /tmp/Tela-icon-theme
    else
      echo "⚠️  Clone Tela-icon-theme thất bại — bỏ qua, giữ icon mặc định."
    fi

    # Bibata cursor theme — tải bản release .tar.xz build sẵn, không cần build
    # từ source (nhanh hơn nhiều so với clone repo + npm build).
    BIBATA_VER=$(curl -fsSL https://api.github.com/repos/ful1e5/Bibata_Cursor/releases/latest \
      | grep -m1 '"tag_name"' | cut -d'"' -f4)
    if [ -n "$BIBATA_VER" ] && curl -fsSL -o /tmp/bibata.tar.xz \
        "https://github.com/ful1e5/Bibata_Cursor/releases/download/${BIBATA_VER}/Bibata-Modern-Classic.tar.xz"; then
      mkdir -p /usr/share/icons
      tar -xf /tmp/bibata.tar.xz -C /usr/share/icons
      rm -f /tmp/bibata.tar.xz
      echo "OK: đã cài Bibata-Modern-Classic ($BIBATA_VER)"
    else
      echo "⚠️  Tải Bibata cursor thất bại (mạng/rate-limit) — giữ cursor mặc định."
    fi

    command -v gtk-update-icon-cache > /dev/null 2>&1 \
      && gtk-update-icon-cache -f /usr/share/icons/Tela 2>/dev/null || true

    # Đặt làm mặc định qua dconf system-db — áp dụng cho MỌI user tạo sau này
    # (kể cả user do Calamares tạo lúc cài thật), không chỉ user live-session.
    mkdir -p /etc/dconf/profile /etc/dconf/db/local.d
    cat <<EOF > /etc/dconf/profile/user
user-db:user
system-db:local
EOF
    cat <<EOF > /etc/dconf/db/local.d/01-hyggshi-theme
[org/cinnamon/desktop/interface]
gtk-theme='Orchis'
icon-theme='Tela'
cursor-theme='Bibata-Modern-Classic'

[org/cinnamon/desktop/wm/preferences]
theme='Orchis'

[org/cinnamon/theme]
name='Orchis'
EOF
    dconf update || echo "⚠️  dconf update thất bại — có thể do chạy trong chroot thiếu D-Bus, kiểm tra lại lúc boot thật."
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

echo "===== Fastfetch (system info khi mở terminal) ====="
# fastfetch CHỈ có sẵn trong repo apt chính thức từ Debian 13 (trixie) trở
# đi — Debian bookworm/bullseye, Ubuntu (kể cả noble) và Linux Mint (dựa
# trên Ubuntu) KHÔNG đóng gói fastfetch, apt-get install sẽ báo "Unable to
# locate package". Thử apt trước (có update tự động qua apt sau này ở
# distro đã hỗ trợ), fail thì tải .deb build sẵn (amd64) thẳng từ GitHub
# Releases của chính dự án — luôn khớp kiến trúc vì ISO builder này chỉ
# nhắm amd64.
if ! apt-get install -y fastfetch; then
  echo "apt không có fastfetch (bình thường trên Debian < 13 / Ubuntu / Mint)."
  echo "Tải .deb trực tiếp từ GitHub Releases (fastfetch-cli/fastfetch)..."
  FASTFETCH_VER=$(curl -fsSL https://api.github.com/repos/fastfetch-cli/fastfetch/releases/latest \
    | grep -m1 '"tag_name"' | cut -d'"' -f4)
  if [ -n "$FASTFETCH_VER" ] && curl -fsSL -o /tmp/fastfetch.deb \
      "https://github.com/fastfetch-cli/fastfetch/releases/download/${FASTFETCH_VER}/fastfetch-linux-amd64.deb"; then
    apt-get install -y /tmp/fastfetch.deb || echo "CẢNH BÁO: cài fastfetch.deb thất bại (thiếu dependency?)."
    rm -f /tmp/fastfetch.deb
  else
    echo "CẢNH BÁO: không lấy được bản fastfetch mới nhất từ GitHub (mạng/rate-limit) — bỏ qua." >&2
  fi
fi
if command -v fastfetch > /dev/null 2>&1; then
  echo "OK: đã cài fastfetch ($(fastfetch --version 2>/dev/null | head -n1))"
else
  echo "CẢNH BÁO: fastfetch KHÔNG được cài — build vẫn tiếp tục, chỉ là thiếu tool này." >&2
fi

echo "===== Memtest86+ (cho mục 'Kiểm tra RAM' trong menu GRUB, xem scripts/iso.sh) ====="
# Best-effort, không fatal: thiếu gói này chỉ làm mất 1 mục GRUB tuỳ chọn
# (iso.sh tự bỏ qua mục đó nếu không tìm thấy binary trong chroot), không
# ảnh hưởng tới việc ISO boot được hay không.
apt-get install -y memtest86+ || \
  echo "CẢNH BÁO: không cài được memtest86+ — mục 'Kiểm tra RAM' trong GRUB sẽ bị bỏ qua." >&2

echo "===== Công cụ dev cơ bản (cmake, gcc) ====="
# Cần để build các component C++ tự sinh trong repo ngay TRÊN máy đã cài
# đặt (hyggshi-welcome, hyggshi-theme-daemon — xem scripts/make-welcome.sh,
# make-theme-daemon.sh), không chỉ lúc build ISO trên CI. Best-effort (không
# fatal): thiếu 1 trong 2 gói này không nên làm hỏng cả build ISO.
for pkg in cmake gcc; do
  if ! apt-get install -y "$pkg"; then
    echo "CẢNH BÁO: cài gói '$pkg' thất bại — không fatal, nhưng build C++ trên máy đích sẽ thiếu công cụ này." >&2
  fi
done

echo "===== Bộ gõ tiếng Việt (Fcitx5 + engine Unikey) ====="
# fcitx5-unikey: engine gõ tiếng Việt kiểu Telex/VNI quen thuộc (tương đương
# Unikey trên Windows), chạy trên nền fcitx5. fcitx5-frontend-gtk3/qt5: cầu
# nối để app GTK3 (XFCE mặc định) và Qt5 nhận input method (Qt6 dùng chung
# module Qt5 qua tương thích ngược của fcitx5, KHÔNG cần gói riêng).
#
# Cài TỪNG gói + best-effort (không fatal): fcitx5 chỉ có trong repo chính
# thức từ Debian 12/Ubuntu 22.04 trở lên — distro cũ hơn sẽ báo "Unable to
# locate package" cho 1 vài gói, giống cách xử lý fastfetch ở trên, không
# nên làm fail cả build ISO chỉ vì thiếu bộ gõ.
for pkg in fcitx5 fcitx5-unikey fcitx5-config-qt fcitx5-frontend-gtk3 fcitx5-frontend-qt5; do
  if ! apt-get install -y "$pkg"; then
    echo "CẢNH BÁO: cài gói '$pkg' (Fcitx5) thất bại — bỏ qua gói này." >&2
  fi
done

if command -v fcitx5 > /dev/null 2>&1; then
  echo "OK: đã cài fcitx5."
  # Biến môi trường input-method chuẩn (GTK/Qt/X11 XIM/SDL) — ghi vào
  # /etc/environment để áp dụng cho MỌI phiên đăng nhập trên MỌI DE (PAM/
  # systemd đọc file này lúc login), không phụ thuộc DE nào cấu hình riêng.
  if ! grep -q '^GTK_IM_MODULE=' /etc/environment 2>/dev/null; then
    cat >> /etc/environment <<'ENVEOF'
GTK_IM_MODULE=fcitx
QT_IM_MODULE=fcitx
XMODIFIERS=@im=fcitx
SDL_IM_MODULE=fcitx
ENVEOF
    echo "OK: đã ghi biến môi trường input-method vào /etc/environment."
  fi
  # Gói fcitx5 (Debian/Ubuntu) tự cài sẵn autostart tại
  # /etc/xdg/autostart/org.fcitx.Fcitx5.desktop — không cần tạo tay.
else
  echo "CẢNH BÁO: fcitx5 KHÔNG được cài — bộ gõ tiếng Việt sẽ không khả dụng, build vẫn tiếp tục." >&2
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

echo "===== sudo không hỏi mật khẩu cho user live (terminal, apt, v.v.) ====="
# Giống lý do bỏ password prompt cho Calamares ở trên: đây là LIVE SESSION,
# user đã autologin thẳng vào desktop (không hề nhập mật khẩu để vào máy),
# nên mỗi lần gõ "sudo ..." trong terminal lại bị hỏi password của chính
# user đó là thừa/khó chịu, không tăng thêm bảo mật thực sự nào (ai ngồi
# trước máy live cũng coi như đã có toàn quyền root rồi, xem ISO này chạy
# hoàn toàn trong RAM). CHỈ áp dụng đúng 1 user live ($OS_USERNAME), không
# đụng tới nhóm sudo nói chung (không ảnh hưởng user khác nếu có ai đó tự
# tạo thêm sau này).
#
# QUAN TRỌNG: đây là tiện lợi CHỈ DÀNH CHO LIVE SESSION — hệ thống THẬT sau
# khi Calamares cài đặt xong PHẢI bị gỡ bỏ, không thì máy cài xong ai đăng
# nhập được cũng sudo tự do không cần mật khẩu (lỗ hổng bảo mật nghiêm
# trọng). Việc gỡ nằm chung trong shellprocess@removeautologin bên dưới
# (đã đổi tên ý nghĩa thành "dọn các tiện lợi chỉ dành cho live session",
# xem chú thích ở khối Calamares users.conf).
mkdir -p /etc/sudoers.d
cat <<EOF > /etc/sudoers.d/90-hyggshi-live-nopasswd
$OS_USERNAME ALL=(ALL) NOPASSWD: ALL
EOF
chmod 440 /etc/sudoers.d/90-hyggshi-live-nopasswd
# visudo -c kiểm tra cú pháp TRƯỚC khi tin file này — sudoers.d lỗi cú pháp
# có thể làm sudo NGỪNG hoạt động hoàn toàn cho MỌI user, kể cả root qua
# sudo (không phải lỗi "chỉ live user", mà lỗi phá cả hệ thống quyền).
if visudo -c -f /etc/sudoers.d/90-hyggshi-live-nopasswd >/dev/null 2>&1; then
  echo "OK: đã ghi /etc/sudoers.d/90-hyggshi-live-nopasswd (chỉ áp dụng cho user '$OS_USERNAME')."
else
  echo "LỖI: cú pháp sai trong sudoers.d vừa ghi — xoá ngay để không phá sudo trên toàn hệ thống." >&2
  rm -f /etc/sudoers.d/90-hyggshi-live-nopasswd
fi

echo "===== Autologin cho live session (AUTOLOGIN=$AUTOLOGIN) ====="
# QUAN TRỌNG: nếu không bật autologin, live ISO sẽ dừng ở màn hình đăng
# nhập LightDM/SDDM. Không ai chạm tới thì KHÔNG session desktop nào được
# tạo, nghĩa là autostart script set-wallpaper trong branding.sh (chỉ chạy
# lúc có phiên desktop) không bao giờ được thực thi -> nhìn như "hình nền
# không tự apply", dù bản thân script set-wallpaper hoàn toàn không có lỗi.
#
# AUTOLOGIN=false: chỉ đơn giản KHÔNG ghi config autologin — display manager
# (đã cài ở trên theo từng DE) mặc định fallback về màn hình đăng nhập bình
# thường, không cần xoá/undo gì thêm.
if [ "$AUTOLOGIN" != "true" ]; then
  echo "AUTOLOGIN=false — bỏ qua, giữ màn hình đăng nhập mặc định của DM."
elif [ "$DE" = "kde" ]; then
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

echo "===== Auto scale màn hình (AUTOSCALE_DISPLAY=$AUTOSCALE_DISPLAY) ====="
# Mục tiêu: máy có màn hình/độ phân giải khác nhau (laptop HiDPI, VM, máy
# chiếu...) tự dò xrandr và chọn --auto (mode ưu tiên) cho MỌI output đang
# cắm, đồng thời set Xft/DPI hợp lý theo chiều cao thực tế để chữ/icon
# không bị quá nhỏ trên màn HiDPI. Chạy 1 lần mỗi khi có phiên desktop mới
# (autostart), không đụng tới cấu hình đã có nếu user tự chỉnh tay sau đó
# trong cùng phiên (chỉ chạy lúc login).
if [ "$AUTOSCALE_DISPLAY" = "true" ]; then
  mkdir -p /usr/local/bin
  cat <<'SCRIPT' > /usr/local/bin/hyggshi-autoscale.sh
#!/bin/bash
# hyggshi-autoscale.sh — tự dò output + đặt mode/scale màn hình lúc login.
# Không set -e: 1 output lỗi không được làm script chết giữa chừng, các
# output còn lại vẫn phải được xử lý.
LOG="$HOME/.cache/hyggshi-autoscale.log"
mkdir -p "$HOME/.cache"
echo "=== hyggshi-autoscale $(date) ===" >> "$LOG"

command -v xrandr >/dev/null 2>&1 || { echo "Không có xrandr, bỏ qua." >> "$LOG"; exit 0; }

# 1) Với mỗi output đang "connected", bật mode ưu tiên nhất (--auto) của
#    chính nó. An toàn hơn nhiều so với đoán 1 mode cứng, vì mỗi màn hình/
#    máy ảo báo danh sách mode khác nhau.
CONNECTED=$(xrandr --query | awk '/ connected/{print $1}')
for OUT in $CONNECTED; do
  xrandr --output "$OUT" --auto >> "$LOG" 2>&1 \
    || echo "Cảnh báo: xrandr --auto thất bại cho $OUT" >> "$LOG"
done

# 2) Ước lượng DPI/scale từ độ phân giải thật của output chính (đầu tiên),
#    để chữ/icon không bị tí hon trên panel 4K nhưng vẫn giữ 96dpi mặc định
#    cho màn hình phổ thông (không ép scale khi không cần).
PRIMARY=$(echo "$CONNECTED" | head -n1)
if [ -n "$PRIMARY" ]; then
  HEIGHT=$(xrandr --query | awk -v o="$PRIMARY" '$1==o && / connected/{ \
    for(i=1;i<=NF;i++){ if ($i ~ /^[0-9]+x[0-9]+\+/) { split($i,a,"x"); split(a[2],b,"+"); print b[1]; exit } } }')
  if [ -n "$HEIGHT" ] && [ "$HEIGHT" -ge 1440 ] 2>/dev/null; then
    # Màn hình cao >=1440px (2K/4K) -> nâng DPI lên 144 (tương đương scale 1.5x)
    xrdb -merge <<< "Xft.dpi: 144" >> "$LOG" 2>&1 || true
    echo "HiDPI ($PRIMARY, height=$HEIGHT) -> Xft.dpi=144" >> "$LOG"
  fi
fi
echo "xong." >> "$LOG"
SCRIPT
  chmod +x /usr/local/bin/hyggshi-autoscale.sh

  mkdir -p /etc/skel/.config/autostart
  cat <<'DESKTOP' > /etc/skel/.config/autostart/hyggshi-autoscale.desktop
[Desktop Entry]
Type=Application
Name=Hyggshi Auto Scale Display
Exec=/usr/local/bin/hyggshi-autoscale.sh
X-GNOME-Autostart-enabled=true
NoDisplay=true
DESKTOP

  # System-wide (như hyggshi-wallpaper.desktop trong branding.sh) để áp dụng
  # cho MỌI user, kể cả user Calamares tạo sau này chứ không chỉ user live.
  mkdir -p /etc/xdg/autostart
  cp /etc/skel/.config/autostart/hyggshi-autoscale.desktop \
    /etc/xdg/autostart/hyggshi-autoscale.desktop
  echo "OK: đã cài autoscale autostart system-wide."
else
  echo "AUTOSCALE_DISPLAY=false — bỏ qua, không cài autostart autoscale."
fi

echo "===== Calamares: user live đi thẳng vào máy, không hỏi mật khẩu khi setup ====="
# Yêu cầu: live ISO thì autologin cho tiện trải nghiệm (đã xử lý ở khối
# AUTOLOGIN phía trên), nhưng hệ thống THẬT sau khi Calamares cài xong thì
# TẮT autologin để bảo mật hơn — reboot xong phải ra màn hình LightDM hỏi
# username/password, không tự vào thẳng desktop.
# Áp dụng cho module "users" của Calamares (chạy lúc CÀI ĐẶT thật vào đĩa,
# khác với autologin ở live session phía trên):
#   - setRootPassword: false  -> KHÔNG có trang hỏi mật khẩu root riêng.
#   - doAutologin: false      -> KHÔNG tick sẵn "log in automatically";
#     hệ thống sau khi cài xong ra màn hình đăng nhập bình thường (username
#     + password), không tự vào thẳng desktop như live nữa.
#   - allowWeakPasswords: true + password rỗng vẫn qua được -> không bị
#     chặn ở bước "Set up your account" bởi yêu cầu mật khẩu mạnh (user vẫn
#     được TỰ CHỌN đặt password mạnh nếu muốn, chỉ là không ép buộc).
# LƯU Ý: doAutologin: false chỉ quyết định checkbox mặc định trong trang
# "Create your account" và việc module "users" có tự ghi cấu hình autologin
# cho hệ thống đích hay không — nó KHÔNG tự xoá các file cấu hình autologin
# của LIVE SESSION (lightdm.conf.d/50-hyggshi-autologin.conf,
# sddm.conf.d/hyggshi-autologin.conf, gdm3/custom.conf...) mà chính
# desktop.sh đã ghi vào squashfs ở khối AUTOLOGIN phía trên — squashfs đó
# được Calamares (unpackfs) chép y nguyên sang đĩa, nên nếu không dọn thì
# hệ thống thật vẫn autologin dù users.conf đã tắt. Việc dọn các file đó
# nằm ở khối "shellprocess@removeautologin" ngay bên dưới.
if command -v calamares >/dev/null 2>&1; then
  mkdir -p /etc/calamares/modules
  cat <<EOF > /etc/calamares/modules/users.conf
---
defaultGroups:
  - sudo
  - live
  - network
  - plugdev
  - video
  - audio
autologinGroup: autologin
doAutologin: false
sudoersGroup: sudo
setRootPassword: false
doReusePassword: true
allowWeakPasswords: true
allowWeakPasswordsDefault: true
userShell: /bin/bash
hostname: $OS_HOSTNAME
EOF
  echo "OK: đã ghi /etc/calamares/modules/users.conf (tắt autologin cho hệ thống thật, không ép mật khẩu mạnh)."

  echo "===== Calamares: xoá các tiện lợi CHỈ DÀNH CHO LIVE SESSION khỏi hệ thống thật ====="
  # shellprocess@removeautologin — job Calamares chạy TRONG chroot của hệ
  # thống đích (dontChroot: false), ngay trước lúc umount, để dọn sạch mọi
  # cấu hình chỉ hợp lý cho LIVE SESSION (autologin + sudo không mật khẩu)
  # mà desktop.sh đã ghi ở trên nhưng bị unpackfs chép nhầm sang cài đặt
  # thật. Giữ nguyên tên job "removeautologin" (đã được chèn vào
  # settings.conf từ trước, đổi tên sẽ phải sửa lại sed anchor phía dưới
  # không cần thiết) dù giờ dọn thêm cả sudoers — về bản chất vẫn là 1 việc:
  # "dọn mọi thứ live-only trước khi giao máy cho user thật".
  # Xoá/an toàn cho MỌI display manager (mate/cinnamon/xfce dùng lightdm,
  # kde/lxqt dùng sddm, gnome dùng gdm3) — lệnh nào không áp dụng cho DE
  # đang build thì đơn giản là no-op (file không tồn tại, "|| true").
  mkdir -p /etc/calamares/modules
  cat <<'EOF' > /etc/calamares/modules/shellprocess-removeautologin.conf
---
dontChroot: false
timeout: 15
exec:
  - "rm -f /etc/lightdm/lightdm.conf.d/50-hyggshi-autologin.conf"
  - "rm -f /etc/sddm.conf.d/hyggshi-autologin.conf"
  - "sh -c \"[ -f /etc/gdm3/custom.conf ] && sed -i -E 's/^#?AutomaticLoginEnable[[:space:]]*=.*/AutomaticLoginEnable = false/' /etc/gdm3/custom.conf; true\""
  - "rm -f /etc/sudoers.d/90-hyggshi-live-nopasswd"
EOF
  echo "OK: đã ghi /etc/calamares/modules/shellprocess-removeautologin.conf"

  echo "===== Chèn 'shellprocess@removeautologin' vào sequence (settings.conf) — sau packages ====="
  if [ -f /etc/calamares/settings.conf ]; then
    if grep -Eq '^\s*-\s*shellprocess@removeautologin\s*$' /etc/calamares/settings.conf; then
      echo "settings.conf đã có 'shellprocess@removeautologin' trong sequence từ trước — bỏ qua, không chèn trùng."
    else
      # Anchor vào "- packages": module này CHẮC CHẮN có trong sequence vì
      # chính desktop.sh vừa ghi /etc/calamares/modules/packages.conf ở
      # trên (mục "Ghi đè packages.conf"). Chèn SAU "packages" (job purge
      # gói live chạy gần cuối exec sequence) để đảm bảo job xoá autologin
      # chạy sau khi mọi thứ khác đã xong, ngay trước umount. Giữ đúng
      # nguyên tắc thụt lề động (dùng \1) như khối chèn "license" ở dưới,
      # tránh lỗi YAML fold dòng khi indent gốc khác 2 space.
      sed -i -E 's/^([[:space:]]*)-[[:space:]]*packages[[:space:]]*$/&\n\1- shellprocess@removeautologin/' /etc/calamares/settings.conf

      if grep -Eq '^\s*-\s*shellprocess@removeautologin\s*$' /etc/calamares/settings.conf; then
        echo "OK: đã chèn 'shellprocess@removeautologin' vào sequence."
      else
        echo "CẢNH BÁO: không tìm thấy pattern '- packages' để chèn 'shellprocess@removeautologin' —" >&2
        echo "hệ thống thật có thể vẫn bị autologin dù users.conf đã tắt. Kiểm tra thủ công /etc/calamares/settings.conf." >&2
      fi
    fi
  else
    echo "CẢNH BÁO: /etc/calamares/settings.conf không tồn tại — bỏ qua chèn shellprocess@removeautologin." >&2
  fi
else
  echo "Calamares chưa được cài (xem cảnh báo phía trên) — bỏ qua bước ghi users.conf."
fi

# ============================================================
# >>> THÊM MỚI: LICENSE MODULE <<<
# Trang "License" của Calamares (module "license") hiển thị thoả thuận
# bản quyền / third-party software TRƯỚC bước locale, để user tick đồng ý
# trước khi cài. Module này KHÔNG có sẵn trong sequence mặc định của
# calamares-settings-debian nên phải: (1) ghi license.conf, (2) chèn
# "license" vào sequence của settings.conf. Chỉ làm khi calamares thật sự
# đã cài được (cùng điều kiện với users.conf ở trên) — nếu không có
# calamares thì ghi config này vô nghĩa.
if command -v calamares >/dev/null 2>&1; then
  echo "===== Ghi /etc/calamares/modules/license.conf ====="
  # Copy sẵn file LICENSE của Hyggshi OS vào chroot để Calamares hiển thị
  # NGAY trong app (field "file:") thay vì chỉ mở link ngoài — user cài
  # offline (live USB không mạng) vẫn đọc được nội dung đầy đủ.
  # Dùng TẠM thẳng file LICENSE sẵn có ở root repo (Hyggshi-OS-Research-Technology/
  # Hyggshi-OS, file "LICENSE" cạnh README.md) thay vì tạo riêng 1 file
  # HYGGSHI_LICENSE.txt — workflow .yml cần copy file này vào /tmp/LICENSE
  # trong chroot TRƯỚC khi chạy desktop.sh (xem hướng dẫn thêm dòng copy
  # trong Build-Hyggshi-OS-ISO.yml, chỗ đang copy kernel-tuning.sh).
  mkdir -p /usr/share/hyggshi-os
  if [ -f /tmp/LICENSE ]; then
    cp /tmp/LICENSE /usr/share/hyggshi-os/LICENSE.txt
  else
    # Fallback tối thiểu nếu build không truyền sẵn file LICENSE qua /tmp —
    # tránh field "file:" trỏ tới đường dẫn không tồn tại làm Calamares lỗi
    # ở bước License (không mở được nội dung).
    cat <<'LICTXT' > /usr/share/hyggshi-os/LICENSE.txt
Hyggshi OS — HOSL-1.3 / MIT
Xem đầy đủ tại: https://hyggshi-os-website.pages.dev/license
LICTXT
    echo "CẢNH BÁO: không tìm thấy /tmp/LICENSE — đã ghi license.conf với nội dung rút gọn. Kiểm tra lại bước copy LICENSE trong .yml." >&2
  fi

  mkdir -p /etc/calamares/modules
  cat <<'EOF' > /etc/calamares/modules/license.conf
---
# entries: danh sách license hiển thị trên 1 trang duy nhất. isMandatory:
# bắt buộc tick "I accept" mới Next được. isOptedIn: mặc định đã tick sẵn
# hay chưa (false = ép user tự đọc & tick, đúng tinh thần "phải đồng ý").
entries:
  - id:          "hyggshi-os"
    name:        "Hyggshi OS"
    vendor:      "Hyggshi OS Research Technology (HORT)"
    url:         "https://hyggshi-os-website.pages.dev/license"
    file:        "/usr/share/hyggshi-os/LICENSE.txt"
    isMandatory: true
    isOptedIn:   false
EOF
  echo "OK: đã ghi /etc/calamares/modules/license.conf"

  echo "===== Chèn 'license' vào sequence (settings.conf) — sau welcome, trước locale ====="
  if [ -f /etc/calamares/settings.conf ]; then
    if grep -Eq '^\s*-\s*license\s*$' /etc/calamares/settings.conf; then
      echo "settings.conf đã có 'license' trong sequence từ trước — bỏ qua, không chèn trùng."
    else
      # Chỉ chèn nếu dòng "- welcome" thực sự có trong khối show — nếu
      # calamares-settings-debian đổi format (khác thụt lề/quote) ở version
      # mới hơn, sed sẽ KHÔNG khớp gì và không chèn được gì cả -> phải kiểm
      # tra lại bằng grep bên dưới, không được coi exit code 0 của sed là
      # "đã chèn thành công".
      #
      # QUAN TRỌNG: KHÔNG hardcode số cột thụt lề (trước đây dùng cứng 4
      # space "    - license") — calamares-settings-debian thường thụt lề
      # "- welcome" bằng 2 space, nên dòng chèn cứng 4 space bị THỤT SÂU HƠN
      # dòng "- welcome" phía trên. Với YAML, một dòng "- license" thụt sâu
      # hơn ngay sau một scalar list item ("- welcome") KHÔNG được hiểu là
      # phần tử anh em cùng cấp, mà bị gộp (folded) vào làm PHẦN TIẾP THEO
      # của chuỗi "welcome", ra một item DUY NHẤT là "welcome - license".
      # Calamares sau đó cố nạp module tên "welcome - license" (không tồn
      # tại) -> lỗi "Calamares Initialization Failed" với thông báo
      # "welcome - license@welcome - license". Fix: dùng nhóm bắt
      # (\1 = phần thụt lề thật sự của dòng "- welcome") và chèn dòng mới
      # với ĐÚNG thụt lề đó, đảm bảo "- license" luôn là anh em cùng cấp
      # với "- welcome" bất kể file gốc thụt lề bao nhiêu space.
      sed -i -E 's/^([[:space:]]*)-[[:space:]]*welcome[[:space:]]*$/&\n\1- license/' /etc/calamares/settings.conf

      if grep -Eq '^\s*-\s*license\s*$' /etc/calamares/settings.conf; then
        echo "OK: đã chèn 'license' vào sequence."
      else
        echo "CẢNH BÁO: không tìm thấy pattern '- welcome' để chèn 'license' —" >&2
        echo "kiểm tra thủ công /etc/calamares/settings.conf, có thể format khác chuẩn." >&2
      fi
    fi
    echo "--- settings.conf (đoạn sequence) ---"
    grep -A 20 '^sequence:' /etc/calamares/settings.conf || true
  else
    echo "CẢNH BÁO: /etc/calamares/settings.conf không tồn tại — bỏ qua chèn license module." >&2
  fi
else
  echo "Calamares chưa được cài — bỏ qua bước ghi license.conf."
fi
# >>> HẾT PHẦN THÊM MỚI: LICENSE MODULE <<<
# ============================================================

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

echo "===== Dọn thêm để giảm kích thước ISO (doc/man sót từ base debootstrap, cache, log) ====="
# path-exclude ở ĐẦU file chỉ chặn được các gói cài SAU nó trong desktop.sh
# này — base rootfs debootstrap (chạy TRƯỚC desktop.sh, ở build.sh trên
# host) có thể đã unpack sẵn doc/man cho các gói base trước khi ta kịp cài
# dpkg.cfg.d. Dọn nốt phần còn sót ở đây.
#
# Giữ lại copyright (yêu cầu Debian Policy §12.5) bằng cách backup ra /tmp
# TRƯỚC khi xoá /usr/share/doc, rồi khôi phục lại đúng cấu trúc
# <package>/copyright sau khi xoá phần còn lại.
find /usr/share/doc -mindepth 1 -maxdepth 1 -type d 2>/dev/null | while read -r d; do
  [ -f "$d/copyright" ] && cp "$d/copyright" "/tmp/$(basename "$d")-copyright" 2>/dev/null
done
rm -rf /usr/share/doc/* /usr/share/man/* /usr/share/info/* /usr/share/groff/* 2>/dev/null || true
mkdir -p /usr/share/doc
for f in /tmp/*-copyright; do
  [ -f "$f" ] || continue
  pkgname="$(basename "$f" -copyright)"
  mkdir -p "/usr/share/doc/$pkgname"
  mv "$f" "/usr/share/doc/$pkgname/copyright"
done

# Cache/log/tmp không cần đóng gói trong ISO — hệ thống tự tạo lại lúc chạy
# thật. truncate thay vì rm cho log hệ thống vẫn muốn giữ file (một số
# service không tự tạo lại file nếu thiếu, chỉ ghi tiếp vào file rỗng).
rm -rf /var/cache/apt/archives/*.deb /tmp/* /var/tmp/* 2>/dev/null || true
find /var/log -type f -exec truncate -s 0 {} \; 2>/dev/null || true

# .git để lại bởi bước clone GTK theme Windows-10 ở trên (chỉ là metadata
# lịch sử git, không cần trong hệ thống đã cài) — vài chục MB không đáng có
# trong ISO.
rm -rf /usr/share/themes/Windows-10/.git 2>/dev/null || true

echo "Checkpoint kernel CUỐI desktop.sh: $(ls /boot/vmlinuz-* 2>/dev/null || echo 'KHÔNG CÓ FILE')"
echo "===== desktop.sh xong ====="
