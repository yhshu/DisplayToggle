<p align="center"><img src="docs/icon.png" width="128" alt="DisplayToggle icon"></p>

<h1 align="center">DisplayToggle</h1>

<p align="center">
A tiny, free macOS menu bar app that <b>soft-disconnects</b> any display — no cable unplugging — and switches resolutions.<br>
一个免费的 macOS 菜单栏小工具：不用拔线，就能<b>断开 / 重新连接</b>任意显示器，并切换分辨率。
</p>

<p align="center"><a href="#english">English</a> · <a href="#中文">中文</a></p>

---

## English

### Features

- **Disconnect / reconnect any display** from the menu bar. macOS treats a disconnected display as if its cable were unplugged: windows move to the remaining screens and the GPU stops driving it. Works for external monitors and the MacBook built-in display.
- **Resolution & refresh rate** — lists every mode, including HiDPI and the system default.
- **Reset Connections** (⌘R) — reconnect everything that was disconnected and forget displays that were physically unplugged. Resolutions are left alone.
- **Safety net** — you can't disconnect the last display, and if all screens ever go dark (e.g. built-in disconnected, then the external cable is pulled) everything is reconnected automatically.
- **Session-only** — disconnections reset on logout/restart, so you can never lock yourself out with a black screen.
- **Launch at Login** toggle (native macOS Login Items). The checkmark always shows the real system state; if macOS needs your approval, the item says so and a notification takes you to System Settings.
- **English / 中文** UI, following the system language or chosen in the menu.
- **Command-line interface** for scripts, Shortcuts, and hotkeys.

### Requirements

macOS 13 Ventura or later, Apple Silicon or Intel.

### Install

**Download:** grab `DisplayToggle-x.y.z.zip` from [Releases](../../releases), unzip, and move `DisplayToggle.app` to `/Applications`.
The app is ad-hoc signed (not notarized), so on first launch right-click it → **Open**, or run:

```bash
xattr -dr com.apple.quarantine /Applications/DisplayToggle.app
```

**Build from source** (needs Xcode Command Line Tools):

```bash
git clone https://github.com/yhshu/DisplayToggle.git
cd DisplayToggle
make install
```

### Command line

```bash
CLI=/Applications/DisplayToggle.app/Contents/MacOS/DisplayToggle

$CLI list                          # list displays with state and current mode
$CLI off Sceptre                   # disconnect (by index, display ID, or part of the name)
$CLI on 2                          # reconnect
$CLI toggle "LG"                   # toggle
$CLI reset                         # reconnect all, forget unplugged displays
$CLI modes Sceptre                 # list all resolutions / refresh rates
$CLI res Sceptre 2560x1440 hidpi 60
$CLI login on|off                  # launch at login
```

Tip: put `$CLI toggle <name>` in a Shortcuts "Run Shell Script" action to bind it to a hotkey.

### How it works

Disconnection uses the private CoreGraphics function `CGSConfigureDisplayEnabled`, applied with `kCGConfigureForSession`. Resolution changes use the public `CGConfigureDisplayWithDisplayMode`. Because the disconnect API is private, a future macOS update could break it.

### Uninstall

Turn off **Launch at Login** in the menu, quit, and delete `/Applications/DisplayToggle.app` (or run `make uninstall`).

---

## 中文

### 功能

- **断开 / 重新连接任意显示器**：在菜单栏点一下即可。断开后 macOS 会把它当作拔掉了线——窗口自动移到其他屏幕，显卡也不再驱动它。外接显示器和 MacBook 自带屏幕都支持。
- **分辨率与刷新率**：列出全部模式，标注 HiDPI 和系统默认分辨率。
- **重置连接**（⌘R）：重新连接所有被断开的显示器，并移除已经拔线的显示器记录，不改动分辨率。
- **安全保护**：不允许断开最后一个显示器；如果所有屏幕都黑了（比如关了自带屏后又拔掉外接线），会自动全部重新连接。
- **仅本次登录有效**：注销或重启后所有显示器都会回来，不会被黑屏锁死。
- **登录时启动**开关（使用 macOS 原生登录项）。对勾始终反映系统的真实状态；如果需要你在系统设置中授权，菜单会注明，并通过系统通知引导你去设置。
- **中文 / English** 界面，默认跟随系统，也可在菜单里切换。
- **命令行**，方便写脚本、配合快捷指令或快捷键。

### 系统要求

macOS 13 Ventura 及以上，Apple Silicon 和 Intel 均可。

### 安装

**下载**：在 [Releases](../../releases) 下载 `DisplayToggle-x.y.z.zip`，解压后把 `DisplayToggle.app` 拖到「应用程序」。
App 使用 ad-hoc 签名、未经公证，首次打开请右键 →「打开」，或运行：

```bash
xattr -dr com.apple.quarantine /Applications/DisplayToggle.app
```

**从源码构建**（需要 Xcode Command Line Tools）：

```bash
git clone https://github.com/yhshu/DisplayToggle.git
cd DisplayToggle
make install
```

### 命令行

用法见上方英文部分的示例。`<display>` 可以是序号、显示器 ID 或名称的一部分。可以把 `toggle <名称>` 放进「快捷指令」的「运行 Shell 脚本」里，再绑定快捷键。

### 原理

断开功能调用 CoreGraphics 私有函数 `CGSConfigureDisplayEnabled`（以 `kCGConfigureForSession` 生效）；改分辨率使用公开的 `CGConfigureDisplayWithDisplayMode`。由于依赖私有接口，未来的 macOS 更新可能使其失效。

### 卸载

在菜单中关闭「登录时启动」，退出 App，删除 `/Applications/DisplayToggle.app`（或运行 `make uninstall`）。

---

## License / 许可证

[PolyForm Noncommercial 1.0.0](LICENSE.md) — free for personal, educational, research, and other noncommercial use. **Commercial use is not permitted.**
免费用于个人、教育、研究等非商业用途，**禁止商业使用**。

Copyright © 2026 Yiheng Shu
