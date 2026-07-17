#!/usr/bin/env bash
# Build release Bezel.app with Bezel + bezel-bridge, ad-hoc codesign, verify.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

ENTITLEMENTS="$ROOT/Sources/Bezel/Bezel.entitlements"
INFO_PLIST="$ROOT/Sources/Bezel/Info.plist"
APP="$ROOT/dist/Bezel.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"

if [[ ! -f "$ENTITLEMENTS" ]]; then
  echo "error: missing entitlements at $ENTITLEMENTS" >&2
  exit 1
fi
if [[ ! -f "$INFO_PLIST" ]]; then
  echo "error: missing Info.plist at $INFO_PLIST" >&2
  exit 1
fi

echo "→ swift build -c release (Bezel + bezel-bridge)"
# SPM accepts a single --product per invocation.
swift build -c release --product Bezel
swift build -c release --product bezel-bridge

BIN_DIR="$(swift build -c release --show-bin-path)"
BEZEL_BIN="$BIN_DIR/Bezel"
BRIDGE_BIN="$BIN_DIR/bezel-bridge"

if [[ ! -x "$BEZEL_BIN" ]]; then
  echo "error: Bezel binary not found at $BEZEL_BIN" >&2
  exit 1
fi
if [[ ! -x "$BRIDGE_BIN" ]]; then
  echo "error: bezel-bridge binary not found at $BRIDGE_BIN" >&2
  exit 1
fi

echo "→ assembling $APP"
rm -rf "$APP"
mkdir -p "$MACOS"
cp "$INFO_PLIST" "$CONTENTS/Info.plist"
cp "$BEZEL_BIN" "$MACOS/Bezel"
cp "$BRIDGE_BIN" "$MACOS/bezel-bridge"
chmod 755 "$MACOS/Bezel" "$MACOS/bezel-bridge"

echo "→ ad-hoc codesign (Bezel + bezel-bridge)"
codesign --force --sign - --entitlements "$ENTITLEMENTS" "$MACOS/bezel-bridge"
codesign --force --sign - --entitlements "$ENTITLEMENTS" "$MACOS/Bezel"
codesign --force --sign - --entitlements "$ENTITLEMENTS" "$APP"

echo "→ verifying codesign"
codesign --verify --verbose "$MACOS/bezel-bridge"
codesign --verify --verbose "$MACOS/Bezel"
codesign --verify --verbose "$APP"

echo "✓ packaged $APP"
echo "  Bezel:        $MACOS/Bezel"
echo "  bezel-bridge: $MACOS/bezel-bridge"
