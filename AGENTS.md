# AGENTS.md — CrossX (SendToX4)

> **Developer reference** for AI coding agents and contributors. This file documents architecture decisions, implementation details, conventions, and patterns used throughout the codebase. For a user-facing overview, see [README.md](README.md).

## Project Overview

CrossX (bundle name: SendToX4) is a **native multiplatform SwiftUI app** for iOS 26+ and macOS 26+ that converts web pages to EPUB 2.0 format and sends them to an Xtreink X4 e-reader over its local WiFi hotspot. The app uses SwiftData for persistence, targets a Liquid Glass UI, and ships with an iOS Share Extension for converting pages directly from Safari.

**Bundle ID**: `com.crossappjtv.point`
**Display Name**: CrossX

## Architecture

```
SendToX4/
  Models/          — SwiftData @Model classes (Article, DeviceSettings, ActivityEvent, QueueItem)
  Views/           — SwiftUI views (Liquid Glass, iOS 26 / macOS 26 adaptive)
  ViewModels/      — @Observable view models with async orchestration (@MainActor)
  Services/        — Business logic (EPUB, device communication, content extraction)
  Intents/         — App Intents for Siri Shortcuts (ConvertURLIntent, CrossXShortcuts)
  Utilities/       — Pure helpers (HTML sanitization, string extensions, design tokens)
  Resources/       — Bundled assets (readability.js)

SendToX4ShareExtension/  — iOS-only Share Extension (receives URLs from Safari)
```

### Data flow

```
Views → ViewModels → Services → Device (HTTP) / SwiftData (persistence)
```

- **Views** observe `@Observable` ViewModels and call methods on user interaction
- **ViewModels** are `@MainActor`, orchestrate service calls, and manage UI state
- **Services** are `nonisolated`, perform async I/O, and throw errors on failure
- **Models** are SwiftData `@Model` classes persisted via `ModelContainer`

## Features Implemented

### Core

1. **URL-to-EPUB conversion** — full pipeline: fetch HTML → extract content → sanitize → build EPUB 2.0 → send to device
2. **Dual firmware support** — Stock firmware (`192.168.3.3`) and CrossPoint firmware (`192.168.4.1` / `crosspoint.local`)
3. **Auto-detection** — probes both firmware endpoints concurrently; CrossPoint tries mDNS first, then static IP fallback
4. **File manager** — browse, upload (`.epub`/`.xtc`/`.bump`/`.txt`), create folders, delete, move (CrossPoint only)
5. **Unified activity history** — merged timeline of EPUB conversions (`Article`) and file operations (`ActivityEvent`)
6. **iOS Share Extension** — convert and send from Safari or any app that shares URLs
7. **Native multiplatform** — iOS, iPadOS, and macOS from a single codebase (not Mac Catalyst)
8. **EPUB send queue** — persists EPUBs to disk when offline, batch-sends when device connects, with queue UI in Convert tab
9. **Siri Shortcuts** — App Intent (`ConvertURLIntent`) for URL-to-EPUB conversion from Shortcuts app, Siri, or Share Sheet automations
10. **Recent conversions** — last 3 completed conversions shown in Convert tab with inline action menus (Resend, Reconvert & Share, Copy URL)

### Content Extraction

11. **SwiftSoup heuristic extraction** — primary extractor using CSS selectors for article body, title, author, description
12. **Readability.js fallback** — WKWebView-based extraction when SwiftSoup yields < 400 characters
13. **Twitter/X extractor** — dedicated handler using fxtwitter API for tweet content and metadata
14. **Chapter splitting** — auto-splits long content at `<h2>` headings or every 50 paragraphs (15,000-char threshold)

### UI/UX

15. **Liquid Glass design** — `.glassEffect()` modifiers on iOS 26 / macOS 26
16. **Design system** — `AppColor` enum (accent/success/error/warning) with `AccentColor` asset (teal, light+dark)
17. **Platform-adaptive status bar** — iOS tab bar bottom accessory vs macOS Xcode-style bottom status bar
18. **Device status display** — firmware version, IP, WiFi mode, RSSI, free heap, uptime
19. **Expandable history rows** — tap to reveal full URL, error details, metadata
20. **History filtering** — All / Conversions / File Activity / Queue tabs with full-text search
21. **Queue section in Convert tab** — always-visible section with populated/empty glass-card states, Send All button, individual remove
22. **Queue connection prompt** — alert when device connects offering to send all queued items
23. **Settings Siri Shortcut guide** — inline 5-step setup guide with "Open Shortcuts App" button (iOS)
24. **Settings storage info** — queue EPUB count and size display with Clear Queue option
25. **Device accessory queue count** — shows "N EPUBs queued" in warning color when disconnected

## Key Design Decisions

### `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`

The project uses this build setting, making **every type implicitly `@MainActor`** unless explicitly opted out. This is the modern Swift concurrency approach but has a critical implication:

- **All service types MUST be marked `nonisolated`** — without this, service structs/protocols inherit `@MainActor`, causing stack overflows (`EXC_BAD_ACCESS code=2`) when called from async contexts.
- Affected types: `DeviceService` protocol + extension, `CrossPointFirmwareService`, `StockFirmwareService`, `DeviceFile`, `DeviceStatus`, `DeviceError`, `FileNameValidator`, `UploadProgressDelegate`, `DiscoveryResult`, `DeviceDiscovery`, `extension Data`.

### Protocol-oriented device communication

The `DeviceService` protocol defines the contract for all device operations:

```swift
nonisolated protocol DeviceService {
    func checkReachability() async throws -> Bool
    func listFiles(at path: String) async throws -> [DeviceFile]
    func createFolder(at path: String) async throws
    func uploadFile(data: Data, filename: String, to path: String, ...) async throws
    func deleteFile(at path: String) async throws
    func deleteFolder(at path: String) async throws
    func moveFile(from: String, to: String) async throws
    func renameFile(at: String, to: String) async throws
    func fetchStatus() async throws -> DeviceStatus
    func ensureFolder(at path: String) async throws
    var supportsMoveRename: Bool { get }
}
```

Two concrete implementations exist:
- `StockFirmwareService` — uses `/list`, `/edit` endpoints; does NOT support move/rename
- `CrossPointFirmwareService` — uses `/api/files`, `/upload`, `/mkdir`, `/delete`; DOES support move/rename

### Dual content extraction strategy

| Priority | Extractor | Method | Trigger |
|----------|-----------|--------|---------|
| 1 | `TwitterExtractor` | fxtwitter JSON API | URL matches `x.com` or `twitter.com` status pattern |
| 2 | `ContentExtractor` | SwiftSoup DOM parsing | All other URLs (primary) |
| 3 | `ReadabilityExtractor` | WKWebView + Readability.js | Fallback when SwiftSoup extracts < 400 chars |

### In-memory EPUB generation

The entire EPUB 2.0 package is built in memory using ZIPFoundation — no temporary files are written to disk. The `EPUBBuilder` produces a `Data` object containing:

```
mimetype (stored, not compressed — EPUB spec requirement)
META-INF/container.xml
OEBPS/content.opf
OEBPS/toc.ncx
OEBPS/chapter-1.xhtml
OEBPS/chapter-2.xhtml  (if split)
...
OEBPS/style.css
```

### EPUB send queue

When the device is not connected, converted EPUBs are persisted to disk and tracked in SwiftData for later batch-sending:

- **Storage**: EPUBs are written to `Application Support/EPUBQueue/<uuid>.epub`
- **Tracking**: Each file is tracked by a `QueueItem` SwiftData record linked to its `Article` by `articleID`
- **Shared enqueue logic**: `QueueViewModel.enqueueEPUB()` is a `static` throwing method used by both the ViewModel (instance wrapper captures errors into `errorMessage`) and the `ConvertURLIntent` (calls directly)
- **Batch send**: `QueueViewModel.sendAll()` sends items sequentially, updates linked `Article` status to `.sent`, deletes files + records on success, logs a summary `ActivityEvent`
- **Connection prompt**: `MainView` observes `deviceVM.isConnected` via `.onChange` and presents an alert offering to send all queued items when the device connects
- **UI**: Convert tab shows an always-visible queue section (glass card with empty state or item list); Settings shows queue storage size with a Clear Queue option; DeviceConnectionAccessory shows queue count when disconnected

### Siri Shortcuts (App Intents)

The app provides a built-in Siri Shortcut for URL-to-EPUB conversion via the App Intents framework (iOS 16+ / macOS 13+):

- **`ConvertURLIntent`** — accepts an optional `String?` parameter with `inputConnectionBehavior: .connectToPreviousIntentResult` to auto-receive URLs from a Shortcuts "Share Sheet" trigger
- **`String?` over `URL?`** — the Shortcuts runtime's type coercion from Share Sheet input to `URL` is unreliable (silently fails to `nil`); `String` is the most universal coercion target and is parsed manually in `perform()`
- **Headless execution** — `openAppWhenRun = false`; the intent creates its own `ModelContainer`/`ModelContext` (same default SwiftData store) and calls the service layer directly (no ViewModel dependency)
- **Pipeline**: validates URL → creates `Article` → fetches page → extracts content (Twitter/SwiftSoup/Readability.js) → builds EPUB → enqueues via `QueueViewModel.enqueueEPUB()`
- **Rich feedback**: returns `ProvidesDialog` with article title, file size, and queue count
- **Error handling**: five specific `ConvertURLIntentError` cases with user-facing `LocalizedStringResource` messages
- **`CrossXShortcuts: AppShortcutsProvider`** — registers pre-built Siri phrases ("Convert a page with CrossX", etc.)
- **Setup guide**: Settings includes an inline 5-step guide for creating a Shortcut with "Show in Share Sheet" enabled, plus an "Open Shortcuts App" button (iOS)

### SwiftData persistence

Four `@Model` types:

| Model | Purpose | Key fields |
|-------|---------|------------|
| `Article` | Conversion history | url, title, author, domain, status (enum), errorMessage |
| `DeviceSettings` | Device configuration (singleton) | firmwareType, customIP, feature toggles, destination folders |
| `ActivityEvent` | File operation log | category, action, status, fileName, detail, timestamp |
| `QueueItem` | EPUB send queue | id, articleID, title, filename, filePath, fileSize, sourceURL, sourceDomain, queuedAt |

## Multiplatform Strategy

The app is a **native multiplatform** Xcode project (`SDKROOT = auto`, `SUPPORTS_MACCATALYST = NO`). Platform differences are handled via conditional compilation:

### iOS-only modifiers wrapped with `#if os(iOS)`

These SwiftUI modifiers don't exist on macOS and must be conditionally compiled:

- `.keyboardType()`
- `.textInputAutocapitalization()`
- `.textContentType()`
- `.submitLabel()`
- `.navigationBarTitleDisplayMode(.inline)`
- `.tabViewBottomAccessory { }`
- `.listStyle(.insetGrouped)` (use `.inset` on macOS)

### Platform-specific components

| Component | iOS | macOS |
|-----------|-----|-------|
| Device status | `DeviceConnectionAccessory` (tab bar bottom accessory) | `MacDeviceStatusBar` (Xcode-style bottom bar) |
| Share/Export | `UIActivityViewController` via `UIViewControllerRepresentable` | `NSSharingServicePicker` via `NSViewRepresentable` |
| Clipboard | `UIPasteboard.general` | `NSPasteboard.general` |
| Toolbar placement | `.topBarLeading` / `.topBarTrailing` | `.navigation` / `.primaryAction` / `.confirmationAction` |

### Entitlements

`SendToX4.entitlements` enables:
- `com.apple.security.app-sandbox` — required for macOS App Store / notarization
- `com.apple.security.network.client` — required for HTTP to device (macOS sandbox blocks all networking without this)
- `com.apple.developer.siri` — required for App Intents / Siri Shortcuts

### Share Extension

The `SendToX4ShareExtension` is **iOS-only**. It should not be modified for macOS. It contains its own embedded copy of the conversion pipeline (no shared framework) and accepts a single web URL via `NSExtensionActivationSupportsWebURLWithMaxCount = 1`.

## Device Communication (Deep Dive)

### Connection flow

1. User taps "Connect" → `DeviceViewModel.search()` is called
2. `DeviceDiscovery` probes endpoints concurrently using `async let`:
   - Stock: `http://192.168.3.3/list`
   - CrossPoint: `http://crosspoint.local/api/files` (mDNS) → fallback to `http://192.168.4.1/api/files`
3. First successful response determines firmware type → `DiscoveryResult` enum
4. `DeviceViewModel` creates the appropriate `DeviceService` implementation and caches it

### Network configuration

| Setting | Value |
|---------|-------|
| Request timeout | 30 seconds |
| Resource timeout | 120 seconds |
| Retry count | 2 |
| Retry delay | 1 second |
| User-Agent | iPhone Safari string |

### Endpoints by firmware

**Stock** (`192.168.3.3`):
- `GET /list?path=` — list directory contents
- `POST /edit` — upload file, create folder, delete

**CrossPoint** (`192.168.4.1` or `crosspoint.local`):
- `GET /api/files?path=` — list directory contents (JSON)
- `POST /upload` — upload file (multipart/form-data)
- `POST /mkdir` — create folder
- `POST /delete` — delete file or folder
- `POST /move` — move file to different path
- `POST /rename` — rename file

### Info.plist requirements

- `NSAllowsLocalNetworking = YES` — ATS exception for plain HTTP to local IPs
- `NSLocalNetworkUsageDescription` — iOS local network permission prompt text

## Activity History System

The history view presents a **unified timeline** merging two data sources:

1. **`Article` records** — created by the conversion pipeline, tracked via `ConversionStatus` enum (pending → fetching → extracting → building → sending → sent/savedLocally/failed)
2. **`ActivityEvent` records** — created by `FileManagerViewModel` when file operations complete

`ActivityEvent` uses three enums:
- `ActivityCategory`: `.fileManager`, `.queue`
- `ActivityAction`: `.upload`, `.createFolder`, `.moveFile`, `.deleteFile`, `.deleteFolder`, `.queueSend`
- `ActivityStatus`: `.success`, `.failed`

The `HistoryView` merges both types by timestamp and supports filtering by category (All / Conversions / File Activity / Queue).

## Design System

### Colors

| Token | Color | Hex (light) | Usage |
|-------|-------|-------------|-------|
| `AppColor.accent` | Teal | `#2AA5A0` | Primary actions, icons, navigation |
| `AppColor.success` | Green | system | Connected state, successful operations |
| `AppColor.error` | Red | system | Errors, destructive actions, disconnected |
| `AppColor.warning` | Orange | system | Warnings, pending states |

The `AccentColor` asset set contains teal variants for both light and dark appearance.

### Styling

- iOS 26 / macOS 26 **Liquid Glass** modifiers (`.glassEffect()`) for translucent chrome
- System `List`, `NavigationStack`, `TabView` with minimal custom styling
- SF Symbols for all icons

## Dependencies

| Package | Min Version | Purpose |
|---------|------------|---------|
| [ZIPFoundation](https://github.com/weichsel/ZIPFoundation.git) | 0.9.0 | In-memory EPUB ZIP archive creation |
| [SwiftSoup](https://github.com/scinfu/SwiftSoup.git) | 2.6.0 | HTML parsing and content extraction |

Managed via Xcode's built-in Swift Package Manager. No `Package.swift` — dependencies are declared in `project.pbxproj`.

## Build Commands

### iOS

```bash
xcodebuild -project SendToX4.xcodeproj \
  -scheme SendToX4 \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' \
  build
```

### macOS

```bash
xcodebuild -project SendToX4.xcodeproj \
  -scheme SendToX4 \
  -destination 'platform=macOS' \
  build
```

### Important build notes

- **LSP errors are unreliable** — the language server frequently reports "Cannot find type X in scope" for cross-file references. These are indexing noise. Only errors from `xcodebuild` are real.
- **Always build both platforms** when making changes to shared code.
- The Share Extension target (`SendToX4ShareExtension`) only builds for iOS.

## Conventions

### Swift style

- **PascalCase** for types (structs, classes, enums, protocols)
- **camelCase** for properties, methods, local variables
- **`@Observable`** for view models (not `ObservableObject`/`@Published`)
- **`async/await`** for all async work (no Combine, no completion handlers)
- **`guard let`** with meaningful error messages (no force unwraps in production code)
- **Structured concurrency**: prefer `Task {}` and `async let` over unstructured patterns

### Architecture rules

- Views never call services directly — always go through a ViewModel
- ViewModels are `@MainActor` and own UI state
- Services are `nonisolated` and stateless (receive all inputs as parameters)
- All service methods `throw` — ViewModels catch and surface user-friendly `errorMessage` strings
- SwiftData `ModelContext` is injected via `@Environment(\.modelContext)` in Views and passed to ViewModels as needed
- **No `.confirmationDialog`** — use `.alert` for destructive confirmations and inline `Menu` for contextual actions (`.confirmationDialog` has broken positioning on iOS/iPad)

### Platform wrapping

- Use `#if os(iOS)` for iOS-only SwiftUI modifiers
- Use `#if canImport(UIKit)` / `#if canImport(AppKit)` for UIKit/AppKit bridging code (e.g., `ShareSheetView`)
- Use `#if os(macOS)` for macOS-only components (e.g., `MacDeviceStatusBar`)
- Prefer `.navigation` and `.primaryAction` toolbar placements (work on both platforms) over `.topBarLeading`/`.topBarTrailing`

### File organization

- One primary type per file (file named after the type)
- Related small types can share a file (e.g., `DeviceFile`, `DeviceStatus`, `DeviceError` in `DeviceService.swift`)
- The project uses **folder references** in Xcode — new/deleted `.swift` files are automatically picked up without modifying `project.pbxproj`

## Testing Notes

- **Services are protocol-based** — inject mock implementations for unit testing
- **ViewModels depend on service protocols**, not concrete types — use dependency injection
- **EPUB generation** can be tested by unzipping the output `Data` object and validating the XML structure
- **Device communication** can be tested against a mock HTTP server (e.g., `URLProtocol` subclass)
- **Content extraction** can be tested with static HTML fixtures
- **No test target exists yet** — tests should be added as the project matures
