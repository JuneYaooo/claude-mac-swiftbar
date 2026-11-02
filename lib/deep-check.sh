#!/bin/bash
# SwiftBar 深度体检动作：跑完整 CheckClaude 报告 + 系统通知
DIR="$HOME/Library/Application Support/CheckClaude"
mkdir -p "$DIR"
bash "$HOME/CheckClaude/claude-check.sh" > "$DIR/last-report.txt" 2>&1
SCORE=$(grep -m1 -o '[0-9]\+/100' "$DIR/last-report.txt" | head -1 | cut -d/ -f1)
osascript -e "display notification \"深度体检完成: ${SCORE:-?}/100  报告在 $DIR/last-report.txt\" with title \"Claude 环境体检\"" >/dev/null 2>&1
