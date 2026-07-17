#!/usr/bin/env bash
# Build and launch Bezel (debug).
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --product Bezel --product bezel-bridge
# Copy bridge next to Bezel for ConfigInstaller
BUILD=".build/debug"
cp -f "$BUILD/bezel-bridge" "$BUILD/bezel-bridge"
exec "$BUILD/Bezel"
