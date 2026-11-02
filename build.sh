#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="ScreenAlarm"
BUILD="build"
BUNDLE="$BUILD/$APP_NAME.app"

echo "==> 清理旧构建"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"

echo "==> 编译 Swift 源码（Universal: arm64 + x86_64）"
swiftc -O -swift-version 5 -target arm64-apple-macos13.0 \
    -framework Cocoa -framework ServiceManagement \
    -o "$BUILD/.arm64" Sources/*.swift

swiftc -O -swift-version 5 -target x86_64-apple-macos13.0 \
    -framework Cocoa -framework ServiceManagement \
    -o "$BUILD/.x86_64" Sources/*.swift

lipo -create "$BUILD/.arm64" "$BUILD/.x86_64" \
    -output "$BUNDLE/Contents/MacOS/$APP_NAME"
rm -f "$BUILD/.arm64" "$BUILD/.x86_64"

echo "==> 组装 App Bundle"
cp Info.plist "$BUNDLE/Contents/Info.plist"

if [ -f AppIcon.icns ]; then
    cp AppIcon.icns "$BUNDLE/Contents/Resources/AppIcon.icns"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$BUNDLE/Contents/Info.plist" 2>/dev/null || true
fi

echo "==> Ad-hoc 签名"
codesign --force --deep --sign - "$BUNDLE"

echo "==> 完成：$BUNDLE"
du -sh "$BUNDLE"
