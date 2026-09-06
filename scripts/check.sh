#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK_DIR="$(mktemp -d)"
trap 'rm -rf "$CHECK_DIR"' EXIT
xcrun swiftc -g "${CAMERA_CHECK_OPTIMIZATION:--O}" -module-cache-path "$ROOT_DIR/.build/checks-module-cache" \
  "$ROOT_DIR/Sources/CameraFileSortSwift/Models.swift" \
  "$ROOT_DIR/Sources/CameraFileSortSwift/Importer.swift" \
  "$ROOT_DIR/Sources/CameraFileSortSwift/AppState.swift" \
  "$ROOT_DIR/Tests/RegressionChecks.swift" -o "$CHECK_DIR/checks"
"$CHECK_DIR/checks" "$@"
