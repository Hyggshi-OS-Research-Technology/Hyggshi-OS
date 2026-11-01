#!/bin/bash
# make-welcome.sh — legacy compatibility wrapper.
#
# Hyggshi Welcome is now maintained directly under:
#   packages/hyggshi/hyggshi-welcome/
#
# IMPORTANT: this script intentionally does NOT generate/overwrite source.
# The old generator could replace the versioned 1.2.x source during ISO builds.
# Use packages/hyggshi/welcome.sh to build/install the committed source.
set -euo pipefail
[ "${DEBUG_MODE:-}" = "true" ] && set -x

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
APP_DIR="$REPO_ROOT/packages/hyggshi/hyggshi-welcome"

if [ ! -f "$APP_DIR/CMakeLists.txt" ] || [ ! -f "$APP_DIR/src/MainWindow.cpp" ]; then
  echo "ERROR: Hyggshi Welcome source tree is missing: $APP_DIR" >&2
  exit 1
fi

echo "Hyggshi Welcome source is maintained directly at:"
echo "  $APP_DIR"

if grep -qE '^project\(hyggshi-welcome VERSION ' "$APP_DIR/CMakeLists.txt"; then
  grep -E '^project\(hyggshi-welcome VERSION ' "$APP_DIR/CMakeLists.txt"
else
  echo "WARNING: CMakeLists.txt has no explicit project version." >&2
fi

cat <<'EOF'
No source generation was performed.
For ISO builds use:
  packages/hyggshi/welcome.sh

This wrapper exists only for backwards compatibility and is safe to run.
EOF
