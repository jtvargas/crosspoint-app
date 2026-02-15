## Summary

<!-- Describe your changes in 2-3 bullet points -->

-
-
-

## Change Type

<!-- Check all that apply -->

- [ ] Bug fix
- [ ] New feature
- [ ] Refactor / code improvement
- [ ] Documentation
- [ ] Build / configuration

## Scope

<!-- Check all areas touched by this PR -->

- [ ] Views
- [ ] ViewModels
- [ ] Services
- [ ] Models
- [ ] Utilities
- [ ] Share Extension
- [ ] Build / project config

## Linked Issue

<!-- Reference related issues. Use "Closes #123" to auto-close on merge -->

- Closes #
- Related #

## How It Was Tested

<!-- Describe what you tested and how -->

- [ ] Builds on iOS (`xcodebuild ... -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`)
- [ ] Builds on macOS (`xcodebuild ... -destination 'platform=macOS'`)
- [ ] Tested manually on simulator / device
- [ ] N/A (docs or config only)

**Test details:**

<!-- Describe the scenarios you tested, edge cases checked, etc. -->

## Screenshots

<!-- Optional: attach screenshots or recordings for UI changes -->

## Checklist

<!-- Confirm before requesting review -->

- [ ] I have read [CONTRIBUTING.md](../CONTRIBUTING.md)
- [ ] No force unwraps (`!`) added
- [ ] iOS-only modifiers wrapped in `#if os(iOS)`
- [ ] New service types are marked `nonisolated`
- [ ] ViewModels go through service protocols (no direct service calls from Views)
