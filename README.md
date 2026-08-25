# Hyggshi OS

Một bản phân phối Linux tùy biến dựa trên Debian, được xây dựng bằng pipeline `debootstrap` + `mksquashfs` + `xorriso` (không sử dụng `live-build`).

## Yêu cầu để Build

* Máy chủ Linux (hoặc sử dụng `Dockerfile` được cung cấp để build trong container)
* Quyền `root` / `sudo`
* Khoảng **5 GB dung lượng ổ đĩa trống**

## Build

```bash
sudo bash scripts/local-build.sh
```

Cấu hình được truyền thông qua các biến môi trường (xem phần giá trị mặc định ở đầu `scripts/local-build.sh`). Ví dụ:

`HYGGSHI_VERSION_ID` là **phiên bản riêng của Hyggshi OS**, độc lập với phiên bản của distro nền. Trong GitHub Actions, có thể chỉnh trực tiếp thông qua input `hyggshi_version`; khi build local, mặc định là `1.0`.

```bash
BASE_DISTRO=debian DEBIAN_VERSION=trixie DE=xfce \
sudo -E bash scripts/local-build.sh
```

GitHub Actions sử dụng cùng pipeline (`scripts/build.sh` + `scripts/desktop.sh` + `scripts/iso.sh`) để build cho các distro nền `debian`, `ubuntu` và `linuxmint` — xem thư mục `.github/workflows`.

## Stack

* **Base:** Debian Trixie (13) theo mặc định — Ubuntu Noble và Linux Mint 22 cũng được hỗ trợ thông qua `BASE_DISTRO`
* **Desktop:** XFCE (mặc định; có thể chọn `kde`, `lxqt`, `gnome`, `mate`, `cinnamon` thông qua `DE`)
* **Display/Login Manager:** LightDM (chỉ tự động đăng nhập trong phiên live — xem mục "Tự động đăng nhập" bên dưới)
* **Trình cài đặt:** Calamares
* **Kiến trúc:** amd64

## Tự động đăng nhập: Live và Hệ thống đã cài đặt

Phiên live trên ISO sẽ tự động đăng nhập vào LightDM/XFCE, giúp người dùng vào thẳng desktop ngay lập tức.

Sau khi Calamares hoàn tất việc cài đặt lên ổ đĩa, job `shellprocess@removeautologin` sẽ xóa cấu hình tự động đăng nhập của phiên live khỏi hệ thống đã cài đặt. Vì vậy, khi máy thật khởi động, LightDM sẽ hiển thị màn hình đăng nhập yêu cầu **tên người dùng + mật khẩu**.

## Liên kết

* Website: [https://hyggshi-os-website.pages.dev](https://hyggshi-os-website.pages.dev)

## Branding nền GRUB

Để áp dụng hình nền GRUB riêng, đặt hai file branding vào đúng đường dẫn:

* `iso-config/branding/desktop-grub.png` — file PNG được GRUB sử dụng làm hình nền.
* `iso-config/branding/desktop-grub.svg` — phiên bản vector được đóng gói kèm theo để làm source branding.

`./scripts/iso.sh` sẽ tự động copy cả hai file vào ISO và sử dụng `desktop-grub.png` làm nền GRUB.

Nếu thiếu file PNG, ISO **vẫn được build bình thường** và GRUB sẽ sử dụng hình nền mặc định.
