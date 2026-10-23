<p align="center"><img src="docs/icon.png" width="128" alt="DisplayToggle icon"></p>

<h1 align="center">DisplayToggle</h1>

<p align="center">
A tiny, free macOS menu bar app that <b>soft-disconnects</b> any display — no cable unplugging — and switches resolutions.
</p>

<p align="center"><b>English</b> · <a href="README.zh-CN.md">简体中文</a></p>

---

## Features

- **Disconnect / reconnect any display** from the menu bar. macOS treats a disconnected display as if its cable were unplugged: windows move to the remaining screens and the GPU stops driving it. Works for external monitors and the MacBook built-in display.
- **Resolution & refresh rate** — lists every mode, including HiDPI and the system default.
- **Brightness & volume sliders** right in the menu. External monitors are controlled over DDC/CI (Apple silicon; the monitor must support DDC), the built-in display natively. Volume follows the current output device, using the monitor's own volume over DDC when audio goes through HDMI/DisplayPort.
- **Reset** — each disconnected display has a ↻ button that re-checks it: reconnect it if it's still plugged in; if it was unplugged, drop it from the menu until it's plugged back in.
- **Reset Connections** (⌘R) — reset every display at once: reconnect everything that was disconnected and forget displays that were physically unplugged. Resolutions are left alone.
- **Safety net** — you can't disconnect the last display, and if all screens ever go dark (e.g. built-in disconnected, then the external cable is pulled) everything is reconnected automatically.
- **Session-only** — disconnections reset on logout/restart, so you can never lock yourself out with a black screen.
- **Launch at Login** toggle (native macOS Login Items). The checkmark always shows the real system state; if macOS needs your approval, the item says so and a notification takes you to System Settings.
- **English / 中文** UI, following the system language or chosen in the menu.
- **Command-line interface** for scripts, Shortcuts, and hotkeys.

## Requirements

macOS 13 Ventura or later, Apple Silicon or Intel.

## Install

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

## Command line

```bash
CLI=/Applications/DisplayToggle.app/Contents/MacOS/DisplayToggle

$CLI list                          # list displays with state and current mode
$CLI off Sceptre                   # disconnect (by index, display ID, or part of the name)
$CLI on 2                          # reconnect
$CLI toggle "LG"                   # toggle
$CLI reset LG                      # reset one display: reconnect if plugged in, else forget
$CLI reset                         # reset every display
$CLI modes Sceptre                 # list all resolutions / refresh rates
$CLI res Sceptre 2560x1440 hidpi 60
$CLI brightness LG 60               # brightness 0–100 (omit the value to read it)
$CLI volume 30                     # volume of the current output device
$CLI login on|off                  # launch at login
```

Tip: put `$CLI toggle <name>` in a Shortcuts "Run Shell Script" action to bind it to a hotkey.

## How it works

Disconnection uses the private CoreGraphics function `CGSConfigureDisplayEnabled`, applied with `kCGConfigureForSession`. Resolution changes use the public `CGConfigureDisplayWithDisplayMode`. Because the disconnect API is private, a future macOS update could break it.

## Uninstall

Turn off **Launch at Login** in the menu, quit, and delete `/Applications/DisplayToggle.app` (or run `make uninstall`).

## License

[PolyForm Noncommercial 1.0.0](LICENSE.md) — free for personal, educational, research, and other noncommercial use. **Commercial use is not permitted.**

Copyright © 2026 Yiheng Shu
