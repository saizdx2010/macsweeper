# MacSweeper

A lightweight, native macOS disk cleaner. Scan, preview, and reclaim space safely — no subscriptions, no scare tactics, free forever.

Inspired by [ncdu](https://dev.yorhel.nl/ncdu) and [mac-cleanup-go](https://github.com/2ykwang/mac-cleanup-go). Full product spec: [PRODUCT.md](PRODUCT.md).

## What it is

MacSweeper does three things well:

1. **Scan** — find reclaimable space (browser/app caches, logs, Xcode junk, optional Dev folders)
2. **Preview** — show every path, size, and risk level before anything moves
3. **Clean safely** — move to Trash by default; never surprise-delete

No malware scanner, no “RAM cleaner,” no upsells. Just real disk reclaim with transparent paths.

## Features

- **Home** — free-space ring, one primary **Scan**, and a secondary **Browse disk**
- **Category results** — sized, risk-labeled rows (Safe / Moderate / Risky / Manual); Safe items checked by default
- **Detail** — expand a category to see paths, why they’re listed, and per-item selection (plus age/size filters for Downloads and Mail)
- **Clean flow** — confirm → progress → “Freed X GB” with Open Trash / undo hints
- **Browse disk** — ncdu-style list drill-down under `~` (or a chosen home folder); **Cleanable** badges jump to matching rules after a scan
- **Dev mode** (opt-in) — `node_modules`, virtualenvs, package-manager caches, Cargo/Gradle, Homebrew/Docker guidance
- **Settings & history** — Dev defaults, custom Dev scan folders, optional persistent cleanup history
- **~46 reclaim rules** — browsers, messaging, JetBrains, Steam, Xcode/simulator, Electron apps, and more (see `MacSweeper/Resources/cleanup-rules.json`)

## Safety

| Rule | Behavior |
|------|----------|
| **Trash first** | Never permanent-delete except explicit Empty Trash |
| **Preview always** | Dry-run sizes; user confirms before any move |
| **Risk labels** | Risky unchecked and de-emphasized; Manual is guide-only (copyable commands, no shell-out) |
| **Hard exclusions** | Documents, Desktop, Pictures, Music, Movies, iCloud, keychains, profiles, SIP paths |
| **Home only** | No system `/private/var` deep cleans; no sudo |
| **Audit** | Session (and optional on-disk) log of what moved where |

Full Disk Access is requested only when needed (e.g. Empty Trash), with a clear explanation.

## Status

Phases **1–9** shipped: scan → preview → Trash-safe clean, Dev mode, selection/history/Settings, broad reclaim rules, **Browse disk**, notarized release scripts, and safety unit tests.

**UX polish** (post Phase 9): Reveal in Finder, bulk Safe selection, Detail search/show-more, Clean progress, Browse breadcrumbs/keys, history labels, shortcuts/a11y.

Phase **10** planned (orphaned-app leftovers). Phase **11** partially shipped (Detail large-list UX); APFS sizing remains. Details in [PRODUCT.md](PRODUCT.md).

## Requirements

- macOS 14+
- Xcode 15+ (tested with Xcode 26)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) to regenerate the Xcode project

```bash
brew install xcodegen
```

## Build & run

```bash
xcodegen generate
open MacSweeper.xcodeproj
```

Or from the CLI:

```bash
xcodegen generate
xcodebuild -scheme MacSweeper -configuration Debug -destination 'platform=macOS' build
```

## Test

```bash
xcodegen generate
xcodebuild test -scheme MacSweeper -destination 'platform=macOS'
```

## Distribution (notarized direct download)

MacSweeper ships as a free, notarized `.app` (not Mac App Store). Requires an Apple Developer ID Application certificate and App Store Connect API key (or Apple ID) for notarization.

```bash
# Set once in your shell / CI secrets (never commit):
export DEVELOPMENT_TEAM=YOUR_TEAM_ID
export NOTARY_PROFILE=MacSweeper-notary   # keychain profile from `xcrun notarytool store-credentials`

./scripts/release.sh
```

The script archives a Release build, notarizes, staples, and writes a zip under `dist/`.

## Project layout

```
MacSweeper/
├── App/           # SwiftUI entry
├── Views/         # Home, Browse, Results, Detail, Clean, Settings
├── Models/        # Categories, results, risk levels
├── Services/      # Scan, browse, cleanup, audit, disk space, Full Disk Access
└── Resources/     # cleanup-rules.json
MacSweeperTests/   # Safety unit tests
scripts/           # Notarized release
```

## License

MIT — see [LICENSE](LICENSE).
