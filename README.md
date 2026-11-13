# EinkRefresh

A hotkey that clears ghosting on an e-ink monitor by driving every pixel to its
far extreme and back. Built for the Bigme B251.

A small macOS menu bar agent. No dependencies: a single Swift file built with
the system `swiftc`.

- **F13** by default; **Change hotkey…** in the menu records any key or combination
- Light pixels go black then white, dark pixels go white then black, per
  colour channel, so nothing is repainted needlessly
- **Duration** submenu: 0.10 to 0.30 s per phase in 0.05 s steps
- Flashes only the e-ink display, and every screen if it is not connected
- **Launch at login** toggle in the menu
- Needs no Accessibility permission

## Why this is not the monitor's own refresh

The B251 has a hardware refresh button, and the obvious goal was to trigger the
same thing from the Mac. The firmware does not allow it.

The monitor shows up as a USB serial device (`MEGAHUNT VCPHID`,
`/dev/cu.usbmodem*`). The vendor tool talks to it with packets of the form
`A0 B0 <cmd> <len> <data…> <xor>`, where the checksum is the XOR of `cmd`,
`len` and the data bytes.

Inside the monitor the button is handled by the controller, which sends
`C0 E0 01 05 04` straight to the FPGA that drives the panel. Checked on
controller firmware M1.1.1 with scaler firmware M1.3:

| Path from the host | Result |
|---|---|
| USB `A2` (set mode) | forwarded to the scaler, which accepts only modes 0-3; switching modes does not redraw the panel |
| USB `A3` (colour settings) | changes settings only |
| Raw `C0 E0 01 05 04` over USB | echoed back, never reaches the FPGA |
| DDC/CI | the scaler has no code path that sends the refresh packet |

So this app is a software substitute: it drives every pixel through both
extremes. The button runs the panel's own clearing cycle, so the result is
close but not identical.

Commands that do work, for reference:

```sh
printf '\xa0\xb0\xa2\x02\x00\xa0' > /dev/cu.usbmodem*   # Web mode
printf '\xa0\xb0\xa2\x02\x01\xa1' > /dev/cu.usbmodem*   # Text mode
printf '\xa0\xb0\xa2\x02\x02\xa2' > /dev/cu.usbmodem*   # Image mode
printf '\xa0\xb0\xa2\x02\x03\xa3' > /dev/cu.usbmodem*   # Video mode
```

## Requirements

- macOS 13+ (tested on macOS 26)
- Xcode command line tools: `xcode-select --install`

## Install

```sh
git clone https://github.com/evtaranov/EinkRefresh.git
cd EinkRefresh
./build.sh
open -a ~/Applications/EinkRefresh.app
```

## Configuration

The hotkey and the flash duration are set from the menu and take effect
immediately. Everything below applies without rebuilding; restart the agent
afterwards.

```sh
# Seconds each phase stays on screen, for a value the menu does not offer
defaults write io.github.einkrefresh holdSeconds -float 0.15

# Name of the display to flash, as shown in System Settings → Displays
defaults write io.github.einkrefresh displayName "DS-DP"
```

The lower bound for `holdSeconds` is set by the refresh rate macOS drives the
monitor at: at 25 Hz a frame lasts 40 ms, so 0.08 is two frames per phase.

## How it works

| File | Purpose |
|---|---|
| `main.swift` | the whole agent |
| `build.sh` | builds the `.app` into `~/Applications` |
| `Info.plist` | `LSUIElement` -- an agent with no Dock icon |

Inside `main.swift`:

- **Hotkey** -- Carbon `RegisterEventHotKey`, which is why no Accessibility
  grant is needed. The chosen key is stored in user defaults.
- **Flash** -- two display gamma tables set with
  `CGSetDisplayTransferByTable`. The first maps every channel value to its far
  extreme (below half to full, above half to zero), the second to its near
  extreme; then `CGDisplayRestoreColorSyncSettings` brings the picture back.
  It needs no screenshot and no Screen Recording permission, and it acts on
  live content. A single inverted frame was tried first and cleared white
  areas worse than two phases.
- **Launch at login** -- `SMAppService.mainApp`.

## Known limitations

- **Not a hardware refresh.** Heavy ghosting may need the real button.
- **The flash resets display gamma.** Apps that keep their own gamma
  table (software brightness or colour adjustments) may need to reapply it
  after a flash.
- **A hotkey taken by another app cannot be registered.** The previous one is
  kept in that case.
