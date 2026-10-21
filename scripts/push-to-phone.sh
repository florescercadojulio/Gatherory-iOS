#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVICE_ID="${DEVICE_ID:-00008140-000211CC0233001C}"
SCHEME="${SCHEME:-Gatherory}"
BUNDLE_ID="${BUNDLE_ID:-com.guide-systems.gatherory}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT/.build/device-install}"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug-iphoneos/Gatherory.app"

xcodebuild \
  -project "$ROOT/Gatherory.xcodeproj" \
  -scheme "$SCHEME" \
  -destination "platform=iOS,id=$DEVICE_ID" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -quiet \
  build

xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH"
xcrun devicectl device process launch --device "$DEVICE_ID" "$BUNDLE_ID"
