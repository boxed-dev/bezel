#!/usr/bin/env bash
# Build a debug-equivalent Bezel.app bundle and open it.
# Never exec bare .build/*/Bezel — ConfigInstaller requires Contents/MacOS/bezel-bridge.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

ENTITLEMENTS="$ROOT/Sources/Bezel/Bezel.entitlements"
INFO_PLIST="$ROOT/Sources/Bezel/Info.plist"
APP="$ROOT/dist/Bezel.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"

if [[ "${1:-}" == "--release" ]]; then
  bash "$ROOT/scripts/package-bezel.sh"
  open "$APP"
  exit 0
fi

echo "→ swift build (debug Bezel + bezel-bridge)"
# SPM accepts a single --product per invocation.
swift build --product Bezel
swift build --product bezel-bridge

BIN_DIR="$(swift build --show-bin-path)"
BEZEL_BIN="$BIN_DIR/Bezel"
BRIDGE_BIN="$BIN_DIR/bezel-bridge"

if [[ ! -x "$BEZEL_BIN" || ! -x "$BRIDGE_BIN" ]]; then
  echo "error: expected binaries at $BIN_DIR/{Bezel,bezel-bridge}" >&2
  exit 1
fi

echo "→ assembling debug-equivalent $APP"
rm -rf "$APP"
mkdir -p "$MACOS"
cp "$INFO_PLIST" "$CONTENTS/Info.plist"
cp "$BEZEL_BIN" "$MACOS/Bezel"
cp "$BRIDGE_BIN" "$MACOS/bezel-bridge"
chmod 755 "$MACOS/Bezel" "$MACOS/bezel-bridge"

if [[ -f "$ENTITLEMENTS" ]]; then
  codesign --force --sign - --entitlements "$ENTITLEMENTS" "$MACOS/bezel-bridge"
  codesign --force --sign - --entitlements "$ENTITLEMENTS" "$MACOS/Bezel"
  codesign --force --sign - --entitlements "$ENTITLEMENTS" "$APP"
fi

echo "→ open $APP"
open "$APP"
