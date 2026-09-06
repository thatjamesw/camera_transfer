#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Camera Media Importer"
APP_BUNDLE_ID="com.jameswright.camerafilesort"
LEGACY_DEFAULTS_DOMAIN="CameraFileSortSwift"
MANIFEST_NAME=".camera_transfer_manifest.json"

APPLY=false
REMOVE_APP=false
SCAN_MANIFESTS=false
MANIFEST_ROOTS=()

usage() {
  cat <<USAGE
Uninstall ${APP_NAME} preferences and app-created metadata.

Usage:
  scripts/uninstall.sh [options]

Options:
  --apply                 Actually remove files. Without this, only prints actions.
  --remove-app            Also remove installed app bundles from /Applications and ./dist.
  --manifest-root PATH    Remove ${MANIFEST_NAME} from a known destination root.
                          Can be passed more than once.
  --scan-manifests        Search common user folders for ${MANIFEST_NAME}.
  -h, --help              Show this help.

Examples:
  scripts/uninstall.sh
  scripts/uninstall.sh --apply
  scripts/uninstall.sh --manifest-root "\$HOME/Pictures/imports" --apply
  scripts/uninstall.sh --scan-manifests --apply
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply)
      APPLY=true
      shift
      ;;
    --remove-app)
      REMOVE_APP=true
      shift
      ;;
    --manifest-root)
      if [[ $# -lt 2 ]]; then
        echo "Missing path after --manifest-root" >&2
        exit 2
      fi
      MANIFEST_ROOTS+=("$2")
      shift 2
      ;;
    --scan-manifests)
      SCAN_MANIFESTS=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

announce_mode() {
  if [[ "$APPLY" == true ]]; then
    echo "Uninstall mode: apply"
  else
    echo "Uninstall mode: dry run. Pass --apply to remove listed items."
  fi
}

remove_path() {
  local path="$1"
  if [[ ! -e "$path" ]]; then
    return
  fi

  if [[ "$APPLY" == true ]]; then
    rm -rf "$path"
    echo "Removed: $path"
  else
    echo "Would remove: $path"
  fi
}

delete_defaults_domain() {
  local domain="$1"
  if defaults read "$domain" >/dev/null 2>&1; then
    if [[ "$APPLY" == true ]]; then
      defaults delete "$domain" >/dev/null 2>&1 || true
      echo "Removed defaults domain: $domain"
    else
      echo "Would remove defaults domain: $domain"
    fi
  fi
}

remove_preference_files() {
  local domain="$1"
  remove_path "$HOME/Library/Preferences/${domain}.plist"
  remove_path "$HOME/Library/Preferences/ByHost/${domain}.plist"
}

remove_manifest_root() {
  local root="$1"
  local manifest="$root/$MANIFEST_NAME"
  remove_path "$manifest"
}

scan_and_remove_manifests() {
  local search_roots=(
    "$HOME/Desktop"
    "$HOME/Documents"
    "$HOME/Downloads"
    "$HOME/Movies"
    "$HOME/Music"
    "$HOME/Pictures"
  )

  for root in "${search_roots[@]}"; do
    [[ -d "$root" ]] || continue
    while IFS= read -r -d '' manifest; do
      remove_path "$manifest"
    done < <(find "$root" -name "$MANIFEST_NAME" -type f -print0 2>/dev/null)
  done
}

announce_mode

delete_defaults_domain "$APP_BUNDLE_ID"
delete_defaults_domain "$LEGACY_DEFAULTS_DOMAIN"

remove_preference_files "$APP_BUNDLE_ID"
remove_preference_files "$LEGACY_DEFAULTS_DOMAIN"

if [[ ${#MANIFEST_ROOTS[@]} -gt 0 ]]; then
  for root in "${MANIFEST_ROOTS[@]}"; do
    remove_manifest_root "$root"
  done
fi

if [[ "$SCAN_MANIFESTS" == true ]]; then
  scan_and_remove_manifests
fi

if [[ "$REMOVE_APP" == true ]]; then
  remove_path "/Applications/${APP_NAME}.app"
  remove_path "$ROOT_DIR/dist/${APP_NAME}.app"
  remove_path "$ROOT_DIR/dist/${APP_NAME}.zip"
fi

if [[ "$APPLY" == true ]]; then
  killall cfprefsd >/dev/null 2>&1 || true
fi
