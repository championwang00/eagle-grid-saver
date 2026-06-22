# Eagle Grid Saver

Eagle Grid Saver is a macOS screen saver for reviewing visual references saved in an [Eagle](https://eagle.cool/) library. It presents images and selected video items as a slow, configurable-column waterfall so the original aspect ratios stay readable.

## 中文说明

### 这个工具做什么

Eagle Grid Saver 会把 Eagle 素材库里的图片和视频素材展示成一个缓慢滚动、可选择列数的瀑布流屏保。它适合用来回顾设计参考、灵感图、界面截图、动效素材和视觉收藏。

### 主要特性

- 直接读取 Eagle `.library`，不把原始图片或高清视频复制进屏保包。
- 可选择 `1` 到 `6` 列瀑布流布局，尽量保留素材原始比例。
- 素材之间无明显间隙，滚动速度很慢，适合屏保场景。
- App 内可以选择 Eagle 素材库路径、构建/更新索引，并跳转到系统屏保设置。
- 系统屏保的 `Options...` 面板也可以选择素材库，用于让 macOS 屏保宿主获得读取权限。
- 本地磁盘素材库支持图片和常见视频文件。
- 网络共享盘素材库会使用更保守的视频加载策略：先显示索引里的封面图，视频真正出画面后才切到播放层，避免读不出视频时出现黑块。

### 安装

下载 `.pkg` 安装包后双击安装。安装后会放置两个组件：

- `/Applications/Eagle Grid Saver.app`
- `/Library/Screen Savers/EagleGridSaver.saver`

从 `0.9.10` 开始，安装包会自动删除当前登录用户目录里的旧版 `~/Applications/Eagle Grid Saver.app`、`~/Library/Screen Savers/EagleGridSaver.saver` 和 `~/Library/Screen Savers/EagleGridSaver.stale.*`，并刷新屏保宿主缓存。安装后请从 `/Applications/Eagle Grid Saver.app` 打开新版 App。

如果升级后另一台电脑仍然像旧版本一样运行，先退出系统设置并运行：

```sh
./Scripts/reset_installed_saver.sh
```

然后重新安装新版 `.pkg`。这是为了清理 macOS 可能缓存或同时加载的旧版 `EagleGridSaver.saver`。

### 完全卸载

只删除 `/Applications/Eagle Grid Saver.app` 不会移除系统屏保列表里的项目，因为屏保本体是独立的 `.saver` 插件。要完全卸载并清掉 macOS 可能缓存的旧版本，退出系统设置后运行：

```sh
./Scripts/reset_installed_saver.sh
```

这个脚本会删除：

- `/Applications/Eagle Grid Saver.app`
- `/Library/Screen Savers/EagleGridSaver.saver`
- `~/Applications/Eagle Grid Saver.app`
- `~/Library/Screen Savers/EagleGridSaver.saver`
- `~/Library/Screen Savers/EagleGridSaver.stale.*`
- Eagle Grid Saver 的偏好设置和本地展示缓存
- 安装包 receipt 记录

如果运行后系统设置里仍然能看到旧项，重启 macOS 一次。系统设置有时会缓存屏保列表。

也可以从源码构建并安装到当前用户目录：

```sh
./Scripts/install.sh
```

本地脚本会安装到：

- `/Applications/Eagle Grid Saver.app`
- `/Library/Screen Savers/EagleGridSaver.saver`

### 推荐使用流程

#### 全新安装

全新安装时，必须先选择 Eagle 素材库，再完成索引构建。没有选择库时，屏保没有素材来源；没有构建索引时，系统屏保宿主可能没有可用的展示缓存。

1. 安装最新版 `.pkg`。
2. 打开 `/Applications/Eagle Grid Saver.app`。
3. 确认窗口右上角显示当前版本，例如 **Version 0.9.12 (102)**。
4. 点击 **Choose Eagle Library...**，选择你的 Eagle `.library` 文件夹。
5. 选择库后，App 会自动开始构建索引，并显示 **Building index. Please wait...**。请等它完成。
6. 索引完成后，底部状态会显示素材数量、视频数量和缓存路径，例如 `Ready. Index has ... items (... videos). Cache: ...`。
7. 点击 **Settings** 打开 macOS **系统设置 -> 屏幕保护程序**。
8. 这一步必须手动做一次：在系统设置里把 **使用屏幕保护程序** 设为 **自定义**，并点击选中 **Eagle Grid Saver**。如果跳过这一步，macOS 可能继续播放太浩湖、红杉等系统屏保。
9. 需要立即查看效果时，回到 App 点击 **Start Screen Saver**。

#### 覆盖更新

已经安装过旧版本的用户，安装新版后也应该先更新索引，再启动屏保。新版安装包会清理旧版 `.saver`、用户目录残留和屏保宿主缓存；**Update Index** 会把当前库、速度、列数、展示索引和运行配置重新同步给真正的系统屏保进程。

1. 退出 macOS 系统设置里的屏保页面。
2. 安装最新版 `.pkg`。
3. 打开 `/Applications/Eagle Grid Saver.app`，确认右上角版本号已经更新。
4. 确认 Eagle 库路径正确。
5. 点击 **Update Index**。
6. 等到底部显示 `Ready. Index has ...` 后，再启动屏保。
7. 如果系统仍播放 Apple 自带屏保，点击 **Settings**，在系统设置里重新确认 **Eagle Grid Saver** 被选中。

后续只是新增或删除 Eagle 素材时，不需要重新安装；打开 App 点击 **Update Index** 即可。

### 详细使用步骤

1. 打开 **Eagle Grid Saver.app**。
2. 确认窗口右上角显示当前版本，例如 **Version 0.9.12 (102)**。
3. 点击 **Choose Eagle Library...**，选择你的 Eagle `.library` 文件夹。
4. 第一次选择后，App 会自动构建索引并提示 **Building index. Please wait...**。请等它完成。
5. 使用 **Scroll Speed** 滑块调节滚动速度，默认是 `1.0x`，范围是 `0.25x` 到 `10.0x`；使用 **Columns** 选择横向列数，范围是 `1` 到 `6` 列，默认 `2` 列。这些设置会立即写入屏保运行配置，不需要重新构建索引。手动重建索引时，App 也会自动刷新屏保宿主的旧缓存和旧路径配置。
6. 索引完成后，底部状态会显示索引数量、视频数量和缓存路径，例如 `Index has ... items (... videos). Cache: ...`。
7. 点击 **Settings** 打开 macOS **系统设置 -> 屏幕保护程序**，选择 **Eagle Grid Saver**。
8. 在系统屏保的 **Options...** 面板右上角确认版本号，确保系统加载的是新版 `.saver`；这里也可以调节 **Scroll Speed** 和 **Columns**。
9. 这一步必须手动做一次：在系统弹窗里把 **使用屏幕保护程序** 设为 **自定义**，并点击选中 **Eagle Grid Saver**。如果跳过这一步，macOS 可能继续播放太浩湖、红杉等系统屏保。
10. 需要立即查看效果时，回到 App 点击 **Start Screen Saver**。如果 App 检测到系统选择还不可靠，会再次打开系统设置并提示手动选择。
11. 如果系统屏保里没有素材，点击该屏保的 **Options...**，在里面重新选择 Eagle `.library`。这一步能让真正的系统屏保宿主获得文件读取权限。
12. 后续往 Eagle 里新增或删除素材后，打开 App 点击 **Update Index** 即可更新索引。

索引构建完成后，App 可以关掉。系统屏保会读取已经准备好的本地展示索引，不需要 App 一直开着。

### 权限说明

macOS 不允许安装包自动授予文件访问权限。用户必须自己选择素材库路径，或者在系统设置中允许对应的文件访问权限。

如果素材库在桌面、文稿、下载、外置硬盘或网络共享盘上，macOS 可能会要求额外权限。遇到黑屏或提示无法读取时，请先在屏保的 **Options...** 里重新选择 Eagle `.library`。

### 关于局域网素材库

不推荐让屏保直接读取大型局域网 Eagle 库。SMB/网络文件系统可能在读取目录、图片、视频或元数据时长时间阻塞。这个项目已经对网络库做了保守处理：图片和视频封面会优先使用本地展示索引，视频播放失败或超时会保留封面图，不会留下黑块。最稳定的方式仍然是使用本机磁盘上的 Eagle 库。

## English

### What It Does

Eagle Grid Saver turns an Eagle asset library into a slow macOS screen saver. It shows your visual references in a configurable-column waterfall layout, keeping source aspect ratios visible while continuously rotating through your collection.

### Features

- Reads media directly from an Eagle `.library` folder.
- Does not copy original source images or high-resolution videos into the screen saver bundle.
- Uses a slow, seamless waterfall layout with `1` to `6` selectable columns.
- Includes a companion macOS app for choosing the Eagle library path, preparing/updating the index, and opening Screen Saver settings.
- Includes a screen saver `Options...` panel so the real macOS screen saver host can be granted folder access.
- Supports still images and common video files for local libraries.
- Uses safer video loading for network shares: poster images appear first, and the video layer is shown only after a real frame is available.

### Installation

Download the `.pkg` installer and open it. It installs:

- `/Applications/Eagle Grid Saver.app`
- `/Library/Screen Savers/EagleGridSaver.saver`

Starting with `0.9.10`, the installer removes stale per-user copies at `~/Applications/Eagle Grid Saver.app`, `~/Library/Screen Savers/EagleGridSaver.saver`, and `~/Library/Screen Savers/EagleGridSaver.stale.*`, then refreshes screen saver host caches. After installing, open the new app from `/Applications/Eagle Grid Saver.app`.

If an upgraded Mac still behaves like an older build, quit System Settings and run:

```sh
./Scripts/reset_installed_saver.sh
```

Then reinstall the latest `.pkg`. This clears stale user/system screen saver copies that macOS may keep loading.

### Full Uninstall

Deleting `/Applications/Eagle Grid Saver.app` alone does not remove the item from Screen Saver settings, because the actual screen saver is a separate `.saver` plugin. To fully uninstall it and clear stale macOS copies, quit System Settings and run:

```sh
./Scripts/reset_installed_saver.sh
```

The script removes:

- `/Applications/Eagle Grid Saver.app`
- `/Library/Screen Savers/EagleGridSaver.saver`
- `~/Applications/Eagle Grid Saver.app`
- `~/Library/Screen Savers/EagleGridSaver.saver`
- `~/Library/Screen Savers/EagleGridSaver.stale.*`
- Eagle Grid Saver preferences and local display cache
- installer package receipts

If the old entry still appears after that, restart macOS once. System Settings can cache the screen saver list.

To build and install from source for the current user:

```sh
./Scripts/install.sh
```

The local install script places files at:

- `/Applications/Eagle Grid Saver.app`
- `/Library/Screen Savers/EagleGridSaver.saver`

### Recommended Flow

#### New Install

On a new install, choose the Eagle library first, then let the app build the index. Without a selected library, the screen saver has no source assets. Without an index, the real macOS screen saver host may not have a usable display cache.

1. Install the latest `.pkg`.
2. Open `/Applications/Eagle Grid Saver.app`.
3. Check the version in the top-right corner, such as **Version 0.9.12 (102)**.
4. Click **Choose Eagle Library...** and select your Eagle `.library` folder.
5. After the library is selected, the app automatically starts building the index and shows **Building index. Please wait...**. Wait until it finishes.
6. When the index is ready, the bottom status shows the item count, video count, and cache path, such as `Ready. Index has ... items (... videos). Cache: ...`.
7. Click **Settings** to open macOS **System Settings -> Screen Saver**.
8. This must be done manually once: set **Use screen saver** to **Custom** and click **Eagle Grid Saver**. If this step is skipped, macOS may keep playing Tahoe, Sequoia, or another Apple screen saver.
9. To see it immediately, return to the app and click **Start Screen Saver**.

#### Updating From an Older Version

After installing over an older version, update the index before starting the screen saver. The installer removes stale `.saver` copies, per-user leftovers, and screen saver host caches; **Update Index** re-syncs the current library, speed, columns, display index, and runtime config to the real macOS screen saver host.

1. Quit the Screen Saver page in macOS System Settings.
2. Install the latest `.pkg`.
3. Open `/Applications/Eagle Grid Saver.app` and confirm the version changed.
4. Confirm the Eagle library path is correct.
5. Click **Update Index**.
6. Wait until the bottom status says `Ready. Index has ...`, then start the screen saver.
7. If macOS still plays an Apple screen saver, click **Settings** and confirm **Eagle Grid Saver** is selected in System Settings.

Later, when you only add or delete Eagle assets, you do not need to reinstall. Open the app and click **Update Index**.

### Detailed Usage

1. Open **Eagle Grid Saver.app**.
2. Check the version in the top-right corner, such as **Version 0.9.12 (102)**.
3. Click **Choose Eagle Library...** and select your Eagle `.library` folder.
4. On first selection, the app automatically builds the index and shows **Building index. Please wait...**. Wait until it finishes.
5. Use the **Scroll Speed** slider to tune the waterfall speed. The default is `1.0x`, and the range is `0.25x` to `10.0x`. Use **Columns** to choose `1` to `6` columns; the default is `2`. These changes are written directly to the screen saver runtime config, so rebuilding the index is not required. A manual index rebuild also refreshes stale screen saver host caches and path preferences automatically.
6. When the index is ready, the bottom status shows the item count, video count, and cache path, such as `Index has ... items (... videos). Cache: ...`.
7. Click **Settings** to open macOS **System Settings -> Screen Saver**, then choose **Eagle Grid Saver**.
8. In the screen saver **Options...** panel, check the version in the top-right corner to confirm macOS loaded the latest `.saver`; the same panel also has **Scroll Speed**.
9. This must be done manually once: in the system sheet, set **Use screen saver** to **Custom** and click **Eagle Grid Saver**. If this step is skipped, macOS may keep playing Tahoe, Sequoia, or another Apple screen saver.
10. To see it immediately, return to the app and click **Start Screen Saver**. If the app cannot trust the current system selection, it opens System Settings again and asks you to choose Eagle Grid Saver manually.
11. If the full system screen saver cannot read your library, open **Options...** for the screen saver and choose the Eagle `.library` there. This gives the actual macOS screen saver host permission to read the folder.
12. After adding or deleting Eagle assets later, open the app and click **Update Index**.

After the index is built, you can close the app. The system screen saver reads the prepared local display index and does not need the app to stay open.

### Permissions

macOS does not let installers silently grant file access. Users must choose the Eagle library folder themselves or allow file access in System Settings.

If your library is on Desktop, Documents, Downloads, an external drive, or a network share, macOS may require additional permission. If the saver shows a loading message or cannot find images, choose the library again from the screen saver **Options...** panel.

### Network Libraries

Large Eagle libraries on SMB or other local network shares are not ideal for a screen saver. Network file systems can block while reading folders, metadata, images, or videos. Eagle Grid Saver uses the local display index first and keeps the poster visible if video playback fails or times out, but a local disk library is still the most reliable setup.

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
