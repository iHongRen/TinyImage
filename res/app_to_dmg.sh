#!/usr/bin/env bash

# app_to_dmg.sh
# 将一个 .app 应用打包为 .dmg 文件（适用于 macOS）
# Usage:
#   ./app_to_dmg.sh /path/to/MyApp.app [output.dmg]
# Example:
#   ./app_to_dmg.sh "./MyApp.app" "./MyApp.dmg"

set -euo pipefail

usage() {
  echo "用法: $0 /path/to/App.app [output.dmg]"
  echo "示例: $0 ./MyApp.app ./MyApp.dmg"
}

if [ "$#" -lt 1 ]; then
  usage
  exit 1
fi

APP_PATH="$1"
OUTPUT_DMG="${2:-}"

# 检查 hdiutil
if ! command -v hdiutil >/dev/null 2>&1; then
  echo "错误: 未找到 hdiutil（仅适用于 macOS）" >&2
  exit 1
fi

# 解析输入路径
if [ ! -e "$APP_PATH" ]; then
  echo "错误: 找不到应用: $APP_PATH" >&2
  exit 1
fi

# 确保是 .app 包
if [[ "${APP_PATH}" != *.app ]]; then
  echo "警告: 输入文件似乎不是 .app 包，但仍将尝试打包。" >&2
fi

# 绝对化路径
APP_PATH_ABS=$(cd "$(dirname "$APP_PATH")" && pwd)/$(basename "$APP_PATH")

# 默认输出文件名
if [ -z "$OUTPUT_DMG" ]; then
  base_name=$(basename "$APP_PATH" .app)
  OUTPUT_DMG="${base_name}.dmg"
fi

# 绝对输出路径
OUTPUT_DMG_ABS=$(cd "$(dirname "$OUTPUT_DMG")" && pwd)/$(basename "$OUTPUT_DMG")

# 创建临时目录
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# 复制 .app 到临时目录
echo "复制 $APP_PATH_ABS 到临时目录..."
cp -R "$APP_PATH_ABS" "$TMPDIR/"

# 在 dmg 内放置 Applications 快捷方式，便于用户拖拽安装
ln -s /Applications "$TMPDIR/Applications" || true

# 卷名使用应用名（去掉 .app）
VOLNAME=$(basename "$APP_PATH" .app)

# 设置合适的权限
chmod -R go-w "$TMPDIR/" || true

echo "正在创建只读压缩 DMG: $OUTPUT_DMG_ABS"
# 使用 hdiutil 创建压缩只读镜像 (UDZO)
hdiutil create -volname "$VOLNAME" -srcfolder "$TMPDIR" -ov -format UDZO "$OUTPUT_DMG_ABS"
ret=$?
if [ $ret -ne 0 ]; then
  echo "错误: 创建 DMG 失败 (hdiutil 返回 $ret)" >&2
  exit $ret
fi

# 设置最终权限
chmod 644 "$OUTPUT_DMG_ABS" || true

echo "完成: $OUTPUT_DMG_ABS"

echo "提示: 可以将 DMG 上传或分发，用户打开后可将应用拖入 Applications 文件夹。"
exit 0
