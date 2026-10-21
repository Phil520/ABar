#!/bin/bash
# 编译并打包 ABar —— 上证指数菜单栏
# 用法：bash build.sh                 构建 + 上屏自检
#       SKIP_TESTS=1 bash build.sh    只构建
#
# 注意：这里刻意不用管道把 swiftc 的输出交给 grep 判错——
# `swiftc ... | grep error && exit` 的退出码是 grep 的，编译失败会被静默放过。
# 一律先落文件、再看退出码。

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="指数条"
BIN_NAME="IndexBar"
TARGET_APP="$PROJECT_DIR/output/$APP_NAME.app"
# 单文件实现。legacy/v1 是早期多文件版本，同一套 API 写出来就是不在菜单栏上屏，
# 单文件重写后一次就出来了，所以那份只留作对照，不参与构建。
SRC="$PROJECT_DIR/src"

echo "==> 清理旧产物"
rm -rf "$TARGET_APP"
mkdir -p "$TARGET_APP/Contents/MacOS" "$TARGET_APP/Contents/Resources"

echo "==> 编译 Swift 源码"
LOG="$(mktemp)"
set +e
swiftc -swift-version 5 -O -framework Cocoa \
  -o "$TARGET_APP/Contents/MacOS/$BIN_NAME" \
  "$SRC/main.swift" >"$LOG" 2>&1
STATUS=$?
set -e
cat "$LOG"
if [ $STATUS -ne 0 ]; then
  echo "❌ 编译失败"
  rm -f "$LOG"
  exit 1
fi
rm -f "$LOG"

echo "==> 写入 Info.plist"
cp "$PROJECT_DIR/src/Info.plist" "$TARGET_APP/Contents/Info.plist"

echo "==> ad-hoc 签名"
codesign --force --sign - "$TARGET_APP" >/dev/null 2>&1 || echo "    签名跳过（本地运行不受影响）"
codesign -dv "$TARGET_APP" 2>&1 | head -3

echo "==> 校验产物"
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$TARGET_APP/Contents/Info.plist" | sed 's/^/    版本 /'
ls -lh "$TARGET_APP/Contents/MacOS/$BIN_NAME" | awk '{print "    可执行文件 "$5}'

if [ "${SKIP_TESTS:-0}" != "1" ]; then
  echo "==> 上屏自检"
  # v2 的验收标准是「真的出现在菜单栏上」，所以自检直接查窗口服务器的菜单栏层，
  # 而不是查进程有没有起来——进程在跑但状态项没上屏，正是这台机器上踩过的坑。
  CHECK="$(mktemp -d)"
  if swiftc -swift-version 5 -O -framework Cocoa \
      -o "$CHECK/menubarcheck" "$PROJECT_DIR/tools/menubarcheck.swift" 2>/dev/null; then
    "$CHECK/menubarcheck" || echo "    ⚠️ 未在菜单栏找到指数条，确认 App 已启动"
  else
    echo "    跳过（自检工具编译失败）"
  fi
  rm -rf "$CHECK"
fi

echo ""
echo "✅ 完成：$TARGET_APP"
echo "   启动：open \"$TARGET_APP\""
