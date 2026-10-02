# Hướng Dẫn & Chuẩn Hoá UEFI Secure Boot — Hyggshi OS

Tài liệu này giải thích chi tiết về kiến trúc **UEFI Secure Boot**, quy trình ký số với **shim được Microsoft chứng thực**, cách khắc phục triệt để lỗi Secure Boot trên máy tính người dùng (điển hình như Dell Vostro 3400), và các quy tắc bảo mật khóa riêng tư (Private Keys).

---

## 1. Phân Tích Sự Cố: Dell SupportAssist Báo Lỗi Secure Boot

### Hiện tượng
Khi người dùng cắm USB Live hoặc khởi động sau khi cài đặt Hyggshi OS trên laptop (ví dụ: Dell Vostro 3400) có bật Secure Boot trong BIOS, màn hình Dell SupportAssist On-board Diagnostics xuất hiện cảnh báo:

> **⚠️ Operating System Loader has no signature. Incompatible with SecureBoot. All bootable devices failed Secure Boot**

### Nguyên nhân kỹ thuật
1. **Đối với bản cài đặt (sau khi chạy Calamares):**
   - Mặc định Calamares với cấu hình `installEFIFallback: true` sẽ copy file `grubx64.efi` đè lên vị trí bootloader mặc định `/boot/efi/EFI/BOOT/BOOTX64.EFI`.
   - File `grubx64.efi` chỉ được ký bởi Debian CA (hoặc không có chữ ký nếu do `grub-install` biên dịch cục bộ). Firmware UEFI của bo mạch chủ Dell **chỉ tin cậy chứng chỉ "Microsoft Corporation UEFI CA"** nằm sẵn trong biến `db` của BIOS từ lúc xuất xưởng.
   - Khi Dell nạp `BOOTX64.EFI`, phát hiện không có chữ ký Microsoft hợp lệ, firmware lập tức khóa máy và hiển thị lỗi.

2. **Đối với USB Live ISO:**
   - Nếu quá trình build ISO không đóng gói đúng file `shimx64.efi.signed` (đã ký bởi Microsoft) làm `BOOTX64.EFI`, hoặc rơi vào nhánh fallback tạo GRUB unsigned (`grub-mkrescue`), USB sẽ bị BIOS từ chối boot ngay lập tức.

---

## 2. Mô Hình Chuỗi Tin Cậy Chuẩn (Chain of Trust)

Trong hệ sinh thái Linux thương mại và cộng đồng (Ubuntu, Fedora, Debian, openSUSE), **tuyệt đối không bao giờ yêu cầu người dùng cuối:**
> *“Vào BIOS → Chuyển sang Custom Mode → Enroll key của Hyggshi”* 💀

Yêu cầu này vi phạm trải nghiệm người dùng, tiềm ẩn nguy cơ làm brick BIOS, và làm mất khả năng boot song song (Dual Boot) với Windows.

### Chuỗi tin cậy chuẩn thực tế:

```
PC Firmware (UEFI BIOS có sẵn "Microsoft Corporation UEFI CA" trong factory db)
     │
     │ 1. Xác thực bằng chữ ký Microsoft UEFI CA
     ▼
  shim (BOOTX64.EFI) — [ĐƯỢC MICROSOFT KÝ SẴN]
     │
     │ 2. Xác thực bằng chứng chỉ Distro nhúng sẵn trong shim hoặc qua MOK
     ▼
  GRUB (grubx64.efi) — [ĐƯỢC DISTRO KÝ]
     │
     │ 3. Xác thực Kernel qua giao thức EFI load image / verify
     ▼
  Linux Kernel (vmlinuz) — [ĐƯỢC DISTRO KÝ]
     │
     ▼
  Hyggshi OS (Khởi chạy hệ thống hoàn chỉnh)
```

---

## 3. Quy Tắc Bảo Mật: Quản Lý Khóa & GitHub

### ⚠️ CẢNH BÁO QUAN TRỌNG: KHÔNG COMMIT PRIVATE KEY LÊN GITHUB

Tuyệt đối không lưu các khóa riêng tư (`.key`) trong repository Git:

```
GitHub Repository
└── secureboot/
    ├── PK.key       ❌ TUYỆT ĐỐI KHÔNG
    ├── KEK.key      ❌ TUYỆT ĐỐI KHÔNG
    └── db.key       ❌ TUYỆT ĐỐI KHÔNG
```

Nếu private key bị lộ lên GitHub, toàn bộ chuỗi chứng thực sẽ bị coi là thỏa hiệp (compromised), và Microsoft/UEFI Forum có thể đưa chứng chỉ vào danh sách thu hồi (`dbx`).

### Phân biệt vai trò của các tầng khóa trong UEFI:

| Loại Khóa | Tên Đầy Đủ | Phạm Vi & Vai Trò | Ai Nắm Giữ? |
| :--- | :--- | :--- | :--- |
| **PK** | Platform Key | Khóa gốc tối cao của bo mạch chủ, kiểm soát quyền ghi đè KEK. | OEM (Dell, Asus, HP, Lenovo...) |
| **KEK** | Key Exchange Key | Khóa trung gian, kiểm soát việc cập nhật danh sách `db` và `dbx`. | OEM & Microsoft |
| **db** | Signature Database | Danh sách chứng chỉ/hash các loader được phép chạy (bao gồm Microsoft Windows CA & Microsoft 3rd Party UEFI CA). | Chứa trong firmware máy |
| **dbx** | Forbidden Database | Danh sách thu hồi các bootloader có lỗ hổng bảo mật. | Cập nhật qua Windows Update / fwupd |
| **MOK** | Machine Owner Key | Khóa riêng do **shim** quản lý trong NVRAM, cho phép người dùng hoặc distro nạp driver ngoài (NVIDIA, VirtualBox) mà không cần can thiệp vào PK/db của BIOS. | Do máy người dùng / distro cấp |

---

## 4. Kiến Trúc Ký Số Trong GitHub Actions Của Hyggshi OS

Đối với Hyggshi OS, quy trình build tự động trên GitHub Actions được chuẩn hoá theo sơ đồ:

```
Hyggshi GitHub Actions Pipeline
        │
        ├── 1. Build ISO & Rootfs (debootstrap, chroot, desktop.sh)
        │
        ├── 2. Cài đặt bootloader:
        │      ├── shim-signed (Microsoft-signed binary từ Debian upstream)
        │      └── grub-efi-*-signed (Signed GRUB từ Debian upstream)
        │
        ├── 3. Môi trường ký số bảo mật (Secure Signing Environment):
        │      ├── Kiểm tra chữ ký hiện tại bằng `sbverify`
        │      └── NẾU có custom kernel/modules:
        │          Ký tự động bằng GitHub Actions Secrets:
        │          - ${{ secrets.SECURE_BOOT_KEY }}
        │          - ${{ secrets.SECURE_BOOT_CERT }}
        │          (Key được ghi vào ramdisk tạm, phân quyền 0600, shred ngay sau khi ký)
        │
        └── 4. Đóng gói Hybrid ISO bằng xorriso:
               - Phân vùng El Torito BIOS MBR
               - Phân vùng UEFI ESP (BOOTX64.EFI = shim Microsoft)
```

---

## 5. Các Thay Đổi Kỹ Thuật Đã Áp Dụng Trong Repo

1. **`.gitignore`:**
   - Đã thêm quy tắc chặn hoàn toàn các định dạng khóa: `*.key`, `*.priv`, `*.pem`, `*.pfx`, `PK.*`, `KEK.*`, `db.*`, `MOK.*`.
2. **`scripts/secureboot.sh`:**
   - Tạo thư viện chuyên trách kiểm tra chữ ký (`hyggshi_sb_verify`), kiểm tra nguồn gốc Microsoft (`hyggshi_sb_is_microsoft_signed`), cấu trúc hóa phân vùng ESP (`hyggshi_sb_setup_esp_tree`), và ký số an toàn bằng GitHub Secrets (`hyggshi_sb_sign_with_secrets_if_available`).
3. **`iso-config/calamares/modules/bootloader.conf`:**
   - Đặt `installEFIFallback: false` để ngăn Calamares copy đè file `grubx64.efi` không có chữ ký Microsoft vào `BOOTX64.EFI`.
   - Đặt `efiBootloaderId: "hyggshi"`.
4. **`iso-config/calamares/hyggshi-secureboot-postinstall.sh` & module `hyggshi-secureboot.conf`:**
   - Chạy ngay sau bước `bootloader` trong Calamares:
   - Đảm bảo `/boot/efi/EFI/BOOT/BOOTX64.EFI` luôn là bản `shimx64.efi` đã được Microsoft ký.
   - Sao chép kèm `grubx64.efi` đã ký và `mmx64.efi` (MokManager).
   - Đăng ký NVRAM entry trỏ đúng vào `\EFI\hyggshi\shimx64.efi` thông qua `efibootmgr`.
5. **`scripts/iso.sh`:**
   - Tích hợp `secureboot.sh`, xác thực tính hợp lệ của shim Microsoft trước khi đóng gói ISO.
   - Loại bỏ hoàn toàn nguy cơ âm thầm fallback sang `grub-mkrescue` unsigned khi build bản phát hành.

---

## 6. Hướng Dẫn Sử Dụng Thực Tế (Usage Guide)

### Trường Hợp 1: Sử Dụng Mặc Định (Khuyên dùng — Không cần cấu hình gì thêm)
Đây là cách 99% người dùng và nhà phát triển sử dụng. Bạn **không cần làm gì cả**:

1. **Build ISO:**
   - Trên GitHub, vào tab **Actions** → chạy workflow **Build Hyggshi OS ISO** (chọn distro mặc định `debian` hoặc `ubuntu`).
   - Workflow sẽ tự động lấy các thành phần đã ký chuẩn từ Debian/Ubuntu:
     - `shim-signed` (được Microsoft ký).
     - `grub-efi-amd64-signed` (được Debian/Ubuntu ký).
     - `linux-image-*` (kernel được Debian/Ubuntu ký).
2. **Flash ra USB & Khởi động:**
   - Ghi file ISO ra USB bằng Rufus, BalenaEtcher hoặc `dd`.
   - Cắm vào laptop (Dell, HP, Lenovo...) có bật **Secure Boot: ON**. Máy sẽ boot thẳng vào Live Desktop của Hyggshi OS mà **không gặp cảnh báo SupportAssist**.
3. **Cài đặt vào máy:**
   - Nhấn icon **Install Hyggshi OS** (Calamares).
   - Calamares cài đặt xong, hook `hyggshi-secureboot-postinstall.sh` sẽ tự động cấu hình `BOOTX64.EFI` là Microsoft Shim và đăng ký NVRAM entry.
   - Khởi động lại máy: Hyggshi OS khởi động trực tiếp mà không cần vào BIOS tắt Secure Boot.

---

### Trường Hợp 2: Bạn Tự Build Kernel Riêng / Driver Riêng (Nâng cao)
Nếu bạn tự biên dịch kernel tùy chỉnh (custom kernel) không có sẵn chữ ký của Debian/Ubuntu, bạn sử dụng hệ thống **GitHub Actions Secrets** để ký tự động:

1. **Tạo cặp khóa ký riêng trên máy cá nhân của bạn (chạy 1 lần):**
   ```bash
   openssl req -new -x509 -newkey rsa:2048 \
     -keyout my-signing-key.key \
     -out my-signing-cert.crt \
     -nodes -days 3650 -subj "/CN=Hyggshi OS Custom Signing Key/"
   ```
   > ⚠️ **TUYỆT ĐỐI KHÔNG commit file `my-signing-key.key` vào GitHub!**

2. **Thêm vào GitHub Repository Secrets:**
   - Vào GitHub Repo: **Settings** → **Secrets and variables** → **Actions** → **New repository secret**.
   - Tạo secret `SECURE_BOOT_KEY`: Dán toàn bộ nội dung file `my-signing-key.key`.
   - Tạo secret `SECURE_BOOT_CERT`: Dán toàn bộ nội dung file `my-signing-cert.crt`.

3. **Chạy Build:**
   - Khi workflow chạy, `scripts/iso.sh` và `scripts/secureboot.sh` sẽ tự động phát hiện 2 secret này và ký kernel tùy biến của bạn bằng `sbsign`.
   - Private key được nạp tạm thời và tiêu hủy ngay sau khi ký, đảm bảo an toàn 100%.

---

### Trường Hợp 3: Kiểm Tra Chữ Ký Thủ Công (Local Debug)
Để kiểm tra xem file `.efi` hoặc `vmlinuz` trên máy có chữ ký hợp lệ hay không:
```bash
# Kiểm tra file shim
sbverify --list live-build/image/EFI/BOOT/BOOTX64.EFI

# Kiểm tra file GRUB
sbverify --list live-build/image/EFI/BOOT/grubx64.efi

# Kiểm tra file Kernel
sbverify --list live-build/image/live/vmlinuz
```
Nếu chữ ký hợp lệ, lệnh sẽ in ra thông tin chứng chỉ (`Microsoft Corporation UEFI CA` hoặc `Debian Secure Boot CA`).

