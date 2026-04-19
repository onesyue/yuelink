#!/usr/bin/env bash
# build_linux.sh — Build YueLink Linux AppImage
#
# Usage:
#   bash scripts/build_linux.sh [version]
#
# Requirements:
#   - flutter, go (1.22+)
#   - appimagetool (https://github.com/AppImage/AppImageKit/releases)
#     or auto-downloaded below
#   - libgtk-3-dev, libblkid-dev, liblzma-dev (build deps)
#
# Output:
#   YueLink-<version>-linux-amd64.AppImage

set -euo pipefail

VERSION="${1:-$(grep '^version:' pubspec.yaml | awk '{print $2}' | tr -d '+' | cut -d'+' -f1)}"

# Release matrix is linux-amd64 only. The rest of this script (setup.dart
# build target, BUNDLE_DIR under build/linux/x64/, installer layout) is
# hardcoded to x86_64 and would silently produce a misnamed AppImage on an
# arm64 host. Refuse non-amd64 hosts up front instead of drifting.
RAW_ARCH="$(uname -m)"
case "$RAW_ARCH" in
  x86_64|amd64) ;;
  *)
    echo "ERROR: unsupported host arch '$RAW_ARCH'. Only x86_64/amd64 is supported." >&2
    echo "  Release matrix ships linux-amd64 only; see .github/workflows/build.yml." >&2
    exit 1
    ;;
esac
ARCH="amd64"
APPIMAGE_ARCH="x86_64"
OUTPUT="YueLink-${VERSION}-linux-${ARCH}.AppImage"
BUNDLE_DIR="build/linux/x64/release/bundle"
APPDIR="build/AppDir"

echo "═══════════════════════════════════════════════════════"
echo "  Building YueLink Linux AppImage"
echo "  Version : ${VERSION}"
echo "  Arch    : ${ARCH}"
echo "  Output  : ${OUTPUT}"
echo "═══════════════════════════════════════════════════════"

# ── 1. Build Go core ────────────────────────────────────────────────────────
echo ""
echo "▸ Building Go core for linux/amd64..."
dart setup.dart build -p linux -a amd64
dart setup.dart install -p linux

# ── 2. Flutter build ─────────────────────────────────────────────────────────
echo ""
echo "▸ Building Flutter Linux release..."
flutter config --enable-linux-desktop
flutter build linux --release

# ── 3. Verify bundle ─────────────────────────────────────────────────────────
if [ ! -d "${BUNDLE_DIR}" ]; then
  echo "ERROR: Flutter bundle not found at ${BUNDLE_DIR}"
  exit 1
fi

if [ ! -f "linux/libs/libclash.so" ]; then
  echo "ERROR: linux/libs/libclash.so not found — did 'dart setup.dart install -p linux' succeed?"
  exit 1
fi

# ── 4. Assemble AppDir ───────────────────────────────────────────────────────
echo ""
echo "▸ Assembling AppDir..."
rm -rf "${APPDIR}"
mkdir -p "${APPDIR}/usr/bin"
mkdir -p "${APPDIR}/usr/lib"
mkdir -p "${APPDIR}/usr/share/applications"
mkdir -p "${APPDIR}/usr/share/icons/hicolor/256x256/apps"

# Copy Flutter bundle
cp -r "${BUNDLE_DIR}/." "${APPDIR}/usr/bin/"

# Desktop entry
cat > "${APPDIR}/usr/share/applications/yuelink.desktop" << 'EOF'
[Desktop Entry]
Name=YueLink
Comment=Cross-platform proxy client
Exec=yuelink
Icon=yuelink
Type=Application
Categories=Network;
StartupNotify=true
EOF

# App icon (use assets/icon.png if available, else create placeholder)
if [ -f "assets/icon.png" ]; then
  cp "assets/icon.png" "${APPDIR}/usr/share/icons/hicolor/256x256/apps/yuelink.png"
  cp "assets/icon.png" "${APPDIR}/yuelink.png"
else
  echo "WARNING: assets/icon.png not found — using placeholder icon"
fi

# AppRun entry point
cat > "${APPDIR}/AppRun" << 'EOF'
#!/usr/bin/env bash
HERE="$(dirname "$(readlink -f "${0}")")"
export LD_LIBRARY_PATH="${HERE}/usr/bin/lib:${LD_LIBRARY_PATH:-}"
exec "${HERE}/usr/bin/yuelink" "$@"
EOF
chmod +x "${APPDIR}/AppRun"

# Symlink .desktop and icon for AppImage spec
ln -sf "usr/share/applications/yuelink.desktop" "${APPDIR}/yuelink.desktop"

# ── 5. Download appimagetool if needed ───────────────────────────────────────
APPIMAGETOOL="$(command -v appimagetool || true)"
if [ -z "${APPIMAGETOOL}" ]; then
  echo ""
  echo "▸ Downloading appimagetool..."
  TOOL_URL="https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage"
  curl -fSL -o /tmp/appimagetool "${TOOL_URL}"
  chmod +x /tmp/appimagetool
  APPIMAGETOOL="/tmp/appimagetool"
fi

# ── 6. Create AppImage ───────────────────────────────────────────────────────
echo ""
echo "▸ Creating AppImage..."
ARCH="${APPIMAGE_ARCH}" "${APPIMAGETOOL}" "${APPDIR}" "${OUTPUT}"

echo ""
echo "✓ Done: ${OUTPUT} ($(du -sh "${OUTPUT}" | cut -f1))"
