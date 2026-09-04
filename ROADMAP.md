# MacSweeper Roadmap

Where MacSweeper goes next — version by version. For the full product spec (vision, safety model, architecture), see [PRODUCT.md](PRODUCT.md). For build/test/release instructions, see [README.md](README.md).

- **Current release:** v1.0.0 (`MARKETING_VERSION` in [project.yml](project.yml))
- **Last updated:** 2026-09-04
- **Ordering, not dates:** releases are ordered by priority; no calendar promises.

## Status legend

| Mark | Meaning |
|------|---------|
| ✅ | Shipped |
| 🚧 | In progress |
| 📅 | Planned — next up, scoped |
| 🔭 | Exploring — no version committed |
| 🚫 | Not planned, on purpose |

## Versioning scheme

MacSweeper follows [Semantic Versioning](https://semver.org/): `MAJOR.MINOR.PATCH`.

| Bump | When | Examples |
|------|------|----------|
| **MAJOR** (`x.0.0`) | Rare. Reserved for a change to the core safety promise, a required migration, or dropping a macOS version | Safety-model rework, macOS 15+ only |
| **MINOR** (`1.x.0`) | One shipped feature phase (a new user-facing capability) | Phase 10 → v1.1.0, APFS sizing → v1.2.0 |
| **PATCH** (`1.0.x`) | Bug fixes, safety fixes, new/expanded cleanup rules (JSON-only wins), UI polish | New cache rules, scan crash fix |

### Where the version lives

- `MARKETING_VERSION` in [project.yml](project.yml) is the **single source of truth**. XcodeGen writes it into the generated project; [scripts/release.sh](scripts/release.sh) reads it to name the artifact (`dist/MacSweeper-<version>.zip`).
- `CURRENT_PROJECT_VERSION` is the build number — increment by 1 for every release build, even within the same marketing version.
- Git tags mirror the marketing version: `v1.1.0`.

### Release ritual (every version)

```bash
# 1. Bump version in project.yml (MARKETING_VERSION + CURRENT_PROJECT_VERSION)
$EDITOR project.yml

# 2. Regenerate + verify
xcodegen generate
xcodebuild test -scheme MacSweeper -destination 'platform=macOS'

# 3. Tag and build the notarized artifact
git add project.yml
git commit -m "chore: release v1.x.y"
git tag v1.x.y
DEVELOPMENT_TEAM=... NOTARY_PROFILE=MacSweeper-notary ./scripts/release.sh

# 4. Publish
#    - Push commit + tag
#    - Upload dist/MacSweeper-1.x.y.zip to GitHub Releases with notes
```

Rules-only PATCH releases are no exception: cleanup rules ship inside the app bundle, so a rules change still changes the binary. **Every release runs the full ritual, including notarization.**

---

## ✅ v1.0.0 — Shipped (Phases 1–9 + UX polish)

The complete scan → preview → clean loop, shipped and notarized:

- ✅ Scan home caches via declarative JSON rules (~50 rules: browsers, messaging, JetBrains, Steam, Xcode/simulators, Electron apps)
- ✅ Risk-labeled preview (Safe / Moderate / Risky / Manual) — Safe checked, Risky unchecked and de-emphasized
- ✅ Trash-safe clean with confirm flow; "Delete immediately" (default) frees space instantly, toggle off for Trash undo
- ✅ Safety policy: home-only allowlist, protected prefixes, hard exclusions (Documents, Desktop, Pictures, Music, Movies, iCloud, keychains, SIP)
- ✅ Dev mode (opt-in): `node_modules`, virtualenvs, Cargo/Gradle/npm/pnpm/pip caches; custom Dev scan roots; brew/Docker as Manual-only guides
- ✅ Unused apps (opt-in, 14+ days, with strict safety exclusions)
- ✅ Browse disk (ncdu-style drill-down under `~`, "Cleanable" badges jump to rules)
- ✅ Detail UX: per-item selection, age/size filters, search, show-more, Reveal in Finder, bulk Safe selection
- ✅ Cleanup history (optional persistence) + session audit log
- ✅ System Data coverage: iOS backups, Time Machine snapshot guidance, regenerable Apple caches
- ✅ Notarized direct-download release (`release.sh`), safety unit tests, CI on GitHub Actions

---

## 📅 v1.1.0 — Orphaned-app leftovers (Phase 10)

**Goal:** reclaim the prefs / Application Support / caches that apps leave behind when uninstalled — the biggest remaining reclaim category. (Mole-inspired; the one PRODUCT.md defers to Phase 10.)

- [ ] Detect installed apps in `/Applications` and `~/Applications` (reuse Unused-apps scanner infrastructure)
- [ ] Map uninstalled apps to their leftover paths: `~/Library/Preferences`, `~/Library/Application Support`, `~/Library/Caches`, `~/Library/Logs`, `~/Library/Saved Application State`, `~/Library/Containers` (user-owned only)
- [ ] Risk model: **Moderate/Risky, unchecked by default** — leftover prefs may hold licenses/settings for reinstallable apps
- [ ] Hard exclusions carry over unchanged (Documents, profiles, keychains, anything outside home)
- [ ] Detail view groups leftovers per app ("Uninstalled app leftovers → Slack — 3 paths, 412 MB") with per-path selection
- [ ] "Why is this here?" copy explains the orphan heuristic and what won't be listed
- [ ] Safety tests: orphan rules never match an installed app's bundle or protected prefixes

## 📅 v1.2.0 — APFS-aware sizing (Phase 11 completion)

**Goal:** make reported sizes match Finder closely enough that "Freed X GB" is never doubted. The only unfinished item from Phase 11.

- [ ] Use APFS logical vs. allocated size correctly (`NSURLTotalFileAllocatedSizeKey` vs. logical) — clones and sparse files undercount/overcount today
- [ ] Hard-link dedupe already applied within a walk — extend across categories so the same inode isn't counted twice
- [ ] Validate a sample of directories against Finder "Get Info" + `du`; document known deltas in the size label ("approximate")
- [ ] Re-measure free-space delta after clean and show it on the done screen ("Finder now shows +2.6 GB")
- [ ] Unit tests with fixture files (clone, sparse, hard-linked) where the filesystem supports it

## 📅 v1.3.0 — Trust pack: report export + ignore list

**Goal:** make every clean auditable after the fact, and give users a permanent say in what's never touched. (From PRODUCT.md's post-ship secondary list.)

- [ ] **Cleanup report export** — CSV + Markdown: timestamp, category, paths, bytes, destination; one row per item; share via NSSavePanel
- [ ] **Ignore list** — user-managed "never scan / never clean" paths (Settings), respected by scan, browse, and future phases; importable/exportable
- [ ] **Audit log viewer** — browse persisted cleanup history with per-session totals and a jump to the matching report
- [ ] History rows link to the exported report for that session

## 📅 v1.4.0 — Update automation: Sparkle + CI notarization

**Goal:** users can update without re-downloading, and releases don't depend on one machine. (From PRODUCT.md's secondary list.)

- [ ] Integrate [Sparkle](https://sparkle-project.org/) for the notarized `.app` (appcast + EdDSA signatures)
- [ ] `release.sh` emits the appcast entry (size, EdDSA signature, release notes URL) alongside the zip
- [ ] GitHub Actions release workflow: tag push → tests → archive → notarize → staple → attach zip + appcast (secrets: `DEVELOPMENT_TEAM`, notary keychain via CI key or App Store Connect API key)
- [ ] Update UX: calm, manual-check-by-default; no popups mid-clean
- [ ] Keep "free forever" — update feed is plain GitHub Releases/static hosting

## 📅 v1.5.0 — Opt-in reclaim reminders

**Goal:** a gentle nudge, not monitoring. PRODUCT.md explicitly excludes menu-bar widgets and live monitoring — reminders are scheduled, local, and opt-in.

- [ ] Optional reminder: "Last clean freed 3.2 GB, 30 days ago — scan again?" as a local notification (no launch agent if avoidable; on-launch check first)
- [ ] Frequency in Settings: off (default) / monthly / weekly
- [ ] Clicking opens the app and starts a scan; never auto-cleans
- [ ] No background daemon, no menu-bar item, no disk polling

## 📅 v1.6.0 — Accessibility & localization

**Goal:** the calm UI works for everyone, in more languages.

- [ ] VoiceOver audit of every screen (labels, hints, focus order, announce scan/clean progress)
- [ ] Full keyboard navigation pass; visible focus rings; shortcuts documented in-app
- [ ] Dynamic Type / text sizing check
- [ ] Localization scaffold + first locales (e.g. de, es, fr, ja, pt-BR, zh-Hans) — strings extracted from code
- [ ] Localize risk labels and safety copy with extra care (these are the trust contract)

---

## Continuous tracks (every release)

- **Rules expansion** — grow `cleanup-rules.json` toward mac-cleanup-go coverage. Cheap JSON wins ship as PATCH releases (e.g. v1.2.1) with the full release ritual.
- **Safety tests grow with every deletion-touching feature** — a phase isn't done until its allowlist/exclusion behavior is unit-tested.
- **Scan performance** — cancel stays responsive; progressive category streaming; no main-thread walks.
- **Docs** — README/PRODUCT.md stay truthful after each phase; roadmap checkboxes updated on ship.

## 🔭 Exploring (no version committed)

Ideas parked with a first take. Nothing here is promised; each must pass the safety-first bar before it earns a version slot.

- **Large-files finder** — read-only "top N biggest files under `~`" list with Reveal in Finder; guidance only, never auto-selected. Extends "where did my space go?" beyond Browse.
- **Scan presets** — one-click "Quick safe clean" (Safe rules only) vs. full review; reduces first-run anxiety.
- **Per-rule toggles in Settings** — fine-grained "never show me X category" beyond the coarse ignore list.
- **Signed remote rule updates** — rules JSON fetched from a signed static feed so new cache rules don't wait for app updates; falls back to bundled rules offline.
- **CLI companion** — `macsweeper scan --json` for scripters. PRODUCT.md's "wrap existing CLI" alternative; revisit only if rule coverage stalls.
- **First-run onboarding** — 3-step tour (scan → review → clean) + Full Disk Access preflight explanation before it's ever requested.

## 🚫 Not planned, on purpose

The product philosophy draws a hard line. These stay out unless the philosophy changes (which would be a MAJOR discussion, not a feature):

- 🚫 Treemap / visual canvas disk maps (list drill-down is the chosen form)
- 🚫 Malware scanning, "RAM cleaner," fake optimization
- 🚫 Live menu-bar monitoring / widgets / background daemons
- 🚫 `sudo`, system `/private/var` deep cleans, paths outside `~` (except top-level `/Applications/*.app` bundles)
- 🚫 Shell-out to `brew` / `docker` (Manual guides with copyable commands only)
- 🚫 App uninstaller / launch-agent / login-items manager
- 🚫 Subscriptions, tip jars, upsells, scare tactics — free forever
- 🚫 App updater built in-house (Sparkle is the chosen path if/when updates ship)

---

## Prioritization: how an idea earns a version slot

1. **Safety first** — does it keep the preview-always, home-only, risk-labeled promises intact?
2. **User trust over feature count** — transparency (sizing, reports, ignore list) beats new cleaning categories.
3. **Cheap wins ship early** — JSON rules and copy fixes ride along with any release.
4. **One phase ≈ one MINOR release** — scoped, shippable, with tests before the next phase starts.

*Shipped something? Move it to ✅, check its boxes, bump this file's "Current release", and add the git tag per the release ritual.*
