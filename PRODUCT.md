# MacSweeper — Simple Mac Disk Cleaner

A lightweight, native macOS app inspired by terminal tools like **ncdu** and **mac-cleanup-go**, with a calm UI that replaces expensive subscriptions like CleanMyMac.

> Working title: **MacSweeper** (see [Open Questions](#open-questions) for alternatives).

## Vision

Most people pay for CleanMyMac for the **UI and confidence**, not magic cleanup logic. MacSweeper focuses on three things:

1. **Scan** — find reclaimable space (caches, logs, old downloads)
2. **Preview** — show what will be removed, with sizes and risk level
3. **Clean safely** — safety-checked deletion that frees space immediately; Trash undo available in Settings

No feature bloat. No scare tactics. Free forever — no subscription, no tip jar.

## What We're NOT Building

- Malware scanning
- App updater
- Menu bar widgets / live monitoring
- "RAM cleaner" or fake optimization
- System `/private/var` deep cleaning
- Launch agents / login items management
- Orphaned app / leftover preference sweeping (deferred to Phase 10)

## MVP Features

### Screens

| Screen | Purpose |
|--------|---------|
| **Home** | Disk free space + one primary "Scan" button |
| **Results** | Categories with checkboxes, sized and risk-labeled |
| **Detail** | Expand a category: paths, sizes, "why is this here?" |
| **Clean** | Summary → confirm → progress → "Freed X GB" + undo hint |

### Safe Defaults (v1)

Scanned and selected by default (risk: **Safe**):

- User `~/Library/Caches` (known regenerable app caches)
- Browser caches (Chrome, Safari, Firefox)
- Old logs in `~/Library/Logs`
- Xcode DerivedData (if present)
- Help Viewer cache (`com.apple.helpd`)

Off by default / opt-in:

- Old files in `~/Downloads` (risk: **Moderate** — user reviews before clean; Detail age/size filters include >14 days)
- Unused apps — in `/Applications` and `~/Applications` not opened in 14+ days by macOS last-used date (risk: **Moderate**). Apple system apps, running apps, and apps with unknown usage are never listed. Sole exception to the home-only allowlist: top-level `/Applications/*.app` bundles only — Utilities, nested folders, and bundle contents stay protected
- iPhone / iPad local backups (risk: **Moderate** — permanent data loss unless an iCloud backup exists)
- Empty Trash (optional, **off by default**; needs Full Disk Access)

Manual guidance (shown when a marker path exists; MacSweeper never executes these):

- Time Machine local snapshots via `tmutil thinlocalsnapshots` — the usual hidden cause of a huge "System Data" number (shown once Time Machine is configured)
- Homebrew `brew cleanup -s`, Docker `docker system prune`, `xcrun simctl delete unavailable`

Deferred to [Phase 4 — Dev mode](#build-phases) (shipped as opt-in):

- `node_modules`, `.venv` / `venv` under common project roots
- Homebrew caches (Trash) + Manual `brew cleanup` guidance
- Manual Docker reclaim guidance (`docker system prune`)

### Never Touch (v1 exclusions)

Hard exclusions — never listed as cleanable, even if large:

- `~/Documents`, `~/Desktop`, `~/Pictures`, `~/Music`, `~/Movies`
- iCloud Drive / Photos libraries
- Keychains, passwords, browser profiles (except regenerable cache dirs)
- SIP-protected system paths
- Anything outside the user home folder, except top-level `/Applications/*.app` bundles (Unused apps rule; nothing deeper)

## Safety Rules

These are the core differentiators. Borrowed from [mac-cleanup-go](https://github.com/2ykwang/mac-cleanup-go) and [Mole](https://github.com/tw93/Mole).

| Rule | Description |
|------|-------------|
| **Safety-checked, then delete** | Every path passes the home-only allowlist + protected prefixes first. "Delete immediately" (default **on**) permanently removes only the items just cleaned — never the whole Trash, which stays behind explicit "Empty Trash". Turn the setting off for Trash-first with undo |
| **Preview always** | Dry-run before any deletion; user must confirm |
| **Risk labels** | Safe / Moderate / Risky / Manual — Risky unchecked by default |
| **SIP-aware** | Don't touch protected system paths |
| **Minimal permissions** | Request Full Disk Access only when needed, explain why |
| **Audit everything** | Log what moved where, for the session (and optionally to disk) |

### Risk Levels

| Level | Meaning | Default selection |
|-------|---------|-------------------|
| **Safe** | Auto-regenerated caches/logs | Checked |
| **Moderate** | May require re-download or re-login | Unchecked |
| **Risky** | Possible user data | Unchecked; visually de-emphasized |
| **Manual** | Guide only — no automatic deletion | N/A (no checkbox) |

### Undo & Audit

- **Undo:** With "Delete immediately" off, after a clean show "Open Trash" (and optionally restore via Finder). Session-level undo = reverse the Trash moves for items still in Trash. No permanent-delete undo. With the setting on (default), items are permanently removed right after cleaning, so the done screen hides Undo and says so.
- **Audit log:** Record timestamp, category id, paths, bytes, and destination for each move. Keep the latest session in-app; optionally write to `~/Library/Application Support/MacSweeper/cleanup.log`.

## Tech Stack

### Decision: Swift + SwiftUI (native scan engine)

Phase 1 ships a **native** scan engine with declarative JSON rules — no CLI dependency.

```
Swift + SwiftUI
├── Scan engine (background FileManager walk)
├── File operations (FileManager → Trash)
└── 4-screen UI (Home → Results → Detail → Clean)
```

**Why:**

- Native Mac feel; list + checkbox UI is a natural fit
- No external binary to bundle, update, or license-check
- Straightforward path to notarized `.app` or Mac App Store

### Alternatives considered

| Approach | Pros | Cons | Status |
|----------|------|------|--------|
| **Swift + SwiftUI** | Native, lightweight, App Store ready | macOS only | **Chosen** |
| **Tauri + Rust** | Cross-platform, small binary | Less native feel | Not for v1 |
| **Electron** | Fast to prototype | Heavy, battery drain | Rejected |
| **Wrap existing CLI** | Proven scan logic | Dependency, licensing, UX friction | Revisit later if rule coverage stalls |

### Inspiration for rules (not bundled in v1)

Reference these for category ideas; Phase 1 reimplements a small subset in Swift + JSON:

- [mac-cleanup-go](https://github.com/2ykwang/mac-cleanup-go) — preview-first, safety levels, 100+ targets
- [Mole](https://github.com/tw93/Mole) — broader clean / uninstall / analyze
- [disky](https://github.com/biliboss/disky) — APFS-aware scanning, Trash-restorable cleanup

## UI Wireframes

### Home

```
┌─────────────────────────────────────┐
│  MacSweeper                      ⚙  │
├─────────────────────────────────────┤
│                                     │
│         42.3 GB free                │
│     ████████░░░░░░░░  68% used      │
│                                     │
│         [  Scan My Mac  ]           │
│                                     │
│  Last clean: freed 2.1 GB           │
└─────────────────────────────────────┘
```

### Results

```
┌─────────────────────────────────────┐
│  Found 4.8 GB to reclaim            │
├─────────────────────────────────────┤
│  ☑ Browser caches      1.2 GB Safe  │
│  ☑ App caches          890 MB Safe  │
│  ☐ Old downloads       2.1 GB Moderate │
│  ☑ Xcode DerivedData   620 MB Safe  │
├─────────────────────────────────────┤
│  Selected: 2.7 GB    [ Clean Now ]  │
└─────────────────────────────────────┘
```

### Detail (expand a category)

```
┌─────────────────────────────────────┐
│  ← Browser caches          1.2 GB   │
├─────────────────────────────────────┤
│  Why: Temporary files. Chrome and   │
│  Safari rebuild these automatically.│
│                                     │
│  ~/Library/Caches/Google/Chrome     │
│    Cache_Data/           980 MB     │
│  ~/Library/Caches/com.apple.Safari  │
│    WebKit/               220 MB     │
└─────────────────────────────────────┘
```

### Clean

```
┌─────────────────────────────────────┐
│  Ready to clean 2.7 GB              │
├─────────────────────────────────────┤
│  • Browser caches        1.2 GB     │
│  • App caches            890 MB     │
│  • Xcode DerivedData     620 MB     │
│                                     │
│  Items move to Trash. You can       │
│  restore them from Trash anytime.   │
│                                     │
│     [ Cancel ]    [ Move to Trash ] │
└─────────────────────────────────────┘
         ↓ (progress) ↓
┌─────────────────────────────────────┐
│  Freed 2.7 GB                       │
│  12 items moved to Trash            │
│                                     │
│     [ Open Trash ]    [ Done ]      │
└─────────────────────────────────────┘
```

### Design Principles

- One primary action per screen
- No dashboards, no upsells, no scare tactics
- Show **paths** on expand (builds trust)
- System fonts and native controls — "simple" means familiar
- Scan and clean run off the main thread; user can cancel a scan

## Architecture

```mermaid
flowchart LR
    UI[SwiftUI App] --> Scanner[Scan Engine]
    Scanner --> Categories[Category Rules JSON]
    Scanner --> FS[File System Walk]
    UI --> Preview[Preview + Selection]
    Preview --> Cleaner[Trash Mover]
    Cleaner --> Audit[Cleanup Log]
```

### Scan Engine: Declarative Rules

Rules live in JSON, not hardcoded Swift:

```json
{
  "id": "browser_chrome_cache",
  "label": "Chrome cache",
  "paths": ["~/Library/Caches/Google/Chrome"],
  "risk": "safe",
  "description": "Temporary files; Chrome rebuilds these automatically."
}
```

Start with ~15–20 high-value, low-risk rules. Expand over time.

**Size reporting (v1):** Use allocated size via `FileManager` / `URLResourceValues` (naive walk). APFS clone / sparse accuracy is Phase 11; hard-link dedupe is already applied. Label sizes as approximate if needed.

**Concurrency:** Scan on a background queue; stream category results to the UI; support cancel.

### Project Structure (proposed)

```
MacSweeper/
├── MacSweeper/
│   ├── App/
│   │   └── MacSweeperApp.swift
│   ├── Views/
│   │   ├── HomeView.swift
│   │   ├── ScanResultsView.swift
│   │   ├── CategoryDetailView.swift
│   │   └── CleanFlowView.swift
│   ├── Models/
│   │   ├── ScanCategory.swift
│   │   ├── ScanResult.swift
│   │   └── RiskLevel.swift
│   ├── Services/
│   │   ├── ScanEngine.swift
│   │   ├── CleanupService.swift
│   │   ├── AuditLogService.swift
│   │   └── DiskSpaceService.swift
│   └── Resources/
│       └── cleanup-rules.json
├── MacSweeperTests/
└── README.md
```

## Permissions

| Permission | When needed | Why |
|------------|-------------|-----|
| None | Scan `~/Library`, `~/Downloads` | Works out of the box for most Safe rules |
| Full Disk Access | Empty Trash; some protected cache paths | macOS privacy gate — request only when user opts in |
| Admin (sudo) | System caches | **Avoid in v1** |

In-app copy: *"We need this to empty Trash. Files never leave your Mac."*

**Distribution note:** Sandboxed Mac App Store builds may need security-scoped bookmarks for some paths; notarized direct download can request Full Disk Access more simply. Choose distribution before locking permission UX.

## Build Phases

| Phase | Scope | Timeline |
|-------|-------|----------|
| **1** | Scan home caches via JSON rules; sizes + checkbox list; Detail expand | Weekend |
| **2** | Move selected items to Trash; confirm flow; undo hint + session audit log | +1 week |
| **3** | Polish: cancelable scan, better size accuracy, optional FDA empty-Trash | +1 week |
| **4** | Dev mode (`node_modules`, Docker, Homebrew) — opt-in section | +2 weeks |
| **5** | Selection & trust polish: per-item checkboxes, Downloads filters, history, Settings | Done |
| **6** | Broader reclaim rules + custom Dev scan folders (still Trash-safe / Manual for brew·Docker) | Done |
| **7** | ncdu-style disk browse (“where did my space go?”) — list drill-down, rule jumps | Done |
| **8** | Ship & sustain: notarized `.app`, safety tests (free forever) | Done |
| **9** | Broader regenerable cache / Manual rules (Brave, JetBrains, messaging, Playwright, etc.) | Done |
| **10** | Orphaned-app leftovers (prefs / Application Support for uninstalled apps) | Planned |
| **11** | APFS-aware sizing + large-list Detail UX (virtualized / show-more / search) | Partial — Detail search / show-more / filters shipped; APFS sizing remains |

### High-ROI priorities (post Phase 4)

These three ideas finished the clean loop for real users (Phases 5–6). Phase 7 browse and Phase 8 shipping followed.

| Idea | Why users care | Phase |
|------|----------------|-------|
| **Per-item selection + Downloads age/size filters** | Avoid “clean half my Downloads by accident” anxiety | **5** (Done) |
| **Custom Dev scan roots** | Real projects aren’t only under `~/Developer` | **6** (Done) |
| **In-app cleanup history** | Makes the Undo / Trash promise feel durable across days | **5** (Done) |

### Phase 9+ (post-ship nice-to-haves)

Chosen first track: **broader cache rules** (cheap JSON wins, same Safe/Moderate/Manual engine). Then orphans, then trust/UX polish.

| Phase | Scope | Notes |
|-------|--------|-------|
| **9** | Grow `cleanup-rules.json` toward mac-cleanup-go coverage | Brave/Opera, JetBrains, Telegram/WhatsApp/Teams, Steam, watchOS/tvOS DeviceSupport, Playwright/Cypress/Puppeteer, Go/Maven/Bun/Carthage/Bundler caches; Manual `xcrun simctl delete unavailable`. Still Trash-first; no shell-out. |
| **10** | Orphaned-app leftover sweeping (Mole-inspired) | Prefs / Application Support / caches for apps no longer in `/Applications` or `~/Applications`. Risk **Moderate/Risky**, unchecked. Keep hard exclusions (Documents, profiles, keychains). Never default-on Safe. |
| **11** | APFS-aware sizing + large-list Detail UX | **Large-list Detail UX shipped** (search, show more, broader age/size filters, Reveal in Finder) along with Results/Browse/Clean polish. **APFS clone/sparse sizing still planned** so totals match Finder more closely. |

**Secondary (after 9–11, packaging polish):** cleanup report export (CSV/Markdown), opt-in reclaim reminders (not menu-bar monitoring), Sparkle self-update for the notarized `.app`, accessibility/localization, CI notarization.

**Still out of scope:** treemap, brew/Docker shell-out, paths outside `~`, sudo/system cleans, malware, RAM theater, live menu-bar monitoring.

**Phase 4 decisions:**

- Off by default (Home toggle: “Include Dev mode”).
- Discovery roots only: `~/Developer`, `~/Projects`, `~/src`, `~/code`, `~/Documents/GitHub`, `~/Desktop` (depth ≤ 6; no nested `node_modules`).
- `node_modules` / virtualenvs: Risky, Trash, unchecked.
- Homebrew caches: Moderate, Trash.
- Docker reclaim and Homebrew deep cleanup: Manual rows with copyable commands — no shell-out.
- No full-home walk or sudo/system paths (custom Dev folders added in Phase 6).

**Phase 5 decisions:**

- Detail supports per-item selection for list/discovery categories (Downloads, Mail, `node_modules`, etc.).
- Downloads/Mail Detail: age filters (>30 / >90 days) and size filters (>100 MB / >1 GB) plus Select/Deselect visible.
- Cleanup history is viewable in-app; optional persistence across launches (Settings).
- Settings gear: Dev mode default, custom Dev folders, history toggle.

**Phase 6 decisions:**

- Extra Safe caches: Slack, Zoom, Discord, Spotify, Adobe temp, common Electron apps.
- Extra Dev rules: Cargo `target`, Gradle caches, CocoaPods, npm/pnpm/yarn caches, pip cache.
- Custom Dev folders via Settings (bookmark once; must stay under home).
- Docker / deep brew remain Manual guides only.

**Phase 7 decisions:**

- Home secondary CTA: “Browse disk” (Scan remains primary).
- ncdu-style **list drill-down** only — size-sorted children + proportional bars; no visual treemap canvas.
- Root defaults to `~`; Choose folder… must stay under home.
- One-level listing with cancelable progressive sizing; packages (`.app`) are opaque.
- **Cleanable** badge jumps to an existing cleanup rule Detail when a scan covers the path; otherwise prompts to scan. Never trash arbitrary browse folders.
- Sizes reuse allocated-size + hard-link dedupe within the current folder walk; labeled approximate.

**Phase 8 decisions:**

- Distribution: **notarized direct download** (not Mac App Store); app stays non-sandboxed for FDA empty-Trash.
- Free forever — no tip jar, no subscription.
- Unit tests cover allowlists/exclusions, `RunningAppSafety`, and Trash move/restore.
- Release via Developer ID + `notarytool` + staple scripts (manual first; CI optional later).

**Phase 9 decisions:**

- First post-ship track is **rules expansion**, not orphans or APFS yet.
- Add Safe regenerable caches: Brave, Opera, JetBrains, messaging (Telegram / WhatsApp / Teams), Steam; expand Electron list (Linear, Obsidian, Loom, Miro); watchOS/tvOS DeviceSupport.
- Add Dev Moderate caches: Playwright/Cypress/Puppeteer, Go build cache, Maven, Bun, Carthage, Bundler/RubyGems.
- Add Manual guide: `xcrun simctl delete unavailable` (copy only; no shell-out).
- Phases 10–11 remain planned as documented under Phase 9+.

### Phase 1 non-goals

- No Trash moves yet (scan + preview only)
- No Full Disk Access prompt
- No system paths, no treemap, no Dev mode
- No CLI wrapping

## Competitive Comparison

| | CleanMyMac | MacSweeper |
|---|------------|------------|
| Price | ~$40/year | Free forever |
| Features | Everything + kitchen sink | 3 clear actions |
| Transparency | Black-box cleaning | Shows every path |
| Marketing | Aggressive upsells | Calm, honest UI |
| "Optimization" | Theater | Only real disk reclaim |
| Platform | macOS | macOS |

## Inspiration & References

| Tool | What to borrow |
|------|----------------|
| [ncdu](https://dev.yorhel.nl/ncdu) | Fast directory scanning, size-sorted navigation |
| [mac-cleanup-go](https://github.com/2ykwang/mac-cleanup-go) | Safety levels, preview-first, category coverage |
| [Mole](https://github.com/tw93/Mole) | Broad cleanup categories, orphaned-app ideas (Phase 10) |
| [disky](https://github.com/biliboss/disky) | APFS-aware scanning, Trash-restorable cleanup patterns |

## Open Questions

- [ ] App name finalization (MacSweeper, TidyMac, Sweep, ClearDesk?)
- [x] Distribution: notarized direct download (not Mac App Store) (Phase 8)
- [x] Monetization: free forever (no tip jar, no subscription)
- [x] Code signing / notarization setup for distribution (Phase 8)
- [x] Persist audit log across launches — optional via Settings “Keep cleanup history” (Phase 5)

## License

MIT — see [LICENSE](LICENSE). Revisit if we later vendor or wrap a third-party scanner (license must stay compatible).
