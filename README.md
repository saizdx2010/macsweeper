# MacSweeper

A lightweight, native macOS disk cleaner — scan, preview, clean safely. No subscriptions, no scare tactics.

Inspired by [ncdu](https://dev.yorhel.nl/ncdu) and [mac-cleanup-go](https://github.com/2ykwang/mac-cleanup-go). Full product spec: [PRODUCT.md](PRODUCT.md).

## Status

Phase 1: real home-folder scan via JSON rules, sized checkbox results, and category detail. Trash moves land in Phase 2.

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

## Project layout

```
MacSweeper/
├── App/           # SwiftUI entry
├── Views/         # Home, Results, Detail, Clean
├── Models/        # Categories, results, risk levels
├── Services/      # Scan engine (live), cleanup/audit stubs (Phase 2)
└── Resources/     # cleanup-rules.json
```

## License

MIT — see [LICENSE](LICENSE).
