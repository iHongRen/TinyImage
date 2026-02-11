# -*- coding: utf-8 -*-
import importlib.util
import locale
import os
import subprocess
import sys

# ==== 配置项，如果未设置则自动回退到环境变量获取。 =========================
# https://tinify.com/dashboard/api 申请免费API Key，每月可免费压缩500张图片
TINIFY_API_KEY = None  # 可在此处直接设置API Key，例如：'YOUR_API_KEY'
# ====================================================================

# 定义Tinify支持的图片格式（小写）
SUPPORTED_FORMATS = ['.avif', '.webp', '.png', '.jpg', '.jpeg']

# ==== 简单中英文提示支持 =========================
def get_lang():
    lang = os.getenv("LANG", "").lower()
    if not lang:
        try:
            locale.setlocale(locale.LC_ALL, '')
            lang_tuple = locale.getlocale()
            lang = lang_tuple[0] or ""
        except Exception:
            lang = ""
    if lang.startswith("zh"):
        return "zh"
    return "en"

LANG = get_lang()


def _(zh, en):
    return zh if LANG == "zh" else en

def get_pip_command():
    pip_cmd = [sys.executable, "-m", "pip"]
    try:
        subprocess.check_call(
            pip_cmd + ["--version"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL
        )
        return pip_cmd
    except (subprocess.CalledProcessError, FileNotFoundError):
        pass
    pip_cmd = ["pip3"]
    try:
        subprocess.check_call(
            pip_cmd + ["--version"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL
        )
        return pip_cmd
    except (subprocess.CalledProcessError, FileNotFoundError):
        pass
    pip_cmd = ["pip"]
    try:
        subprocess.check_call(
            pip_cmd + ["--version"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL
        )
        return pip_cmd
    except (subprocess.CalledProcessError, FileNotFoundError):
        raise RuntimeError(_("未找到可用的pip/pip3命令，请先安装Python包管理工具", "No available pip/pip3 command found, please install Python package management tools"))

def check_and_install_tinify():
    tinify_spec = importlib.util.find_spec("tinify")
    if tinify_spec is None:
        print(_("未检测到tinify库，正在自动安装...", "tinify library not found, installing automatically..."), file=sys.stdout)
        pip_cmd = get_pip_command()
        install_cmd = pip_cmd + ["install", "tinify"]
        try:
            subprocess.check_call(
                install_cmd,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.STDOUT
            )
            print(_("tinify库安装成功！", "tinify library installed successfully!"), file=sys.stdout)
        except subprocess.CalledProcessError as e:
            raise RuntimeError(_(
                f"tinify库安装失败：执行命令 {install_cmd} 出错，可尝试手动执行：sudo pip3 install tinify，错误信息：{str(e)}",
                f"tinify library installation failed: error running {install_cmd}. Try manually: sudo pip3 install tinify. Error: {str(e)}"
            ))

check_and_install_tinify()
import tinify


def validate_tinify_key():
    tinify_api_key = TINIFY_API_KEY if TINIFY_API_KEY else os.getenv("TINIFY_API_KEY")
    tinify.key = tinify_api_key
    tinify.validate()

def compress_image(input_path, output_path):
    out_dir = os.path.dirname(output_path)
    if out_dir and not os.path.exists(out_dir):
        os.makedirs(out_dir)
    source = tinify.from_file(input_path)
    source.to_file(output_path)
    return {
        "input_path": input_path,
        "output_path": output_path,
        "remaining_quota": tinify.compression_count
    }

def find_images_in_directory(directory, recursive=False):
    image_files = []
    if recursive:
        for root, _, files in os.walk(directory):
            for f in files:
                ext = os.path.splitext(f)[1].lower()
                if ext in SUPPORTED_FORMATS:
                    image_files.append(os.path.join(root, f))
    else:
        for f in os.listdir(directory):
            path = os.path.join(directory, f)
            if os.path.isfile(path):
                ext = os.path.splitext(f)[1].lower()
                if ext in SUPPORTED_FORMATS:
                    image_files.append(path)
    return image_files

def parse_args(args):
    dir_to_files = {}
    for arg in args:
        if os.path.isdir(arg):
            files = find_images_in_directory(arg)
            if files:
                dir_to_files[arg] = files
        else:
            dir_name = os.path.dirname(arg) or os.getcwd()
            dir_to_files.setdefault(dir_name, []).append(arg)
    return dir_to_files

def prepare_output_dirs(dir_to_files):
    tinified_dirs = {}
    has_supported = False
    for dir_name, files in dir_to_files.items():
        supported_files = [f for f in files if os.path.splitext(f)[1].lower() in SUPPORTED_FORMATS]
        if supported_files:
            has_supported = True
            base_tinified_dir = os.path.join(dir_name, "tinified")
            tinified_dir = base_tinified_dir
            count = 1
            while os.path.exists(tinified_dir):
                tinified_dir = f"{base_tinified_dir}({count})"
                count += 1
            os.makedirs(tinified_dir)
            tinified_dirs[dir_name] = tinified_dir
    return tinified_dirs, has_supported

def compress_files(dir_to_files, tinified_dirs):
    success_count = 0
    fail_count = 0
    skip_count = 0
    for dir_name, files in dir_to_files.items():
        tinified_dir = tinified_dirs.get(dir_name)
        for file_path in files:
            ext = os.path.splitext(file_path)[1].lower()
            if ext not in SUPPORTED_FORMATS:
                print(_(f"跳过不支持格式：{file_path}", f"Skipped unsupported format: {file_path}"), file=sys.stdout)
                skip_count += 1
                continue
            if not tinified_dir:
                continue
            file_name = os.path.basename(file_path)
            output_path = os.path.join(tinified_dir, file_name)
            try:
                result = compress_image(file_path, output_path)
                print(_(f"✅ 压缩完成：{result['output_path']}", f"✅ Compressed: {result['output_path']}"), file=sys.stdout)
                print(_(f"📊 剩余Tinify额度：{result['remaining_quota']}/500", f"📊 Remaining Tinify quota: {result['remaining_quota']}/500"), file=sys.stdout)
                success_count += 1
            except Exception as e:
                print(_(f"压缩失败 {file_path}：{str(e)}", f"Compression failed {file_path}: {str(e)}"), file=sys.stderr)
                fail_count += 1
    print(_(
        f"\n压缩完成 - 成功：{success_count} | 失败：{fail_count} | 跳过非支持格式：{skip_count}",
        f"\nCompression finished - Success: {success_count} | Failed: {fail_count} | Skipped unsupported: {skip_count}"
    ), file=sys.stdout)
    return 0 if fail_count == 0 else 1


def main():
    if len(sys.argv) < 2:
        print(_("请传入需要压缩的图片文件路径或目录（支持多个）", "Please provide image file paths or directories to compress (multiple supported)"), file=sys.stderr)
        return 1

    dir_to_files = parse_args(sys.argv[1:])
    if not dir_to_files:
        print(_("未找到需要压缩的图片文件。", "No image files found to compress."), file=sys.stderr)
        return 1

    tinified_dirs, has_supported = prepare_output_dirs(dir_to_files)
    if not has_supported:
        raise RuntimeError(_(
            "图片格式不支持，仅支持['.avif', '.webp', '.png', '.jpg', '.jpeg']",
            "Image format not supported. Only ['.avif', '.webp', '.png', '.jpg', '.jpeg'] are supported."
        ))

    try:
        validate_tinify_key()
    except Exception as e:
        print(_(f"Tinify API Key校验失败：{str(e)}", f"Tinify API Key validation failed: {str(e)}"), file=sys.stderr)
        return 1
    
    return compress_files(dir_to_files, tinified_dirs)


if __name__ == "__main__":
    try:
        exit_code = main()
        sys.exit(exit_code)
    except Exception as e:
        print(_(f"压缩失败：{str(e)}", f"Compression failed: {str(e)}"), file=sys.stderr)
        sys.exit(1)