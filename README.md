# Darkware Zapret for macOS

[![Release](https://img.shields.io/github/v/release/RoninReilly/darkware-zapret?style=flat&color=green)](https://github.com/RoninReilly/darkware-zapret/releases/latest)
[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-black?style=flat)](https://github.com/RoninReilly/darkware-zapret)
[![License](https://img.shields.io/github/license/RoninReilly/darkware-zapret?style=flat&color=blue)](LICENSE)
[![Stars](https://img.shields.io/github/stars/RoninReilly/darkware-zapret?style=flat&color=yellow)](https://github.com/RoninReilly/darkware-zapret/stargazers)

**[На русском](README.ru.md)**

**Darkware Zapret** is a native macOS menu bar app that wraps the [zapret](https://github.com/bol-van/zapret) DPI bypass tool into a simple one-click solution.

![Darkware Zapret UI](assets/preview.png)

## Features

- **Native macOS UI** — Clean SwiftUI interface in your menu bar
- **One-Click Toggle** — Instantly enable/disable DPI bypass
- **Multiple Strategies** — Switch between bypass methods for different services
- **Auto-Start** — Launches automatically on system startup
- **Auto-Hostlist** — Automatically detects and adds blocked domains

## Installation

1. Download [`DarkwareZapret_Installer.dmg`](https://github.com/RoninReilly/darkware-zapret/releases/latest) from Releases
2. Open DMG, drag app to **Applications**
3. Launch the app
4. Click **Install Service** (requires admin password once)
5. Toggle switch to **ON**

> **Note:** If you see "App is damaged" error, run in Terminal:
> ```bash
> xattr -cr /Applications/"darkware zapret.app"
> ```

## Strategies

| Strategy | Description | Best for |
|----------|-------------|----------|
| **Split+Disorder** | TCP splitting with packet reordering | YouTube, most sites |
| **TLSRec+Split** | TLS record + TCP splitting | Discord, Telegram |
| **TLSRec MidSLD** | TLS record split at domain boundary | Some ISPs |
| **TLSRec+OOB** | TLS record + OOB byte injection | Last resort |

## How it Works

The app uses `tpws` transparent proxy to modify outgoing TCP traffic, bypassing DPI (Deep Packet Inspection) filters. Traffic is redirected through macOS PF firewall rules.

## Build from Source

```bash
git clone https://github.com/RoninReilly/darkware-zapret.git
cd darkware-zapret
./create_app.sh
```

> **Note:** Building requires macOS 15+ and Xcode 16+ (Swift 6). The pre-built binary from [Releases](https://github.com/RoninReilly/darkware-zapret/releases) works on macOS 13+.

## Credits

- Powered by [zapret](https://github.com/bol-van/zapret) by bol-van
- Hostlist from [Re-filter](https://github.com/1andrevich/Re-filter-lists)

## License

MIT License
