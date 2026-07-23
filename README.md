# MacSweeper

A lightweight, native macOS disk cleaner — scan, preview, clean safely. No subscriptions, no scare tactics. Free forever.

Inspired by [ncdu](https://dev.yorhel.nl/ncdu) and [mac-cleanup-go](https://github.com/2ykwang/mac-cleanup-go). Full product spec: [PRODUCT.md](PRODUCT.md).

## Status

Phases 1–9 complete: scan → preview → Trash-safe clean, Dev mode, selection/history/Settings, reclaim rules (including Phase 9 cache expansion), **Browse disk**, notarized release scripts, and safety unit tests.

Phases **10–11** planned: orphaned-app leftovers, then APFS sizing + large-list Detail UX (see [PRODUCT.md](PRODUCT.md) Phase 9+).

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

MacSweeper is distributed as a free, notarized `.app` (not Mac App Store). Requires an Apple Developer ID Application certificate and App Store Connect API key (or Apple ID) for notarization.

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
