#!/usr/bin/env python3
"""
upload_to_sourceforge.py

Upload large release files (e.g. ISO images that exceed the 500MB web-upload
and 2GB GitHub Release limits) directly to SourceForge's File Release System
via SFTP.

Usage:
    python upload_to_sourceforge.py \
        --user hyggshios \
        --project hyggshi-os \
        --folder "Hyggshi OS 1.4.0 Archive" \
        --file /path/to/hyggshi-os-468.iso \
        --file /path/to/hyggshi-os-468.iso.sha256

Password auth:
    You'll be prompted for your SourceForge password (the same one you use
    to log into sourceforge.net). SourceForge's SFTP endpoint is:
        frs.sourceforge.net  (port 22)

Key auth (recommended for CI / GitHub Actions):
    Add your SSH public key under sourceforge.net -> Account -> SSH Keys,
    then pass --key /path/to/private_key (and --key-passphrase if needed).

Install dependency once:
    pip install paramiko --break-system-packages
"""

import argparse
import getpass
import os
import sys
import time

try:
    import paramiko
except ImportError:
    sys.exit(
        "Missing dependency 'paramiko'.\n"
        "Install it with: pip install paramiko --break-system-packages"
    )

SF_HOST = "frs.sourceforge.net"
SF_PORT = 22
REMOTE_BASE = "/home/frs/project/{project}/{folder}/"


def human(n: float) -> str:
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if n < 1024:
            return f"{n:.1f}{unit}"
        n /= 1024
    return f"{n:.1f}PB"


def make_progress_callback(filename: str, total: int):
    start = time.time()
    last_print = [0.0]

    def cb(transferred: int, _total: int):
        now = time.time()
        if now - last_print[0] < 0.5 and transferred != total:
            return
        last_print[0] = now
        elapsed = max(now - start, 1e-6)
        speed = transferred / elapsed
        pct = (transferred / total * 100) if total else 0
        eta = (total - transferred) / speed if speed > 0 else 0
        sys.stdout.write(
            f"\r{filename}: {human(transferred)}/{human(total)} "
            f"({pct:5.1f}%)  {human(speed)}/s  ETA {eta:6.0f}s   "
        )
        sys.stdout.flush()
        if transferred == total:
            sys.stdout.write("\n")

    return cb


def connect(user: str, password: str | None, key_path: str | None, key_passphrase: str | None):
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())

    pkey = None
    if key_path:
        pkey = paramiko.Ed25519Key.from_private_key_file(key_path, password=key_passphrase) \
            if _looks_like_ed25519(key_path) else \
            paramiko.RSAKey.from_private_key_file(key_path, password=key_passphrase)

    client.connect(
        hostname=SF_HOST,
        port=SF_PORT,
        username=user,
        password=password,
        pkey=pkey,
        look_for_keys=key_path is None and password is None,
        allow_agent=key_path is None,
        timeout=30,
    )
    return client


def _looks_like_ed25519(path: str) -> bool:
    try:
        with open(path, "r") as f:
            head = f.readline()
        return "OPENSSH PRIVATE KEY" in head
    except OSError:
        return False


def ensure_remote_dir(sftp: "paramiko.SFTPClient", remote_dir: str):
    """SourceForge auto-creates folders you upload into, but be defensive."""
    parts = remote_dir.strip("/").split("/")
    path = ""
    for part in parts:
        path += "/" + part
        try:
            sftp.stat(path)
        except FileNotFoundError:
            try:
                sftp.mkdir(path)
            except OSError:
                # Folder likely created concurrently by SF or already exists
                pass


def upload_file(sftp: "paramiko.SFTPClient", local_path: str, remote_dir: str):
    filename = os.path.basename(local_path)
    remote_path = remote_dir.rstrip("/") + "/" + filename
    total = os.path.getsize(local_path)
    print(f"Uploading {filename} ({human(total)}) -> {remote_path}")
    sftp.put(local_path, remote_path, callback=make_progress_callback(filename, total))
    print(f"Done: {filename}")


def main():
    ap = argparse.ArgumentParser(description="Upload files to SourceForge FRS via SFTP")
    ap.add_argument("--user", required=True, help="SourceForge username")
    ap.add_argument("--project", required=True, help="SourceForge project unixname, e.g. hyggshi-os")
    ap.add_argument("--folder", required=True, help='Target folder, e.g. "Hyggshi OS 1.4.0 Archive"')
    ap.add_argument("--file", action="append", required=True, dest="files",
                     help="File to upload; repeat --file for multiple files")
    ap.add_argument("--key", help="Path to SSH private key (for CI / non-interactive use)")
    ap.add_argument("--key-passphrase", help="Passphrase for the private key, if any")
    ap.add_argument("--password-env", default="SF_PASSWORD",
                     help="Env var to read password from (default: SF_PASSWORD). "
                          "If unset and no --key given, you'll be prompted.")
    args = ap.parse_args()

    for f in args.files:
        if not os.path.isfile(f):
            sys.exit(f"File not found: {f}")

    password = None
    if not args.key:
        password = os.environ.get(args.password_env)
        if not password:
            password = getpass.getpass(f"SourceForge password for {args.user}: ")

    print(f"Connecting to {SF_HOST} as {args.user} ...")
    client = connect(args.user, password, args.key, args.key_passphrase)
    sftp = client.open_sftp()
    sftp.get_channel().settimeout(120)

    remote_dir = REMOTE_BASE.format(project=args.project, folder=args.folder)
    ensure_remote_dir(sftp, remote_dir)

    try:
        for f in args.files:
            upload_file(sftp, f, remote_dir)
    finally:
        sftp.close()
        client.close()

    print("All uploads complete.")


if __name__ == "__main__":
    main()
