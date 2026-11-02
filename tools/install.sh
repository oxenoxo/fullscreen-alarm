#!/bin/bash
# ScreenAlarm 安装脚本
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
APP_SRC="$DIR/ScreenAlarm.app"
APP_DEST="/Applications/ScreenAlarm.app"

echo ""
echo "  ScreenAlarm 安装程序"
echo "  ────────────────────────────────"

OS_VER="$(sw_vers -productVersion)"
MAJOR="$(echo "$OS_VER" | cut -d. -f1)"
if [ "$MAJOR" -lt 13 ]; then
    echo "  ✗ 需要 macOS 13 或更高版本，当前为 $OS_VER"
    exit 1
fi
echo "  · 系统版本 $OS_VER ✓"

ARCH="$(uname -m)"
echo "  · 芯片架构 $ARCH ✓"

if [ ! -d "$APP_SRC" ]; then
    echo "  ✗ 找不到 ScreenAlarm.app"
    echo "    请确认 ScreenAlarm.app 与本脚本位于同一个文件夹内。"
    exit 1
fi
echo "  · 安装包完整 ✓"

echo "  · 关闭正在运行的旧版本"
osascript -e 'tell application "ScreenAlarm" to quit' >/dev/null 2>&1 || true
sleep 1

echo "  · 复制到 /Applications"
rm -rf "$APP_DEST"
cp -R "$APP_SRC" "$APP_DEST"

echo "  · 解除系统隔离标记"
xattr -dr com.apple.quarantine "$APP_DEST" >/dev/null 2>&1 || true

echo "  · 重新签名"
codesign --force --deep --sign - "$APP_DEST" >/dev/null 2>&1 || true

echo "  · 启动"
open "$APP_DEST"

echo ""
echo "  ✓ 安装完成"
echo ""
echo "  ScreenAlarm 已在「应用程序」和 Dock 中。"
echo "  首次使用：点右上角 + 添加闹钟，建议在菜单里打开「开机自动启动」。"
echo ""
