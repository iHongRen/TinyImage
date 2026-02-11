#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import importlib.util
import os
import subprocess
import sys

# 定义Tinify支持的图片格式（小写）
SUPPORTED_FORMATS = ['.avif', '.webp', '.png', '.jpg', '.jpeg']

def get_pip_command():
    """
    自动检测当前Python环境对应的pip命令
    优先级：python -m pip > pip3 > pip
    :return: 可用的pip命令列表
    """
    # 优先使用 python -m pip（最可靠）
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

    # 尝试pip3
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

    # 最后尝试pip
    pip_cmd = ["pip"]
    try:
        subprocess.check_call(
            pip_cmd + ["--version"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL
        )
        return pip_cmd
    except (subprocess.CalledProcessError, FileNotFoundError):
        raise RuntimeError("未找到可用的pip/pip3命令，请先安装Python包管理工具")

def check_and_install_tinify():
    """检查并安装tinify库（必须依赖）"""
    # 检查tinify是否安装
    tinify_spec = importlib.util.find_spec("tinify")
    if tinify_spec is None:
        print("⚠️ 未检测到tinify库，正在自动安装...", file=sys.stdout)
        pip_cmd = get_pip_command()
        # 移除--user参数，安装到全局目录
        install_cmd = pip_cmd + ["install", "tinify"]  # 关键修改：删掉--user
        try:
            subprocess.check_call(
                install_cmd,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.STDOUT
            )
            print("✅ tinify库安装成功！", file=sys.stdout)
        except subprocess.CalledProcessError as e:
            # 安装失败时提示用sudo重试
            raise RuntimeError(f"tinify库安装失败：执行命令 {install_cmd} 出错，可尝试手动执行：sudo pip3 install tinify，错误信息：{str(e)}")

# 自动检查并安装tinify（必须依赖）
check_and_install_tinify()

# 导入tinify库
import tinify


def compress_image_with_tinify(input_path):
    """
    使用Tinify API压缩图片
    仅处理AVIF、WebP、PNG、JPEG格式
    :param input_path: 原图片路径
    :return: 压缩结果字典
    """
    # 生成输出路径
    dir_name, file_name = os.path.split(input_path)
    

    # tinified_dir由外部传入，直接使用
    output_path = os.path.join(dir_name, file_name)  # 仅作占位，实际外部会传tinified_dir
    # 但此处output_path会被外部覆盖
    # ...existing code...

    # 调用Tinify API压缩（原生支持目标格式）
    source = tinify.from_file(input_path)
    source.to_file(output_path)

    return {
        "input_path": input_path,
        "output_path": output_path,
        "remaining_quota": tinify.compression_count
    }

def find_images_in_directory(directory, recursive=True):
    """
    查找目录下所有支持格式的图片文件
    :param directory: 目录路径
    :param recursive: 是否递归子目录
    :return: 图片文件路径列表
    """
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

def main():
        # 统一做API Key校验
    tinify_api_key = os.getenv("TINIFY_API_KEY")
    if not tinify_api_key:
        print("❌ 未设置TINIFY_API_KEY环境变量，无法使用Tinify API压缩", file=sys.stderr)
        return 1
    tinify.key = tinify_api_key
    try:
        tinify.validate()
    except tinify.AccountError as e:
        print(f"❌ Tinify账号错误 - {str(e)}", file=sys.stderr)
        return 1
    except Exception as e:
        print(f"❌ Tinify API Key校验失败：{str(e)}", file=sys.stderr)
        return 1
    
    """主函数：批量压缩、异常捕获，支持目录参数"""
    if len(sys.argv) < 2:
        raise ValueError("请传入需要压缩的图片文件路径或目录（支持多个）")

    # 初始化统计
    success_count = 0
    fail_count = 0
    skip_count = 0
    all_files = []

    # 支持传入文件或目录，只一级目录查找图片
    dir_to_files = {}
    for arg in sys.argv[1:]:
        if os.path.isdir(arg):
            files = find_images_in_directory(arg, recursive=False)
            if files:
                dir_to_files[arg] = files
        else:
            dir_name = os.path.dirname(arg) or os.getcwd()
            dir_to_files.setdefault(dir_name, []).append(arg)

    if not dir_to_files:
        print("未找到需要压缩的图片文件。", file=sys.stderr)
        return 1

    # 为每个目录只创建一次tinified目录，若已存在则递增
    tinified_dirs = {}
    for dir_name in dir_to_files:
        base_tinified_dir = os.path.join(dir_name, "tinified")
        tinified_dir = base_tinified_dir
        count = 1
        while os.path.exists(tinified_dir):
            tinified_dir = f"{base_tinified_dir}({count})"
            count += 1
        os.makedirs(tinified_dir)
        tinified_dirs[dir_name] = tinified_dir



    for dir_name, files in dir_to_files.items():
        tinified_dir = tinified_dirs[dir_name]
        for file_path in files:
            try:
                # 校验文件是否存在
                if not os.path.exists(file_path):
                    raise FileNotFoundError(f"图片文件不存在：{file_path}")
                # 校验格式是否支持
                ext = os.path.splitext(file_path)[1].lower()
                if ext not in SUPPORTED_FORMATS:
                    raise ValueError(f"不支持的图片格式：{ext}，仅支持{SUPPORTED_FORMATS}")
                # 生成输出文件路径
                file_name = os.path.basename(file_path)
                output_path = os.path.join(tinified_dir, file_name)
                # 调用tinify API压缩
                source = tinify.from_file(file_path)
                source.to_file(output_path)
                print(f"✅ 压缩完成：{output_path}", file=sys.stdout)
                print(f"📊 剩余Tinify额度：{tinify.compression_count}/500", file=sys.stdout)
                success_count += 1
            except ValueError as e:
                print(f"ℹ️ 跳过非支持格式文件 {file_path}：{str(e)}", file=sys.stdout)
                skip_count += 1
            except FileNotFoundError as e:
                print(f"❌ 压缩失败 {file_path}：{str(e)}", file=sys.stderr)
                fail_count += 1
            except EnvironmentError as e:
                print(f"❌ 压缩失败 {file_path}：{str(e)}", file=sys.stderr)
                fail_count += 1
            except tinify.AccountError as e:
                print(f"❌ 压缩失败 {file_path}：Tinify账号错误 - {str(e)}", file=sys.stderr)
                fail_count += 1
            except tinify.ClientError as e:
                print(f"❌ 压缩失败 {file_path}：图片格式/内容错误 - {str(e)}", file=sys.stderr)
                fail_count += 1
            except tinify.ServerError as e:
                print(f"❌ 压缩失败 {file_path}：Tinify服务器错误 - {str(e)}", file=sys.stderr)
                fail_count += 1
            except Exception as e:
                print(f"❌ 压缩失败 {file_path}：{str(e)}", file=sys.stderr)
                fail_count += 1

    print(f"\n📈 压缩完成 - 成功：{success_count} | 失败：{fail_count} | 跳过非支持格式：{skip_count}", file=sys.stdout)
    return 0 if fail_count == 0 else 1

if __name__ == "__main__":
    try:
        exit_code = main()
        sys.exit(exit_code)
    except Exception as e:
        print(f"💥 程序执行失败：{str(e)}", file=sys.stderr)
        sys.exit(1)