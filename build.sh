#!/bin/bash
# 构建 dist/TinyImage.app：以系统 Automator Stub 为骨架，注入工作流脚本与图标，签名。
# 用法：./build.sh [版本号]   版本号写入 App 的 Info.plist，默认 0.0.0
set -euo pipefail
cd "$(cd "$(dirname "$0")" && pwd)"

APP_VERSION="${1:-0.0.0}"
case "$APP_VERSION" in
  v*) APP_VERSION="${APP_VERSION#v}" ;;
esac
if ! printf '%s' "$APP_VERSION" | grep -Eq '^[0-9]+\.[0-9]+(\.[0-9]+)?$'; then
  echo "版本号格式应为 x.y 或 x.y.z：$APP_VERSION" >&2
  exit 1
fi
STUB="/System/Library/CoreServices/Automator Application Stub.app"
APP="dist/TinyImage.app"
PLIST="$APP/Contents/Info.plist"

[ -d "$STUB" ] || {
  echo "未找到系统 Automator Stub: $STUB" >&2
  exit 1
}

echo "组装应用骨架"
rm -rf "$APP"
mkdir -p dist
# 系统 Stub 带 restricted 标记，ditto 无法读取，改用 cp -R
cp -R "$STUB" "$APP"
rm -rf "$APP/Contents/_CodeSignature"

echo "注入工作流脚本"
# 模板中的占位符替换为 TinyImage.sh 的 XML 转义内容
perl -e '
  my ($tpl, $script, $out) = @ARGV;
  open(my $t, "<", $tpl) or die "打开模板失败: $!";
  local $/; my $xml = <$t>; close $t;
  open(my $s, "<", $script) or die "打开脚本失败: $!";
  my $sh = <$s>; close $s;
  $sh =~ s/&/&amp;/g;
  $sh =~ s/</&lt;/g;
  $sh =~ s/>/&gt;/g;
  my $placeholder = "__TINYIMAGE_SCRIPT__";
  my $i = index($xml, $placeholder);
  die "模板缺少占位符 $placeholder" if $i < 0;
  substr($xml, $i, length($placeholder)) = $sh;
  open(my $o, ">", $out) or die "写出工作流失败: $!";
  print $o $xml;
' src/document.wflow TinyImage.sh "$APP/Contents/document.wflow"
plutil -lint "$APP/Contents/document.wflow" >/dev/null

echo "写入版本与图标"
cp assets/TinyIcon.icns "$APP/Contents/Resources/TinyIcon.icns"
set_plist() { # $1=键 $2=类型 $3=值
  /usr/libexec/PlistBuddy -c "Delete :$1" "$PLIST" >/dev/null 2>&1 || true
  /usr/libexec/PlistBuddy -c "Add :$1 $2 $3" "$PLIST" >/dev/null
}
set_plist CFBundleIdentifier string com.apple.automator.TinyImage
set_plist CFBundleName string TinyImage
set_plist CFBundleShortVersionString string "$APP_VERSION"
set_plist CFBundleVersion string "$APP_VERSION"
# 使用自带的 icns；去掉指向 Assets.car 的 CFBundleIconName
/usr/libexec/PlistBuddy -c "Delete :CFBundleIconName" "$PLIST" >/dev/null 2>&1 || true
set_plist CFBundleIconFile string TinyIcon

echo "签名（ad-hoc）"
xattr -cr "$APP"
codesign --force --deep --sign - --identifier com.apple.automator.TinyImage "$APP"
codesign --verify --deep --strict "$APP"

echo
echo "构建完成: $(pwd)/$APP"
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST" | sed 's/^/版本: /'
du -sh "$APP"
