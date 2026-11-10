# UEFI Secure Boot Guide & Standardization — Hyggshi OS

This document explains in detail the **UEFI Secure Boot** architecture, the code signing workflow with **Microsoft-authenticated shim**, methods to permanently resolve Secure Boot errors on user machines (e.g., Dell Vostro 3400), and security policies for Private Key management.

---

## 1. Incident Analysis: Dell SupportAssist Reports Secure Boot Error

### Symptoms
When a user boots a Live USB or boots after installing Hyggshi OS on a laptop (e.g., Dell Vostro 3400) with Secure Boot enabled in BIOS, the Dell SupportAssist On-board Diagnostics screen displays the error:

> **⚠️ Operating System Loader has no signature. Incompatible with SecureBoot. All bootable devices failed Secure Boot**

### Root Causes
1. **For Installed Systems (Post-Calamares):**
   - By default, Calamares with `installEFIFallback: true` copies `grubx64.efi` over the fallback bootloader path `/boot/efi/EFI/BOOT/BOOTX64.EFI`.
   - The file `grubx64.efi` is only signed by Debian CA (or unsigned if compiled locally by `grub-install`). Dell motherboard UEFI firmware **only trusts the "Microsoft Corporation UEFI CA" certificate** embedded in the factory BIOS `db` variable.
   - When Dell loads `BOOTX64.EFI` and discovers no valid Microsoft signature, the firmware immediately halts boot and shows the error.

2. **For Live USB ISOs:**
   - If the ISO build pipeline does not properly package `shimx64.efi.signed` (signed by Microsoft) as `BOOTX64.EFI`, or falls back to generating an unsigned GRUB image (`grub-mkrescue`), the BIOS rejects the USB instantly.

---

## 2. Standard Chain of Trust Model

In commercial and community Linux distributions (Ubuntu, Fedora, Debian, openSUSE), **end users must never be instructed to:**
> *“Enter BIOS → Switch to Custom Mode → Enroll Hyggshi's key”* 💀

Such requirements degrade user experience, risk bricking the BIOS, and break dual-boot compatibility with Windows.

### Standard Real-World Chain of Trust:

```
PC Firmware (UEFI BIOS with "Microsoft Corporation UEFI CA" in factory db)
     │
     │ 1. Verified by Microsoft UEFI CA signature
     ▼
  shim (BOOTX64.EFI) — [SIGNED BY MICROSOFT]
     │
     │ 2. Verified by Distro certificate embedded in shim or via MOK
     ▼
  GRUB (grubx64.efi) — [SIGNED BY DISTRO]
     │
     │ 3. Verified Kernel via EFI load image / verify protocol
     ▼
  Linux Kernel (vmlinuz) — [SIGNED BY DISTRO]
     │
     ▼
  Hyggshi OS (Complete system boot)
```

---

## 3. Security Policy: Key Management & GitHub

### ⚠️ CRITICAL WARNING: NEVER COMMIT PRIVATE KEYS TO GITHUB

Under no circumstances should private keys (`.key`) be stored in the Git repository:

```
GitHub Repository
└── secureboot/
    ├── PK.key       ❌ NEVER COMMIT
    ├── KEK.key      ❌ NEVER COMMIT
    └── db.key       ❌ NEVER COMMIT
```

If private keys are leaked on GitHub, the entire chain of trust is compromised, and Microsoft/UEFI Forum may revoke the certificate via the forbidden database (`dbx`).

### Distinguishing UEFI Key Roles:

| Key Type | Full Name | Scope & Role | Key Holder |
| :--- | :--- | :--- | :--- |
| **PK** | Platform Key | Supreme root key of the motherboard; governs permission to update KEK. | OEM (Dell, ASUS, HP, Lenovo...) |
| **KEK** | Key Exchange Key | Intermediate key; governs updates to the `db` and `dbx` databases. | OEM & Microsoft |
| **db** | Signature Database | List of authorized certificates/hashes allowed to execute (includes Microsoft Windows CA & Microsoft 3rd Party UEFI CA). | Preloaded in machine firmware |
| **dbx** | Forbidden Database | Revocation list of bootloaders with known vulnerabilities. | Updated via Windows Update / fwupd |
| **MOK** | Machine Owner Key | Private key managed by **shim** in NVRAM, allowing users or distros to load third-party drivers (NVIDIA, VirtualBox) without altering BIOS PK/db. | Maintained by user / distro |

---

## 4. Digital Signing Architecture in Hyggshi OS GitHub Actions

For Hyggshi OS, the automated build process on GitHub Actions is standardized as follows:

```
Hyggshi GitHub Actions Pipeline
        │
        ├── 1. Build ISO & Rootfs (debootstrap, chroot, desktop.sh)
        │
        ├── 2. Install bootloader:
        │      ├── shim-signed (Microsoft-signed binary from Debian upstream)
        │      └── grub-efi-*-signed (Signed GRUB from Debian upstream)
        │
        ├── 3. Secure Signing Environment:
        │      ├── Verify current signatures using `sbverify`
        │      └── IF custom kernel/modules are present:
        │          Automatically sign using GitHub Actions Secrets:
        │          - ${{ secrets.SECURE_BOOT_KEY }}
        │          - ${{ secrets.SECURE_BOOT_CERT }}
        │          (Key written to temporary ramdisk, permissions 0600, shredded immediately after signing)
        │
        └── 4. Package Hybrid ISO using xorriso:
               - El Torito BIOS MBR partition
               - UEFI ESP partition (BOOTX64.EFI = Microsoft shim)
```

---

## 5. Technical Changes Implemented in the Repository

1. **`.gitignore`:**
   - Strict patterns added to block all key formats: `*.key`, `*.priv`, `*.pem`, `*.pfx`, `PK.*`, `KEK.*`, `db.*`, `MOK.*`.
2. **`scripts/secureboot.sh`:**
   - Dedicated library for signature verification (`hyggshi_sb_verify`), Microsoft origin validation (`hyggshi_sb_is_microsoft_signed`), ESP tree structuring (`hyggshi_sb_setup_esp_tree`), and secure signing via GitHub Secrets (`hyggshi_sb_sign_with_secrets_if_available`).
3. **`iso-config/calamares/modules/bootloader.conf`:**
   - Set `installEFIFallback: false` to prevent Calamares from overwriting `BOOTX64.EFI` with an unsigned `grubx64.efi`.
   - Set `efiBootloaderId: "hyggshi"`.
4. **`iso-config/calamares/hyggshi-secureboot-postinstall.sh` & `hyggshi-secureboot.conf` module:**
   - Executed immediately following Calamares `bootloader` step:
   - Ensures `/boot/efi/EFI/BOOT/BOOTX64.EFI` is always the Microsoft-signed `shimx64.efi`.
   - Copies companion signed `grubx64.efi` and `mmx64.efi` (MokManager).
   - Registers NVRAM boot entry pointing directly to `\EFI\hyggshi\shimx64.efi` using `efibootmgr`.
5. **`scripts/iso.sh`:**
   - Integrates `secureboot.sh` to validate Microsoft shim integrity before packaging the ISO.
   - Eliminates silent fallbacks to unsigned `grub-mkrescue` for release builds.

---

## 6. Practical Usage Guide

### Scenario 1: Standard Build (Recommended — No Extra Configuration Required)
This is the default path for 99% of users and developers. **No manual actions are needed**:

1. **Build ISO:**
   - On GitHub, navigate to **Actions** → run workflow **Build Hyggshi OS ISO** (select `debian` or `ubuntu`).
   - The workflow automatically retrieves standard signed binaries from Debian/Ubuntu:
     - `shim-signed` (signed by Microsoft).
     - `grub-efi-amd64-signed` (signed by Debian/Ubuntu).
     - `linux-image-*` (kernel signed by Debian/Ubuntu).
2. **Flash to USB & Boot:**
   - Write the ISO to USB using Rufus, BalenaEtcher, or `dd`.
   - Insert into laptop (Dell, HP, Lenovo...) with **Secure Boot: ON**. The system boots directly into the Hyggshi OS Live Desktop **without SupportAssist errors**.
3. **Install to Disk:**
   - Click **Install Hyggshi OS** (Calamares).
   - Once installation completes, the `hyggshi-secureboot-postinstall.sh` hook automatically configures `BOOTX64.EFI` as Microsoft Shim and registers the NVRAM entry.
   - Reboot: Hyggshi OS boots directly without requiring Secure Boot to be disabled in BIOS.

---

### Scenario 2: Custom Kernel / Proprietary Driver Builds (Advanced)
If you compile a custom kernel that lacks upstream Debian/Ubuntu signatures, use **GitHub Actions Secrets** for automated signing:

1. **Generate signing key pair locally (one-time setup):**
   ```bash
   openssl req -new -x509 -newkey rsa:2048 \
     -keyout my-signing-key.key \
     -out my-signing-cert.crt \
     -nodes -days 3650 -subj "/CN=Hyggshi OS Custom Signing Key/"
   ```
   > ⚠️ **NEVER commit `my-signing-key.key` to GitHub!**

2. **Add to GitHub Repository Secrets:**
   - Go to GitHub Repo: **Settings** → **Secrets and variables** → **Actions** → **New repository secret**.
   - Create secret `SECURE_BOOT_KEY`: Paste the full contents of `my-signing-key.key`.
   - Create secret `SECURE_BOOT_CERT`: Paste the full contents of `my-signing-cert.crt`.

3. **Run Build:**
   - During the workflow run, `scripts/iso.sh` and `scripts/secureboot.sh` automatically detect these secrets and sign your custom kernel using `sbsign`.
   - The private key is loaded into temporary volatile storage and immediately shredded after signing.

---

### Scenario 3: Manual Signature Verification (Local Debugging)
To verify whether `.efi` binaries or `vmlinuz` carry valid digital signatures:
```bash
# Check shim binary
sbverify --list live-build/image/EFI/BOOT/BOOTX64.EFI

# Check GRUB binary
sbverify --list live-build/image/EFI/BOOT/grubx64.efi

# Check Kernel binary
sbverify --list live-build/image/live/vmlinuz
```
If signatures are valid, the command prints certificate details (`Microsoft Corporation UEFI CA` or `Debian Secure Boot CA`).
