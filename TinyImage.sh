#!/bin/bash

# TinyImage - 图片压缩工具，使用Tinify API进行高效压缩，支持批量处理

# ==== 配置项 ==========================================================
# 前往 https://tinify.com/dashboard/api 申请免费API Key，每月可免费压缩500张图片
TINIFY_IMAGE_API_KEY_HARDCODED=""  # 可在此处直接设置API Key, 优先级高于环境变量

# 成功后的提示方式配置
# "dialog" - 弹窗提示（默认）
# "notification" - 系统通知
# "none" - 不显示提示
TINIFY_SUCCESS_NOTIFICATION_TYPE_HARDCODED=""  # 可在此处直接设置提示方式, 优先级高于环境变量


DEBUG_MODE="${DEBUG:-0}"     # 设置为1启用调试模式
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
set openFolder to display dialog "$title" & return & return & "$message" & return & return & "$dialog_text" buttons {"$cancel_text", "$open_text"} default button 2 with icon note giving up after 10

if button returned of openFolder is "$open_text" then
    tell application "Finder"
        open folder (POSIX file "$folder_path")
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
        # 使用 osascript 发送通知
        osascript -e "display notification \"$message\" with title \"$title\" sound name \"$sound\"" 2>/dev/null || true
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
    log_info "    dialog - 弹窗提示（默认）" "    dialog - Dialog prompt (default)"
    log_info "    notification - 系统通知" "    notification - System notification"
    log_info "    none - 不显示提示" "    none - No notification"
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
        api_key=$(get_env_from_profiles "TINIFY_IMAGE_API_KEY")
    fi
    if [ -z "$api_key" ]; then
        log_error "错误: 未设置 TINIFY_IMAGE_API_KEY" "Error: TINIFY_IMAGE_API_KEY not set"
        log_info "请设置环境变量: export TINIFY_IMAGE_API_KEY=\"your_api_key\"" "Please set environment variable: export TINIFY_IMAGE_API_KEY=\"your_api_key\""
        log_info "或在脚本中设置 TINIFY_IMAGE_API_KEY_HARDCODED" "Or set TINIFY_IMAGE_API_KEY_HARDCODED in the script"
        log_info "或将环境变量添加到 ~/.zshrc, ~/.bash_profile, ~/.bashrc 或 ~/.profile 文件中" "Or add the environment variable to ~/.zshrc, ~/.bash_profile, ~/.bashrc or ~/.profile"
        exit 1
    fi
    echo "$api_key"
}

validate_api_key() {
    local api_key="$1"
    local response
    
    response=$(curl -s -u "api:$api_key" "https://api.tinify.com/shrink" \
        -H "Content-Type: application/json" \
        -d '{}' \
        -w "%{http_code}")
    
    local http_code="${response: -3}"
    
    if [ "$http_code" != "400" ]; then
        local title
        local message
        title=$(msg "TinyImage - API 验证失败" "TinyImage - API validation failed")
        if [ "$http_code" = "401" ]; then
            log_error "错误: API Key 无效" "Error: Invalid API Key"
        else
            log_error "错误: API 验证失败 (HTTP $http_code)" "Error: API validation failed (HTTP $http_code)"
        fi
        return 1
    fi
    
    return 0
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

find_images_in_directory() {
    local dir="$1"
    
    find "$dir" -maxdepth 1 -type f | while read -r file; do
        if is_supported_format "$file"; then
            echo "$file"
        fi
    done
}

# ==== 压缩功能 ====
compress_image() {
    local input_file="$1"
    local output_file="$2"
    local api_key="$3"
    
    log_debug "开始压缩: $input_file -> $output_file"
    
    # 创建输出目录
    local output_dir
    output_dir=$(dirname "$output_file")
    mkdir -p "$output_dir"
    
    # 调用 Tinify API
    local temp_response=$(mktemp)
    local temp_headers=$(mktemp)
    
    # 检测文件MIME类型
    local mime_type="application/octet-stream"
    if command -v file >/dev/null 2>&1; then
        mime_type=$(file -b --mime-type "$input_file" 2>/dev/null || echo "application/octet-stream")
    fi
    
    log_debug "文件MIME类型: $mime_type"
    
    # 使用curl获取响应和HTTP状态码
    local http_code
    http_code=$(curl -s -u "api:$api_key" "https://api.tinify.com/shrink" \
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
        if [ -f "$temp_response" ] && [ -s "$temp_response" ]; then
            if command -v jq >/dev/null 2>&1 && echo "$json_response" | jq -e . >/dev/null 2>&1; then
                error_message=$(echo "$json_response" | jq -r '.error // .message // "Unknown error"')
            fi
        fi
        local title
        local message
        log_error "压缩失败 $input_file: $error_message" "Compression failed $input_file: $error_message"
        # 清理临时文件
        rm -f "$temp_response" "$temp_headers"
        return 1
    fi
    
    # 检查响应是否为空
    if [ ! -s "$temp_response" ]; then
        local title
        local message
        log_error "API 返回空响应: $input_file" "API returned empty response: $input_file"
        # 清理临时文件
        rm -f "$temp_response" "$temp_headers"
        return 1
    fi
    
    # 获取下载URL
    local download_url
    if ! download_url=$(echo "$json_response" | jq -r '.output.url'); then
        local title
        local message
        log_error "解析响应失败: $input_file" "Failed to parse response: $input_file"
        # 清理临时文件
        rm -f "$temp_response" "$temp_headers"
        return 1
    fi

    
    # 下载压缩后的图片
    if ! curl -s -u "api:$api_key" "$download_url" -o "$output_file"; then
        local title
        local message
        log_error "下载失败: $output_file" "Download failed: $output_file"
        # 清理临时文件
        rm -f "$temp_response" "$temp_headers"
        return 1
    fi
    
    # 清理临时文件
    rm -f "$temp_response" "$temp_headers"

    log_info "✅ 压缩完成: $output_file" "✅ Compressed: $output_file"

    # 已使用的压缩次数
    # local compression_count
    # compression_count=$(curl -s -I \
    # -u "api:$api_key" \
    # -X POST https://api.tinify.com/shrink \
    # | grep -i "Compression-Count" \
    # | awk '{print $2}' \
    # | tr -d '\r')
 
 

    # if [ -n "$compression_count" ]; then
    #     log_info "📊 已使用 $compression_count 次压缩" "📊 "Compression count used: $compression_count""
    # fi
    
    return 0
}

# ==== 主要逻辑 ====
process_files() {
    local api_key="$1"
    shift
    
    local success_count=0
    local fail_count=0
    local skip_count=0
    local last_output_dir=""  # 跟踪最后一个输出目录
    
    # 创建临时文件来存储目录和文件的映射
    local temp_dir_list=$(mktemp)
    local temp_file_list=$(mktemp)
    local temp_results=$(mktemp)
    
    # 清理函数
    cleanup() {
        rm -f "$temp_dir_list" "$temp_file_list" "$temp_results"
    }
    trap cleanup EXIT
    
    # 收集所有需要处理的文件
    for arg in "$@"; do
        # 跳过空参数和 .app 应用自身
        if [ -z "$arg" ] || [[ "$arg" == *.app ]]; then
            continue
        fi
        if [ -d "$arg" ]; then
            # 处理目录
            find_images_in_directory "$arg" | while read -r file; do
                if [ -n "$file" ]; then
                    local dir
                    dir=$(dirname "$file")
                    echo "$dir|$file" >> "$temp_file_list"
                fi
            done
        elif [ -f "$arg" ]; then
            # 处理单个文件
            if is_supported_format "$arg"; then
                local dir
                dir=$(dirname "$arg")
                echo "$dir|$arg" >> "$temp_file_list"
            else
                log_info "跳过不支持格式: $arg" "Skipped unsupported format: $arg"
                echo "skip" >> "$temp_results"
            fi
        else
            local title
            local message
            log_error "文件或目录不存在: $arg" "File or directory not found: $arg"
            echo "fail" >> "$temp_results"
        fi
    done

  
    # 获取所有唯一的目录
    if [ -f "$temp_file_list" ] && [ -s "$temp_file_list" ]; then
        cut -d'|' -f1 "$temp_file_list" | sort -u > "$temp_dir_list"
        
        # 处理每个目录
        while read -r dir; do
            if [ -n "$dir" ]; then
                # 计算输出目录名称（选择一个不存在的名称）
                local tinified_dir="$dir/tinified"
                local counter=1
                while [ -d "$tinified_dir" ]; do
                    tinified_dir="$dir/tinified($counter)"
                    counter=$((counter + 1))
                done

                # 标记为我们将创建的新目录（尚未创建）
                local created_dir=0
                local dir_success_count=0

                # 先创建目录，如果没有任何成功则在稍后删除
                if mkdir -p "$tinified_dir"; then
                    created_dir=1
                fi

                # 处理该目录中的文件（使用process substitution以便在同一shell中更新变量）
                while IFS='|' read -r file_dir file_path; do
                    if [ -n "$file_path" ]; then
                        local filename
                        filename=$(basename "$file_path")
                        local output_file="$tinified_dir/$filename"

                        if compress_image "$file_path" "$output_file" "$api_key"; then
                            echo "success" >> "$temp_results"
                            dir_success_count=$((dir_success_count + 1))
                            # 记录最后一个非空的输出目录
                            last_output_dir="$tinified_dir"
                        else
                            echo "fail" >> "$temp_results"
                        fi
                    fi
                done < <(grep "^$dir|" "$temp_file_list")

                # 如果我们创建了该目录但没有任何成功，则删除该空目录
                if [ "$created_dir" -eq 1 ] && [ "$dir_success_count" -eq 0 ]; then
                    # 尝试使用 rmdir 删除空目录；如果非空则强制删除以满足用户要求
                    if rmdir "$tinified_dir" 2>/dev/null; then
                        log_info "已移除空目录: $tinified_dir" "Removed empty directory: $tinified_dir"
                    else
                        rm -rf "$tinified_dir" 2>/dev/null || true
                        log_info "已移除空目录（强制）: $tinified_dir" "Removed empty directory (forced): $tinified_dir"
                    fi
                    # 如果刚刚删除的是 last_output_dir，则清空该变量
                    if [ "$last_output_dir" = "$tinified_dir" ]; then
                        last_output_dir=""
                    fi
                fi
            fi
        done < "$temp_dir_list"
    fi
    
    # 统计结果
    success_count=0
    fail_count=0
    skip_count=0
    
    if [ -f "$temp_results" ] && [ -s "$temp_results" ]; then
        # 使用wc -l来计算行数，更可靠
        success_count=$(grep "success" "$temp_results" 2>/dev/null | wc -l | tr -d ' ')
        fail_count=$(grep "fail" "$temp_results" 2>/dev/null | wc -l | tr -d ' ')
        skip_count=$(grep "skip" "$temp_results" 2>/dev/null | wc -l | tr -d ' ')
        
        # 确保是数字，如果为空则设为0
        case "$success_count" in
            ''|*[!0-9]*) success_count=0 ;;
        esac
        case "$fail_count" in
            ''|*[!0-9]*) fail_count=0 ;;
        esac
        case "$skip_count" in
            ''|*[!0-9]*) skip_count=0 ;;
        esac
    fi
    
    # 显示总结
    log_info "" ""
    log_info "压缩完成 - 成功: $success_count | 失败: $fail_count | 跳过非支持格式: $skip_count" "Compression finished - Success: $success_count | Failed: $fail_count | Skipped unsupported: $skip_count"
    
    # 显示成功通知（根据配置）
    if [ "$success_count" -gt 0 ] && [ -n "$last_output_dir" ]; then
        local title=$(msg "TinyImage 压缩完成" "TinyImage Compression Complete")
        local message
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
        if [ -d "$arg" ]; then
            for ext in "${SUPPORTED_FORMATS[@]}"; do
                if find "$arg" -maxdepth 1 -type f -iname "*.${ext}" | grep -q .; then
                    return 0
                fi
            done
        elif [ -f "$arg" ]; then
            if is_supported_format "$arg"; then
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
        log_error "请提供以下格式的图片: \n$(format_supported_formats)" "Please provide images in the following formats: \n$(format_supported_formats)"
        exit 1
    fi

    # 获取 API Key
    local api_key=$(get_api_key)

    # 处理文件
    process_files "$api_key" "$@"
    exit $?
}

# 运行主函数
main "$@"