# YouShot

YouShot 是一款原生 macOS 菜单栏截图工具。当前源码版本为 **1.1.0**（Bundle ID：`top.yayalu.youshot`）。它常驻菜单栏、不显示 Dock 图标，支持当前屏幕、全部屏幕、窗口吸附、自由区域和滚动长截图，并可以在截图原位置直接标注。

截图使用 ScreenCaptureKit，按显示器原生像素输出无损 PNG。窗口吸附使用独立窗口采集，背景透明，并排除系统投影。

- 官网：<https://youshot.yayalu.top>
- 发布页：<https://github.com/lageev/youshot/releases>
- 当前版本下载：[YouShot-1.1.0.zip](https://github.com/lageev/youshot/releases/download/v1.1.0/YouShot-1.1.0.zip)

## 功能

- 当前屏幕、全部屏幕、自由区域截图
- 区域框选完成后直接进入标注；选区右侧的「长截图」可接着选择自动或手动滚动。滚动长截图快捷键会进入同一标注层，并直接展开滚动方式
- 滚动长截图：自动 / 手动滚动、逐行比对拼接、右侧实时预览。页面不再产生新内容，或达到高度上限后停止
- 长截图支持暂停 / 继续、提前完成、Esc 取消。粘性顶栏、底部悬浮条、静止侧栏和滚动条不会在长图中重复出现
- 完成后打开预览窗口，可继续标注、裁掉首尾、复制或保存
- 零延迟区域截图会在触发瞬间冻结各屏幕，可框选失焦后消失的菜单、Popover、Spotlight / Raycast 浮层。设置了延迟时，倒计时结束后重新采集
- 窗口悬停吸附与单击选取，按住 `⌥` 可临时关闭吸附
- 矩形（圆角矩形或椭圆）、直线、箭头、画笔、文字、序号、高亮、马赛克、模糊和水印
- 画笔有硬笔、荧光笔、柔边；序号有实心圆、白底圆、方块和纯数字，按点击顺序生成 1、2、3
- 文字背景可选无、圆角、胶囊、圆形、横幅。水印可选斜向平铺、居中大字、右下角、底部横幅
- 标注颜色、粗细、透明度可调。矩形、椭圆、文字和序号绘制后可拖动；直线、箭头、画笔、高亮、马赛克和模糊写入图像，支持撤销与重做
- 标注选区可从八个方向调整，指针会随边缘方向变化
- 多显示器与 Retina 原生像素输出
- 导出 PNG 为透明底，可配置圆角和阴影。长截图裁剪导出不套用这套圆角和阴影
- 0–60 秒延迟截图。菜单栏提供立即、3 秒、5 秒、10 秒；设置里可用步进器调整到 60 秒
- 可自定义全局快捷键，组合键需包含 `⌘`、`⌥` 或 `⌃`
- 基于 Sparkle 2.9.6 的自分发更新：检查更新、签名校验，以及自动检查、自动下载

## 系统要求

- macOS 14 Sonoma 或更高版本
- 屏幕录制权限
- 从源码构建时需要 Xcode，以及带 macOS SDK 的 Swift 6 工具链

首次截图时，请前往：

> 系统设置 → 隐私与安全性 → 屏幕录制

允许 YouShot 录制屏幕。修改权限后可能需要重新启动应用。

只有自动滚动长截图需要「辅助功能」权限，用来向选区发送滚轮事件。手动滚动只需屏幕录制权限。

## 安装

下载 [YouShot-1.1.0.zip](https://github.com/lageev/youshot/releases/download/v1.1.0/YouShot-1.1.0.zip)，解压后打开 `YouShot.app`。应用启动后出现在菜单栏。

已安装的版本可通过菜单栏「检查更新…」，或「设置 → 关于」中的自动检查、自动下载获取更新。更新源为 <https://youshot.yayalu.top/updates/appcast.xml>。

## 构建与运行

可分发的菜单栏应用由 Xcode 工程生成，其中包含 `Info.plist`、图标和 Sparkle 配置。

```bash
open YouShot.xcodeproj
```

选择共享的 `YouShot` Scheme，运行目标选择 `My Mac`，然后按 `⌘R`。该 Scheme 的运行配置是 Release。

下面的命令只编译 Swift Package，不会组装成带资源的 `.app`：

```bash
swift build
swift build -c release
```

## 使用方法

启动后，YouShot 常驻菜单栏，不显示 Dock 图标。选区遮罩、倒计时和标注层不会被截进成品；可见的设置窗口可以被截到。

1. 从菜单栏选择截图模式，或使用全局快捷键。
2. 区域模式下，悬停窗口可吸附，单击选取窗口；拖动则自由框选。框选后直接进入标注层。需要长截图时，点击选区右侧的「长截图」，再选择自动滚动或手动滚动。
   长截图请框住实际滚动内容（例如网页正文），不要包含浏览器标签栏。
3. 当前屏幕和全部屏幕会先按设置倒计时，再截图。区域模式在选区完成后才开始倒计时。
4. 普通区域截图在原位置显示标注层。点击绿色勾只复制到剪贴板，点击下载按钮才把 PNG 保存到「图片/YouShot」。
5. 长截图在选区右侧显示实时拼接预览。手动模式下在选区内缓慢滚动；自动模式会滚动页面，并在不再产生新内容时停止。两种模式都可以暂停、提前完成或取消。
6. 长截图完成时已复制到剪贴板，并打开预览窗口，可继续标注、裁掉首尾或保存。若没有检测到滚动，会保留当前选区并打开同一预览。

按 `Esc` 可以取消选区、倒计时、长截图或标注。文字输入过程中按 `Esc` 会先取消输入。

标注时，画笔、直线和箭头按住 `⇧` 可吸附为水平、垂直或 45° 直线；矩形和椭圆按住 `⇧` 可绘制正方形或正圆。

## 默认快捷键

| 操作 | 快捷键 |
| --- | --- |
| 当前屏幕 | `⌥⇧⌘3` |
| 区域截图 | `⌥⇧⌘4` |
| 全部屏幕 | `⌥⇧⌘5` |
| 滚动长截图 | `⌥⇧⌘6` |

快捷键可以在「设置 → 快捷键」中重新录制。

## 输出

文件保存在 `~/Pictures/YouShot`（访达中的「图片/YouShot」）。

- 当前屏幕保存为 `YouShot-<时间>.png`，并写入剪贴板
- 全部屏幕按显示器各存一张 `YouShot-<时间>-<序号>.png`。剪贴板是指针所在的那一块屏幕
- 区域截图点击绿色勾只复制到剪贴板；点击下载才保存 `YouShot-<时间>.png`
- 输出尺寸为截图点尺寸乘以该显示器的像素比例
- 窗口吸附截图单独采集该窗口，圆角外透明，不包含系统投影
- 菜单和高层浮窗在零延迟时使用触发瞬间的屏幕合成帧，保留透明、模糊及其背景
- 成品默认不包含鼠标指针，可在菜单栏或「设置 → 截图」中打开。长截图始终不包含鼠标指针
- 长截图保存为 `YouShot-Long-<时间>.png`。预览里的首尾裁剪只影响复制和保存的结果

## 设置

设置窗口有六个标签：截图、标注、水印、导出、快捷键、关于。

- 截图：模式、倒计时、鼠标指针、窗口吸附，以及长截图的单次滚动比例和最大高度（1.2 万、3 万、6 万像素，默认 3 万）
- 标注：颜色、粗细、笔刷、透明度、矩形形状、文字背景、高亮遮罩、模糊强度和羽化
- 水印：文字、颜色、大小、透明度和样式
- 导出：圆角、阴影和深浅；可在 Finder 中显示最近截图，或回到尚未关闭的标注层
- 关于：版本、官网，以及 Sparkle 自动检查、自动下载和手动检查更新

## 项目结构

```text
Sources/YouShot/
├── YouShotApp.swift          # 菜单栏、设置窗口、热键注册
├── ContentView.swift         # 设置窗口
├── CaptureController.swift   # 截图、保存、编辑状态
├── RegionSelector.swift      # 区域选择与窗口吸附
├── ScrollCapture.swift       # 长截图拼接、采集 HUD 与结果预览
├── AnnotationOverlay.swift   # 原位置全屏标注层
├── EditorView.swift          # 标注画布、工具栏、文字输入
├── AnnotationRenderer.swift  # 标注模型与渲染
├── ImageMosaic.swift         # 马赛克、模糊、圆角阴影与 PNG 写入
├── AppSettings.swift         # 设置持久化
├── HotKeyManager.swift       # Carbon 全局热键
├── KeyChord.swift            # 快捷键模型
├── CaptureMode.swift         # 截图模式
└── UpdateController.swift    # Sparkle 更新
```

## 参考项目

YouShot 的截图交互和鼠标指针处理参考了以下开源项目：

- [macshot](https://github.com/sw33tLie/macshot)
- [capcap](https://github.com/realskyrin/capcap)

## English

YouShot is a native macOS menu bar screenshot app. The source tree is version **1.1.0** (bundle ID `top.yayalu.youshot`). It stays in the menu bar, has no Dock icon, and captures the current display, every display, a snapped window, a free region, or a scrolling page. Region shots can be annotated in place.

Captures use ScreenCaptureKit and are written as lossless PNGs at the display’s native pixel size. A snapped window is captured on its own, with a transparent background and without the system shadow.

- Website: <https://youshot.yayalu.top>
- Releases: <https://github.com/lageev/youshot/releases>
- Current download: [YouShot-1.1.0.zip](https://github.com/lageev/youshot/releases/download/v1.1.0/YouShot-1.1.0.zip)

### Features

- Current display, all displays, and free-region capture
- Annotation starts as soon as a region is selected. A **Long screenshot** control on the right offers automatic or manual scrolling. The scroll shortcut opens the same editor with that choice already expanded
- Scrolling capture stitches frames by comparing rows, shows a live preview, and stops when the page no longer adds content or the height limit is reached
- Pause, resume, finish early, or press Esc. Sticky headers, floating bottom bars, static sidebars, and scrollbars are not repeated
- The result window supports more annotation, top and bottom trimming, copy, and save
- A zero-delay region capture freezes every display at the trigger moment, so menus, popovers, Spotlight, and Raycast panels can still be framed. A delay recaptures after the countdown
- Hover a window to snap, click to capture it, or drag a free rectangle. Hold Option to ignore snapping
- Rounded rectangle or ellipse, line, arrow, pen, text, numbered badges, highlight, mosaic, blur, and watermark
- Pen brushes are hard, highlighter, and soft. Number badges are filled circle, ring, square, or plain digits, inserted as 1, 2, 3
- Text backdrops are none, rounded, capsule, circle, or banner. Watermarks are tiled, centered, bottom-right, or a bottom banner
- Rectangles, ellipses, text, and numbers can be dragged. Lines, arrows, pen strokes, highlights, mosaics, and blurs are painted into the image and can be undone
- The selection can be resized from eight edges, with a cursor that matches the edge
- Multi-display and Retina native pixels
- Exported PNGs are transparent and can include a corner radius and shadow. Long-screenshot export does not apply that style
- Delay from 0 to 60 seconds. The menu offers immediate, 3, 5, and 10 seconds; Settings can step up to 60
- Custom global shortcuts. A shortcut must include Command, Option, or Control
- Sparkle 2.9.6 updates with signature checks, automatic checks, and automatic downloads

### Requirements

- macOS 14 Sonoma or later
- Screen Recording permission
- Xcode and a Swift 6 toolchain with the macOS SDK, when building from source

On the first capture, allow YouShot under **System Settings → Privacy & Security → Screen Recording**. Restart the app if the permission change does not take effect.

Automatic scrolling also needs **Accessibility**, because it posts scroll-wheel events. Manual scrolling only needs Screen Recording.

### Install

Download [YouShot-1.1.0.zip](https://github.com/lageev/youshot/releases/download/v1.1.0/YouShot-1.1.0.zip), unzip it, and open `YouShot.app`. The app appears in the menu bar.

Use **Check for Updates…** in the menu bar, or the controls under **Settings → About**. The update feed is <https://youshot.yayalu.top/updates/appcast.xml>.

### Build and run

The distributable menu bar app comes from the Xcode project, which supplies `Info.plist`, the icon, and the Sparkle configuration.

```bash
open YouShot.xcodeproj
```

Select the shared **YouShot** scheme, set the run destination to **My Mac**, and press Command-R. The scheme runs the Release configuration.

These commands only compile the Swift package. They do not assemble a `.app`:

```bash
swift build
swift build -c release
```

### Usage

YouShot stays in the menu bar and does not show a Dock icon. The selection shade, countdown, and annotation layer are excluded from the image. A visible Settings window can be captured.

1. Choose a mode from the menu bar, or use a global shortcut.
2. In region mode, hover to snap a window and click it, or drag a free rectangle. Annotation opens immediately. For a long screenshot, click **Long screenshot** and then choose automatic or manual scrolling.
   Frame the scrolling content, such as a page body, and leave the browser tab bar outside the selection.
3. Current-display and all-displays captures wait for the delay first. Region capture starts the countdown after the selection is finished.
4. On the annotation layer, the green check copies the image. The download button saves a PNG to `~/Pictures/YouShot`.
5. A long capture shows a live stitched preview. Scroll slowly inside the selection for manual mode. Automatic mode scrolls and stops when new content stops appearing. Either mode can be paused, finished, or cancelled.
6. The finished long image is already on the clipboard. A preview window opens for annotation, trimming, and saving. If no scroll is detected, the current selection is kept in that same preview.

Esc cancels selection, countdown, scrolling capture, or annotation. During text entry, Esc cancels the text first.

Hold Shift while drawing with the pen, line, or arrow to snap to horizontal, vertical, or 45 degrees. Hold Shift with the rectangle or ellipse tool to draw a square or circle.

### Default shortcuts

| Action | Shortcut |
| --- | --- |
| Current display | Option-Shift-Command-3 |
| Region | Option-Shift-Command-4 |
| All displays | Option-Shift-Command-5 |
| Scrolling capture | Option-Shift-Command-6 |

Record new shortcuts in **Settings → Shortcuts**.

### Output

Files are saved in `~/Pictures/YouShot`.

- The current display is saved as `YouShot-<timestamp>.png` and copied to the clipboard
- All displays are saved as `YouShot-<timestamp>-<index>.png`. The clipboard receives the display under the pointer
- A region copy does not write a file. Download saves `YouShot-<timestamp>.png`
- Pixel size is the point size multiplied by that display’s scale factor
- A snapped window is captured alone, transparent outside its corners, without the system shadow
- With zero delay, menus and high-level floating panels come from the frozen composite frame
- The pointer is omitted unless enabled in the menu bar or **Settings → Capture**. Long screenshots never include it
- A saved long screenshot is `YouShot-Long-<timestamp>.png`. Top and bottom trimming affects the copied and saved image

### Settings

The settings window has six tabs: Capture, Annotate, Watermark, Export, Shortcuts, and About.

- Capture: mode, countdown, pointer, window snapping, scroll step, and maximum height (12,000, 30,000, or 60,000 pixels; 30,000 by default)
- Annotate: color, width, brush, opacity, rectangle shape, text backdrop, highlight dim, blur strength, and feather
- Watermark: text, color, size, opacity, and style
- Export: corner radius and shadow, plus a link to the last file or a return to an open annotation
- About: version, website, and Sparkle automatic checks, automatic downloads, and manual update check
