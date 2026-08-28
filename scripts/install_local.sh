#!/bin/bash
# install_local.sh — build, stamp, sign, and install a local Debug vPhone.app
# into /Applications, replacing the correct bottom-up manual recipe that was
# previously copy-pasted by hand each time (see VPHONE_WORKLOG.md).
#
# The build number shown in "About vPhone" is stamped from the local git
# commit + build time here rather than from Build.xcconfig's static
# CURRENT_PROJECT_VERSION — that number never changes between dev builds, so
# there was no way to tell from the UI whether a reinstall actually took.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

DEST=".build/vPhone.app"
ENT="Platform/macOS/local-launch.entitlements"
INSTALLED="/Applications/vPhone.app"

echo "==> Building (Debug, macOS) ..."
xcodebuild -project UTM.xcodeproj -scheme macOS -destination "platform=macOS" -configuration Debug build \
  | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" || true

TARGET_BUILD_DIR="$(xcodebuild -project UTM.xcodeproj -scheme macOS -configuration Debug -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ TARGET_BUILD_DIR /{print $2; exit}')"
BUILT_APP="$TARGET_BUILD_DIR/vPhone.app"
[[ -d "$BUILT_APP" ]] || { echo "error: built app not found at $BUILT_APP" >&2; exit 1; }

echo "==> Stamping build number ..."
BUILD_STAMP="$(git rev-parse --short HEAD 2>/dev/null || echo local)-$(date -u +%Y%m%d.%H%M%S)"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_STAMP" "$BUILT_APP/Contents/Info.plist"
echo "  CFBundleVersion -> $BUILD_STAMP"

echo "==> Signing (bottom-up: frameworks/XPC first, no entitlements; app last, with entitlements) ..."
rm -rf "$DEST" && cp -R "$BUILT_APP" "$DEST"
find "$DEST/Contents/Frameworks" -maxdepth 1 -type d -name "*.framework" -print0 \
  | xargs -0 -n1 codesign --force --sign - --options runtime --timestamp=none
codesign --force --sign - --options runtime --timestamp=none \
  "$DEST/Contents/XPCServices/QEMUHelper.xpc/Contents/MacOS/QEMULauncher.app"
codesign --force --sign - --options runtime --timestamp=none \
  "$DEST/Contents/XPCServices/QEMUHelper.xpc/Contents/MacOS/QEMURenderServer.app"
codesign --force --sign - --options runtime --timestamp=none \
  "$DEST/Contents/XPCServices/QEMUHelper.xpc"
codesign --force --sign - --options runtime --timestamp=none --entitlements "$ENT" "$DEST"
codesign --verify --deep --strict "$DEST"
echo "  signature verified OK"

echo "==> Installing to $INSTALLED ..."
pkill -f "vPhone.app/Contents/MacOS/vPhone" 2>/dev/null || true
sleep 1
rsync -a --delete "$DEST/" "$INSTALLED/"

echo "==> Launching ..."
open -a "$INSTALLED"
echo "==> Done. Build $BUILD_STAMP — check Apple menu > About vPhone to confirm."
