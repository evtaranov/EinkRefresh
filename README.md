# eink-refresh

A macOS menu bar app that clears ghosting on an e-ink monitor (built for the Bigme B251) by flashing the screen black, then white.

- Press **F13** or choose **Refresh screen** from the menu bar icon.
- Flashes only the display named `DS-DP`; if it is not connected, flashes every screen.
- **Launch at login** toggle in the menu.
- Needs no Accessibility permission.

## Build

Requires macOS 13+ and the Swift compiler (Xcode Command Line Tools).

```bash
./build.sh
open ~/Applications/EinkRefresh.app
```

## Settings

Edit the constants at the top of `main.swift`, then rebuild:

- `holdSeconds` — time per colour (default `0.15`)
- `einkDisplayName` — display to flash (default `DS-DP`)
- `kVK_F13` in `registerHotKey` — the hotkey

## Why not the monitor's own refresh button

The B251 firmware (controller M1.1.1, scaler M1.3) has no host command for a full refresh: its USB protocol only accepts mode and colour settings, so this app is a software substitute.
