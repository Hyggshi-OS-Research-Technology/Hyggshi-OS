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
: "${PKGLIST_DIR:=/tmp/pkglists}"

# Đọc danh sách gói từ file .list trong packages/packages/ (bỏ dòng trống
# và dòng comment '#') — nguồn duy nhất cho các nhóm gói installer/devtools/
# vietnamese-input/desktop-xfce, thay vì hardcode rải rác trong script này.
read_pkglist() {
  local file="$PKGLIST_DIR/$1"
  if [ ! -f "$file" ]; then
    echo "CẢNH BÁO: không tìm thấy package list '$file' (PKGLIST_DIR=$PKGLIST_DIR) — nhóm gói này sẽ bị BỎ QUA." >&2
    return 0
  fi
  grep -v '^[[:space:]]*#' "$file" | grep -v '^[[:space:]]*$'
}


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
  initramfs-tools plymouth plymouth-themes network-manager sudo locales tzdata \
  lsb-release || \
apt-get install -y linux-image-amd64 live-boot systemd-sysv \
  initramfs-tools plymouth plymouth-themes network-manager sudo locales tzdata \
  lsb-release

if true; then
  echo "===== Gỡ Plymouth theme mặc định của Ubuntu (chờ branding.sh cài theme Hyggshi riêng) ====="
  # plymouth-themes (vừa cài ở trên) là gói TỔNG HỢP kéo theo nhiều theme,
  # trong đó "spinner" (logo tròn xoay 5 chấm) chính là theme ĐANG active
  # mặc định trên Ubuntu ngay sau khi cài (update-alternatives ưu tiên nó
  # cao nhất). "ubuntu-text" là theme text-mode fallback riêng của Ubuntu
  # (không có trên Debian upstream). Nếu không gỡ, 2 theme này vẫn nằm
  # trong danh sách update-alternatives --list plymouth-theme và sẽ hiện
  # lại (logo Ubuntu) trong các trường hợp branding.sh không tạo được
  # theme "hyggshi-boot" (thiếu logo, convert lỗi...) — lúc đó code ở
  # branding.sh chỉ cảnh báo rồi "giữ Plymouth theme mặc định của distro
  # gốc", và distro gốc ở đây chính là spinner/ubuntu-text. Gỡ hẳn 2 gói
  # này TRƯỚC khi branding.sh chạy để không có đường lùi về logo Ubuntu,
  # kể cả khi tạo theme Hyggshi thất bại (best-effort, không fatal nếu 1
  # trong 2 gói không tồn tại — tuỳ version Ubuntu).
  apt-get purge -y plymouth-theme-spinner plymouth-theme-ubuntu-text 2>/dev/null || true
  # Một số phiên bản đóng gói theme dưới tên khác (ubuntu-mate, kubuntu...)
  # — quét dpkg theo pattern để dọn sạch bất kỳ theme nào có chữ "ubuntu"
  # trong tên gói, không phụ thuộc đúng 2 tên cứng ở trên.
  UBUNTU_PLYMOUTH_PKGS=$(dpkg-query -W -f='${Package}\n' 'plymouth-theme-*ubuntu*' 2>/dev/null || true)
  if [ -n "$UBUNTU_PLYMOUTH_PKGS" ]; then
    echo "Gỡ thêm: $UBUNTU_PLYMOUTH_PKGS"
    echo "$UBUNTU_PLYMOUTH_PKGS" | xargs apt-get purge -y 2>/dev/null || true
  fi
fi

echo "===== Cài GRUB + công cụ cho Calamares (partition/bootloader module) ====="
# Calamares (Calamares settings) mặc định yêu cầu gói "grub-pc" có
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
# Nguồn danh sách gói: packages/packages/installer.list
GRUB_INSTALL_FAILED=0
while IFS= read -r pkg; do
  if ! apt-get install -y "$pkg"; then
    echo "LỖI: cài gói '$pkg' thất bại (xem log apt ở trên để biết lý do — hết mạng, gói bị transition tạm thời, debconf chưa preseed đúng, v.v.)." >&2
    GRUB_INSTALL_FAILED=1
  fi
done < <(read_pkglist installer.list)
if [ "$GRUB_INSTALL_FAILED" = "1" ]; then
  echo "LỖI NGHIÊM TRỌNG: thiếu ít nhất 1 gói GRUB/partition ở trên." >&2
  echo "Calamares bootloader/partition module CHẮC CHẮN sẽ lỗi khi cài đặt" >&2
  echo "thật nếu tiếp tục đóng ISO với chroot thiếu gói này. Dừng build ở" >&2
  echo "đây (thay vì chỉ cảnh báo rồi đóng ISO hỏng) để phát hiện sớm." >&2
  exit 1
fi

echo "===== Cài Calamares (installer) — optional, không làm fail cả build ====="
# Calamares settings cung cấp cấu hình module cài đặt (partition, unpackfs,
# bootloader...) cho mọi distro Debian-based. Thử cài cả hai; nếu settings không
# có thì vẫn giữ calamares core; nếu cả hai đều không có thì ISO boot live được
# nhưng không có graphical installer (không fatal).
apt-get install -y calamares || \
apt-get install -y calamares || \
echo "CẢNH BÁO: không cài được calamares/Calamares settings — ISO sẽ không có graphical installer hoặc installer chưa được cấu hình."

if command -v calamares >/dev/null 2>&1; then
    echo "OK: đã cài calamares tại $(command -v calamares)"
else
    echo "CẢNH BÁO: calamares không có trong PATH — installer sẽ không khả dụng."
fi

# ===== Hyggshi Calamares config: GHI ĐÈ /etc/calamares =====
# config/calamares được workflow/local-build stage vào /tmp/calamares vì
# desktop.sh chạy bên trong chroot và không nhìn thấy source tree trên host.
# Phải ghi đè SAU apt install để Calamares settings không thay thế
# cấu hình Hyggshi bằng cấu hình Debian mặc định.
if [ -d /tmp/calamares ]; then
  echo "===== Ghi đè /etc/calamares bằng config/calamares ====="
  rm -rf /etc/calamares
  mkdir -p /etc/calamares
  cp -a /tmp/calamares/. /etc/calamares/
  chmod -R a+rX /etc/calamares
  echo "OK: /etc/calamares đã được ghi đè hoàn toàn từ source Hyggshi."
else
  echo "CẢNH BÁO: không có /tmp/calamares — giữ cấu hình Calamares do package cung cấp." >&2
fi

# ===== Calamares launcher: đổi "Install Debian" -> "Install Hyggshi OS" =====
# Calamares settings có thể cài launcher ở nhiều vị trí/tên khác nhau
# tùy phiên bản Debian. Dò theo nội dung .desktop thay vì hardcode 1 filename,
# sau đó ghi đè tên + icon của launcher.
INSTALLER_ICON_SRC="/tmp/Hyggshi-OS-Installer.png"
INSTALLER_ICON_DIR="/usr/share/icons/hicolor/256x256/apps"
INSTALLER_ICON_NAME="hyggshi-installer"
if [ -f "$INSTALLER_ICON_SRC" ]; then
  echo "===== Branding Calamares launcher: Install Hyggshi OS ====="
  mkdir -p "$INSTALLER_ICON_DIR" /usr/share/pixmaps
  install -m 0644 "$INSTALLER_ICON_SRC" "$INSTALLER_ICON_DIR/${INSTALLER_ICON_NAME}.png"
  install -m 0644 "$INSTALLER_ICON_SRC" "/usr/share/pixmaps/${INSTALLER_ICON_NAME}.png"

  FOUND_INSTALLER=0
  while IFS= read -r -d '' desktop_file; do
    if grep -Eiq '^(Name|Name\[[^]]+\])=.*Install Debian|^(Name|Name\[[^]]+\])=.*Debian Installer|^Exec=.*(pkexec[[:space:]]+)?calamares' "$desktop_file"; then
      FOUND_INSTALLER=1
      # Đổi mọi tên locale có sẵn để không còn hiện "Install Debian".
      sed -i -E 's/^Name([[:space:]]*=|\[[^]]+\][[:space:]]*=).*/Name=Install Hyggshi OS/; s/^Name\[[^]]+\][[:space:]]*=.*/Name=Install Hyggshi OS/' "$desktop_file"
      # Các bản desktop có thể dùng tên tiếng Việt/locale khác; thay theo key.
      sed -i -E 's/^Name\[[^]]+\][[:space:]]*=.*/Name=Install Hyggshi OS/' "$desktop_file"
      sed -i -E 's/^Icon=.*/Icon=hyggshi-installer/' "$desktop_file"
      chmod 644 "$desktop_file"
      echo "OK: đã rebrand launcher $desktop_file"
    fi
  done < <(find /usr/share/applications /usr/local/share/applications /etc/xdg/applications -type f -name '*.desktop' -print0 2>/dev/null)

  # Nếu package đặt shortcut trực tiếp trên Desktop của user live/skel,
  # sửa luôn shortcut đó để icon + tên trên màn hình cũng đồng nhất.
  while IFS= read -r -d '' desktop_file; do
    if grep -Eiq '^(Name|Name\[[^]]+\])=.*Install Debian|^(Name|Name\[[^]]+\])=.*Debian Installer|^Exec=.*(pkexec[[:space:]]+)?calamares' "$desktop_file"; then
      sed -i -E 's/^Name\[[^]]+\][[:space:]]*=.*/Name=Install Hyggshi OS/; s/^Name[[:space:]]*=.*/Name=Install Hyggshi OS/; s/^Icon=.*/Icon=hyggshi-installer/' "$desktop_file"
      chmod 755 "$desktop_file" 2>/dev/null || chmod 644 "$desktop_file"
      echo "OK: đã rebrand shortcut $desktop_file"
    fi
  done < <(find /etc/skel/Desktop /home /root/Desktop -type f -name '*.desktop' -print0 2>/dev/null)

  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database /usr/share/applications >/dev/null 2>&1 || true
  fi
  echo "OK: icon nguồn: $INSTALLER_ICON_SRC -> $INSTALLER_ICON_NAME"
  if [ "$FOUND_INSTALLER" = "0" ]; then
    echo "CẢNH BÁO: không tìm thấy launcher Calamares để đổi tên/icon." >&2
  fi
else
  echo "CẢNH BÁO: không có $INSTALLER_ICON_SRC — bỏ qua rebrand launcher Calamares." >&2
fi

echo "===== Polkit: cho phép user live mở Calamares KHÔNG cần nhập mật khẩu ====="
# Icon "Install Debian/Hyggshi OS" trên desktop live gọi launcher của
# Calamares settings, mặc định Exec=pkexec calamares — pkexec luôn
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
#      Calamares settings/calamares đăng ký.
#   2. action.id là action pkexec chung "org.freedesktop.policykit.exec" VÀ
#      chương trình được exec có chứa "calamares" -> khớp trường hợp không
#      có action riêng nào được đăng ký, pkexec rơi về action mặc định.
# Chỉ áp dụng cho ĐÚNG username live, không phải "mọi user trong nhóm sudo"
# — phạm vi hẹp nhất có thể để không mở rộng bypass mật khẩu sang việc khác.
if command -v pkexec >/dev/null 2>&1; then
  mkdir -p /etc/polkit-1/rules.d
  cat <<EOF > /etc/polkit-1/rules.d/45-hyggshi-calamares-noauth.rules
// Cho phép user live "$OS_USERNAME" mở Calamares (installer) qua pkexec mà
// không cần nhập mật khẩu — sinh tự động bởi scripts/target/desktop.sh.
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
# Calamares settings, xem calamares/modules/packages.conf trong repo
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
#         - Calamares settings
# Danh sách này giả định build bằng the old live-build layout (debian-live) đầy đủ. Build
# này KHÔNG dùng the old live-build layout, desktop.sh chỉ cài "live-boot" ở trên nên phần
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
CANDIDATE_LIVE_PKGS="live-boot live-boot-doc live-config live-config-doc live-config-systemd live-tools live-task-localisation live-task-recommended calamares"
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

# Cấu hình kernel boot của hệ thống ĐÃ CÀI. Calamares chạy update-grub trên
# target, vì vậy chỉ sửa grub.cfg của ISO là chưa đủ. Luôn giữ splash + KMS
# và cho phép GRUB dùng framebuffer hiện tại để Plymouth có nền đồ hoạ ổn định.
mkdir -p /etc/default
if [ -f /etc/default/grub ]; then
  sed -i -E 's#^GRUB_CMDLINE_LINUX_DEFAULT=.*#GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"#' /etc/default/grub
else
  cat > /etc/default/grub <<'GRUBEOF'
GRUB_DEFAULT=0
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR="Hyggshi OS"
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"
GRUB_CMDLINE_LINUX=""
GRUB_GFXPAYLOAD_LINUX=auto
GRUBEOF
fi
grep -q '^GRUB_GFXPAYLOAD_LINUX=' /etc/default/grub || echo 'GRUB_GFXPAYLOAD_LINUX=auto' >> /etc/default/grub

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

echo "===== Firmware / driver phần cứng (wifi, GPU, virtio...) ====="
# Cài firmware + các module đồ hoạ/network phổ biến thay vì chỉ cài
# linux-firmware/firmware-linux ở mức tối thiểu. Quan trọng: firmware phải
# thực sự được cài vào ROOTFS và initramfs phải được rebuild SAU CÙNG; nếu chỉ
# cài package mà giữ initrd cũ thì Plymouth/KMS có thể vẫn boot bằng fallback
# và máy thật có thể mất Wi-Fi/GPU firmware.
# Linux Mint is Ubuntu-based: install the firmware bundle and extra generic modules.
apt-get install -y linux-firmware
KERNEL_FLAVOUR=$(dpkg-query -W -f='${Package}\n' 'linux-image-*-generic' 'linux-image-*-lowlatency' 2>/dev/null | sed -E 's/^linux-image-[0-9.]+-[0-9]+-//' | sort -u | head -n1 || true)
: "${KERNEL_FLAVOUR:=generic}"
apt-get install -y "linux-modules-extra-${KERNEL_FLAVOUR}" || \
  apt-get install -y linux-modules-extra-generic || \
  echo "CẢNH BÁO: không cài được linux-modules-extra-* — một số driver ngoài kernel core có thể thiếu." >&2

# Driver Xorg/Mesa cho máy thật và QEMU (virtio-gpu). Không cài NVIDIA
# proprietary mặc định; nouveau + Mesa an toàn hơn cho ISO dùng chung.
GPU_PKGS="
  mesa-vulkan-drivers
  libgl1-mesa-dri
  libegl1-mesa
  libglx-mesa0
  xserver-xorg-video-amdgpu
  xserver-xorg-video-intel
  xserver-xorg-video-nouveau
  xserver-xorg-video-fbdev
"
GPU_AVAILABLE=""
for pkg in $GPU_PKGS; do
  if apt-cache show "$pkg" >/dev/null 2>&1; then
    GPU_AVAILABLE="$GPU_AVAILABLE $pkg"
  fi
done
apt-get install -y $GPU_AVAILABLE || true

# Các module KMS/virtio cần có trong initramfs để Plymouth có framebuffer/KMS
# thay vì rơi vào màn hình đen. MODULES=most cũng bảo đảm initramfs không bị
# tối giản quá mức sau khi Calamares cài hệ thống.
mkdir -p /etc/initramfs-tools
cat > /etc/initramfs-tools/conf.d/hyggshi-kms <<'EOF'
MODULES=most
EOF
touch /etc/initramfs-tools/modules
for mod in i915 amdgpu nouveau virtio_gpu virtio_pci drm drm_kms_helper e1000e r8169; do
  grep -qxF "$mod" /etc/initramfs-tools/modules || echo "$mod" >> /etc/initramfs-tools/modules
done

# Build a small helper so a newly installed system can regenerate firmware/KMS
# initramfs after a kernel or firmware update as well.
cat > /usr/local/sbin/hyggshi-refresh-initramfs <<'EOF'
#!/bin/sh
set -eu
if command -v update-initramfs >/dev/null 2>&1; then
  update-initramfs -u -k all
fi
EOF
chmod 0755 /usr/local/sbin/hyggshi-refresh-initramfs

# Rebuild NOW, after firmware + drivers + Plymouth have been installed.
echo "===== Rebuild initramfs sau khi cài firmware/driver ====="
update-initramfs -u -k all

# Bảo đảm NetworkManager được bật khi boot hệ thống đã cài. Trong chroot
# không start daemon, chỉ tạo symlink enable; Calamares sau đó giữ nguyên
# trạng thái này trên target.
if command -v systemctl >/dev/null 2>&1; then
  systemctl enable NetworkManager 2>/dev/null || systemctl enable NetworkManager.service 2>/dev/null || true
fi

echo "===== Bluetooth + tiện ích quản lý mạng không dây (mọi distro) ====="
# bluez (daemon/stack Bluetooth thật sự) trước giờ KHÔNG được cài ở đâu
# trong toàn bộ build — mục "Bluetooth Manager" hiện trong menu (do
# task-*-desktop kéo theo GUI applet) nhưng bấm vào không thấy adapter/
# thiết bị nào vì thiếu hẳn bluetoothd phía sau. blueman là applet GUI
# dùng chung được cho XFCE/Cinnamon/MATE/LXQt (khác panel riêng của từng
# DE). rfkill để tự bỏ soft-block wifi/bluetooth (khá nhiều máy/VM boot
# lên với card bị soft-block sẵn, wifi/bluetooth hiện trong danh sách
# nhưng không bật được tới khi rfkill unblock). wireless-tools/iw + 
# wpasupplicant khai báo tường minh dù network-manager thường tự kéo theo,
# để không phụ thuộc ngầm vào Recommends (một số build tắt Recommends).
apt-get install -y bluez bluez-obexd blueman rfkill wireless-tools iw wpasupplicant || \
  echo "CẢNH BÁO: thiếu ít nhất 1 gói bluetooth/wifi ở trên — kiểm tra log apt phía trên." >&2

# Bật bluetooth service (một số distro không auto-enable) + unblock rfkill
# ngay trong chroot cho session đầu tiên; systemctl trong chroot chỉ ghi
# symlink enable, không start được service thật (không có PID 1 thật) nên
# không cần chạy `systemctl start`, chỉ enable là đủ để boot thật tự bật.
if command -v systemctl > /dev/null 2>&1; then
  systemctl enable bluetooth 2>/dev/null || true
fi
mkdir -p /etc/systemd/system/multi-user.target.wants
cat <<'RFKILLEOF' > /usr/local/bin/hyggshi-rfkill-unblock.sh
#!/bin/sh
# Hyggshi OS — tự unblock wifi/bluetooth mỗi lần boot, phòng trường hợp
# firmware/BIOS soft-block sẵn (rfkill list hiện "Soft blocked: yes").
command -v rfkill >/dev/null 2>&1 && rfkill unblock all 2>/dev/null || true
exit 0
RFKILLEOF
chmod 0755 /usr/local/bin/hyggshi-rfkill-unblock.sh
cat <<'RFKILLSVC' > /etc/systemd/system/hyggshi-rfkill-unblock.service
[Unit]
Description=Hyggshi OS - unblock wifi/bluetooth rfkill at boot
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/hyggshi-rfkill-unblock.sh

[Install]
WantedBy=multi-user.target
RFKILLSVC
if command -v systemctl > /dev/null 2>&1; then
  systemctl enable hyggshi-rfkill-unblock.service 2>/dev/null || true
fi

# hostname
echo "$OS_HOSTNAME" > /etc/hostname
echo "127.0.1.1 $OS_HOSTNAME" >> /etc/hosts

# timezone
ln -sf "/usr/share/zoneinfo/$OS_TIMEZONE" /etc/localtime
dpkg-reconfigure -f noninteractive tzdata || true

case "$DE" in
  kde)
    apt-get install -y kde-plasma-desktop plasma-workspace sddm
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
      tela)
        apt-get install -y git > /dev/null 2>&1 || true
        if git clone --depth=1 https://github.com/vinceliuice/Tela-icon-theme.git /tmp/Tela-icon-theme; then
          /tmp/Tela-icon-theme/install.sh -d /usr/share/icons \
            || echo "⚠️  Cài Tela icon theme thất bại — giữ icon mặc định (Papirus)."
          rm -rf /tmp/Tela-icon-theme
        else
          echo "⚠️  Clone Tela-icon-theme thất bại — bỏ qua, giữ icon mặc định (Papirus)."
        fi
        ;;
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
    # Luôn kéo FULL Cinnamon qua metapackage, không tự chọn từng gói con lẻ
    # (cinnamon-core, nemo, cjs, muffin... riêng lẻ) — vì nếu 1 gói lẻ nào
    # đó lỗi/thiếu, hệ thống dễ thiếu app quan trọng mà không biết ngay lúc
    # build. cinnamon-desktop-environment là metapackage "full desktop with
    # extra components" có trên cả Debian lẫn Ubuntu (universe). Fallback
    # theo thứ tự nếu tên gói không có: task-cinnamon-desktop (task package
    # của tasksel, cũng kéo đủ cinnamon-desktop-environment) -> cinnamon-core
    # (chỉ desktop lõi, không kèm app phụ trợ — phương án cuối để build không
    # fail hoàn toàn nếu 2 lựa chọn trên đều không có trong repo/mirror).
    apt-get install -y cinnamon-desktop-environment lightdm lightdm-gtk-greeter || \
    apt-get install -y task-cinnamon-desktop lightdm lightdm-gtk-greeter || \
    { echo "CẢNH BÁO: cinnamon-desktop-environment/task-cinnamon-desktop không cài được — fallback cinnamon-core (thiếu một số app phụ trợ so với bản full)." >&2; \
      apt-get install -y cinnamon-core lightdm lightdm-gtk-greeter; }

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

# Hyggshi OS wallpaper mặc định cho Cinnamon. Đây là system default,
# áp dụng cho user mới kể cả khi user chưa chạy Hyggshi Welcome.
[org/cinnamon/desktop/background]
picture-uri='file:///usr/share/backgrounds/hyggshi/Verdant-Valley.png'
picture-uri-dark='file:///usr/share/backgrounds/hyggshi/Verdant-Valley.png'
picture-options='zoom'
EOF
    dconf update || echo "⚠️  dconf update thất bại — có thể do chạy trong chroot thiếu D-Bus, kiểm tra lại lúc boot thật."

    # Calamares can create the installed user's dconf database from the live
    # session. A user database has higher priority than /etc/dconf/db/local,
    # so install a one-time first-login guard that explicitly applies Tela to
    # the newly installed Cinnamon user. It runs only once and then leaves the
    # user's later theme choices untouched.
    if [ -f /tmp/fix-cinnamon-tela-persistence.sh ]; then
      bash /tmp/fix-cinnamon-tela-persistence.sh
    fi
    ;;

  *)
    # mặc định: xfce
    # Nguồn danh sách gói: packages/packages/desktop-xfce.list
    XFCE_PKGS="$(read_pkglist desktop-xfce.list | tr '\n' ' ')"
    if [ -n "$XFCE_PKGS" ]; then
      # shellcheck disable=SC2086
      apt-get install -y $XFCE_PKGS
    else
      echo "LỖI: desktop-xfce.list rỗng hoặc không đọc được — không cài được desktop XFCE." >&2
      exit 1
    fi

    # icon theme theo lựa chọn
    case "$ICON_THEME" in
      numix)   apt-get install -y numix-icon-theme ;;
      breeze)  apt-get install -y breeze-icon-theme ;;
      adwaita) apt-get install -y adwaita-icon-theme ;;
      tela)
        # Tela không có gói .deb chính thức trên mirror Debian/Ubuntu — cài
        # từ source giống hệt cách nhánh "cinnamon" bên dưới đã làm, có
        # fallback rõ ràng nếu clone lỗi (mạng/rate-limit) thay vì để build
        # fail giữa chừng.
        apt-get install -y git > /dev/null 2>&1 || true
        if git clone --depth=1 https://github.com/vinceliuice/Tela-icon-theme.git /tmp/Tela-icon-theme; then
          /tmp/Tela-icon-theme/install.sh -d /usr/share/icons \
            || echo "⚠️  Cài Tela icon theme thất bại — giữ icon mặc định (Papirus)."
          rm -rf /tmp/Tela-icon-theme
        else
          echo "⚠️  Clone Tela-icon-theme thất bại — bỏ qua, giữ icon mặc định (Papirus)."
        fi
        ;;
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

# ===== Fix "đơ" khi Restart/Shut Down/Suspend từ menu power (greeter hoặc
# trong session) =====
# NGUYÊN NHÂN PHỔ BIẾN NHẤT: task-*-desktop không đảm bảo cài kèm
# policykit-1 + 1 polkit authentication agent (mỗi DE có agent riêng: XFCE
# dùng xfce-polkit, MATE dùng mate-polkit, Cinnamon có agent tích hợp sẵn).
# Khi bấm Restart, lightdm-gtk-greeter/xfce4-session gọi thẳng
# org.freedesktop.login1.Reboot qua D-Bus -> polkit chặn lại hỏi xác thực ->
# KHÔNG có agent nào chạy để hiện hộp thoại nhập mật khẩu -> yêu cầu treo
# vô thời hạn, nhìn giống hệt "màn hình đơ" dù máy không hề crash.
# Fix gồm 2 phần: (1) cài agent đúng theo DE, (2) thêm polkit rule cho phép
# LUÔN thực hiện các hành động login1 (reboot/poweroff/suspend/hibernate,
# kể cả khi còn phiên khác đang mở) mà KHÔNG cần hỏi mật khẩu — hợp lý cho
# máy cá nhân/live session, không phải máy chia sẻ nhiều người dùng.
echo "===== Cài polkit agent + rule cho phép Restart/Shut Down không bị treo ====="
# Ubuntu 26.04/Resolute không còn package meta `policykit-1`; nó đã được
# thay bằng `polkitd` + `pkexec`. Không để lệnh cũ thất bại rồi vẫn đóng ISO
# thiếu polkit daemon. Với Debian cũ, fallback về policykit-1 vẫn được giữ.
if ! apt-get install -y polkitd pkexec; then
  apt-get install -y policykit-1 || true
fi
case "$DE" in
  xfce)     apt-get install -y xfce-polkit || apt-get install -y policykit-1-gnome || true ;;
  mate)     apt-get install -y mate-polkit || true ;;
  lxqt)     apt-get install -y lxqt-policykit || true ;;
  gnome)    : ;; # gnome-shell tự có agent tích hợp
  cinnamon) : ;; # cinnamon-settings-daemon tự có agent tích hợp
  kde)      : ;; # plasma-workspace tự có agent tích hợp (polkit-kde-agent)
esac

mkdir -p /etc/polkit-1/rules.d
cat <<'EOF' > /etc/polkit-1/rules.d/46-hyggshi-power-noauth.rules
// Hyggshi OS — cho phép reboot/poweroff/suspend/hibernate không cần mật
// khẩu (áp dụng cho user thuộc nhóm sudo, tức user cài đặt qua Calamares
// hoặc user mặc định live session). Nếu KHÔNG có rule này, thiếu polkit
// agent (xem desktop.sh) sẽ khiến nút Restart/Shut Down treo vô thời hạn
// thay vì báo lỗi rõ ràng.
polkit.addRule(function(action, subject) {
    if (subject.isInGroup("sudo") &&
        (action.id == "org.freedesktop.login1.reboot" ||
         action.id == "org.freedesktop.login1.reboot-multiple-sessions" ||
         action.id == "org.freedesktop.login1.power-off" ||
         action.id == "org.freedesktop.login1.power-off-multiple-sessions" ||
         action.id == "org.freedesktop.login1.suspend" ||
         action.id == "org.freedesktop.login1.suspend-multiple-sessions" ||
         action.id == "org.freedesktop.login1.hibernate" ||
         action.id == "org.freedesktop.login1.hibernate-multiple-sessions")) {
        return polkit.Result.YES;
    }
});
EOF
chmod 644 /etc/polkit-1/rules.d/46-hyggshi-power-noauth.rules
echo "OK: đã ghi /etc/polkit-1/rules.d/46-hyggshi-power-noauth.rules"

# systemd-logind là service socket-activated, không cần enable thủ công,
# nhưng chắc chắn có D-Bus policy cho phép gọi (mặc định Debian/Ubuntu đã
# đúng — chỉ log lại để dễ debug nếu vẫn còn bị treo sau khi build).
if command -v systemctl > /dev/null 2>&1; then
  systemctl status systemd-logind > /dev/null 2>&1 \
    && echo "systemd-logind: OK" \
    || echo "⚠️  Không thấy systemd-logind — kiểm tra lại nếu Restart vẫn treo sau khi build."
fi

# trình duyệt / office (tùy chọn)
if [ "$INCLUDE_BROWSER" = "true" ]; then
  if true; then
    # Ubuntu 26.04/Resolute (và Ubuntu-based Mint) cung cấp `firefox` como
    # snap-transition package. apt cài gói đó sẽ chạy preinst của snapd,
    # nhưng trong chroot build không có snapd/systemd/dev/tty đầy đủ:
    #   cannot create /dev/tty: No such device or address
    # Vì vậy KHÔNG cài gói snap-transition trong chroot. Dùng tarball chính
    # thức của Mozilla, chạy độc lập với snapd và phù hợp cho ISO offline.
    echo "===== Cài Firefox Mozilla tarball (không dùng snap trong chroot) ====="
    apt-get install -y curl ca-certificates xz-utils
    FIREFOX_TMP="$(mktemp -d)"
    trap 'rm -rf "$FIREFOX_TMP"' EXIT
    # Mozilla hiện phát hành Linux x86_64 tarball dạng .tar.xz. Endpoint
    # download.mozilla.org vẫn dùng được nhưng không còn đảm bảo trả về
    # .tar.bz2 như script cũ, nên tar -xjf sẽ lỗi "not a bzip2 file".
    FIREFOX_ARCHIVE="$FIREFOX_TMP/firefox.tar.xz"
    curl -fL --retry 3 --retry-delay 2 --retry-all-errors \
      "https://download.mozilla.org/?product=firefox-latest&os=linux64&lang=en-US" \
      -o "$FIREFOX_ARCHIVE"
    # Kiểm tra archive trước khi giải nén để báo lỗi rõ ràng nếu CDN
    # trả về HTML/error page thay vì tarball. `xz -t` không cần gói `file`.
    test -s "$FIREFOX_ARCHIVE"
    if ! xz -t "$FIREFOX_ARCHIVE" >/dev/null 2>&1; then
      echo "ERROR: Mozilla không trả về Firefox .tar.xz hợp lệ." >&2
      echo "HTTP/đầu file nhận được:" >&2
      head -c 200 "$FIREFOX_ARCHIVE" >&2 || true
      exit 1
    fi
    rm -rf /opt/firefox
    mkdir -p /opt
    tar -xJf "$FIREFOX_ARCHIVE" -C /opt
    test -x /opt/firefox/firefox
    ln -sf /opt/firefox/firefox /usr/local/bin/firefox
    cat > /usr/share/applications/firefox.desktop <<'FIREFOX_DESKTOP'
[Desktop Entry]
Name=Firefox
Comment=Web Browser
Exec=/opt/firefox/firefox %u
Icon=/opt/firefox/browser/chrome/icons/default/default128.png
Terminal=false
Type=Application
Categories=Network;WebBrowser;
MimeType=text/html;application/xhtml+xml;application/xml;image/webp;x-scheme-handler/http;x-scheme-handler/https;
StartupNotify=true
FIREFOX_DESKTOP
    chmod 0755 /opt/firefox/firefox
    rm -rf "$FIREFOX_TMP"
    trap - EXIT
  else
    apt-get install -y firefox || true
  fi
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

echo "===== Memtest86+ (cho mục 'Kiểm tra RAM' trong menu GRUB, xem scripts/host/build-iso.sh) ====="
# Best-effort, không fatal: thiếu gói này chỉ làm mất 1 mục GRUB tuỳ chọn
# (iso.sh tự bỏ qua mục đó nếu không tìm thấy binary trong chroot), không
# ảnh hưởng tới việc ISO boot được hay không.
apt-get install -y memtest86+ || \
  echo "CẢNH BÁO: không cài được memtest86+ — mục 'Kiểm tra RAM' trong GRUB sẽ bị bỏ qua." >&2

echo "===== Công cụ dev cơ bản (cmake, gcc) ====="
# Cần để build các component C++ tự sinh trong repo ngay TRÊN máy đã cài
# đặt (hyggshi-welcome — xem packages/hyggshi/hyggshi-welcome/,), không chỉ lúc build ISO trên CI. Best-effort (không
# fatal): thiếu 1 trong 2 gói này không nên làm hỏng cả build ISO.
# Nguồn danh sách gói: packages/packages/devtools.list
while IFS= read -r pkg; do
  if ! apt-get install -y "$pkg"; then
    echo "CẢNH BÁO: cài gói '$pkg' thất bại — không fatal, nhưng build C++ trên máy đích sẽ thiếu công cụ này." >&2
  fi
done < <(read_pkglist devtools.list)

echo "===== Flatpak + Software Center (Flathub-only) ====="
# Chỉ dùng Flathub trong Software. Debian trixie gnome-software vẫn có
# PackageKit plugin tích hợp sẵn; nếu để plugin này chạy, Software sẽ hiện
# thêm nguồn PACKAGE/"Hyggshi OS - Unknown source". Không cần gỡ thư viện
# PackageKit (gnome-software cần libpackagekit), chỉ block plugin lúc runtime.
# Đồng thời cài fuse3 + nạp module fuse để Flatpak revokefs-fuse có thể mount
# runtime (lỗi "Could not mount ... Child process exited with code 1").
for pkg in flatpak fuse3 gnome-software gnome-software-plugin-flatpak \
           xdg-desktop-portal xdg-desktop-portal-xapp xdg-desktop-portal-gtk; do
  if ! apt-get install -y --no-install-recommends "$pkg"; then
    echo "CẢNH BÁO: cài gói '$pkg' thất bại — bỏ qua gói này." >&2
  fi
done

# Không cài plugin .deb của GNOME Software. Đây là phần hỗ trợ hiển thị/cài
# package truyền thống; Hyggshi Software Center chỉ dùng Flatpak/Flathub.
apt-get purge -y gnome-software-plugin-deb 2>/dev/null || true

# Đảm bảo module FUSE được nạp ở mỗi lần boot. fuse3 tạo /dev/fuse khi module
# được nạp; Flatpak cần nó cho revokefs-fuse khi tải runtime/app.
mkdir -p /etc/modules-load.d
printf '%s\n' fuse > /etc/modules-load.d/fuse.conf

# Block PackageKit plugin của GNOME Software. GNOME Software hỗ trợ biến môi
# trường GNOME_SOFTWARE_PLUGINS_BLOCKLIST trong các bản hiện tại. Ghi vào
# /etc/environment để desktop launcher và các phiên đăng nhập mới cùng nhận.
if [ -f /etc/environment ]; then
  sed -i '/^GNOME_SOFTWARE_PLUGINS_BLOCKLIST=/d' /etc/environment
fi
printf '%s\n' 'GNOME_SOFTWARE_PLUGINS_BLOCKLIST=packagekit' >> /etc/environment

# Đăng ký duy nhất Flathub ở cấp hệ thống để mọi user mới đều thấy ứng dụng
# Flatpak trong Software. Không cài ứng dụng Flatpak trong lúc build ISO.
if command -v flatpak >/dev/null 2>&1; then
  if ! flatpak remote-add --if-not-exists --system flathub https://dl.flathub.org/repo/flathub.flatpakrepo; then
    echo "CẢNH BÁO: không thêm được Flathub — kiểm tra mạng/SSL rồi thử lại sau." >&2
  else
    echo "OK: Flathub đã được đăng ký ở cấp hệ thống."
  fi
  flatpak remotes --system || true
  # Dọn cache cũ có thể được tạo bởi các lần build lại cùng chroot.
  flatpak repair --system || true
fi

# GNOME Software cache/database có thể được tạo trước khi Flathub được thêm.
rm -rf /root/.cache/gnome-software /root/.cache/gnome-software/* 2>/dev/null || true

echo "===== Bộ gõ tiếng Việt (Fcitx5 + Fcitx5 Lotus) ====="
# Fcitx5 Lotus được cung cấp qua repo chính thức của dự án. Thêm repo theo
# VERSION_CODENAME, sau đó cài fcitx5-lotus. Nếu repo/package không hỗ trợ
# distro hiện tại thì build vẫn tiếp tục với fcitx5-unikey làm fallback.
for pkg in ca-certificates curl gnupg; do
  if ! apt-get install -y "$pkg"; then
    echo "CẢNH BÁO: cài gói '$pkg' thất bại — không thể chuẩn bị repo Lotus đầy đủ." >&2
  fi
done

LOTUS_REPO_ADDED=0
if command -v curl >/dev/null 2>&1 && command -v gpg >/dev/null 2>&1; then
  CODENAME=$(grep '^VERSION_CODENAME=' /etc/os-release 2>/dev/null | cut -d'=' -f2- | tr -d '"' || true)
  if [ -n "$CODENAME" ]; then
    mkdir -p /etc/apt/keyrings
    if curl -fsSL https://fcitx5-lotus.pages.dev/pubkey.gpg -o /tmp/fcitx5-lotus-pubkey.gpg && \
       gpg --dearmor --yes -o /etc/apt/keyrings/fcitx5-lotus.gpg /tmp/fcitx5-lotus-pubkey.gpg && \
       echo "deb [signed-by=/etc/apt/keyrings/fcitx5-lotus.gpg] https://fcitx5-lotus.pages.dev/apt/$CODENAME $CODENAME main" > /etc/apt/sources.list.d/fcitx5-lotus.list; then
      echo "OK: đã thêm repo Fcitx5 Lotus cho codename '$CODENAME'."
      if apt-get update; then
        LOTUS_REPO_ADDED=1
      else
        echo "CẢNH BÁO: apt update với repo Lotus thất bại — gỡ repo để không làm hỏng các bước apt sau." >&2
        rm -f /etc/apt/sources.list.d/fcitx5-lotus.list /etc/apt/keyrings/fcitx5-lotus.gpg
        apt-get update || true
      fi
    else
      echo "CẢNH BÁO: không tải/thiết lập được khóa hoặc repo Fcitx5 Lotus — bỏ qua Lotus." >&2
    fi
  else
    echo "CẢNH BÁO: không tìm thấy VERSION_CODENAME — bỏ qua repo Fcitx5 Lotus." >&2
  fi
fi

# Nguồn danh sách gói: packages/packages/vietnamese-input.list
while IFS= read -r pkg; do
  if ! apt-get install -y "$pkg"; then
    echo "CẢNH BÁO: cài gói '$pkg' (Fcitx5) thất bại — bỏ qua gói này." >&2
  fi
done < <(read_pkglist vietnamese-input.list)

if [ "$LOTUS_REPO_ADDED" = "1" ]; then
  if apt-get install -y fcitx5-lotus; then
    echo "OK: đã cài Fcitx5 Lotus."
  else
    echo "CẢNH BÁO: không cài được fcitx5-lotus — giữ fcitx5-unikey làm fallback." >&2
  fi
fi

if command -v fcitx5 > /dev/null 2>&1; then
  echo "OK: đã cài fcitx5."
  # Biến môi trường input-method chuẩn (GTK/Qt/X11 XIM/SDL) — áp dụng
  # cho MỌI phiên đăng nhập. GLFW_IM_MODULE=ibus được giữ đúng theo hướng
  # dẫn Lotus; các ứng dụng GLFW riêng có thể dùng IBus compatibility layer.
  # Thay giá trị cũ nếu tồn tại để không bị trùng biến.
  sed -i '/^GTK_IM_MODULE=/d; /^QT_IM_MODULE=/d; /^XMODIFIERS=/d; /^SDL_IM_MODULE=/d; /^GLFW_IM_MODULE=/d' /etc/environment 2>/dev/null || true
  cat >> /etc/environment <<'ENVEOF'
GTK_IM_MODULE=fcitx
QT_IM_MODULE=fcitx
XMODIFIERS=@im=fcitx
SDL_IM_MODULE=fcitx
GLFW_IM_MODULE=ibus
ENVEOF
  echo "OK: đã ghi biến môi trường input-method vào /etc/environment."

  # Fcitx5 thường đã cài autostart. Tạo thêm session helper để bật server
  # Lotus theo từng user sau khi desktop đã có systemd --user.
  cat > /usr/local/bin/hyggshi-fcitx5-lotus-session <<'LOTOSEOF'
#!/bin/sh
if command -v systemctl >/dev/null 2>&1; then
  systemctl --user enable --now "fcitx5-lotus-server@$(id -un).service" 2>/dev/null || true
fi
exit 0
LOTOSEOF
  chmod 0755 /usr/local/bin/hyggshi-fcitx5-lotus-session
  mkdir -p /etc/xdg/autostart
  cat > /etc/xdg/autostart/hyggshi-fcitx5-lotus-server.desktop <<'DESKTOPEOF'
[Desktop Entry]
Type=Application
Name=Fcitx5 Lotus Server
Comment=Start the Fcitx5 Lotus server for the current user
Exec=/usr/local/bin/hyggshi-fcitx5-lotus-session
OnlyShowIn=Cinnamon;GNOME;XFCE;MATE;KDE;LXQt;
X-GNOME-Autostart-Phase=Application
X-GNOME-Autostart-enabled=true
NoDisplay=true
DESKTOPEOF

  # Tắt IBus autostart để tránh chạy song song với Fcitx5. Không purge ibus
  # vì một số desktop/meta-package có thể phụ thuộc vào nó.
  cat > /etc/xdg/autostart/ibus.desktop <<'IBUSOFF'
[Desktop Entry]
Type=Application
Name=IBus (disabled by Hyggshi OS)
Hidden=true
NoDisplay=true
X-GNOME-Autostart-enabled=false
IBUSOFF
  rm -f /etc/xdg/autostart/ibus-daemon.desktop /etc/xdg/autostart/ibus-autostart.desktop 2>/dev/null || true
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
  #
  # BUG VỪA PHÁT HIỆN (regression): job này TRƯỚC ĐÂY còn có tên
  # "shellprocess@removeuser" và có xoá luôn tài khoản + home của user live
  # (comment cũ đã nói vậy), nhưng lúc gộp vào "removeautologin" thì lệnh
  # userdel bị RỚT MẤT — kết quả: user live ($OS_USERNAME, vd "hyggshi")
  # cùng /home/$OS_USERNAME của nó sống sót nguyên vẹn trên hệ thống đã cài,
  # song song với tài khoản thật user tự tạo trong Calamares (nếu họ gõ
  # username khác, vd "my") -> 2 thư mục trong /home, folder mới bị chặn
  # quyền truy cập vì đang login bằng account live cũ.
  # Ghi 1 script cleanup riêng (thay vì nhét hết vào 1 dòng exec YAML) để dễ
  # đọc/debug, và AN TOÀN: chỉ xoá user live nếu phát hiện có ÍT NHẤT 1 user
  # thật KHÁC (uid 1000-59999, khác $OS_USERNAME) đã được Calamares tạo —
  # tức là user đã đổi username khi cài. Nếu user giữ nguyên username cũ
  # (gõ lại đúng "$OS_USERNAME" ở bước Create your account) thì KHÔNG xoá,
  # vì lúc đó chính tài khoản đó là tài khoản thật.
  mkdir -p /etc/calamares/modules
  cat <<EOF > /usr/local/sbin/hyggshi-cleanup-live-user.sh
#!/bin/sh
set -e
LIVE_USER="$OS_USERNAME"
OTHER_USER=\$(awk -F: -v lu="\$LIVE_USER" '\$3>=1000 && \$3<60000 && \$1!=lu {print \$1; exit}' /etc/passwd)
if [ -n "\$OTHER_USER" ] && id "\$LIVE_USER" >/dev/null 2>&1; then
  echo "hyggshi-cleanup-live-user: phat hien user that '\$OTHER_USER' khac user live '\$LIVE_USER' -> xoa user live."
  userdel -r "\$LIVE_USER" 2>/dev/null || userdel "\$LIVE_USER" 2>/dev/null || true
  rm -rf "/home/\$LIVE_USER" 2>/dev/null || true
else
  echo "hyggshi-cleanup-live-user: khong co user that nao khac '\$LIVE_USER' -> giu nguyen, khong xoa."
fi
EOF
  chmod 755 /usr/local/sbin/hyggshi-cleanup-live-user.sh
  echo "OK: đã ghi /usr/local/sbin/hyggshi-cleanup-live-user.sh (LIVE_USER=$OS_USERNAME)."

  # QUAN TRỌNG (đây là root cause thật sự của toàn bộ bug sudoers/autologin
  # sống sót, xác nhận qua session.log lúc cài thật):
  # Calamares tra config của 1 job INSTANCE (dạng "module@instance") theo
  # TÊN INSTANCE, tức phải là "<instance>.conf" (ở đây là
  # "removeautologin.conf") — KHÔNG PHẢI "<module>-<instance>.conf". Bản cũ
  # ghi nhầm thành "shellprocess-removeautologin.conf" nên Calamares không
  # tìm thấy config, fallback tìm theo tên MODULE gốc "shellprocess.conf"
  # (cũng không có luôn), rồi load job với "No commands to execute" — job
  # chạy "thành công" trong log nhưng thực chất KHÔNG LÀM GÌ CẢ. Đây là lý
  # do 90-hyggshi-live-nopasswd và autologin sống sót nguyên vẹn dù mọi thứ
  # khác (ghi file, chèn vào sequence) đều đúng.
  cat <<'EOF' > /etc/calamares/modules/removeautologin.conf
---
dontChroot: false
timeout: 30
script:
  - "rm -f /etc/lightdm/lightdm.conf.d/50-hyggshi-autologin.conf"
  - "rm -f /etc/sddm.conf.d/hyggshi-autologin.conf"
  - "sh -c \"if [ -f /etc/gdm3/custom.conf ]; then sed -i -E 's/^#?[[:space:]]*AutomaticLoginEnable[[:space:]]*=.*/AutomaticLoginEnable = false/' /etc/gdm3/custom.conf; sed -i -E 's/^#?[[:space:]]*AutomaticLogin[[:space:]]*=.*/#AutomaticLogin =/' /etc/gdm3/custom.conf; fi; true\""
  - "rm -f /etc/sudoers.d/90-hyggshi-live-nopasswd"
  - "sh -c \"[ -x /usr/local/sbin/hyggshi-cleanup-live-user.sh ] && /usr/local/sbin/hyggshi-cleanup-live-user.sh || true\""
  - "rm -f /usr/local/sbin/hyggshi-cleanup-live-user.sh"
  - "sh -c \"! test -e /etc/sudoers.d/90-hyggshi-live-nopasswd && ! test -e /etc/lightdm/lightdm.conf.d/50-hyggshi-autologin.conf && ! test -e /etc/sddm.conf.d/hyggshi-autologin.conf\""
EOF
  echo "OK: đã ghi /etc/calamares/modules/removeautologin.conf (tên file PHẢI khớp instance id, không phải module-instance)."

  echo "===== Đăng ký instance shellprocess@removeautologin + chèn vào sequence ====="
  if [ -f /etc/calamares/settings.conf ]; then
    # Calamares KHÔNG tự suy ra config của custom shellprocess instance từ
    # tên file. Instance phải được khai báo rõ trong settings.conf:
    #   id: removeautologin
    #   module: shellprocess
    #   config: removeautologin.conf
    # Nếu thiếu block này, shellprocess@removeautologin có thể không dùng
    # removeautologin.conf và cleanup user/autologin/sudoers sẽ không chạy.
    if ! grep -Eq '^\s*-\s*id:[[:space:]]*removeautologin[[:space:]]*$' /etc/calamares/settings.conf; then
      if grep -Eq '^instances:[[:space:]]*$' /etc/calamares/settings.conf; then
        sed -i '/^instances:[[:space:]]*$/a - id: removeautologin\n  module: shellprocess\n  config: removeautologin.conf' /etc/calamares/settings.conf
      else
        sed -i '/^sequence:[[:space:]]*$/i instances:\n- id: removeautologin\n  module: shellprocess\n  config: removeautologin.conf\n' /etc/calamares/settings.conf
      fi
    fi

    if grep -Eq '^\s*-\s*id:[[:space:]]*removeautologin[[:space:]]*$' /etc/calamares/settings.conf; then
      echo "OK: đã đăng ký instance removeautologin -> shellprocess / removeautologin.conf."
    else
      echo "LỖI NGHIÊM TRỌNG: không đăng ký được instance removeautologin trong settings.conf." >&2
      cat /etc/calamares/settings.conf >&2
      exit 1
    fi

    if grep -Eq '^\s*-\s*shellprocess@removeautologin\s*$' /etc/calamares/settings.conf; then
      echo "settings.conf đã có shellprocess@removeautologin trong sequence — bỏ qua, không chèn trùng."
    else
      # Anchor chính vào "- packages": module này CHẮC CHẮN có trong sequence vì
      # chính desktop.sh vừa ghi /etc/calamares/modules/packages.conf ở
      # trên (mục "Ghi đè packages.conf"). Chèn SAU "packages" (job purge
      # gói live chạy gần cuối exec sequence) để đảm bảo job xoá autologin
      # chạy sau khi mọi thứ khác đã xong, ngay trước umount. Giữ đúng
      # nguyên tắc thụt lề động (dùng \1) như khối chèn "license" ở dưới,
      # tránh lỗi YAML fold dòng khi indent gốc khác 2 space.
      sed -i -E 's/^([[:space:]]*)-[[:space:]]*packages[[:space:]]*$/&\n\1- shellprocess@removeautologin/' /etc/calamares/settings.conf

      # FALLBACK: nếu Calamares settings trên nhánh trixie hiện tại
      # đổi format/tên job "packages" (khác version, khác cấu trúc YAML) thì
      # anchor trên sẽ không khớp và KHÔNG được chèn — trước đây trường hợp
      # này chỉ in CẢNH BÁO rồi build vẫn tiếp tục, kết quả là ISO xuất xưởng
      # với sudoers NOPASSWD + autologin sống sót nguyên vẹn sau khi cài thật
      # (đây chính là bug đã gặp: sau Calamares + reboot, "sudo apt update"
      # không hỏi mật khẩu và cũng không có màn hình đăng nhập). Anchor dự
      # phòng vào "- umount" (job gần như luôn có, luôn là bước chroot cuối
      # cùng) và chèn TRƯỚC nó để job vẫn chạy trong lúc còn chroot.
      if ! grep -Eq '^\s*-\s*shellprocess@removeautologin\s*$' /etc/calamares/settings.conf; then
        echo "CẢNH BÁO: không tìm thấy pattern '- packages', thử anchor dự phòng '- umount'..." >&2
        sed -i -E 's/^([[:space:]]*)-[[:space:]]*umount[[:space:]]*$/\1- shellprocess@removeautologin\n&/' /etc/calamares/settings.conf
      fi

      if grep -Eq '^\s*-\s*shellprocess@removeautologin\s*$' /etc/calamares/settings.conf; then
        echo "OK: đã chèn 'shellprocess@removeautologin' vào sequence."
        echo "--- settings.conf (instance + sequence, để kiểm tra trong build log) ---"
        grep -A 8 '^instances:' /etc/calamares/settings.conf || true
        grep -A 30 '^sequence:' /etc/calamares/settings.conf || true
      else
        # KHÔNG chỉ warn rồi cho qua nữa: đây là lỗ hổng bảo mật thật sự
        # (NOPASSWD sudo + autologin sống sót sang hệ thống đã cài đặt thật)
        # nên phải làm FAIL cả build để không lỡ tay xuất xưởng ISO lỗi.
        echo "LỖI NGHIÊM TRỌNG: không tìm được cả 2 anchor ('packages' và 'umount') trong" >&2
        echo "/etc/calamares/settings.conf để chèn 'shellprocess@removeautologin'. Nếu build tiếp" >&2
        echo "tục, ISO xuất ra sẽ để lại sudoers NOPASSWD + autologin trên hệ thống cài thật." >&2
        echo "--- settings.conf hiện tại (để debug) ---" >&2
        cat /etc/calamares/settings.conf >&2
        exit 1
      fi
    fi
  else
    echo "LỖI NGHIÊM TRỌNG: /etc/calamares/settings.conf không tồn tại — không thể chèn" >&2
    echo "shellprocess@removeautologin, ISO sẽ để lại sudoers NOPASSWD + autologin sau khi cài thật." >&2
    exit 1
  fi
else
  echo "Calamares chưa được cài (xem cảnh báo phía trên) — bỏ qua bước ghi users.conf."
fi

# ============================================================
# >>> THÊM MỚI: LICENSE MODULE <<<
# Trang "License" của Calamares (module "license") hiển thị thoả thuận
# bản quyền / third-party software TRƯỚC bước locale, để user tick đồng ý
# trước khi cài. Module này KHÔNG có sẵn trong sequence mặc định của
# Calamares settings nên phải: (1) ghi license.conf, (2) chèn
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
  # trong build-hyggshi-os.yml, chỗ đang copy kernel-tuning.sh).
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
      # Calamares settings đổi format (khác thụt lề/quote) ở version
      # mới hơn, sed sẽ KHÔNG khớp gì và không chèn được gì cả -> phải kiểm
      # tra lại bằng grep bên dưới, không được coi exit code 0 của sed là
      # "đã chèn thành công".
      #
      # QUAN TRỌNG: KHÔNG hardcode số cột thụt lề (trước đây dùng cứng 4
      # space "    - license") — Calamares settings thường thụt lề
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
# Linux Mint uses one standard tuning profile; edition-specific Debian/Arch tuning is removed.
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
