# CrossX — Xteink iOS App Manager

<p align="center">
  <strong>Convert web pages to EPUB. Send them to your e-reader. All over WiFi.</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-iOS_26%2B_|_macOS_26%2B-blue?style=for-the-badge&logo=apple" alt="Platform">
  <img src="https://img.shields.io/badge/Swift-5-orange?style=for-the-badge&logo=swift&logoColor=white" alt="Swift 5">
  <img src="https://img.shields.io/badge/SwiftUI-Liquid_Glass-007AFF?style=for-the-badge" alt="SwiftUI">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-green.svg?style=for-the-badge" alt="MIT License"></a>
</p>

**CrossX** is a native SwiftUI app for **iOS, iPadOS, and macOS** that converts any web page into an EPUB 2.0 e-book and transfers it to an [Xteink device](https://www.xteink.com/) e-reader over its local WiFi hotspot. No cloud services, no accounts, no subscriptions — just paste a URL, tap convert, and read.

The app supports both **Stock** and **CrossPoint** firmware variants with automatic device detection, includes a full on-device **file manager**, and ships with an **iOS Share Extension** so you can send pages directly from Safari.

[Features](#features) · [How It Works](#how-it-works) · [Getting Started](#getting-started) · [Device Setup](#device-setup) · [Architecture](#architecture) · [Roadmap](#roadmap)

---

## Features

### EPUB Conversion

- **URL-to-EPUB pipeline** — paste any web page URL and get a properly formatted EPUB 2.0 e-book
- **Dual content extraction** — fast SwiftSoup heuristic extraction with automatic Readability.js fallback for complex pages
- **Twitter/X support** — dedicated extractor using the fxtwitter API for tweet threads
- **Auto chapter splitting** — long articles are split at `<h2>` headings or by paragraph count (50 max per chapter)
- **HTML sanitization** — strips scripts, forms, media, styles, and images for clean text-only EPUBs
- **In-memory generation** — no temp files; the entire EPUB is built as a `Data` object via ZIPFoundation
- **Smart filenames** — generated as `Title - Author - domain - YYYY-MM-DD.epub`

### Device Communication

- **Dual firmware support** — works with both Stock firmware (`192.168.3.3`) and CrossPoint firmware (`192.168.4.1` / `crosspoint.local`)
- **Auto-detection** — probes both firmware endpoints concurrently on connect and caches the result
- **mDNS/Bonjour** — CrossPoint firmware is discovered via `crosspoint.local` with static IP fallback
- **Retry logic** — 2 automatic retries with 1-second delay on transient failures
- **Upload progress** — real-time progress tracking via `URLSessionUploadTask` delegate
- **Connection status** — persistent status bar showing firmware version, IP, WiFi mode, signal strength, free heap, and uptime

### File Manager

- **Browse device storage** — navigate directories with breadcrumb trail
- **Upload files** — supports `.epub`, `.xtc`, `.bump`, and `.txt` formats
- **Create folders** — with filesystem-safe name validation
- **Delete files and folders** — with confirmation dialogs
- **Move files** — directory picker for reorganizing content (CrossPoint firmware only)
- **Rename files** — edit filename stem while preserving extension (CrossPoint firmware only, coming soon)

### Activity History

- **Unified timeline** — merges EPUB conversion history and file manager operations into a single chronological view
- **Filtering** — switch between All, Conversions, File Activity, and Queue
- **Search** — full-text search across all activity events
- **Granular clear** — clear conversions only, file activity only, or everything
- **Expandable detail rows** — tap to see full URLs, error messages, and metadata

### Share Extension (iOS)

- **Send from Safari** — use the iOS Share Sheet to convert any web page without opening CrossX
- **Auto-detect device** — the extension finds your X4 automatically
- **Fallback to local save** — if the device isn't connected, the EPUB is saved locally
- **Full pipeline** — runs the complete fetch → extract → build → send flow in the extension

### EPUB Send Queue

- **Offline queuing** — EPUBs converted while the device is disconnected are saved to disk and queued for later sending
- **Auto-prompt on connect** — when the device connects, an alert offers to send all queued items at once
- **Queue management** — view queued items in the Convert tab, remove individual items, or clear the entire queue from Settings
- **Persistent storage** — queued EPUBs survive app restarts; stored in Application Support with SwiftData tracking
- **Batch sending** — sends queued items sequentially with progress indicator, logs results to activity history

### Siri Shortcuts

- **Convert from Shortcuts** — use the "Convert to EPUB & Add to Queue" action in the Shortcuts app
- **Share Sheet integration** — create a Shortcut with "Show in Share Sheet" to convert pages directly from Safari
- **Background execution** — conversions run without opening the app; results are queued automatically
- **Siri voice support** — say "Convert a page with CrossX" to convert by voice
- **Rich feedback** — shows article title, file size, and queue count on completion
- **Setup guide** — in-app guide in Settings walks you through enabling the Share Sheet shortcut

### Cross-Platform

- **Native multiplatform** — single codebase builds natively for iOS, iPadOS, and macOS (not Mac Catalyst)
- **Platform-adaptive UI** — tab bar bottom accessory on iOS, Xcode-style status bar on macOS
- **Liquid Glass design** — leverages iOS 26 / macOS 26 `.glassEffect()` modifiers
- **Cross-platform clipboard** — unified helper abstracts `UIPasteboard` (iOS) and `NSPasteboard` (macOS)

---

## How It Works

```
┌──────────────────────────────────────────────────────────┐
│                      CrossX App                          │
│                                                          │
│  URL ──► Fetch HTML ──► Extract Content ──► Sanitize     │
│              │               │                  │        │
│              │          SwiftSoup (fast)         │        │
│              │              or                   │        │
│              │       Readability.js (fallback)   │        │
│              │              or                   │        │
│              │       Twitter API (tweets)        │        │
│              │                                   ▼        │
│              │                             Build EPUB     │
│              │                          (in-memory ZIP)   │
│              │                                │           │
│              │                     ┌──────────┴─────────┐│
│              │                     │                    ││
│              ▼               Device connected?          ││
│         URLSession                 │                    ││
│                              ┌─────┴─────┐              ││
│                              Yes         No             ││
│                              │           │              ││
│                        multipart    Queue to disk       ││
│                          POST       (send later)        ││
└──────────────────────────┬───────────────┬──────────────┘│
                           │               │
                    WiFi Hotspot     App Support/
                           │         EPUBQueue/
                           ▼
                 ┌─────────────────────────┐
                 │       Xteink X4         │
                 │       E-Reader          │
                 │                         │
                 │  Stock:     192.168.3.3  │
                 │  CrossPoint: 192.168.4.1 │
                 │             (or mDNS)    │
                 └─────────────────────────┘
```

---

## Requirements

| Requirement | Version |
|------------|---------|
| **Xcode** | 26.0+ (beta) |
| **iOS / iPadOS** | 26.0+ |
| **macOS** | 26.0+ |
| **Swift** | 5 |

> **Note**: This app targets the latest Apple platform SDKs. You need Xcode 26 beta or later to build.

---

## Getting Started

### 1. Clone the repository

```bash
git clone https://github.com/jtvargas/crosspoint-app.git
cd crosspoint-app
```

### 2. Open in Xcode

```bash
open SendToX4.xcodeproj
```

Xcode will automatically resolve Swift Package Manager dependencies (ZIPFoundation and SwiftSoup).

### 3. Build and run

**iOS Simulator:**

```bash
xcodebuild -project SendToX4.xcodeproj \
  -scheme SendToX4 \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build
```

**macOS:**

```bash
xcodebuild -project SendToX4.xcodeproj \
  -scheme SendToX4 \
  -destination 'platform=macOS' \
  build
```

Or simply select your target device in Xcode and press **Cmd+R**.

### 4. Connect to your device

See [Device Setup](#device-setup) below.

---

## Device Setup

The Xteink X4 e-reader creates its own WiFi hotspot. CrossX communicates with it over plain HTTP on the local network.

### Step 1: Connect to the X4 WiFi

1. Power on your Xteink X4
2. On your iPhone/iPad/Mac, go to **Settings → WiFi**
3. Connect to the X4's WiFi network (the SSID varies by firmware)

### Step 2: Open CrossX

The app will automatically detect which firmware your device is running:

| Firmware | IP Address | mDNS | Endpoints |
|----------|-----------|------|-----------|
| **Stock** | `192.168.3.3` | — | `/list`, `/edit` |
| **CrossPoint** | `192.168.4.1` | `crosspoint.local` | `/api/files`, `/upload`, `/mkdir`, `/delete` |

### Step 3: Configure (optional)

Open **Settings** (gear icon) to:

- Choose your firmware type manually (or leave on auto-detect)
- Set a custom IP address
- Configure destination folders for conversions and wallpapers
- Toggle optional features (File Manager, WallpaperX)

> **Network note**: The app requires the `NSAllowsLocalNetworking` ATS exception and `com.apple.security.network.client` entitlement for plain HTTP communication with the device. These are already configured in the project.

---

## Architecture

CrossX follows **MVVM** (Model-View-ViewModel) with protocol-oriented services:

```
Views → ViewModels → Services
  │                      │
  │                      ├─ DeviceService (protocol)
  │                      │    ├─ StockFirmwareService
  │                      │    └─ CrossPointFirmwareService
  │                      │
  │                      ├─ ContentExtractor (SwiftSoup)
  │                      ├─ ReadabilityExtractor (WKWebView)
  │                      ├─ TwitterExtractor (fxtwitter API)
  │                      ├─ EPUBBuilder (ZIPFoundation)
  │                      └─ WebPageFetcher (URLSession)
  │
  └─ SwiftData Models
       ├─ Article (conversion history)
       ├─ DeviceSettings (configuration)
       ├─ ActivityEvent (file operations log)
       └─ QueueItem (EPUB send queue)
```

### Key design decisions

- **Protocol-oriented device communication** — `DeviceService` protocol with concrete implementations per firmware, enabling easy mocking and future firmware support
- **Dual content extraction** — SwiftSoup for speed (primary), WKWebView + Readability.js for accuracy (fallback), Twitter API for tweets
- **In-memory EPUB generation** — no temporary files; all ZIP operations produce `Data` objects directly
- **Offline queue** — EPUBs are written to disk and tracked via SwiftData when the device is disconnected; batch-sent when it reconnects
- **Headless Siri Shortcuts** — `ConvertURLIntent` runs the full conversion pipeline without opening the app, using its own `ModelContext` against the shared SwiftData store
- **`@MainActor` by default** — the project uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`; services are explicitly marked `nonisolated` to avoid stack overflows
- **Native multiplatform** — `SDKROOT = auto` with `#if os(iOS)` / `#if canImport(UIKit)` conditional compilation (not Mac Catalyst)

---

## Project Structure

```
crosspoint-app/
├── SendToX4.xcodeproj/          # Xcode project (SPM dependencies, build settings)
├── Info.plist                   # ATS local networking exception
├── AGENTS.md                    # Developer reference (architecture, conventions, deep dives)
├── README.md                    # This file
├── LICENSE                      # MIT License
│
├── SendToX4/                    # Main app target
│   ├── SendToX4App.swift        # @main entry point, SwiftData ModelContainer setup
│   ├── SendToX4.entitlements    # App Sandbox + network client + Siri
│   │
│   ├── Models/
│   │   ├── Article.swift        # Conversion history model (URL, title, status, error)
│   │   ├── DeviceSettings.swift # Device config singleton (firmware type, IP, toggles)
│   │   ├── ActivityEvent.swift  # File operation log (upload, mkdir, move, delete, queue)
│   │   └── QueueItem.swift      # EPUB send queue model (file path, size, linked Article)
│   │
│   ├── Views/
│   │   ├── MainView.swift       # Root tab view (Convert, History, File Manager, WallpaperX)
│   │   ├── ConvertView.swift    # URL input, convert & send actions, share sheet
│   │   ├── HistoryView.swift    # Unified activity timeline with filtering and search
│   │   ├── FileManagerView.swift      # Device file browser with breadcrumbs
│   │   ├── FileManagerRow.swift       # File/folder row with context menu
│   │   ├── SettingsSheet.swift        # Device configuration form
│   │   ├── SettingsToolbarModifier.swift # Reusable gear button toolbar modifier
│   │   ├── DeviceStatusBar.swift      # Device info bar (version, IP, RSSI, uptime)
│   │   ├── DeviceConnectionAccessory.swift # iOS bottom tab accessory (connect status)
│   │   ├── MacDeviceStatusBar.swift   # macOS bottom status bar (Xcode-style)
│   │   ├── WallpaperXView.swift       # Placeholder for future wallpaper feature
│   │   ├── MoveFileSheet.swift        # Destination folder picker for move
│   │   ├── RenameFileSheet.swift      # File rename with extension lock
│   │   └── CreateFolderSheet.swift    # New folder name input with validation
│   │
│   ├── ViewModels/
│   │   ├── ConvertViewModel.swift     # URL → EPUB → device pipeline orchestrator
│   │   ├── DeviceViewModel.swift      # Connection state, auto-detection, upload progress
│   │   ├── FileManagerViewModel.swift # File browsing, CRUD operations, activity logging
│   │   ├── HistoryViewModel.swift     # Search, delete, granular clear for history
│   │   └── QueueViewModel.swift       # Queue management (enqueue, sendAll, remove, clear)
│   │
│   ├── Services/
│   │   ├── DeviceService.swift        # Protocol + models (DeviceFile, DeviceStatus, DeviceError)
│   │   ├── StockFirmwareService.swift # Stock firmware implementation (192.168.3.3)
│   │   ├── CrossPointFirmwareService.swift # CrossPoint implementation (192.168.4.1 / mDNS)
│   │   ├── DeviceDiscovery.swift      # Concurrent firmware auto-detection engine
│   │   ├── EPUBBuilder.swift          # In-memory EPUB 2.0 ZIP builder
│   │   ├── EPUBTemplates.swift        # EPUB XML templates (OPF, NCX, XHTML, CSS)
│   │   ├── ChapterSplitter.swift      # Long content → multi-chapter splitting
│   │   ├── ContentExtractor.swift     # SwiftSoup heuristic article extraction
│   │   ├── ReadabilityExtractor.swift # WKWebView + Readability.js fallback
│   │   ├── WebPageFetcher.swift       # URLSession HTML fetcher with encoding detection
│   │   └── TwitterExtractor.swift     # X/Twitter via fxtwitter API
│   │
│   ├── Intents/
│   │   ├── ConvertURLIntent.swift     # App Intent: URL → EPUB → queue (Siri/Shortcuts)
│   │   └── CrossXShortcuts.swift      # AppShortcutsProvider (Siri phrases)
│   │
│   ├── Utilities/
│   │   ├── HTMLSanitizer.swift        # Strip unsafe HTML for text-only EPUB
│   │   ├── StringExtensions.swift     # XML escaping, domain extraction, truncation
│   │   ├── FileNameGenerator.swift    # EPUB filename from metadata
│   │   ├── ClipboardHelper.swift      # Cross-platform clipboard (UIKit/AppKit)
│   │   ├── StorageCalculator.swift    # Storage size calculations (DB, cache, queue, temp)
│   │   ├── ReviewPromptManager.swift  # In-app review prompt after successful actions
│   │   └── DesignTokens.swift         # AppColor design system (accent, success, error, warning)
│   │
│   ├── Resources/
│   │   └── readability.js            # Mozilla Readability.js (bundled for WKWebView)
│   │
│   └── Assets.xcassets/              # App icon, AccentColor (teal light/dark)
│
└── SendToX4ShareExtension/           # iOS Share Extension target
    ├── Info.plist                     # Extension config (accepts 1 web URL)
    └── ShareViewController.swift     # Full pipeline: fetch → extract → EPUB → send/save
```

---

## EPUB Pipeline (Deep Dive)

The conversion pipeline runs entirely in memory with no temporary files:

1. **Fetch** — `WebPageFetcher` downloads the HTML via `URLSession` with a Safari user-agent, encoding detection, and redirect following
2. **Extract** — `ContentExtractor` (SwiftSoup) parses the DOM for article content using semantic selectors (`<article>`, `[role=main]`, `.post-content`, etc.). If extraction fails (< 400 chars), falls back to `ReadabilityExtractor` (WKWebView + Readability.js). Twitter/X URLs use `TwitterExtractor` via the fxtwitter API
3. **Sanitize** — `HTMLSanitizer` strips all scripts, styles, forms, media, images, SVGs, iframes, event handlers, and data attributes. Links are converted to plain text for a clean reading experience
4. **Build** — `EPUBBuilder` assembles the EPUB 2.0 package in memory: `mimetype` (uncompressed), `META-INF/container.xml`, `content.opf`, `toc.ncx`, and one or more `chapter-N.xhtml` files. Long content is auto-split by `ChapterSplitter` at `<h2>` boundaries or every 50 paragraphs
5. **Send** — The `Data` blob is uploaded via multipart/form-data POST to the device's upload endpoint, with real-time progress tracking

---

## Content Extraction Strategy

CrossX uses a tiered extraction approach to handle the widest range of web pages:

| Tier | Extractor | Method | When |
|------|-----------|--------|------|
| **1** | `TwitterExtractor` | fxtwitter JSON API | Twitter/X status URLs |
| **2** | `ContentExtractor` | SwiftSoup DOM parsing | All other URLs (primary) |
| **3** | `ReadabilityExtractor` | WKWebView + Readability.js | Fallback when SwiftSoup extracts < 400 chars |

The SwiftSoup extractor uses a priority list of CSS selectors to find article content:
`article`, `[role=main]`, `.post-content`, `.entry-content`, `.article-body`, `#content`, `main`, and more.

Metadata (title, author, description, language) is extracted from Open Graph tags, meta tags, and heading elements.

---

## Design System

CrossX uses a minimal design token system with four semantic colors:

| Token | Color | Usage |
|-------|-------|-------|
| `AppColor.accent` | Teal | Primary actions, navigation, icons |
| `AppColor.success` | Green | Successful operations, connected state |
| `AppColor.error` | Red | Errors, destructive actions, disconnected state |
| `AppColor.warning` | Orange | Warnings, pending states |

The `AccentColor` asset is set to teal with light and dark mode variants. The UI uses iOS 26 / macOS 26 **Liquid Glass** modifiers (`.glassEffect()`) for a translucent, modern appearance.

---

## Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) | >= 0.9.0 | In-memory EPUB ZIP archive creation |
| [SwiftSoup](https://github.com/scinfu/SwiftSoup) | >= 2.6.0 | HTML parsing and content extraction |

Dependencies are managed via **Xcode's Swift Package Manager** integration. They resolve automatically when you open the project.

---

## Roadmap

- [ ] **WallpaperX** — custom wallpaper upload and management for the X4
- [ ] **Share Extension queue integration** — update the iOS Share Extension to use the queue system instead of temp file saves
- [ ] **File rename** — currently disabled; waiting for CrossPoint firmware API stabilization
- [ ] **Image support in EPUBs** — optionally include images for richer e-books
- [ ] **Batch conversion** — convert multiple URLs in one session
- [ ] **Reading list integration** — import from Safari Reading List
- [ ] **visionOS support** — deployment target is already set; UI needs spatial adaptation
- [ ] **Localization** — multi-language support

---

## Contributing

Contributions are welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for the full guide, including:

- Development setup and build commands
- Code conventions and architecture rules
- PR process and checklist
- Common pitfalls to avoid

Quick start:

1. **Fork** the repository
2. **Create a branch** (`git checkout -b feature/my-feature`)
3. **Make your changes** — follow the conventions in [AGENTS.md](AGENTS.md)
4. **Build both platforms** — `xcodebuild` for iOS and macOS
5. **Open a Pull Request** — the [PR template](.github/pull_request_template.md) will guide you

---

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

---

<p align="center">
  Built for the <a href="https://Xteink.com">Xteink X4</a> e-reader community.
</p>
