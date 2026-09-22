#!/usr/bin/env bash
# Regenerates the screenshots used by the GitHub Pages site (site/assets/screenshots).
#
# Builds a small harness from the app's own UI sources plus scripts/screenshots/main.swift,
# which feeds the real StatusItemController / SettingsWindowController fictitious data
# (no network, Keychain or UserDefaults access), captures the windows with `screencapture`
# and post-processes them into WebP with scripts/screenshots/process.py (needs Pillow;
# set PYTHON=/path/to/python3 if your default python3 lacks it).
#
# Requirements: macOS 13+, Swift toolchain, python3 + Pillow, and Screen Recording
# permission for the terminal that runs this script. Captures are taken on the main
# display — keep the menu bar visible while it runs (~30 s).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${WORK:-$(mktemp -d)}"
RAW="$WORK/raw"
mkdir -p "$RAW"

echo "==> Building MenuBarCore"
swiftc -emit-library -emit-module -module-name MenuBarCore -parse-as-library \
  -emit-module-path "$WORK/MenuBarCore.swiftmodule" \
  "$ROOT"/Sources/MenuBarCore/*.swift -o "$WORK/libMenuBarCore.dylib"

echo "==> Building screenshot harness"
swiftc -I "$WORK" -L "$WORK" -lMenuBarCore -Xlinker -rpath -Xlinker "$WORK" \
  "$ROOT"/Sources/MRJiraMenuBar/StatusItemController.swift \
  "$ROOT"/Sources/MRJiraMenuBar/SettingsView.swift \
  "$ROOT"/Sources/MRJiraMenuBar/SettingsWindowController.swift \
  "$ROOT"/scripts/screenshots/main.swift \
  -o "$WORK/harness"

echo "==> Capturing scenes"
# Status-item menus always render with the system menu bar's material, so a forced light
# appearance on a dark-mode Mac gives a grey, unrealistic menu. Menus are therefore captured
# in dark only (run on a light-mode Mac to get genuine light ones); the settings window
# renders faithfully in both.
for appearance in dark light; do
  scenes="menu menu-update menu-error menu-compact needs-config settings"
  [ "$appearance" = light ] && scenes="settings"
  for scene in $scenes; do
    expected="$RAW/$scene-menu-$appearance.png"
    [ "$scene" = settings ] && expected="$RAW/settings-$appearance.png"
    for attempt in 1 2 3 4; do
      echo "   $scene ($appearance) attempt $attempt"
      "$WORK/harness" "$scene" "$RAW" "$appearance" 2>/dev/null || true
      sleep 0.7
      [ -f "$expected" ] && break
    done
    [ -f "$expected" ] || { echo "failed to capture $expected" >&2; exit 1; }
  done
done

echo "==> Post-processing"
"${PYTHON:-python3}" "$ROOT/scripts/screenshots/process.py" "$RAW" "$ROOT/site/assets"

echo "Done. Raw captures kept in $RAW"
