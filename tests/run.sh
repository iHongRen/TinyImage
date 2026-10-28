#!/bin/bash
# TinyImage 回归测试：用假的 curl/osascript 模拟 Tinify API，不联网、不需要真实 Key。
# 用法：bash tests/run.sh [TinyImage.sh 路径]
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${1:-$ROOT/TinyImage.sh}"
BASE="$(mktemp -d)"
BIN="$BASE/bin"
trap 'rm -rf "$BASE"' EXIT

pass=0
fail=0
ok() { echo "PASS: $1"; pass=$((pass + 1)); }
ng() { echo "FAIL: $1"; [ -n "${2:-}" ] && echo "      $2"; fail=$((fail + 1)); }

mkdir -p "$BIN"
cat > "$BIN/curl" <<'EOF'
#!/bin/bash
# 假 curl：从 -K - 读取 API Key，/shrink 返回 201，输出 URL 返回假图片内容
key=""; out=""; url=""; failflag=0
while [ $# -gt 0 ]; do
  case "$1" in
    -K)
      if [ "$2" = "-" ]; then
        cfg=$(cat)
        key=$(printf '%s' "$cfg" | sed -n 's/^user = "api:\(.*\)"$/\1/p')
      fi
      shift 2;;
    -o) out="$2"; shift 2;;
    -w) shift 2;;
    -H|--data-binary|--connect-timeout|--max-time|--retry|--retry-delay) shift 2;;
    -u) key="${2#api:}"; shift 2;;
    -f|-fsS|--fail) failflag=1; shift;;
    -*) shift;;
    *) url="$1"; shift;;
  esac
done
[ -n "${KEYLOG:-}" ] && printf '%s\n' "$key" >> "$KEYLOG"
case "$url" in
  *api.tinify.com/shrink)
    if [ -n "${SHRINK_FAIL:-}" ]; then
      [ -n "$out" ] && printf '{"error":"Unauthorized"}' > "$out"
      printf '401'; [ "$failflag" = 1 ] && exit 22; exit 0
    fi
    [ -n "$out" ] && printf '{"output":{"url":"https://api.tinify.com/output/fake"}}' > "$out"
    printf '201'
    ;;
  *)
    if [ -n "${DL_FAIL:-}" ]; then
      [ -n "$out" ] && printf '<html>not found</html>' > "$out"
      [ "$failflag" = 1 ] && exit 22
      exit 0
    fi
    [ -n "$out" ] && printf 'compressed-output' > "$out"
    ;;
esac
EOF
cat > "$BIN/osascript" <<'EOF'
#!/bin/bash
if [ $# -gt 0 ]; then
  printf '%s\n' "$*" >> "${OSALOG:-/dev/null}"
else
  cat >> "${OSALOG:-/dev/null}"
fi
exit 0
EOF
chmod +x "$BIN/curl" "$BIN/osascript"

# 在隔离的 HOME 下运行脚本；ARGS 存放要处理的路径
run_at() {
  (
    cd "${ARGS[0]}" || exit 1
    env -u TINIFY_IMAGE_API_KEY -u TINIFY_SUCCESS_NOTIFICATION_TYPE -u DEBUG \
      HOME="$BASE/home" PATH="$BIN:$PATH" KEYLOG="$BASE/keylog" OSALOG="$BASE/osalog" \
      TINIFY_SUCCESS_NOTIFICATION_TYPE=none "$@" \
      bash "$SRC" "${ARGS[@]}" >"$BASE/stdout" 2>"$BASE/stderr"
    echo $? > "$BASE/status"
  )
}
run() { ARGS=("$1"); shift; run_at "$@"; }
status() { cat "$BASE/status" 2>/dev/null || echo "?"; }

setup() {
  rm -rf "$BASE/home" "$BASE/work"
  mkdir -p "$BASE/home" "$BASE/work"
  : > "$BASE/keylog"; : > "$BASE/osalog"
  rm -f "$BASE/status"
}

setup
printf x > "$BASE/work/a.png"
run "$BASE/work" TINIFY_IMAGE_API_KEY=envkey
[ -f "$BASE/work/tinified/a.png" ] && ok "基线：环境变量 API Key 可压缩" || ng "基线：环境变量 API Key 可压缩"

# T1 目录名含点：不能串到别的目录
setup; mkdir -p "$BASE/work/A.b" "$BASE/work/Axb"
printf a > "$BASE/work/A.b/a.png"; printf b > "$BASE/work/Axb/b.png"
ARGS=("$BASE/work/A.b" "$BASE/work/Axb"); run_at TINIFY_IMAGE_API_KEY=k
a=$(ls "$BASE/work/A.b/tinified" 2>/dev/null | tr '\n' ' ')
b=$(ls "$BASE/work/Axb/tinified" 2>/dev/null | tr '\n' ' ')
[ "$a" = "a.png " ] && ok "T1 目录名含 . 不串目录" || ng "T1 目录名含 . 不串目录" "A.b=[$a] Axb=[$b]"
[ "$b" = "b.png " ] || ng "T1b Axb 目录内容正确" "Axb=[$b]"

# T2/T3 目录名含 glob 字符
setup; mkdir -p "$BASE/work/A[1]"; printf a > "$BASE/work/A[1]/a.png"
run "$BASE/work/A[1]" TINIFY_IMAGE_API_KEY=k
[ -f "$BASE/work/A[1]/tinified/a.png" ] && ok "T2 目录名含 [ 可压缩" || ng "T2 目录名含 [ 可压缩" "$(tail -1 "$BASE/stderr")"

setup; mkdir -p "$BASE/work/A*B"; printf a > "$BASE/work/A*B/a.png"
run "$BASE/work/A*B" TINIFY_IMAGE_API_KEY=k
[ -f "$BASE/work/A*B/tinified/a.png" ] && ok "T3 目录名含 * 可压缩" || ng "T3 目录名含 * 可压缩"

# T4 缺少 API Key：非零退出、不发请求、给出提示
setup; mkdir -p "$BASE/work/d"; printf a > "$BASE/work/d/a.png"
run "$BASE/work/d"
[ "$(status)" != "0" ] && ok "T4 无 API Key 非零退出 ($(status))" || ng "T4 无 API Key 应非零退出" "exit=$(status)"
[ ! -s "$BASE/keylog" ] && ok "T4b 无 API Key 不发起请求" || ng "T4b 无 API Key 仍发起了请求"
grep -q "TINIFY_IMAGE_API_KEY" "$BASE/stderr" && ok "T4c 无 API Key 有提示信息" || ng "T4c 无 API Key 缺少提示"

# T5 下载失败：计为失败、不留坏文件
setup; mkdir -p "$BASE/work/d"; printf a > "$BASE/work/d/a.png"
run "$BASE/work/d" TINIFY_IMAGE_API_KEY=k DL_FAIL=1
out=$(cat "$BASE/stdout" "$BASE/stderr")
echo "$out" | grep -q "Failed: 1" && ok "T5 下载失败计为失败" || ng "T5 下载失败计为失败" "$(echo "$out" | tail -2)"
[ ! -f "$BASE/work/d/tinified/a.png" ] && ok "T5b 下载失败不留坏文件" || ng "T5b 下载失败留下了错误页文件"

# T6 递归子目录，跳过已有 tinified
setup; mkdir -p "$BASE/work/d/sub" "$BASE/work/d/tinified"
printf a > "$BASE/work/d/a.png"; printf b > "$BASE/work/d/sub/b.png"; printf old > "$BASE/work/d/tinified/old.png"
run "$BASE/work/d" TINIFY_IMAGE_API_KEY=k
[ -f "$BASE/work/d/sub/b.png" ] && [ -f "$BASE/work/d/sub/tinified/b.png" ] && ok "T6 递归处理子目录" || ng "T6 递归处理子目录"
ls "$BASE/work/d/tinified" | grep -q "^old.png$" && ! ls "$BASE/work/d/tinified" | grep -q "sub" && ok "T6b 跳过已有 tinified" || ng "T6b 跳过已有 tinified" "$(ls "$BASE/work/d/tinified" | tr '\n' ' ')"

# T7 跳过隐藏目录
setup; mkdir -p "$BASE/work/d/.hidden" "$BASE/work/d/sub"
printf a > "$BASE/work/d/.hidden/a.png"; printf b > "$BASE/work/d/sub/b.png"
run "$BASE/work/d" TINIFY_IMAGE_API_KEY=k
[ ! -d "$BASE/work/d/.hidden/tinified" ] && [ -f "$BASE/work/d/sub/tinified/b.png" ] && ok "T7 跳过隐藏目录" || ng "T7 跳过隐藏目录" "$(find "$BASE/work/d" -type d -name tinified | tr '\n' ' ')"

# T8 文件名含换行
setup; mkdir -p "$BASE/work/d"; printf a > "$BASE/work/d/$(printf 'a\nb').png"
run "$BASE/work/d" TINIFY_IMAGE_API_KEY=k
[ -f "$BASE/work/d/tinified/$(printf 'a\nb').png" ] && ok "T8 文件名含换行可处理" || ng "T8 文件名含换行可处理" "$(ls "$BASE/work/d/tinified" 2>/dev/null | cat -v)"

# T9 配置文件 NOTIFY 生效
setup; mkdir -p "$BASE/work/d" "$BASE/home/.config/tinyimage"; printf a > "$BASE/work/d/a.png"
printf 'API_KEY=k\nNOTIFY=notification\n' > "$BASE/home/.config/tinyimage/config"
( cd "$BASE/work" && env -u TINIFY_IMAGE_API_KEY -u TINIFY_SUCCESS_NOTIFICATION_TYPE -u DEBUG \
    HOME="$BASE/home" PATH="$BIN:$PATH" OSALOG="$BASE/osalog" \
    bash "$SRC" "$BASE/work/d" >/dev/null 2>&1 )
grep -q "display notification" "$BASE/osalog" && ok "T9 配置文件 NOTIFY 生效" || ng "T9 配置文件 NOTIFY 未生效"

# T10 配置文件优先于 shell profile
setup; mkdir -p "$BASE/work/d" "$BASE/home/.config/tinyimage"; printf a > "$BASE/work/d/a.png"
printf 'API_KEY=cfgkey\nNOTIFY=none\n' > "$BASE/home/.config/tinyimage/config"
printf 'export TINIFY_IMAGE_API_KEY="profilekey"\n' > "$BASE/home/.zshrc"
run "$BASE/work/d"
grep -qx 'cfgkey' "$BASE/keylog" && ok "T10 配置文件优先于 profile" || ng "T10 配置文件优先于 profile" "$(head -1 "$BASE/keylog")"

# T11 环境变量优先于配置文件
setup; mkdir -p "$BASE/work/d" "$BASE/home/.config/tinyimage"; printf a > "$BASE/work/d/a.png"
printf 'API_KEY=cfgkey\nNOTIFY=notification\n' > "$BASE/home/.config/tinyimage/config"
run "$BASE/work/d" TINIFY_IMAGE_API_KEY=envkey
grep -qx 'envkey' "$BASE/keylog" && ok "T11 环境变量优先于配置文件" || ng "T11 环境变量优先于配置文件"
[ ! -s "$BASE/osalog" ] && ok "T11b 环境变量 NOTIFY 优先于配置文件" || ng "T11b 环境变量 NOTIFY 未优先" "$(head -1 "$BASE/osalog")"

# T12 配置文件 DEBUG=1 生效
setup; mkdir -p "$BASE/work/d" "$BASE/home/.config/tinyimage"; printf a > "$BASE/work/d/a.png"
printf 'API_KEY=k\nNOTIFY=none\nDEBUG=1\n' > "$BASE/home/.config/tinyimage/config"
run "$BASE/work/d"
grep -q '\[DEBUG\]' "$BASE/stderr" && ok "T12 配置文件 DEBUG=1 生效" || ng "T12 配置文件 DEBUG=1 未生效"

# T12b shell profile 中的 DEBUG 同样生效（与 API Key、NOTIFY 的优先级一致）
setup; mkdir -p "$BASE/work/d"; printf a > "$BASE/work/d/a.png"
printf 'export DEBUG=1\n' > "$BASE/home/.zshrc"
run "$BASE/work/d" TINIFY_IMAGE_API_KEY=k
grep -q '\[DEBUG\]' "$BASE/stderr" && ok "T12b shell profile DEBUG 生效" || ng "T12b shell profile DEBUG 未生效"

# T13 默认提示方式为 notification
setup; mkdir -p "$BASE/work/d"; printf a > "$BASE/work/d/a.png"
run "$BASE/work/d" TINIFY_IMAGE_API_KEY=k TINIFY_SUCCESS_NOTIFICATION_TYPE=
grep -q "display notification" "$BASE/osalog" && ok "T13 默认提示方式为 notification" || ng "T13 默认提示方式异常"

# T14 全部失败：清理空输出目录
setup; mkdir -p "$BASE/work/d"; printf a > "$BASE/work/d/a.png"
run "$BASE/work/d" TINIFY_IMAGE_API_KEY=k SHRINK_FAIL=1
[ ! -d "$BASE/work/d/tinified" ] && ok "T14 全部失败时清理空输出目录" || ng "T14 全部失败时清理空输出目录" "$(ls "$BASE/work/d/tinified" 2>/dev/null)"

echo "---- 结果: PASS=$pass FAIL=$fail ----"
[ "$fail" -eq 0 ]
