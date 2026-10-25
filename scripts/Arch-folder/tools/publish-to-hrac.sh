#!/usr/bin/env bash
# publish-to-hrac.sh - Publishes built packages and database to Hyggshi Repository for Arch Components (HRAC).
# Repository: https://github.com/Hyggshi-OS-Foundation/HRAC
# Usage: ./tools/publish-to-hrac.sh [REPO_DIR] [HRAC_GIT_DIR]
set -euo pipefail

REPO_DIR="${1:-/opt/localrepo}"
HRAC_DIR="${2:-}"
ARCH="x86_64"

echo "==> HRAC Package Publisher"
echo "  Source repository directory: $REPO_DIR"

if [[ -z "$HRAC_DIR" ]]; then
    HRAC_DIR=$(mktemp -d)
    trap 'rm -rf "$HRAC_DIR"' EXIT
    echo "  Cloning https://github.com/Hyggshi-OS-Foundation/HRAC..."
    git clone git@github.com:Hyggshi-OS-Foundation/HRAC.git "$HRAC_DIR"
fi

TARGET_DIR="$HRAC_DIR/$ARCH"
mkdir -p "$TARGET_DIR"

echo "==> Copying packages and database to $TARGET_DIR..."
cp -f "$REPO_DIR"/*.pkg.tar.zst "$TARGET_DIR/" 2>/dev/null || true
cp -f "$REPO_DIR"/hyggshi.db* "$TARGET_DIR/" 2>/dev/null || true
cp -f "$REPO_DIR"/hyggshi.files* "$TARGET_DIR/" 2>/dev/null || true

(
    cd "$HRAC_DIR"
    git add "$ARCH"
    git status
    echo ""
    read -p "Commit and push to HRAC? [y/N] " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        git commit -m "chore(repo): update $ARCH packages and database"
        git push origin main
        echo "==> Published successfully to HRAC!"
    else
        echo "Publish cancelled by user."
    fi
)
