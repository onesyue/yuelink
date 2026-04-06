#!/bin/bash
# YueLink — 修复 macOS Gatekeeper 拦截
# Fix macOS Gatekeeper blocking YueLink from opening
#
# 双击运行此脚本，输入密码后即可正常打开 YueLink。
# Double-click this script and enter your password to fix the issue.

APP_PATH="/Applications/YueLink.app"

if [ ! -d "$APP_PATH" ]; then
    echo "❌ 未找到 YueLink.app，请先将其拖入 Applications 文件夹。"
    echo "   YueLink.app not found. Please drag it to Applications first."
    echo ""
    read -n 1 -s -r -p "按任意键退出 / Press any key to exit..."
    exit 1
fi

echo "🔧 正在移除 Gatekeeper 隔离标记..."
echo "   Removing Gatekeeper quarantine attribute..."
echo ""

sudo xattr -cr "$APP_PATH"

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ 修复成功！现在可以正常打开 YueLink 了。"
    echo "   Fixed! You can now open YueLink normally."
    echo ""
    echo "🚀 正在启动 YueLink..."
    open "$APP_PATH"
else
    echo ""
    echo "❌ 修复失败，请手动在终端运行："
    echo "   sudo xattr -cr /Applications/YueLink.app"
fi

echo ""
read -n 1 -s -r -p "按任意键关闭 / Press any key to close..."
