# AGENTS.md — SendToX4

## Project Overview

SendToX4 is an iOS 26+ SwiftUI app that converts web pages to EPUB 2.0 format and sends them to an Xtreink X4 e-reader over its local WiFi hotspot. The app uses SwiftData for persistence and targets a minimal, glass-styled UI.

## Architecture

```
SendToX4/
  Models/          — SwiftData models (Article, DeviceSettings)
  Views/           — SwiftUI views (Liquid Glass design, iOS 26)
  ViewModels/      — @Observable view models with async orchestration
  Services/        — Business logic (EPUB generation, device communication, content extraction)
  Utilities/       — Pure helper functions (HTML sanitization, string extensions)
  Resources/       — Bundled assets (readability.js)
```

## Key Design Decisions

- **MVVM architecture** with clear separation: Views → ViewModels → Services
- **Protocol-oriented device communication**: `DeviceService` protocol with Stock and CrossPoint firmware implementations
- **Dual content extraction strategy**: SwiftSoup (fast, primary) → WKWebView + Readability.js (accurate, fallback)
- **EPUB 2.0** for maximum e-reader compatibility; text-only (no images) for fast transfer
- **In-memory EPUB generation**: no temp files, all Data objects via ZIPFoundation
- **Swift Concurrency throughout**: async/await, @MainActor ViewModels, nonisolated services

## Dependencies

| Package | Purpose |
|---------|---------|
| [ZIPFoundation](https://github.com/weichsel/ZIPFoundation.git) | EPUB ZIP archive creation |
| [SwiftSoup](https://github.com/scinfu/SwiftSoup.git) | HTML parsing and content extraction |

## Device Communication

The Xtreink X4 creates a WiFi hotspot. The user connects their iPhone to it. The device runs a plain HTTP server:

- **Stock firmware** at `192.168.3.3` — uses `/list`, `/edit` endpoints
- **CrossPoint firmware** at `192.168.4.1` — uses `/api/files`, `/upload`, `/mkdir`, `/delete` endpoints
- **No authentication** — the WiFi network is the only access control
- **Auto-detection**: the app tries both IPs on connect and caches the result

## EPUB Pipeline

1. Fetch web page HTML via URLSession
2. Extract article content (SwiftSoup heuristic → Readability.js fallback)
3. Sanitize HTML (strip scripts, forms, media, styles, images)
4. Build EPUB 2.0 in memory (mimetype → container.xml → content.opf → toc.ncx → content.xhtml)
5. Send via multipart/form-data POST to device

## Conventions

- **iOS 26 minimum deployment target** — use Liquid Glass modifiers (.glassEffect)
- **SwiftData** for persistence (Article history, DeviceSettings)
- **@Observable** for view models (not ObservableObject)
- **Structured concurrency**: prefer async/await over Combine, use Task groups where parallel
- **Error handling**: all service methods throw; ViewModels catch and surface user-friendly messages
- **File naming**: PascalCase for types, camelCase for properties/methods
- **No force unwraps** in production code; guard-let with meaningful errors

## Testing Notes

- Services are protocol-based for easy mocking
- ViewModels depend on service protocols, not concrete types
- EPUB generation can be tested by unzipping output Data and validating XML structure
- Device communication can be tested against a mock HTTP server

## Info.plist Requirements

- `NSAllowsLocalNetworking = YES` (ATS exception for plain HTTP to local IPs)
- `NSLocalNetworkUsageDescription` (local network permission prompt)
