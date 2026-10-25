#!/usr/bin/env bash
# Generate the Secure Boot signing key pair used by secureboot-iso.sh.
# Keep sb.key PRIVATE (never commit it). Users enrol sb.crt through MokManager.
set -euo pipefail
out="${1:-.}"
mkdir -p "$out"
openssl req -new -x509 -newkey rsa:2048 -sha256 -nodes -days 3650 \
    -subj "/CN=Hyggshi OS Secure Boot/O=Hyggshi OS/" \
    -addext "keyUsage=digitalSignature" \
    -addext "extendedKeyUsage=codeSigning" \
    -keyout "$out/sb.key" -out "$out/sb.crt"
chmod 600 "$out/sb.key"
echo "Created $out/sb.key (PRIVATE) and $out/sb.crt"
