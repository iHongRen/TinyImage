#!/bin/bash

# TinyImage - 图片压缩工具，使用Tinify API进行高效压缩，支持批量处理

# ==== 配置项 ==========================================================
# 前往 https://tinify.com/developers 申请免费API Key，每月可免费压缩500张图片
TINIFY_IMAGE_API_KEY_HARDCODED=""  # 可在此处直接设置API Key, 优先级高于环境变量

# 成功后的提示方式配置
# "dialog" - 弹窗提示
# "notification" - 系统通知（默认）
# "none" - 不显示提示
TINIFY_SUCCESS_NOTIFICATION_TYPE_HARDCODED=""  # 可在此处直接设置提示方式, 优先级高于环境变量

# ==== 配置文件（可选） =================================================
# 文件位置: ~/.config/tinyimage/config，内容为 shell 语法: API_KEY=xxx
#   mkdir -p ~/.config/tinyimage
#   cp config.example ~/.config/tinyimage/config
# 优先级: 硬编码 > 环境变量 > 配置文件 > shell profile > 默认值
TINIFY_CONFIG_FILE="$HOME/.config/tinyimage/config"
CONFIG_API_KEY=""
CONFIG_NOTIFY=""
CONFIG_DEBUG=""

load_config_file() {
    [ -f "$TINIFY_CONFIG_FILE" ] || return 0
    local values
    # 在子 shell 中读取，避免配置文件里的其他变量污染脚本
    values=$(
        unset API_KEY NOTIFY DEBUG
        . "$TINIFY_CONFIG_FILE" >/dev/null 2>&1 || exit 0
        printf '%s\n%s\n%s\n' "${API_KEY:-}" "${NOTIFY:-}" "${DEBUG:-}"
    ) || return 0
    {
        IFS= read -r CONFIG_API_KEY
        IFS= read -r CONFIG_NOTIFY
        IFS= read -r CONFIG_DEBUG
    } <<< "$values"
}

load_config_file

DEBUG_MODE="${DEBUG:-${CONFIG_DEBUG:-0}}"     # 设置为1启用调试模式
# =====================================================================

# 支持的图片格式
SUPPORTED_FORMATS=("jpg" "jpeg" "png" "webp" "avif")

# 返回格式化的支持格式列表（根据语言选择分隔符）
format_supported_formats() {
    local sep=", "
    if [ "${LANG_CODE:-en}" = "zh" ]; then
        sep="、"
    fi
    local out=""
    for ext in "${SUPPORTED_FORMATS[@]}"; do
        if [ -z "$out" ]; then
            out="$ext"
        else
            out="$out$sep$ext"
        fi
    done
    echo "$out"
}

# ==== 通用环境变量读取函数 ====
get_env_from_profiles() {
    local var_name="$1"
    local value=""

    for profile in "$HOME/.zshrc" "$HOME/.bash_profile" "$HOME/.bashrc" "$HOME/.profile"; do
        if [ -f "$profile" ]; then
            # 提取原始右侧内容 (可能包含引号、注释或分号)
            local raw
            raw=$(sed -nE "s/^[[:space:]]*export[[:space:]]+${var_name}[[:space:]]*=[[:space:]]*(.*)$/\1/p" "$profile" 2>/dev/null)
            if [ -n "$raw" ]; then
                # 去掉行尾注释和末尾分号
                raw=$(echo "$raw" | sed -E 's/[[:space:]]*#.*$//' | sed -E 's/[[:space:]]*;[[:space:]]*$//')
                # 去掉首尾空白
                raw=$(echo "$raw" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')

                # 如果首尾是配对的单/双引号，则去掉
                if [ "${#raw}" -ge 2 ]; then
                    local first_char="${raw:0:1}"
                    local last_char="${raw: -1}"
                    if { [ "$first_char" = '"' ] && [ "$last_char" = '"' ]; } || { [ "$first_char" = "'" ] && [ "$last_char" = "'" ]; }; then
                        raw="${raw:1:${#raw}-2}"
                    fi
                fi

                # 将处理结果作为提取值
                value="$raw"
                break
            fi
        fi
    done

    echo "$value"
}

# 获取提示方式，优先级：硬编码 > 环境变量 > 默认
get_success_notification_type() {
    local notif_type="$TINIFY_SUCCESS_NOTIFICATION_TYPE_HARDCODED"
    if [ -z "$notif_type" ]; then
        notif_type="$TINIFY_SUCCESS_NOTIFICATION_TYPE"
    fi
    if [ -z "$notif_type" ]; then
        notif_type="$CONFIG_NOTIFY"
    fi
    if [ -z "$notif_type" ]; then
        notif_type=$(get_env_from_profiles "TINIFY_SUCCESS_NOTIFICATION_TYPE")
    fi
    if [ -z "$notif_type" ]; then
        notif_type="notification"
    fi
    echo "$notif_type"
}



# ==== 语言检测 ====
detect_language() {
    local lang="${LANG:-}"
    
    # 如果 LANG 为空，尝试从 locale 获取
    if [ -z "$lang" ]; then
        lang=$(locale | grep LANG | cut -d= -f2 | tr -d '"')
    fi
    
    # 检查其他语言环境变量
    if [ -z "$lang" ] || [ "$lang" = "C" ] || [ "$lang" = "C.UTF-8" ]; then
        # 尝试 LC_MESSAGES
        lang="${LC_MESSAGES:-}"
        if [ -z "$lang" ] || [ "$lang" = "C" ] || [ "$lang" = "C.UTF-8" ]; then
            # 尝试 LC_ALL
            lang="${LC_ALL:-}"
            if [ -z "$lang" ] || [ "$lang" = "C" ] || [ "$lang" = "C.UTF-8" ]; then
                # 尝试从系统偏好设置获取 (macOS)
                if [[ "$OSTYPE" == "darwin"* ]] && command -v defaults >/dev/null 2>&1; then
                    lang=$(defaults read -g AppleLanguages 2>/dev/null | grep -o '"[^"]*"' | head -1 | tr -d '"')
                fi
            fi
        fi
    fi
    
    # 检查是否为中文
    if echo "$lang" | grep -q -i "zh\|chinese\|中文"; then
        echo "zh"
    else
        echo "en"
    fi
}

LANG_CODE=$(detect_language)

# ==== 多语言消息 ====
msg() {
    local zh="$1"
    local en="$2"
    if [ "$LANG_CODE" = "zh" ]; then
        echo "$zh"
    else
        echo "$en"
    fi
}

# ==== 工具函数 ====
to_absolute_path() {
    local path="$1"
    if [[ "$path" = /* ]]; then
        echo "$path"
    else
        echo "$(cd "$(dirname "$path")" 2>/dev/null && pwd)/$(basename "$path")"
    fi
}

log_info() {
    echo "$(msg "$1" "$2")" >&1
}

log_error() {
    echo "$(msg "$1" "$2")" >&2
}

log_debug() {
    if [ "$DEBUG_MODE" = "1" ]; then
        echo "[DEBUG] $1" >&2
    fi
}

# 转义 AppleScript 字符串中的反斜杠和双引号
as_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# ==== 通知函数 ====
show_folder_dialog() {
    local title="$1"
    local message="$2"
    local folder_path="$3"
    
    # 检查是否在 macOS 上
    if [[ "$OSTYPE" == "darwin"* ]]; then
        if [ -n "$folder_path" ] && [ -d "$folder_path" ]; then
            # 准备国际化的对话框文本
            local dialog_text
            local cancel_text
            local open_text
            local e_title e_message e_folder
            e_title=$(as_escape "$title")
            e_message=$(as_escape "$message")
            e_folder=$(as_escape "$folder_path")
            if [ "$LANG_CODE" = "zh" ]; then
                dialog_text="是否打开压缩后的文件夹？"
                cancel_text="取消"
                open_text="打开文件夹"
            else
                dialog_text="Open the compressed folder?"
                cancel_text="Cancel"
                open_text="Open Folder"
            fi
            
            # 使用 AppleScript 在屏幕右上角显示对话框
            osascript << EOF 2>/dev/null || true
-- 获取屏幕尺寸
tell application "Finder"
    set screenBounds to bounds of window of desktop
    set screenWidth to item 3 of screenBounds
    set screenHeight to item 4 of screenBounds
end tell

-- 计算右上角位置 (距离右边和上边各50像素)
set dialogX to screenWidth - 400
set dialogY to 50

-- 显示对话框在指定位置
activate
set openFolder to display dialog "$e_title" & return & return & "$e_message" & return & return & "$dialog_text" buttons {"$cancel_text", "$open_text"} default button 2 with icon note giving up after 10

if button returned of openFolder is "$open_text" then
    tell application "Finder"
        open folder (POSIX file "$e_folder")
        activate
    end tell
end if
EOF
        fi
    fi
}

send_notification() {
    local title="$1"
    local message="$2"
    local sound="${3:-default}"
    
    # 检查是否在 macOS 上
    if [[ "$OSTYPE" == "darwin"* ]]; then
        local e_title e_message e_sound
        e_title=$(as_escape "$title")
        e_message=$(as_escape "$message")
        e_sound=$(as_escape "$sound")
        # 使用 osascript 发送通知
        osascript -e "display notification \"$e_message\" with title \"$e_title\" sound name \"$e_sound\"" 2>/dev/null || true
    fi
}

show_success_notification() {
    local title="$1"
    local message="$2"
    local folder_path="$3"
    
    local notif_type
    notif_type=$(get_success_notification_type)
    case "$notif_type" in
        "dialog")
            show_folder_dialog "✅ $title" "$message" "$folder_path"
            ;;
        "notification")
            send_notification "✅ $title" "$message" "Glass"
            ;;
        *)
            # 默认不提示
            ;;
    esac
}

show_usage() {
    log_info "用法: $0 <图片文件或目录> [图片文件或目录...]" "Usage: $0 <image_file_or_directory> [image_file_or_directory...]"
    log_info "支持格式: $(format_supported_formats)" "Supported formats: $(format_supported_formats)"
    log_info "" ""
    log_info "环境变量配置:" "Environment Variables:"
    log_info "  TINIFY_IMAGE_API_KEY - Tinify API 密钥" "  TINIFY_IMAGE_API_KEY - Tinify API key"
    log_info "  DEBUG - 设置为1启用调试模式" "  DEBUG - Set to 1 to enable debug mode"
    log_info "  TINIFY_SUCCESS_NOTIFICATION_TYPE - 成功后的提示方式:" "  TINIFY_SUCCESS_NOTIFICATION_TYPE - Success notification type:"
    log_info "    dialog - 弹窗提示" "    dialog - Dialog prompt"
    log_info "    notification - 系统通知（默认）" "    notification - System notification (default)"
    log_info "    none - 不显示提示" "    none - No notification"
    log_info "配置文件: $TINIFY_CONFIG_FILE (API_KEY / NOTIFY / DEBUG)" "Config file: $TINIFY_CONFIG_FILE (API_KEY / NOTIFY / DEBUG)"
    log_info "  优先级: 脚本内硬编码 > 环境变量 > 配置文件 > shell profile > 默认值" "  Priority: hardcoded in script > environment variables > config file > shell profiles > defaults"
}

# ==== 检查依赖 ====
check_dependencies() {
    if ! command -v curl >/dev/null 2>&1; then
        log_error "错误: 未找到 curl 命令，请先安装 curl" "Error: curl command not found, please install curl first"
        exit 1
    fi
    
    if ! command -v jq >/dev/null 2>&1; then
        log_error "错误: 未找到 jq 命令，请先安装 jq" "Error: jq command not found, please install jq first"
        log_info "安装方法: brew install jq" "Install with: brew install jq"
        exit 1
    fi
}

# ==== 获取 API Key ====
get_api_key() {
    local api_key="$TINIFY_IMAGE_API_KEY_HARDCODED"
    if [ -z "$api_key" ]; then
        api_key="$TINIFY_IMAGE_API_KEY"
    fi
    if [ -z "$api_key" ]; then
        api_key="$CONFIG_API_KEY"
    fi
    if [ -z "$api_key" ]; then
        api_key=$(get_env_from_profiles "TINIFY_IMAGE_API_KEY")
    fi
    if [ -z "$api_key" ]; then
        # 提示信息走 stderr，避免被调用方当成返回值捕获
        log_error "错误: 未设置 TINIFY_IMAGE_API_KEY" "Error: TINIFY_IMAGE_API_KEY not set"
        log_error "请设置环境变量: export TINIFY_IMAGE_API_KEY=\"your_api_key\"" "Please set environment variable: export TINIFY_IMAGE_API_KEY=\"your_api_key\""
        log_error "或在 ~/.config/tinyimage/config 中设置 API_KEY" "Or set API_KEY in ~/.config/tinyimage/config"
        log_error "或将环境变量添加到 ~/.zshrc, ~/.bash_profile, ~/.bashrc 或 ~/.profile 文件中" "Or add the environment variable to ~/.zshrc, ~/.bash_profile, ~/.bashrc or ~/.profile"
        return 1
    fi
    echo "$api_key"
}

# ==== 文件处理 ====
is_supported_format() {
    local file="$1"
    local ext="${file##*.}"
    ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
    
    for format in "${SUPPORTED_FORMATS[@]}"; do
        if [ "$ext" = "$format" ]; then
            return 0
        fi
    done
    return 1
}

# 递归输出目录下的图片（NUL 分隔，兼容含换行的文件名）
# 跳过 .app 应用包和历次生成的 tinified 输出目录
find_images_in_directory() {
    local dir="$1"

    find -H "$dir" -mindepth 1 \
        \( -iname '*.app' -o -name 'tinified' -o -name 'tinified(*)' \) -prune -o \
        -type f -print0 2>/dev/null | while IFS= read -r -d '' file; do
        if is_supported_format "$file"; then
            printf '%s\0' "$file"
        fi
    done
}

# ==== 压缩功能 ====
# 通过 stdin 传入凭据，避免 API Key 出现在进程参数里
curl_tinify() {
    local api_key="$1"
    shift
    printf 'user = "api:%s"\n' "$api_key" | curl -K - "$@"
}

compress_image() {
    local input_file="$1"
    local output_file="$2"
    local api_key="$3"

    log_debug "开始压缩: $input_file -> $output_file"

    local temp_response
    local temp_output="$output_file.part"
    temp_response=$(mktemp)

    # 检测文件MIME类型
    local mime_type="application/octet-stream"
    if command -v file >/dev/null 2>&1; then
        mime_type=$(file -b --mime-type "$input_file" 2>/dev/null || echo "application/octet-stream")
    fi

    log_debug "文件MIME类型: $mime_type"

    # 使用curl获取响应和HTTP状态码
    local http_code
    http_code=$(curl_tinify "$api_key" -sS --connect-timeout 10 --max-time 120 --retry 2 \
        "https://api.tinify.com/shrink" \
        --data-binary "@$input_file" \
        -H "Content-Type: $mime_type" \
        -o "$temp_response" \
        -w "%{http_code}")

    log_debug "HTTP状态码: $http_code"

    local json_response
    json_response=$(cat "$temp_response")

    if [ "$DEBUG_MODE" = "1" ] && [ -s "$temp_response" ]; then
        log_debug "API响应: $(echo "$json_response" | head -c 200)..."
    fi

    if [ "$http_code" != "201" ]; then
        local error_message="HTTP $http_code"
        if [ -s "$temp_response" ] && command -v jq >/dev/null 2>&1 && echo "$json_response" | jq -e . >/dev/null 2>&1; then
            error_message=$(echo "$json_response" | jq -r '.error // .message // "Unknown error"')
        fi
        log_error "压缩失败 $input_file: $error_message" "Compression failed $input_file: $error_message"
        rm -f "$temp_response"
        return 1
    fi

    # 检查响应是否为空
    if [ ! -s "$temp_response" ]; then
        log_error "API 返回空响应: $input_file" "API returned empty response: $input_file"
        rm -f "$temp_response"
        return 1
    fi

    # 获取下载URL
    local download_url
    download_url=$(echo "$json_response" | jq -r '.output.url // empty')
    if [ -z "$download_url" ]; then
        log_error "解析响应失败: $input_file" "Failed to parse response: $input_file"
        rm -f "$temp_response"
        return 1
    fi

    # 先落临时文件，下载失败或内容为空时不留半成品
    if ! curl_tinify "$api_key" -fsS --connect-timeout 10 --max-time 300 --retry 2 \
        "$download_url" -o "$temp_output"; then
        log_error "下载失败: $output_file" "Download failed: $output_file"
        rm -f "$temp_response" "$temp_output"
        return 1
    fi
    if [ ! -s "$temp_output" ]; then
        log_error "下载内容为空: $output_file" "Downloaded file is empty: $output_file"
        rm -f "$temp_response" "$temp_output"
        return 1
    fi
    mv -f "$temp_output" "$output_file"

    rm -f "$temp_response"

    log_info "✅ 压缩完成: $output_file" "✅ Compressed: $output_file"
    return 0
}

# ==== 主要逻辑 ====
process_files() {
    local api_key="$1"
    shift

    local success_count=0
    local fail_count=0
    local skip_count=0
    local last_output_dir=""

    local temp_files temp_dirs temp_map
    temp_files=$(mktemp)
    temp_dirs=$(mktemp)
    temp_map=$(mktemp)

    cleanup() {
        rm -f "$temp_files" "$temp_dirs" "$temp_map"
    }
    trap cleanup EXIT

    # 收集所有需要处理的文件（NUL 分隔，兼容含换行的文件名）
    for arg in "$@"; do
        # 跳过空参数和 .app 应用自身
        if [ -z "$arg" ] || [[ "$arg" == *.app ]]; then
            continue
        fi

        if [ ! -e "$arg" ]; then
            log_error "文件或目录不存在: $arg" "File or directory not found: $arg"
            fail_count=$((fail_count + 1))
            continue
        fi

        local abs_arg
        abs_arg=$(to_absolute_path "$arg")

        if [ -d "$abs_arg" ]; then
            find_images_in_directory "$abs_arg" >> "$temp_files"
        elif [ -f "$abs_arg" ]; then
            if is_supported_format "$abs_arg"; then
                printf '%s\0' "$abs_arg" >> "$temp_files"
            else
                log_info "跳过不支持格式: $abs_arg" "Skipped unsupported format: $abs_arg"
                skip_count=$((skip_count + 1))
            fi
        else
            # 这不应该发生，因为我们已经检查了存在性
            log_error "未知文件类型: $abs_arg" "Unknown file type: $abs_arg"
            fail_count=$((fail_count + 1))
        fi
    done

    # 去重，避免同一文件被多次压缩
    sort -zu "$temp_files" -o "$temp_files"

    if [ "$DEBUG_MODE" = "1" ]; then
        log_debug "待处理文件:"
        while IFS= read -r -d '' f; do log_debug "  $f"; done < "$temp_files"
    fi

    # 收集涉及的源目录，每个目录对应一个本次新建的输出目录：tinified、tinified(1)……
    while IFS= read -r -d '' f; do
        printf '%s\0' "$(dirname "$f")" >> "$temp_dirs"
    done < "$temp_files"
    sort -zu "$temp_dirs" -o "$temp_dirs"

    # 用 mkdir 的原子性占位，避免并发运行选中同一个目录
    while IFS= read -r -d '' d; do
        local n=0 out
        while :; do
            if [ "$n" -eq 0 ]; then
                out="$d/tinified"
            else
                out="$d/tinified($n)"
            fi
            if mkdir "$out" 2>/dev/null; then
                printf '%s\0%s\0' "$d" "$out" >> "$temp_map"
                break
            fi
            n=$((n + 1))
            if [ "$n" -ge 1000 ]; then
                log_error "无法创建输出目录: $d" "Cannot create output directory: $d"
                break
            fi
        done
    done < "$temp_dirs"

    get_outdir() {
        local needle="$1" d o
        while IFS= read -r -d '' d && IFS= read -r -d '' o; do
            if [ "$d" = "$needle" ]; then
                printf '%s' "$o"
                return 0
            fi
        done < "$temp_map"
        return 1
    }

    # 逐个压缩；输出目录按源目录一对一映射，不做任何名称匹配
    while IFS= read -r -d '' f; do
        local dir outdir out
        dir=$(dirname "$f")
        outdir=$(get_outdir "$dir")
        if [ -z "$outdir" ]; then
            log_error "压缩失败 $f: 无法创建输出目录" "Compression failed $f: cannot create output directory"
            fail_count=$((fail_count + 1))
            continue
        fi
        out="$outdir/$(basename "$f")"
        if compress_image "$f" "$out" "$api_key"; then
            success_count=$((success_count + 1))
            last_output_dir="$outdir"
        else
            fail_count=$((fail_count + 1))
        fi
    done < "$temp_files"

    # 删除本次创建但没有任何输出的空目录，同时统计有效输出目录
    local outdir_count=0
    local last_output_dir_seen=""
    while IFS= read -r -d '' d && IFS= read -r -d '' out; do
        [ -d "$out" ] || continue
        if rmdir "$out" 2>/dev/null; then
            continue
        fi
        outdir_count=$((outdir_count + 1))
        last_output_dir_seen="$out"
    done < "$temp_map"
    last_output_dir="$last_output_dir_seen"

    # 显示总结
    log_info "" ""
    log_info "压缩完成 - 成功: $success_count | 失败: $fail_count | 跳过非支持格式: $skip_count" "Compression finished - Success: $success_count | Failed: $fail_count | Skipped unsupported: $skip_count"

    # 显示成功通知（根据配置）
    if [ "$success_count" -gt 0 ] && [ -n "$last_output_dir" ]; then
        local title message
        title=$(msg "TinyImage 压缩完成" "TinyImage Compression Complete")
        if [ "$fail_count" -eq 0 ]; then
            message=$(msg "成功压缩 $success_count 张图片" "Successfully compressed $success_count images")
        else
            message=$(msg "成功: $success_count | 失败: $fail_count" "Success: $success_count | Failed: $fail_count")
        fi
        show_success_notification "$title" "$message" "$last_output_dir"
    fi

    if [ "$fail_count" -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

# 检查传入的参数中是否存在受支持的图片（文件或目录中包含受支持图片）
has_supported_images() {
    for arg in "$@"; do
        local abs_arg
        abs_arg=$(to_absolute_path "$arg")

        if [ -d "$abs_arg" ]; then
            local found
            while IFS= read -r -d '' _; do
                found=1
                break
            done < <(find_images_in_directory "$abs_arg")
            [ -n "$found" ] && return 0
        elif [ -f "$abs_arg" ]; then
            if is_supported_format "$abs_arg"; then
                return 0
            fi
        fi
    done
    return 1
}

# ==== 主函数 ====
main() {
    if [ "$#" -eq 0 ]; then
        show_usage
        exit 1
    fi

    # 检查依赖
    check_dependencies

    # 先检查是否有受支持的图片可以处理
    if ! has_supported_images "$@"; then
        log_error "请提供以下格式的图片: $(format_supported_formats)" "Please provide images in the following formats: $(format_supported_formats)"
        exit 1
    fi

    # 获取 API Key；缺失时 get_api_key 返回非零，必须在此终止
    local api_key
    api_key=$(get_api_key) || exit 1

    # 处理文件
    process_files "$api_key" "$@"
    exit $?
}

# 运行主函数
main "$@"