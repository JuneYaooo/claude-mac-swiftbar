#!/bin/bash
# claude-mac-swiftbar 一键安装
# 用法: bash install.sh [SwiftBar 插件目录]   (默认 ~/Documents/swiftbar)
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_DIR="${1:-$HOME/Documents/swiftbar}"

echo "══ 1/2 安装检测脚本到 ~/CheckClaude ══"
mkdir -p "$HOME/CheckClaude"
cp "$DIR/lib/claude-check.sh" "$DIR/lib/auto-timezone.sh" "$DIR/lib/deep-check.sh" "$HOME/CheckClaude/"
chmod +x "$HOME/CheckClaude/"*.sh
echo "   ✓ ~/CheckClaude/{claude-check,auto-timezone,deep-check}.sh"

echo "══ 2/2 安装 SwiftBar 插件到 $PLUGIN_DIR ══"
mkdir -p "$PLUGIN_DIR"
cp "$DIR/swiftbar/claude-risk.10m.sh" "$PLUGIN_DIR/"
chmod +x "$PLUGIN_DIR/claude-risk.10m.sh"
echo "   ✓ $PLUGIN_DIR/claude-risk.10m.sh"

echo "══ 完成 ══"
echo "插件每 10 分钟刷新; 深度体检报告在 ~/Library/Application Support/CheckClaude/"
[ -d /Applications/SwiftBar.app ] || echo "⚠️ 未检测到 SwiftBar, 请先安装: https://github.com/swiftbar/SwiftBar 并将插件目录设为 $PLUGIN_DIR"
open swiftbar://refreshall 2>/dev/null || true
