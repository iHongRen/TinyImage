# TinyImage

A macOS image compression tool built on the Tinify API that enables quick and easy image compression directly from the Finder toolbar or right-click context menu.

[中文 README](./README.md)

## Features

- Easy operation: integrated into Finder toolbar, one-click compression
- Batch processing: compress multiple images or entire folders at once
- Flexible notifications: choose between dialog, system notification, or silent mode
- Context menu: add TinyImage to Finder's right-click menu via Automator
- Supports Tinify formats: png, jpeg, jpg, webp, avif

## Installation

1. Download [TinyImage.dmg](https://github.com/iHongRen/TinyImage/releases/download/1.0/TinyImage.dmg), double-click, and drag `TinyImage.app` into your `/Applications` folder.
2. Remove quarantine attribute (required): open Terminal and run:
   ```bash
   xattr -d com.apple.quarantine /Applications/TinyImage.app
   ```
   > Because the app is unsigned, macOS may block it. This command removes the quarantine so the app can run.
3. In Applications, hold `⌘ Command` and drag `TinyImage.app` to the Finder toolbar.

![](./screenshots/install.gif)

## Configuration

1. Go to [Tinify Dashboard](https://tinify.com/developers) and apply for a free API Key (500 images/month).
2. Add your API Key and notification type to your shell config file (`~/.zshrc`, `~/.bash_profile`, or `~/.bashrc`):
   ```bash
   export TINIFY_IMAGE_API_KEY="your_api_key_here"
   export TINIFY_SUCCESS_NOTIFICATION_TYPE="dialog"
   # Options:
   # - dialog: dialog prompt
   # - notification: system notification
   # - none: no notification
   ```
3. Run `source ~/.zshrc` (or the relevant file) in Terminal to apply changes.

If you're not familiar with editing environment variables, you can use [ConfigEditor](https://github.com/iHongRen/configEditor) for a graphical interface.

![](./screenshots/config.png)

## Usage

### Finder Toolbar (Recommended)

1. In Finder, select images or folders to compress
2. Click the TinyImage icon in the toolbar
3. On first use, grant permissions if prompted
   
   > If you accidentally deny, go to `Privacy & Security` > `Automation` > `TinyImage.app` and allow Finder access
4. Compression involves upload > compress > download, so please wait patiently

![](./screenshots/tinyimage.gif)

### Command Line

```bash
# Compress a single file
./TinyImage.sh image.jpg

# Compress multiple files
./TinyImage.sh image1.jpg image2.png image3.webp

# Compress a directory
./TinyImage.sh /path/to/images/

# Mixed usage
./TinyImage.sh image.jpg /path/to/images/
```

## Output

Compressed images are saved in a `tinified` subfolder in the original directory. If `tinified` already exists, new folders like `tinified(1)`, `tinified(2)` are created automatically.

Example:
```
OriginalFolder/
├── image1.jpg
├── image2.png
└── tinified/
    ├── image1.jpg  (compressed)
    └── image2.png  (compressed)
```

## Context Menu

Use Automator to add TinyImage to Finder's right-click menu for quick access.

![](./screenshots/quick_contextmenu.png)

Search for 'Automator' in Launchpad, open Automator, create a new Quick Action, and follow the steps below. Name it TinyImage to add the menu item.

![](./screenshots/auto_quick.png)

![](./screenshots/auto_guide.png)

## Support

If TinyImage improves your workflow, please star the project and stay tuned!

Buy me a coffee? [💖Sponsor the developer](https://ihongren.github.io/donate.html)
