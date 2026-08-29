<p align="center">
  <img src="docs/images/logo.svg" width="72" alt="logo">
</p>

<h1 align="center">AI Mac Mini Display</h1>

<p align="center">A tiny AI status computer for your desk — ESP8266 · Open Source Hardware · Desktop Companion</p>

<p align="center">
  <a href="README.md">中文</a> ·
  English
</p>

<p align="center">
  <a href="https://mac.qust.me">Website</a> ·
  <a href="https://mac.qust.me/#flash">Web Flasher</a> ·
  <a href="https://github.com/pengchujin/esp8266-ai/releases/latest">Download</a>
</p>

<p align="center">
  <img src="docs/images/hero.jpg" width="640" alt="AI Mac Mini Display">
</p>

A retro mini-TV with a 240×240 screen that sits on your desk showing **what Claude Code / Codex CLI are doing right now and how much quota you have left**. No API key needed: everything comes from the CLI credentials and session logs already on your machine, served to the device over your LAN by the companion Mac / Windows bridge app.

## Features

| | |
|---|---|
| <img src="docs/images/feature1.jpg" width="360" alt="AI status"> | **AI status & quota**<br>Pet is walking = the AI is working. A square progress ring plus large digits show your real 5-hour / weekly quota usage; when a window is used up the pet becomes a reset countdown, and the border flashes red when the AI is waiting for your approval. |
| <img src="docs/images/feature2.jpg" width="360" alt="Network monitor"> | **Live network monitor**<br>Task-manager-style upload/download curves, 56-second rolling window, auto-scaling axis. |
| <img src="docs/images/music.jpg" width="360" alt="Now playing"> | **Now playing**<br>Album art, title, artist and progress bar in real time; switches in automatically when music starts, back when it stops. |
| <img src="docs/images/feature3.jpg" width="360" alt="Swappable pets"> | **Swappable pets**<br>Built-in [petdex.dev](https://petdex.dev) gallery with 3300+ open-source pets, or upload any GIF — decoded on the board itself, no reflashing needed. |

The display also includes an **enhanced weather page** and a **daily quote page**. Weather covers current/feels-like/high/low temperature, humidity, wind, AQI, precipitation probability, and a three-day forecast. Quotes alternate between Chinese Hitokoto and English ZenQuotes, with the last successful result kept for offline use.

## Getting started

What you need: an "SD2 mini-TV" dev board ([open-source hardware](https://oshwhub.com/q21182889/sd2), or [buy one assembled](https://mobile.yangkeduo.com/goods.html?ps=OuBjGMWE82)) and a USB **data** cable.

### Step 1 · Flash the firmware (~30 s)

Open **[mac.qust.me/#flash](https://mac.qust.me/#flash)** in Chrome / Edge, plug the device in over USB, click "Connect & Flash", pick the serial port and wait. No tools to install.

> Serial port not showing up? On Windows install the [CH340 driver](https://www.wch.cn/downloads/CH341SER_EXE.html); macOS has it built in. Try another USB cable (many are charge-only). More troubleshooting in the [website FAQ](https://mac.qust.me/#flash-faq).
>
> Command-line folks can also flash `esp8266-ai-firmware-*.bin` from [Releases](https://github.com/pengchujin/esp8266-ai/releases/latest) to address `0x0` with esptool.

### Step 2 · Connect WiFi

On first boot the device opens a hotspot named **`AI-Clock-Setup`**: join it from your phone and the setup page pops up (or browse to `192.168.4.1`), pick your WiFi and enter the password. Done.

### Step 3 · Install the bridge app

Download from [Releases](https://github.com/pengchujin/esp8266-ai/releases/latest) and open:

- **macOS**: `AIClockBridge-*-macOS.dmg`, drag into Applications (ad-hoc signed; on first launch allow it in "System Settings → Privacy & Security" and grant local-network access)
- **Windows**: `AIClockBridge-*-Windows-x64.exe`, just double-click

The bridge lives in your menu bar / tray and **auto-discovers and pairs** with the device on the same LAN — at this point the screen comes alive.

<p align="center">
  <img src="docs/images/working.jpg" width="640" alt="In action">
</p>

Daily use is all on the tray icon: **left-click** opens a live mirror of the device screen (with a brightness slider at the bottom), **right-click** opens the full menu (quota details, screen switching, weather city, pet swapping, music/network pages, and more).

### Automatic display and quotes

On macOS, right-click the menu bar icon and choose **“自动显示设置…” (Automatic Display Settings)**. **Event-triggered** items appear immediately while an event is active; **scheduled** items become due at their configured interval and stay up for the configured duration. The shipped defaults are:

| Type | Item | Enabled | Interval | Duration |
|---|---|---:|---:|---:|
| Event | Claude working | No | — | While active |
| Event | Codex working | Yes | — | While active |
| Event | Approval required | Yes | — | While active |
| Event | Music playing | Yes | — | While playing |
| Scheduled | Weather | Yes | 15 min | 10 s |
| Scheduled | Daily quote | Yes | 30 min | 12 s |
| Scheduled | Stocks | No | 15 min | 10 s |
| Scheduled | Network speed | No | 10 min | 10 s |

Scheduled intervals accept 1–240 minutes and durations accept 5–60 seconds. AUTO priority is **approval required > active Claude/Codex agents > music > due scheduled content > idle pet**. When both Claude and Codex are working and enabled, the display alternates between them every 2 seconds. If several scheduled items are due, the least recently shown one wins. An event interrupts scheduled content; when the event ends, that content resumes with a fresh full duration.

Disabling an item affects **AUTO mode only**. You can still choose any page manually from the Display menu or mirror controls. Choose **Display → 名人名言 (Daily Quote)** to keep the quote page fixed; **换一句 (Next Quote)** requests a new quote immediately and refreshes the device when quote mode is already fixed.

The Mac bridge alternates between Chinese quotes from Hitokoto and English quotes from ZenQuotes. Neither source needs an API key. It refreshes about every 30 minutes, avoids recent duplicates, and persists the latest Chinese quote, latest English quote, and 20-item recent history (migrating the former single-snapshot cache automatically). When the network is unavailable the cache remains visible; after 30 minutes it is marked stale. Quotes require both the current Mac bridge and ESP8266 firmware. Automatic-display settings are always saved on the Mac first; if a reachable device runs firmware older than v0.4.13, the app warns that an upgrade is required instead of implying that the local save synced to the device.

### Weather

Choose **Display → Weather** for a fixed weather page, or **Set weather city…** to search for a city (Chengdu is the default). The bridge refreshes weather about every 10 minutes and keeps its last successful cache through temporary network failures. Weather is enabled in AUTO mode by default as shown above.

### Updating from source (macOS)

Quit any installed AIClockBridge from the menu bar first so it does not keep port 8765 occupied, then update and launch the bridge:

```bash
git switch main
git pull --ff-only origin main
cd mac-app
swift run
```

Or build and run the optimized binary:

```bash
cd mac-app
swift build -c release
.build/release/AIClockBridge
```

Connect the ESP8266 with a USB data cable, list the available serial ports, then build and flash:

```bash
cd firmware
pio device list
pio run -t upload
```

If the project default `/dev/cu.usbserial-130` does not match your device, add `--upload-port /dev/cu.usbserial-your-port`. After flashing, the board reboots automatically; use its `AI-Clock-Setup` hotspot if WiFi still needs configuration.

## FAQ

- **Screen border flashing red**: the device can't reach the bridge — make sure the app is running and on the same WiFi.
- **Quota shows `-` forever**: no Claude Code / Codex CLI login on this machine, so the bridge has no credentials to read.
- **Want a different pet**: right-click the tray icon → "Change pet animation…", pick one and upload.

## Development

```
firmware/     ESP8266 firmware (PlatformIO + Arduino, with on-board GIF decoding)
mac-app/      macOS menu bar bridge (Swift/SPM, zero third-party dependencies)
windows-app/  Windows tray bridge (C# / .NET 8 WinForms)
tools/        GIF → RGB565 built-in sprite conversion script
docs/         Developer docs (pinout, HTTP API, architecture details)
```

```bash
cd firmware && pio run -t upload   # firmware: build + flash over USB
cd mac-app && swift run            # Mac bridge: run locally
```

Hardware pinout, display-driver gotchas, the device HTTP API and the on-board GIF decoding architecture are documented in **[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)** (Chinese).

Hardware, firmware and software are all open source — modify it, build it, even sell it.
