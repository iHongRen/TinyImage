#!/bin/bash

# TinyImage - 图片压缩工具 (Shell版本)
# 使用 Tinify API 压缩图片，无需 Python 环境

# ==== 配置项 ====
# https://tinify.com/dashboard/api 申请免费API Key，每月可免费压缩500张图片
TINIFY_API_KEY_HARDCODED=""  # 可在此处直接设置API Key
DEBUG_MODE="${DEBUG:-0}"     # 设置为1启用调试模式

# 支持的图片格式
SUPPORTED_FORMATS=("jpg" "jpeg" "png" "webp" "avif")

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

show_usage() {
    log_info "用法: $0 <图片文件或目录> [图片文件或目录...]" "Usage: $0 <image_file_or_directory> [image_file_or_directory...]"
    log_info "支持格式: ${SUPPORTED_FORMATS[*]}" "Supported formats: ${SUPPORTED_FORMATS[*]}"
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

# ==== API Key 验证 ====
get_api_key() {
    local api_key="$TINIFY_API_KEY_HARDCODED"
    if [ -z "$api_key" ]; then
        api_key="$TINIFY_API_KEY"
    fi
    
    # 如果环境变量为空，尝试从常见的环境变量文件中读取
    if [ -z "$api_key" ]; then
        # 尝试从 ~/.zshrc 读取
        if [ -f "$HOME/.zshrc" ]; then
            api_key=$(grep "^export TINIFY_API_KEY=" "$HOME/.zshrc" 2>/dev/null | cut -d'=' -f2 | tr -d '"' | tr -d "'")
        fi
        
        # 如果还是为空，尝试从 ~/.bash_profile 读取
        if [ -z "$api_key" ] && [ -f "$HOME/.bash_profile" ]; then
            api_key=$(grep "^export TINIFY_API_KEY=" "$HOME/.bash_profile" 2>/dev/null | cut -d'=' -f2 | tr -d '"' | tr -d "'")
        fi
        
        # 尝试从 ~/.bashrc 读取
        if [ -z "$api_key" ] && [ -f "$HOME/.bashrc" ]; then
            api_key=$(grep "^export TINIFY_API_KEY=" "$HOME/.bashrc" 2>/dev/null | cut -d'=' -f2 | tr -d '"' | tr -d "'")
        fi
        
        # 尝试从 ~/.profile 读取
        if [ -z "$api_key" ] && [ -f "$HOME/.profile" ]; then
            api_key=$(grep "^export TINIFY_API_KEY=" "$HOME/.profile" 2>/dev/null | cut -d'=' -f2 | tr -d '"' | tr -d "'")
        fi
    fi
    
    if [ -z "$api_key" ]; then
        log_error "错误: 未设置 TINIFY_API_KEY" "Error: TINIFY_API_KEY not set"
        log_info "请设置环境变量: export TINIFY_API_KEY=\"your_api_key\"" "Please set environment variable: export TINIFY_API_KEY=\"your_api_key\""
        log_info "或在脚本中设置 TINIFY_API_KEY_HARDCODED" "Or set TINIFY_API_KEY_HARDCODED in the script"
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
        log_error "压缩失败 $input_file: $error_message" "Compression failed $input_file: $error_message"
        # 清理临时文件
        rm -f "$temp_response" "$temp_headers"
        return 1
    fi
    
    # 检查响应是否为空
    if [ ! -s "$temp_response" ]; then
        log_error "API 返回空响应: $input_file" "API returned empty response: $input_file"
        # 清理临时文件
        rm -f "$temp_response" "$temp_headers"
        return 1
    fi
    
    # 获取下载URL和压缩统计
    local download_url
    local compression_count
    
    if ! download_url=$(echo "$json_response" | jq -r '.output.url'); then
        log_error "解析响应失败: $input_file" "Failed to parse response: $input_file"
        # 清理临时文件
        rm -f "$temp_response" "$temp_headers"
        return 1
    fi
    
    compression_count=$(curl -s -I -u "api:$api_key" "https://api.tinify.com/shrink" | grep -i "compression-count" | cut -d: -f2 | tr -d ' \r')
    
    # 下载压缩后的图片
    if ! curl -s -u "api:$api_key" "$download_url" -o "$output_file"; then
        log_error "下载失败: $output_file" "Download failed: $output_file"
        # 清理临时文件
        rm -f "$temp_response" "$temp_headers"
        return 1
    fi
    
    # 清理临时文件
    rm -f "$temp_response" "$temp_headers"
    
    # 显示结果
    log_info "✅ 压缩完成: $output_file" "✅ Compressed: $output_file"
    if [ -n "$compression_count" ]; then
        log_info "📊 剩余Tinify额度: $compression_count/500" "📊 Remaining Tinify quota: $compression_count/500"
    fi
    
    return 0
}

# ==== 主要逻辑 ====
process_files() {
    local api_key="$1"
    shift
    
    local success_count=0
    local fail_count=0
    local skip_count=0
    
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
                # 创建输出目录
                local tinified_dir="$dir/tinified"
                local counter=1
                while [ -d "$tinified_dir" ]; do
                    tinified_dir="$dir/tinified($counter)"
                    counter=$((counter + 1))
                done
                
                mkdir -p "$tinified_dir"
                
                # 处理该目录中的文件
                grep "^$dir|" "$temp_file_list" | while IFS='|' read -r file_dir file_path; do
                    if [ -n "$file_path" ]; then
                        local filename
                        filename=$(basename "$file_path")
                        local output_file="$tinified_dir/$filename"
                        
                        if compress_image "$file_path" "$output_file" "$api_key"; then
                            echo "success" >> "$temp_results"
                        else
                            echo "fail" >> "$temp_results"
                        fi
                    fi
                done
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
    
    # 发送系统通知
    if [ "$success_count" -gt 0 ]; then
        if [ "$fail_count" -eq 0 ]; then
            # 全部成功
            send_notification "$(msg "TinyImage 压缩完成" "TinyImage Compression Complete")" "$(msg "成功压缩 $success_count 张图片" "Successfully compressed $success_count images")" "Glass"
        else
            # 部分成功
            send_notification "$(msg "TinyImage 压缩完成" "TinyImage Compression Complete")" "$(msg "成功: $success_count | 失败: $fail_count" "Success: $success_count | Failed: $fail_count")" "default"
        fi
    else
        # 全部失败或无文件处理
        if [ "$fail_count" -gt 0 ]; then
            send_notification "$(msg "TinyImage 压缩失败" "TinyImage Compression Failed")" "$(msg "压缩失败，请检查文件和网络连接" "Compression failed, please check files and network")" "Basso"
        fi
    fi
    
    if [ "$fail_count" -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

# ==== 主函数 ====
main() {
    if [ "$#" -eq 0 ]; then
        show_usage
        exit 1
    fi
    
    # 检查依赖
    check_dependencies
    
    # 获取和验证 API Key
    local api_key
    api_key=$(get_api_key)
    
    log_info "验证 API Key..." "Validating API Key..."
    if ! validate_api_key "$api_key"; then
        exit 1
    fi
    log_info "✅ API Key 验证成功" "✅ API Key validated successfully"
    
    # 处理文件
    process_files "$api_key" "$@"
    exit $?
}

# 运行主函数
main "$@"