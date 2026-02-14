# [TinyImage](https://github.com/iHongRen/TinyImage)

macOS image compression tool - compress images in one click from Finder toolbar.

[中文 README](./README.md)

## Features

- One-click compression from Finder toolbar
- Batch process files and folders
- Supports PNG, JPG, JPEG, WebP, AVIF formats
- Flexible notifications (dialog, system notification, or silent)
- 500 free compressions per month, no 5MB size limit



## Quick Start

### 1️⃣ Installation

1. Download [TinyImage.dmg](https://github.com/iHongRen/TinyImage/releases/download/1.0/TinyImage.dmg)
2. Double-click the DMG and drag `TinyImage.app` to `/Applications` folder
3. Open Terminal and run this command to remove quarantine restriction:
   ```bash
   xattr -d com.apple.quarantine /Applications/TinyImage.app
   ```
4. Hold `⌘ Command` key and drag `TinyImage.app` to the Finder toolbar

![](./screenshots/install.gif)



### 2️⃣ Get API Key

Visit [Tinify Website](https://tinify.com/developers) to sign up and get your free API Key.



### 3️⃣ Configure Environment Variables (One-time setup)

Copy the command below, **replace `your_api_key_here` with your actual API Key**, then paste and run in Terminal:

#### Recommended Method (Single command)

If you use **zsh** (default):
```bash
echo 'export TINIFY_IMAGE_API_KEY="your_api_key_here"' >> ~/.zshrc && echo 'export TINIFY_SUCCESS_NOTIFICATION_TYPE="dialog"' >> ~/.zshrc && source ~/.zshrc
```

If you use **bash**:
```bash
echo 'export TINIFY_IMAGE_API_KEY="your_api_key_here"' >> ~/.bash_profile && echo 'export TINIFY_SUCCESS_NOTIFICATION_TYPE="dialog"' >> ~/.bash_profile && source ~/.bash_profile
```

#### Verify Configuration

Run this command to verify:
```bash
echo $TINIFY_IMAGE_API_KEY
```

If it displays your API Key, configuration is successful ✅



### 4️⃣ Start Using

1. Select images or folders in Finder
2. Click the TinyImage icon in the toolbar
3. Grant permission when prompted on first use
4. Wait for completion (upload → compress → download)

Compressed images are saved in a `tinified` folder.

![](./screenshots/tinyimage.gif)



## Notification Preferences

Customize notification type by changing `TINIFY_SUCCESS_NOTIFICATION_TYPE`:

| Value | Effect |
|---|---|
| `dialog` | Dialog prompt (**recommended**) |
| `notification` | System notification |
| `none` | Silent (no notification) |

To change notification type:
```bash
# zsh users
echo 'export TINIFY_SUCCESS_NOTIFICATION_TYPE="notification"' >> ~/.zshrc && source ~/.zshrc

# bash users
echo 'export TINIFY_SUCCESS_NOTIFICATION_TYPE="notification"' >> ~/.bash_profile && source ~/.bash_profile
```



## Command Line Usage (Optional)

```bash
# Compress single image
./TinyImage.sh image.jpg

# Compress multiple images
./TinyImage.sh image1.jpg image2.png image3.webp

# Compress entire folder
./TinyImage.sh /path/to/images/
```



## Right-Click Context Menu (Optional)

Want to add TinyImage to Finder's right-click menu?

1. Open "Automator" application
2. New → Quick Action
3. Add "Run Shell Script" to the workflow
4. Paste this code:
   ```bash
   open -a "/Applications/TinyImage.app" "$@"
   ```
5. Save and name it `TinyImage`

Now you'll see TinyImage in your right-click context menu.

![](./screenshots/quick_contextmenu.png)

![](./screenshots/auto_quick.png)

![](./screenshots/auto_guide.png)



## FAQ

**Q: I see "Operation Run Shell Script Error" when clicking TinyImage in Finder toolbar?**

A: Open Automator, right-click TinyImage.app in Applications → Open With → Automator, then save directly.

**Q: What if I accidentally denied the permission prompt?**

A: Go to System Settings → Privacy & Security → Automation → Find TinyImage.app and check "Finder" permission.

**Q: How do I change my configured API Key?**

A: Edit `~/.zshrc` or `~/.bash_profile` with a text editor, modify the API Key line, save, then run `source ~/.zshrc` or `source ~/.bash_profile` to reload.



## Support

If you find this tool helpful, please [⭐ Star](https://github.com/iHongRen/TinyImage) the project!

[💖 Support the Developer](https://ihongren.github.io/donate.html)
