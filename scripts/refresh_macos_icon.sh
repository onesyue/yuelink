#!/usr/bin/env bash
# Force-refresh macOS dock / Finder / Launch Services so they pick up the
# new YueLink icon. Use this when `flutter run` rebuilds the .icns correctly
# but the dock still shows the old (cached) icon.
#
# Backstory: macOS Launch Services keeps a database of every app it has
# ever seen, including the icons of apps in mounted DMGs and stale build
# directories. The dock can pick the "wrong" icon from that database when
# multiple YueLink.app paths are registered.
#
# What this does, in order:
#   1. Regenerates every icon from scripts/round_appicon.py (squircle masked
#      from v1.0.13 sources, brand-color sampled)
#   2. Ejects any mounted YueLink DMG (the old install in /Volumes/YueLink/
#      is the most common pollution source)
#   3. Removes the empty Release/ build stub (older Xcode runs leave one)
#   4. Wipes the Flutter build cache so the next `flutter run` recompiles
#      Assets.car / AppIcon.icns from the fresh PNGs
#   5. Force-quits any running YueLink
#   6. Removes /Applications/YueLink.app if present
#   7. Clears the macOS icon-services cache
#   8. Rebuilds the Launch Services database from scratch
#   9. Re-registers the current debug bundle as the canonical YueLink
#  10. Kills iconservices daemons + Dock + Finder so they re-read everything

set -euo pipefail
cd "$(dirname "$0")/.."

LSREG="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

echo "→ 1/10  Regenerating icons (squircle masked + composited from real icon)..."
git checkout v1.0.13 -- macos/Runner/Assets.xcassets/AppIcon.appiconset/ assets/icon.png 2>/dev/null || true
python3 scripts/round_appicon.py >/dev/null

echo "→ 2/10  Ejecting any mounted YueLink DMG..."
for vol in /Volumes/YueLink /Volumes/YueLink\ * ; do
  if [ -d "$vol" ]; then
    echo "    Ejecting $vol"
    hdiutil detach "$vol" -force 2>/dev/null \
      || diskutil unmount force "$vol" 2>/dev/null \
      || true
  fi
done

echo "→ 3/10  Removing empty Release stub..."
if [ -d build/macos/Build/Products/Release/YueLink.app ]; then
  rm -rf build/macos/Build/Products/Release/YueLink.app
  echo "    removed"
fi

echo "→ 4/10  Cleaning Flutter build cache..."
flutter clean >/dev/null

echo "→ 5/10  Force-quitting any running YueLink..."
osascript -e 'tell application "YueLink" to quit' 2>/dev/null || true
pkill -9 -f "YueLink.app/Contents/MacOS/YueLink" 2>/dev/null || true

echo "→ 6/10  Removing /Applications/YueLink.app if present..."
if [ -d "/Applications/YueLink.app" ]; then
  rm -rf "/Applications/YueLink.app" 2>/dev/null \
    || sudo rm -rf "/Applications/YueLink.app"
  echo "    removed"
fi

echo "→ 7/10  Clearing macOS icon services cache..."
rm -rf ~/Library/Caches/com.apple.iconservices.store 2>/dev/null || true
sudo find /private/var/folders/ -name 'com.apple.iconservices*' \
  -exec rm -rf {} + 2>/dev/null || true

echo "→ 8/10  Rebuilding Launch Services database..."
"$LSREG" -kill -r -domain local -domain system -domain user 2>/dev/null || true

echo "→ 9/10  Pre-building debug bundle so it can be re-registered..."
# Need a fresh bundle on disk before lsregister can index it. Use --no-pub
# so this is a fast rebuild after `flutter clean`.
flutter build macos --debug 2>&1 | tail -3 || true
if [ -d build/macos/Build/Products/Debug/YueLink.app ]; then
  "$LSREG" -f build/macos/Build/Products/Debug/YueLink.app 2>/dev/null || true
  echo "    registered debug bundle"
fi

echo "→ 10/10 Restarting Dock + Finder + iconservices..."
killall iconservicesagent 2>/dev/null || true
killall iconservicesd 2>/dev/null || true
killall Dock 2>/dev/null || true
killall Finder 2>/dev/null || true

echo
echo "✓ Done. Verify with:"
echo "    $LSREG -dump | grep 'path:.*YueLink.app'"
echo "  Should show ONLY the Debug bundle (and possibly Trash)."
echo
echo "  Now run:  flutter run -d macos"
