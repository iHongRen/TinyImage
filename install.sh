#!/bin/sh
# TinyImage 安装脚本：从 GitHub Releases 下载 TinyImage.dmg 并安装到 /Applications。
# 用法：curl -fsSL https://raw.githubusercontent.com/iHongRen/TinyImage/main/install.sh | sh
set -eu

REPO="iHongRen/TinyImage"
APP="TinyImage"
INSTALL_DIR="/Applications"
DMG_URL="https://github.com/${REPO}/releases/latest/download/${APP}.dmg"
ZIP_URL="https://github.com/${REPO}/releases/latest/download/${APP}.zip"

# 用 sudo 安装时，配置要写到真实用户的家目录
if [ -n "${SUDO_USER:-}" ]; then
  USER_HOME=$(eval echo "~$SUDO_USER")
else
  USER_HOME="$HOME"
fi

if [ "$(uname -s)" != "Darwin" ]; then
  echo "TinyImage 仅支持 macOS。" >&2
  exit 1
fi

for cmd in curl hdiutil ditto xattr codesign mktemp; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "缺少命令：$cmd" >&2
    exit 1
  fi
done

if [ ! -w "$INSTALL_DIR" ]; then
  echo "没有写入 $INSTALL_DIR 的权限，请用 sudo sh 重新运行。" >&2
  exit 1
fi

TMP="$(mktemp -d)"
MOUNT="$TMP/mnt"
NEW="$INSTALL_DIR/.${APP}.app.new"
mkdir -p "$MOUNT"
cleanup() {
  hdiutil detach "$MOUNT" >/dev/null 2>&1 || true
  rm -rf "$TMP" "$NEW"
}
trap cleanup EXIT

SRC_APP=""
echo "下载 ${APP}.dmg"
if curl -fL --progress-bar -o "$TMP/$APP.dmg" "$DMG_URL"; then
  echo "挂载安装包"
  if ! hdiutil attach -nobrowse -readonly -mountpoint "$MOUNT" "$TMP/$APP.dmg" >/dev/null; then
    echo "挂载 ${APP}.dmg 失败。" >&2
    exit 1
  fi
  SRC_APP="$MOUNT/$APP.app"
else
  echo "DMG 下载失败，改用 ZIP 安装包"
  if ! curl -fL --progress-bar -o "$TMP/$APP.zip" "$ZIP_URL"; then
    echo "下载失败，请确认 ${REPO} 已发布 ${APP}.dmg 或 ${APP}.zip。" >&2
    exit 1
  fi
  if ! ditto -x -k "$TMP/$APP.zip" "$TMP/zip"; then
    echo "解压 ${APP}.zip 失败。" >&2
    exit 1
  fi
  SRC_APP="$TMP/zip/$APP.app"
fi

if [ ! -d "$SRC_APP" ]; then
  echo "安装包中未找到 ${APP}.app。" >&2
  exit 1
fi

# 签名校验只作为提示：早期版本是 ad-hoc 签名，资源稍有改动就校验不通过，
# 不能因此拒绝安装，但要让用户知道安装包完整性存疑。
if ! codesign --verify --deep --strict "$SRC_APP" >/dev/null 2>&1; then
  echo "警告：$APP.app 签名校验未通过，安装包可能已损坏或被改动。" >&2
fi

echo "安装到 $INSTALL_DIR"
# 先复制到临时名再替换，避免中途失败留下残缺的 App
rm -rf "$NEW"
cp -R "$SRC_APP" "$NEW"
rm -rf "$INSTALL_DIR/$APP.app"
mv "$NEW" "$INSTALL_DIR/$APP.app"

# 去掉下载隔离标记，避免首次启动被 Gatekeeper 拦截
xattr -dr com.apple.quarantine "$INSTALL_DIR/$APP.app"

# 生成默认配置，已有配置不覆盖
CONFIG_DIR="$USER_HOME/.config/tinyimage"
CONFIG_FILE="$CONFIG_DIR/config"
CONFIG_URL="https://raw.githubusercontent.com/${REPO}/main/config.example"
if [ -f "$CONFIG_FILE" ]; then
  echo "保留已有配置：$CONFIG_FILE"
else
  mkdir -p "$CONFIG_DIR"
  if [ -n "${SUDO_USER:-}" ]; then
    chown "$SUDO_USER" "$CONFIG_DIR"
  fi
  # 默认值只在 config.example 中维护一份，避免与仓库里的模板不一致
  if curl -fsSL -o "$CONFIG_FILE" "$CONFIG_URL"; then
    if [ -n "${SUDO_USER:-}" ]; then
      chown "$SUDO_USER" "$CONFIG_FILE"
    fi
    echo "已生成默认配置：$CONFIG_FILE"
  else
    rm -f "$CONFIG_FILE"
    echo "未能下载默认配置模板，可稍后手动创建 ${CONFIG_FILE}。" >&2
  fi
fi

echo
echo "安装完成：$INSTALL_DIR/$APP.app"
echo "请编辑 $CONFIG_FILE 填入 API_KEY（或用环境变量 TINIFY_IMAGE_API_KEY）。"
echo "按住 ⌘ 把 $APP.app 拖到 Finder 工具栏，选中图片或文件夹后点击图标即可压缩。"
