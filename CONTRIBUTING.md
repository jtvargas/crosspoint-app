# Contributing to CrossX

Thanks for your interest in contributing! Whether it's a bug fix, new feature, or documentation improvement, all contributions are welcome.

## Quick Links

- **Repository:** https://github.com/jtvargas/crosspoint-app
- **README:** [README.md](README.md) — project overview and getting started
- **Developer Reference:** [AGENTS.md](AGENTS.md) — architecture, conventions, and deep dives

## How to Contribute

- **Bug fixes and small improvements** — open a PR directly
- **New features or architecture changes** — open an issue first to discuss the approach
- **Documentation** — PRs welcome for any docs improvements

## Development Setup

### Prerequisites

| Requirement | Version |
|------------|---------|
| **Xcode** | 26.0+ (beta) |
| **iOS SDK** | 26.0+ |
| **macOS SDK** | 26.0+ |
| **Swift** | 5 |

### Getting started

```bash
git clone https://github.com/jtvargas/crosspoint-app.git
cd crosspoint-app
open SendToX4.xcodeproj
```

Xcode will resolve Swift Package Manager dependencies (ZIPFoundation and SwiftSoup) automatically.

### Build commands

Always verify your changes build on **both platforms**:

```bash
# iOS
xcodebuild -project SendToX4.xcodeproj \
  -scheme SendToX4 \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build

# macOS
xcodebuild -project SendToX4.xcodeproj \
  -scheme SendToX4 \
  -destination 'platform=macOS' \
  build
```

> **Note:** LSP errors like "Cannot find type X in scope" are cross-file indexing noise. Only errors from `xcodebuild` are real.

## PR Process

1. **Fork** the repository
2. **Create a branch** from `main` (`git checkout -b feature/my-change`)
3. **Make your changes** following the conventions below
4. **Build both platforms** to verify no regressions
5. **Commit** with a clear message (e.g., `feat: add batch URL conversion`, `fix: handle empty URL input`)
6. **Open a Pull Request** — the PR template will guide you through the required information

### Commit message style

Use conventional-style prefixes:

- `feat:` — new feature
- `fix:` — bug fix
- `docs:` — documentation changes
- `refactor:` — code restructuring without behavior change
- `chore:` — build config, dependencies, tooling

## Code Conventions

See [AGENTS.md](AGENTS.md) for the full reference. Here's a summary of the most important patterns:

### Architecture (MVVM)

- **Views** observe ViewModels and call methods on user interaction
- **ViewModels** are `@MainActor` and `@Observable` — they orchestrate services and own UI state
- **Services** are `nonisolated` and stateless — they perform async I/O and throw errors
- **Views never call services directly** — always go through a ViewModel

### Swift patterns

- Use **`@Observable`** (not `ObservableObject` / `@Published`)
- Use **`async/await`** (no Combine, no completion handlers)
- Use **`guard let`** with meaningful errors (no force unwraps `!`)
- Use **structured concurrency**: `Task {}` and `async let`

### `@MainActor` isolation (critical)

The project uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, which makes **every type implicitly `@MainActor`**. If you add a new service type (struct, protocol, or enum used in async contexts), you **must** mark it `nonisolated` to avoid stack overflow crashes:

```swift
// Correct
nonisolated struct MyNewService { ... }

// Wrong — inherits @MainActor, causes EXC_BAD_ACCESS
struct MyNewService { ... }
```

### Multiplatform (iOS + macOS)

When using iOS-only SwiftUI modifiers, wrap them:

```swift
#if os(iOS)
.keyboardType(.URL)
.textInputAutocapitalization(.never)
.navigationBarTitleDisplayMode(.inline)
#endif
```

For UIKit/AppKit bridging code:

```swift
#if canImport(UIKit)
// iOS implementation
#elseif canImport(AppKit)
// macOS implementation
#endif
```

### File organization

- One primary type per file, named after the type
- The project uses **folder references** — new `.swift` files are automatically picked up by Xcode without modifying `project.pbxproj`

## What to Watch Out For

| Pitfall | Prevention |
|---------|-----------|
| Stack overflow from `@MainActor` inheritance | Mark all service types `nonisolated` |
| macOS build failures from iOS-only modifiers | Wrap in `#if os(iOS)` |
| `.insetGrouped` list style on macOS | Use `.inset` on macOS |
| Force unwraps in production code | Use `guard let` with error messages |
| Modifying Share Extension for macOS | Don't — it's iOS-only |
| LSP "Cannot find type" errors | Ignore — only trust `xcodebuild` output |

## AI-Assisted PRs Welcome

Built your contribution with AI tools (Claude, Copilot, etc.)? That's totally fine. Just note it in your PR description so reviewers know what to look for. Transparency helps everyone.

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).
