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
    echo "OK: calamares đã cài tại $(command -v calamares)"
else
    echo "CẢNH BÁO: calamares không có trong PATH — installer sẽ không khả dụng."
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
# Yêu cầu: "live > root luôn đi với tư cách là khách dùng mới không hỏi Pass
# khi setup". Áp dụng cho module "users" của Calamares (chạy lúc CÀI ĐẶT
# thật vào đĩa, khác với autologin ở live session phía trên):
#   - setRootPassword: false  -> KHÔNG có trang hỏi mật khẩu root riêng.
#   - doAutologin: true       -> mặc định tick sẵn "log in automatically",
#     hệ thống sau khi cài xong cũng vào thẳng desktop như live, không hỏi
#     mật khẩu ở màn hình đăng nhập (giống hành vi "khách" hiện tại).
#   - allowWeakPasswords: true + password rỗng vẫn qua được -> không bị
#     chặn ở bước "Set up your account" bởi yêu cầu mật khẩu mạnh.
# LƯU Ý: Calamares (module "users") vẫn hiển thị trang tạo tài khoản (nhập
# username/tên máy) vì đây là bước bắt buộc để có 1 user thật trên hệ thống
# đích — không thể ẩn hoàn toàn trang này chỉ bằng users.conf. Muốn hoàn
# toàn không hỏi gì (kiểu "OEM"/unattended) cần cấu hình settings.conf riêng
# (bỏ module "users"/"welcome" khỏi sequence) — nằm ngoài phạm vi override
# packages.conf/users.conf hiện có trong repo này.
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
doAutologin: true
sudoersGroup: sudo
setRootPassword: false
doReusePassword: true
allowWeakPasswords: true
allowWeakPasswordsDefault: true
userShell: /bin/bash
hostname: $OS_HOSTNAME
EOF
  echo "OK: đã ghi /etc/calamares/modules/users.conf (autologin + không ép mật khẩu mạnh)."
else
  echo "Calamares chưa được cài (xem cảnh báo phía trên) — bỏ qua bước ghi users.conf."
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
