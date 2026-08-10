<div align="center">
  <img src="docs/icon.png" width="128" alt="Statly">
  <h1>Statly</h1>
  <p><b>A lightweight system monitor for macOS</b></p>
  <p>
    <img src="https://img.shields.io/badge/macOS-13%2B-000000?logo=apple&logoColor=white" alt="macOS 13+">
    <img src="https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white" alt="Swift 5.9">
    <img src="https://img.shields.io/badge/Size-0.71%20MB-4c1" alt="Size 0.71 MB">
    <img src="https://img.shields.io/badge/Dependencies-0-4c1" alt="Zero dependencies">
    <img src="https://img.shields.io/badge/License-MIT-4c1" alt="MIT License">
  </p>
  <p><b>English</b> · <a href="README.zh-CN.md">简体中文</a></p>
</div>

Statly is a lightweight system monitor for macOS that lives in the menu bar, showing CPU, memory, temperature, network rate, and disk usage in real time. Click any icon to open a detail panel for that module.

Designed with resource usage as the primary constraint: menu bar content is drawn off-screen with AppKit, SwiftUI is used only for the on-demand detail panels and settings window; a single process, zero third-party dependencies, a 0.71 MB bundle, no background daemons, and no system permissions required.

![Menu bar and detail popover](docs/statusbar.jpg)

## Features

- **Modular** — Each of the five metrics is an independent menu bar icon, individually enabled/disabled, reorderable by ⌘-dragging, with position persisted.
- **Menu bar display** — Usage metrics shown as ring + percentage; network rate as up/down rows; values use a monospaced font with reserved width to avoid layout jitter.
- **Configurable styles** — Usage style (ring + percentage / plain text) and label style (icon / vertical / horizontal text / hidden) freely combined, with live preview in the settings window.
- **Dual temperature display** — The thermometer icon's mercury level changes across three tiers (<50°C / 50–80°C / ≥80°C); the ring fills by the reading, consistent with other modules.
- **Selectable temperature source** — Switch between CPU (hottest die sensor) and battery; automatically disabled on desktops without a battery sensor.
- **Detail panels** — Historical curves per module; CPU/memory list the top 5 processes, memory adds pressure state and breakdown, network adds local IP / gateway / DNS / public IP, disk adds a capacity bar and read/write rates.
- **Hover tooltips** — Hover an icon in ring mode for the exact value.
- **System integration** — Template images adapt to light/dark appearance; settings use system grouped cards and vibrancy; UI in Simplified Chinese.
- **Low overhead** — One shared timer wake per sample cycle; no redraw when results are unchanged; sampling pauses while locked/asleep; process lists are collected only while the panel is open.
- **No residue** — No Dock icon, no login-item daemon; uninstalling is just deleting the app and one config file.

## Installation

Download the DMG from [Releases](https://github.com/imliusx/statly/releases) and drag Statly into the Applications folder. Requires **macOS 13 or later**.

> Not currently notarized by Apple. On first launch, right-click the app → Open, or run `xattr -d com.apple.quarantine /Applications/Statly.app`.

Uninstall:

```sh
rm -rf /Applications/Statly.app
defaults delete com.statly.app
```

## Usage

| Action | Effect |
|--------|--------|
| Click an icon | Open that module's detail panel |
| Hover an icon | Tooltip with the exact value |
| Right-click any icon | Settings / About / Check for Updates / Quit |
| ⌘ + drag | Reorder icons |

| Module | Menu bar | Detail panel |
|--------|----------|--------------|
| CPU | Total usage | Usage curve, top 5 processes |
| Memory | Used ratio | Usage curve, App / Wired / Compressed breakdown, top 5 processes |
| Temperature | Hottest of selected source | Temperature curve, average and sensor count |
| Network | Live up/down rates | Rate curves, local IP / gateway / DNS, public IP and ISP |
| Disk | Used capacity ratio | Capacity bar, read/write rates |

## Settings

Organized by module, with live style preview. Sample interval of 1 / 2 / 5 seconds, default 2. Launch at login is built on `SMAppService`; the public IP lookup can be disabled in settings — no outbound requests at all once disabled.

![Settings window](docs/settings.jpg)

## Performance

Measured (Apple Silicon, all five modules, 2-second interval):

| Metric | Target | Measured |
|--------|--------|----------|
| Bundle size | < 10 MB | **0.71 MB** |
| Resident memory (RSS, panels closed) | < 35 MB | **32 MB** |
| Timer wakes per sample cycle | 1 | **1** (all modules combined) |
| Background processes / privileges / root | 0 | **0** |
| Average CPU usage | < 0.5% | **0.42%** |

Implementation constraints:

- **Combined wake** — All modules share a single `DispatchSourceTimer`.
- **Diff updates** — Skips the `NSStatusItem` call when output is unchanged from the previous cycle.
- **Pause while hidden** — Sampling stops while locked/asleep; baselines reset on resume to avoid rate spikes.
- **On-demand collection** — Process lists and network info are collected only while the panel is open.
- **Temperature throttling** — Fixed 5-second sampling of a small sensor subset (4 CPU / 2 battery); per-sample cost drops from 16.7 ms to 3.6 ms, within 0.01°C of the full read.

CPU usage breakdown (from sampling profiler and controlled benchmarks):

| Source | Share |
|--------|-------|
| Inherent AppKit cost of updating menu bar items | ~0.23% |
| Statly's own sampling and rendering | ~0.06% |
| Rest (timers, event loop, etc.) | ~0.13% |

The 0.23% is the measured floor of a minimal control program (just swapping two menu bar item images every 2 seconds still costs 0.21–0.25%), so 0.3% is unreachable at a 2-second interval. The original < 0.3% target was revised to < 0.5%; at a 5-second interval it's ~0.2%.

## Data sources

All data is gathered locally via public user-space APIs, no special privileges:

| Metric | API |
|--------|-----|
| CPU | `host_processor_info` (per-core tick deltas) |
| Memory | `host_statistics64`; pressure via `DISPATCH_SOURCE_TYPE_MEMORYPRESSURE` |
| Network rate | `getifaddrs` (per-interface deltas, 32-bit counter wraparound handled) |
| Network info | `SCDynamicStore`, `getifaddrs` |
| Disk | `URL.resourceValues`, IOKit `IOBlockStorageDriver` |
| Processes | libproc (`proc_listallpids` / `proc_pid_rusage`) |
| Temperature | `IOHIDEventSystemClient` (**private API**) |
| Public IP | `ipinfo.io` (**only outbound request**, can be disabled) |

macOS has no public API for temperature; symbols are resolved dynamically via `dlsym`, and the module degrades to "unavailable" on failure without affecting the others. Because of the private API, Statly is distributed directly and not on the App Store. Wi-Fi SSID has required location services authorization since 10.15, so it's not shown — Statly asks for no permissions. The public IP is queried once when the network panel opens, cached until the local IP/gateway changes, and can be turned off at any time.

## Building

Requires macOS 13+, Xcode 15+, and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`):

```sh
make run        # dev run (SPM, fastest iteration; launch-at-login unavailable in this mode)
make xcodeproj  # generate Statly.xcodeproj for debugging the full app in Xcode
make app        # Release build to dist/Statly.app
```

`project.yml` is the single source of truth for the Xcode project; the generated `.xcodeproj` is not committed.

```
Sources/StatlyKit/
├── App/        Entry point, AppCoordinator (orchestrates sampling, menu bar, panels, settings)
├── Core/       Timer scheduler, ring history buffer, monospaced formatting, settings model, update check
├── Samplers/   The five metric samplers and process list collection
└── UI/         NSStatusItem rendering, SwiftUI detail panels and settings window
```

## Releasing

```sh
scripts/release.sh 0.1.0             # build, sign, and produce a DMG in dist/
scripts/release.sh 0.1.0 --publish   # same, plus tag and GitHub Release
```

Signing strategy is picked automatically based on the local machine: Developer ID + notarytool credentials → signed, notarized, and stapled; Developer ID only → signed, skipping notarization; dev certificate or none → ad-hoc signed.

To configure notary credentials (requires a paid Apple Developer account):

```sh
xcrun notarytool store-credentials statly-notary \
    --apple-id <AppleID> --team-id <TeamID> --password <app-specific password>
```

## Roadmap

- ✅ Full pipeline for all five modules, process lists, update check, DMG release flow
- ⏳ Menu bar render caching, Developer ID signing and notarization
- 📋 Planned: fan speed, GPU, battery, threshold alerts, localization, Homebrew cask

## License

[MIT](LICENSE) © 2026 liusx
