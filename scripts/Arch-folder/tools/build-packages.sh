#!/usr/bin/env bash
# build-packages.sh - Builds Hyggshi OS packages and creates/updates a pacman repository.
# Usage: ./tools/build-packages.sh [REPO_DIR]
set -euo pipefail

REPO_DIR="${1:-/opt/localrepo}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKGS_DIR="$ROOT_DIR/pkgs"

echo "==> Hyggshi Package Builder"
echo "  Repository directory: $REPO_DIR"
echo "  Source packages:     $PKGS_DIR"

mkdir -p "$REPO_DIR"

for pkg in "$PKGS_DIR"/*; do
    if [ -f "$pkg/PKGBUILD" ]; then
        pkgname=$(basename "$pkg")
        echo -e "\n==> Building package: $pkgname..."
        (
            cd "$pkg"
            makepkg -s -f --noconfirm --needed
            cp -f ./*.pkg.tar.zst "$REPO_DIR/"
            rm -f "$REPO_DIR"/*-debug-*.pkg.tar.zst 2>/dev/null || true
        )
    fi
done

echo -e "\n==> Updating repository database..."
(
    cd "$REPO_DIR"
    repo-add -n -R hyggshi.db.tar.gz ./*.pkg.tar.zst
    ln -sf hyggshi.db.tar.gz hyggshi-local.db.tar.gz
    [ -f hyggshi.files.tar.gz ] && ln -sf hyggshi.files.tar.gz hyggshi-local.files.tar.gz || true
)

echo -e "\n==> Package repository ready in $REPO_DIR"
ls -lh "$REPO_DIR"
