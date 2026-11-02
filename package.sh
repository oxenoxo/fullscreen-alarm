#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

NAME="ScreenAlarm"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)
STAGE="dist/${NAME}-${VERSION}"
ZIP="dist/${NAME}-${VERSION}-macOS.zip"

echo "==> 构建"
./build.sh

echo "==> 整理分发目录"
rm -rf dist
mkdir -p "$STAGE"
cp -R "build/${NAME}.app" "$STAGE/"
cp tools/install.sh "$STAGE/"
cp tools/INSTALL.md "$STAGE/INSTALL.md"
chmod +x "$STAGE/install.sh"

echo "==> 打包 zip"
cd dist && zip -r -X -q "$(basename "$ZIP")" "$(basename "$STAGE")" && cd ..

echo "==> 完成"
ls -lh "$ZIP"
echo ""
echo "内容清单："
unzip -l "$ZIP" | head -20
