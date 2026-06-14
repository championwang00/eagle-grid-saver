# Eagle Grid Saver

Eagle Grid Saver is a macOS screen saver for reviewing visual references saved in an [Eagle](https://eagle.cool/) library. It presents images and selected video items as a slow, two-column waterfall so the original aspect ratios stay readable.

## 中文说明

### 这个工具做什么

Eagle Grid Saver 会把 Eagle 素材库里的图片和视频素材展示成一个缓慢滚动的双列瀑布流屏保。它适合用来回顾设计参考、灵感图、界面截图、动效素材和视觉收藏。

### 主要特性

- 直接读取 Eagle `.library`，不把原始图片或高清视频复制进屏保包。
- 双列瀑布流布局，尽量保留素材原始比例。
- 素材之间无明显间隙，滚动速度很慢，适合屏保场景。
- App 内可以选择 Eagle 素材库路径、构建/更新索引，并跳转到系统屏保设置。
- 系统屏保的 `Options...` 面板也可以选择素材库，用于让 macOS 屏保宿主获得读取权限。
- 本地磁盘素材库支持图片和常见视频文件。
- 网络共享盘素材库会进入保守模式：后台扫描、限量索引、默认不播放远程视频，避免 SMB/局域网卡住屏保。

### 安装

下载 `.pkg` 安装包后双击安装。安装后会放置两个组件：

- `/Applications/Eagle Grid Saver.app`
- `/Library/Screen Savers/EagleGridSaver.saver`

也可以从源码构建并安装到当前用户目录：

```sh
./Scripts/install.sh
```

本地脚本会安装到：

- `~/Applications/Eagle Grid Saver.app`
- `~/Library/Screen Savers/EagleGridSaver.saver`

### 使用步骤

1. 打开 **Eagle Grid Saver.app**。
2. 点击 **Choose Eagle Library...**，选择你的 Eagle `.library` 文件夹。
3. 第一次选择后，App 会自动构建索引并提示 **Building index. Please wait...**。请等它完成。
4. 点击 **Settings** 打开 macOS **系统设置 -> 屏幕保护程序**，选择 **Eagle Grid Saver**。
5. 需要立即查看效果时，回到 App 点击 **Start Screen Saver**。
6. 如果系统屏保里没有素材，点击该屏保的 **Options...**，在里面重新选择 Eagle `.library`。这一步能让真正的系统屏保宿主获得文件读取权限。
7. 后续往 Eagle 里新增或删除素材后，打开 App 点击 **Update Index** 即可更新索引。

索引构建完成后，App 可以关掉。系统屏保会读取已经准备好的本地展示索引，不需要 App 一直开着。

### 权限说明

macOS 不允许安装包自动授予文件访问权限。用户必须自己选择素材库路径，或者在系统设置中允许对应的文件访问权限。

如果素材库在桌面、文稿、下载、外置硬盘或网络共享盘上，macOS 可能会要求额外权限。遇到黑屏或提示无法读取时，请先在屏保的 **Options...** 里重新选择 Eagle `.library`。

### 关于局域网素材库

不推荐让屏保直接读取大型局域网 Eagle 库。SMB/网络文件系统可能在读取目录、图片、视频或元数据时长时间阻塞。这个项目已经对网络库做了保守处理，但最稳定的方式仍然是使用本机磁盘上的 Eagle 库，或未来增加本地缓存机制。

## English

### What It Does

Eagle Grid Saver turns an Eagle asset library into a slow macOS screen saver. It shows your visual references in a two-column waterfall layout, keeping source aspect ratios visible while continuously rotating through your collection.

### Features

- Reads media directly from an Eagle `.library` folder.
- Does not copy original source images or high-resolution videos into the screen saver bundle.
- Uses a slow, seamless two-column waterfall layout.
- Includes a companion macOS app for choosing the Eagle library path, preparing/updating the index, and opening Screen Saver settings.
- Includes a screen saver `Options...` panel so the real macOS screen saver host can be granted folder access.
- Supports still images and common video files for local libraries.
- Uses a safer fallback mode for network shares: background scanning, limited indexing, and remote video playback disabled by default.

### Installation

Download the `.pkg` installer and open it. It installs:

- `/Applications/Eagle Grid Saver.app`
- `/Library/Screen Savers/EagleGridSaver.saver`

To build and install from source for the current user:

```sh
./Scripts/install.sh
```

The local install script places files at:

- `~/Applications/Eagle Grid Saver.app`
- `~/Library/Screen Savers/EagleGridSaver.saver`

### Usage

1. Open **Eagle Grid Saver.app**.
2. Click **Choose Eagle Library...** and select your Eagle `.library` folder.
3. On first selection, the app automatically builds the index and shows **Building index. Please wait...**. Wait until it finishes.
4. Click **Settings** to open macOS **System Settings -> Screen Saver**, then choose **Eagle Grid Saver**.
5. To see it immediately, return to the app and click **Start Screen Saver**.
6. If the full system screen saver cannot read your library, open **Options...** for the screen saver and choose the Eagle `.library` there. This gives the actual macOS screen saver host permission to read the folder.
7. After adding or deleting Eagle assets later, open the app and click **Update Index**.

After the index is built, you can close the app. The system screen saver reads the prepared local display index and does not need the app to stay open.

### Permissions

macOS does not let installers silently grant file access. Users must choose the Eagle library folder themselves or allow file access in System Settings.

If your library is on Desktop, Documents, Downloads, an external drive, or a network share, macOS may require additional permission. If the saver shows a loading message or cannot find images, choose the library again from the screen saver **Options...** panel.

### Network Libraries

Large Eagle libraries on SMB or other local network shares are not ideal for a screen saver. Network file systems can block while reading folders, metadata, images, or videos. Eagle Grid Saver includes defensive behavior for network shares, but a local disk library is still the most reliable setup.

## Build

Requirements:

- macOS 13 or newer
- Xcode Command Line Tools

Build only:

```sh
./Scripts/build.sh
```

Build and install for the current user:

```sh
./Scripts/install.sh
```

Build a `.pkg` installer:

```sh
./Scripts/package.sh
```

## Privacy

Eagle Grid Saver stores only the selected Eagle library path, a macOS security-scoped bookmark for folder access, and a local display index/cache for faster screen saver startup. It does not upload data, call external services, or copy original media into the application bundle. The local display cache contains resized JPEG display images/posters, not your original source files or full-resolution videos.

## License

MIT
