# TinyImage

一个基于 Tinify API 的 macOS 图片压缩工具，支持批量处理，在Finder工具栏上操作简单快捷。

[English](./README_EN.md)

## 功能特点

- 便捷操作：集成到 Finder 工具栏，一键压缩
- 批量处理：支持多个图片或整个目录的批量压缩
- 多语言支持：自动检测系统语言（中文/英文）
- 灵活提示：支持弹窗、通知或静默三种提示方式
- 依赖Tinify支持的图片格式：png、jpeg、jpg、webp、avif



## 安装步骤

1. 下载 `TinyImage.dmg`, 双击后将 `TinyImage.app` 拖放到 `/Applications`（应用程序）文件夹中
3. 去除隔离属性（重要）：打开终端，执行以下命令
   ```bash
   xattr -d com.apple.quarantine /Applications/TinyImage.app
   ```
   > 由于应用未签名，macOS 会阻止其运行。此命令会移除隔离属性，允许应用正常使用。
4. 按住 `⌘ Command` 键，将 `TinyImage.app` 拖动到 Finder 工具栏上



## 配置

##### 1. 获取 API Key

前往 [Tinify Dashboard](https://tinify.com/dashboard/api) 申请免费 API Key（每月可免费压缩 500 张图片）

##### 2. 在环境变量配置文件中添加 API Key

将以下内容添加到 `~/.zshrc`、`~/.bash_profile` 或 `~/.bashrc` 文件中：

```bash
export TINIFY_IMAGE_API_KEY="your_api_key_here"
```

然后执行 `source ~/.zshrc`（或对应的配置文件）使其生效。

##### 3. 配置提示方式（可选）

设置压缩成功后的提示方式：

```bash
export TINIFY_SUCCESS_NOTIFICATION_TYPE="dialog"
```

可选值：
- `dialog` - 弹窗提示，可点击直接打开压缩后的文件夹
- `notification` - 系统通知
- `none` - 不显示提示



## 使用方法

### 通过 Finder 工具栏使用（推荐）

1. 在 访达(Finder) 中选择要压缩的图片文件或包含图片的文件夹
2. 点击工具栏上的 TinyImage 图标
3. 首次使用时，同意权限请求。如果不小心点了拒绝，可前往 隐私与安全性 > 自动化 > TinyImage.app 打开访达访问权限
4. 等待压缩完成，压缩后的图片会保存在 `tinified` 文件夹中



### 源码执行，通过命令行使用

```bash
# 压缩单个文件
./TinyImage.sh image.jpg

# 压缩多个文件
./TinyImage.sh image1.jpg image2.png image3.webp

# 压缩整个目录
./TinyImage.sh /path/to/images/

# 混合使用
./TinyImage.sh image.jpg /path/to/images/
```



## 输出说明

压缩后的图片会保存在原文件所在目录的 `tinified` 子文件夹中。如果 `tinified` 文件夹已存在，会自动创建 `tinified(1)`、`tinified(2)` 等文件夹。

示例：
```
原始目录/
├── image1.jpg
├── image2.png
└── tinified/
    ├── image1.jpg  (压缩后)
    └── image2.png  (压缩后)
```




