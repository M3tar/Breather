#!/usr/bin/env bash
set -euo pipefail

MODE="${1:---dry-run}"
RELEASE_BUNDLE_ID="com.mercury.breather"
INSTALLED_APP="/Applications/Breather.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

usage() {
  cat <<'EOF'
Usage: ./scripts/reset-local-release-registration.sh [--dry-run|--apply]

  --dry-run  List duplicate release apps without changing registration (default).
  --apply    Unregister duplicate release apps, keep /Applications/Breather.app,
             and restart the current user's notification services.

This script never deletes an app or its settings.
EOF
}

case "$MODE" in
  --dry-run|--apply) ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; exit 1 ;;
esac

if [[ "$MODE" == "--apply" ]] && pgrep -x Breather >/dev/null 2>&1; then
  echo "Quit Breather and Breather Debug before resetting app registration." >&2
  exit 1
fi

if [[ "$MODE" == "--apply" ]] && find /Volumes -maxdepth 2 -path '*/Breather.app' -print -quit 2>/dev/null | grep -q .; then
  echo "Eject every mounted Breather DMG before resetting app registration." >&2
  exit 1
fi

is_release_app() {
  local app_path="$1"
  local plist_path="$app_path/Contents/Info.plist"
  [[ -f "$plist_path" ]] || return 1
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist_path" 2>/dev/null || true)" == "$RELEASE_BUNDLE_ID" ]]
}

duplicate_count=0
while IFS= read -r app_path; do
  [[ -n "$app_path" ]] || continue
  [[ "$app_path" == "$INSTALLED_APP" ]] && continue
  is_release_app "$app_path" || continue

  duplicate_count=$((duplicate_count + 1))
  if [[ "$MODE" == "--apply" ]]; then
    echo "Unregistering: $app_path"
    "$LSREGISTER" -u "$app_path" >/dev/null 2>&1 || true
  else
    echo "Would unregister: $app_path"
  fi
done < <(mdfind "kMDItemCFBundleIdentifier == '$RELEASE_BUNDLE_ID'" | LC_ALL=C sort -u)

if [[ "$MODE" == "--dry-run" ]]; then
  echo
  echo "Duplicate release apps found: $duplicate_count"
  echo "Run with --apply after reviewing the list. No files will be deleted."
  exit 0
fi

if is_release_app "$INSTALLED_APP"; then
  echo "Registering: $INSTALLED_APP"
  "$LSREGISTER" -f "$INSTALLED_APP"
else
  echo "No valid $RELEASE_BUNDLE_ID app was found at $INSTALLED_APP." >&2
  echo "Install Breather into Applications, then run this command again." >&2
  exit 1
fi

killall NotificationCenter >/dev/null 2>&1 || true
killall usernoted >/dev/null 2>&1 || true

echo
echo "Registration reset complete. Launch only $INSTALLED_APP for release testing."
