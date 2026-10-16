# Darkware Zapret for macOS

[![Release](https://img.shields.io/github/v/release/RoninReilly/darkware-zapret?style=flat&color=green)](https://github.com/RoninReilly/darkware-zapret/releases/latest)
[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-black?style=flat)](https://github.com/RoninReilly/darkware-zapret)
[![License](https://img.shields.io/github/license/RoninReilly/darkware-zapret?style=flat&color=blue)](LICENSE)

**[На русском](README.ru.md)**

Native macOS menu bar app for DPI bypass, with an experimental packet engine and two local SOCKS engines. The 2.0 beta adds a packet path based on [Flowseal's Mac fork](https://github.com/Flowseal/zapret-mac-discord-youtube), safer process control, recoverable proxy settings and HTTPS diagnostics.

**Darkware 2.0 is the app version.** It does not bundle zapret2: [upstream zapret2](https://github.com/bol-van/zapret2) does not support macOS. Version **2.0.0-beta.1 is a prerelease**; the latest stable release remains 1.0.39.

## Choose a mode

| Engine | Requirements | Traffic and limits |
| --- | --- | --- |
| Native Packet · experimental | macOS 14+, administrator access | `nfqws` through `utun`/BPF, 21 Flowseal profiles, IPv4 TCP/UDP packet processing. May conflict with tunnel VPNs. Effectiveness, QUIC and Discord voice need testing on your network. |
| zapret · tpws | macOS 13+ | Local SOCKS5 for TCP. The proxy process runs without root. |
| ByeDPI | macOS 13+ | Local SOCKS5 with TCP strategies. No automatic capture of application UDP/voice. |

Universal binaries include Apple Silicon and Intel. SOCKS works for applications that use it. Enabling the system SOCKS setting does **not** route every application's traffic or all UDP through the proxy. DPI bypass does not supply an external VPN server and does not solve every DNS or IP block.

## Install and connect

1. Download the beta DMG from [2.0.0-beta.1](https://github.com/RoninReilly/darkware-zapret/releases/tag/v2.0.0-beta.1), open it and drag **darkware zapret.app** to **Applications**. Use [latest stable](https://github.com/RoninReilly/darkware-zapret/releases/latest) if you do not want the beta.
2. Open the app and click its shield in the menu bar. If macOS blocks an unsigned build, use **System Settings → Privacy & Security → Open Anyway** after checking the download source.
3. For an existing 1.x installation, choose **Migrate service…** and approve the macOS administrator prompt. This retires the old service and sudo permissions; saved custom strategies are kept.
4. Select an engine and strategy, then **Connect**. For SOCKS, configure `127.0.0.1:1080` in your application, or explicitly enable **System SOCKS proxy**. Changing system settings may require macOS authorization. For Native Packet, disconnect tunnel VPNs first and approve administrator access.
5. Use **Disconnect** before changing the engine or strategy. **Quit** also stops Darkware and restores its proxy settings; restoration errors keep the app open with a recovery action.

System SOCKS changes are journalled and restored on disconnect; recovery also runs at the next launch after an app crash. If another program changes proxy settings meanwhile, Darkware preserves those changes. The old 1.x app did not save the original proxy settings, so verify them before the first 2.0 connection.

## Profiles and diagnostics

- **Diagnose** compares direct HTTPS with two requests through each local SOCKS preset. It does not change system settings. A successful result validates that domain over HTTPS, rather than video playback, QUIC, packet mode or Discord voice. Select the suggested preset explicitly to use it.
- **Custom strategies** accepts quoted arguments for tpws/ByeDPI as an argument array; shell expressions are not executed. The app manages listener, process and file options.
- In packet mode, use **Open domain lists** to edit user lists under `~/Library/Application Support/DarkwareZapret/lists`; reconnect to apply changes. IPSet choices are domains only, the bundled IP list or all IPv4.
- **Activity log**, report copying and **Launch at login** are available from the menu. Login launch opens the app; it does not automatically connect.

If connectivity fails, disconnect and use **Restore network** if shown. If the app is force-killed while system SOCKS is enabled, reopen it to recover the saved settings. Include macOS version, engine, strategy and the copied diagnostic report in an [issue](https://github.com/RoninReilly/darkware-zapret/issues). Redact private domains and addresses before sharing.

## Build from source

Requires macOS, Xcode Command Line Tools and Swift 6. The source tree contains pinned engine sources; engine builds do not fetch mutable upstream branches.

```bash
git clone https://github.com/RoninReilly/darkware-zapret.git
cd darkware-zapret
git checkout v2.0.0-beta.1
./scripts/build-engines.sh
./scripts/check-engine-presets.sh
./scripts/test-native.sh
./scripts/check-runtime.sh
./scripts/check-runtime-engines.sh
swift test
./create_app.sh v2.0.0-beta.1
```

Full `swift test` requires the Swift Testing modules supplied by Xcode. On a CLT-only installation, the two runtime check scripts above run the standalone regression and engine suites.


Release notes: [CHANGELOG.md](CHANGELOG.md).

## Credits and license

- [bol-van / zapret](https://github.com/bol-van/zapret): original zapret and tpws.
- [Flowseal / zapret-mac-discord-youtube](https://github.com/Flowseal/zapret-mac-discord-youtube): macOS packet port and profiles.
- [hufrea / ByeDPI](https://github.com/hufrea/byedpi): ciadpi.
- [Re-filter](https://github.com/1andrevich/Re-filter-lists): hostlist source used by earlier versions.

Darkware is an independent app. Source and bundled upstream notices are distributed under their respective licenses; Darkware itself uses the [MIT License](LICENSE).

## Support development

Donations help fund development and an Apple Developer membership for signing and notarization.

- **Solana (SOL):** `2CP3BLyPSjiKYcr6j17UJ35FmmBdvVWkWwESqaeuqMCu`
- **ETH / Polygon:** `0x8aa4a9784995C8f558A46CdB604C7440d0506044`
