#!/usr/bin/env bash
# build_ios_core.sh — Compile mihomo Go core → iOS/Simulator static library
# Usage: bash scripts/build_ios_core.sh
# Output: ios/Frameworks/libclash.a  (fat binary arm64 + arm64-sim)
#
# Requirements:
#   - Go 1.22+
#   - Xcode Command Line Tools (xcrun available)
#   - macOS host with iOS SDK
#
# Run: chmod +x scripts/build_ios_core.sh  before first use.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
CORE_DIR="$REPO_ROOT/core"
OUT_DIR="$REPO_ROOT/ios/Frameworks"

mkdir -p "$OUT_DIR"

echo "==> Building for iOS arm64 (device)..."
pushd "$CORE_DIR" > /dev/null

IPHONEOS_SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
CLANG_IOS="$(xcrun --sdk iphoneos --find clang)"

CGO_ENABLED=1 \
  GOOS=ios \
  GOARCH=arm64 \
  CGO_CFLAGS="-arch arm64 -isysroot $IPHONEOS_SDK -miphoneos-version-min=15.0" \
  CGO_LDFLAGS="-arch arm64 -isysroot $IPHONEOS_SDK" \
  CC="$CLANG_IOS" \
  go build -buildmode=c-archive -o "$OUT_DIR/libclash-arm64.a" .

echo "==> Building for iOS arm64 Simulator..."

IPHONESIMULATOR_SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
CLANG_SIM="$(xcrun --sdk iphonesimulator --find clang)"

CGO_ENABLED=1 \
  GOOS=ios \
  GOARCH=arm64 \
  CGO_CFLAGS="-arch arm64 -target arm64-apple-ios15.0-simulator -isysroot $IPHONESIMULATOR_SDK" \
  CGO_LDFLAGS="-arch arm64 -target arm64-apple-ios15.0-simulator -isysroot $IPHONESIMULATOR_SDK" \
  CC="$CLANG_SIM" \
  go build -buildmode=c-archive -o "$OUT_DIR/libclash-arm64-sim.a" .

popd > /dev/null

echo "==> Creating fat library (lipo)..."
# Note: device arm64 and simulator arm64 cannot be in same fat binary.
# For device builds use libclash-arm64.a; for simulator use libclash-arm64-sim.a.
# Copy device build as default libclash.a
cp "$OUT_DIR/libclash-arm64.a" "$OUT_DIR/libclash.a"

echo "==> Done. Output: $OUT_DIR/libclash.a"
echo ""
echo "NEXT STEPS (manual in Xcode):"
echo "  1. Open ios/Runner.xcworkspace in Xcode"
echo "  2. File → New → Target → Network Extension → Packet Tunnel Provider"
echo "     Bundle ID: com.yueto.yuelink.PacketTunnel"
echo "     Language: Swift"
echo "  3. Remove Xcode-generated PacketTunnelProvider.swift, use ios/PacketTunnel/PacketTunnelProvider.swift"
echo "  4. In PacketTunnel target → Build Phases → Link Binary With Libraries:"
echo "     Add ios/Frameworks/libclash.a"
echo "  5. In PacketTunnel target → Build Settings:"
echo "     OTHER_LDFLAGS = -lresolv -lbsm -lc++"
echo "  6. Runner target → Signing & Capabilities → + App Groups → group.com.yueto.yuelink"
echo "  7. PacketTunnel target → Signing & Capabilities → + App Groups → group.com.yueto.yuelink"
echo "  8. PacketTunnel target → Signing & Capabilities → + Network Extensions → Packet Tunnel"
echo "  9. Runner target → Build Phases → + New Copy Files → Embed App Extensions → add PacketTunnel.appex"
echo " 10. Both targets: set DEVELOPMENT_TEAM to your Apple Developer Team ID"
