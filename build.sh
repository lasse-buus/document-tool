#!/bin/bash
# Builds "Document Tool.app" into ./build. Needs Xcode or the Xcode Command Line Tools.
#   ./build.sh          build the app
#   ./build.sh run      build and launch it
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="build/Document Tool.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/DocumentTool" "$APP/Contents/MacOS/DocumentTool"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo "Built: $APP"

if [[ "${1:-}" == "run" ]]; then
  pkill -x DocumentTool 2>/dev/null || true
  open "$APP"
fi
