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

## Engines

### tpws
Lightweight TCP-only transparent proxy. Best for simple web browsing and standard HTTPS bypass.
- **Protocol:** TCP Only
- **Mode:** Transparent Proxy

### ciadpi (ByeDPI)
Advanced SOCKS5 proxy with **UDP support**.
- **Protocol:** TCP + UDP
- **Mode:** System SOCKS5 Proxy (Auto-configured)
- **Features:** Fake packets, UDP traversal

## Strategies

### tpws Strategies
| Strategy | Description |
|----------|-------------|
| **Split+Disorder** | Splits TCP packet at position 1 and middle of domain name (midsld). Sends second fragment before first using `--disorder` flag. DPI expects ordered packets and fails to reassemble the hostname. |
| **TLSRec+Split** | Creates two TLS records by splitting at SNI extension boundary (`--tlsrec=sniext`). Combined with TCP split at midsld position and disorder. DPI sees incomplete TLS handshake in first record. |
| **TLSRec MidSLD** | Splits TLS record right in the middle of second-level domain (`--tlsrec=midsld`). Example: `disco` + `rd.com`. DPI cannot match partial domain against blocklist. |
| **TLSRec+OOB** | All of the above plus `--hostdot` which adds a dot after hostname in HTTP Host header. Additional confusion layer for HTTP-level DPI inspection. |

### ciadpi Strategies
| Strategy | Description |
|----------|-------------|
| **Disorder (Simple)** | Splits TCP stream at the first byte (`-d 1`). Sends the first byte *after* the rest of the packet. Extremely effective against most DPI systems. |
| **Disorder (SNI)** | Splits at the SNI (Server Name Indication) position. More precise but slightly more complex than simple disorder. |
| **Fake (OOB)** | Injects Out-of-Band (OOB) data. Effective strategy that confuses DPI inspection logic without relying on TTL tricks. |
| **Auto (Torst)** | Automatically detects the block type using `torst` method and applies the best bypass technique. |

## How it Works

The app uses `tpws` (transparent proxy) or `ciadpi` (SOCKS5 proxy) to modify outgoing traffic, bypassing DPI (Deep Packet Inspection) filters. TCP traffic is redirected through macOS PF firewall rules, while UDP traffic is routed via system SOCKS settings (when using ciadpi).

## Build from Source

```bash
git clone https://github.com/RoninReilly/darkware-zapret.git
cd darkware-zapret
# Compile TPWS binary
cd zapret_src/tpws && make mac && cd ../..
# Build App
./create_app.sh
```

> **Note:** Building requires macOS 15+ and Xcode 16+ (Swift 6). The pre-built binary from [Releases](https://github.com/RoninReilly/darkware-zapret/releases) works on macOS 13+.

## Credits

- Powered by [zapret](https://github.com/bol-van/zapret) by bol-van
- Powered by [byedpi](https://github.com/hufrea/byedpi) by hufrea (ciadpi engine)
- Hostlist from [Re-filter](https://github.com/1andrevich/Re-filter-lists)

## Support

Development requires an Apple Developer Program membership ($99/year) to sign and notarize the app, protecting it from "damaged" errors and Gatekeeper blocks.

If you'd like to help fund the certificate:

- **Solana (SOL):** `2CP3BLyPSjiKYcr6j17UJ35FmmBdvVWkWwESqaeuqMCu`
- **ETH / Polygon:** `0x8aa4a9784995C8f558A46CdB604C7440d0506044`

## License

MIT License
