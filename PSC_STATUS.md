# PSC — Project Status & Roadmap

**Updated:** July 17, 2026  
**Repo:** https://github.com/tcsdoc/Doctor-Schedule-Calendar  
**Charter:** One admin (Lisa), one iPad, manual Save, memory master while editing, Cloud backup + zone share for ScheduleViewer, printed master = ultimate integrity reference, KISS, grid layout sacred, no code without explicit approval. User-facing text says **Cloud**, not CloudKit.

---

## Current state

| Item | Status |
|------|--------|
| **Production branch (`main`)** | **v4.3** (build 5) — local cache, offline Save, network monitor, Documents PDF |
| **App Store** | v4.3 submission in progress (Mark, July 2026) — replaces Xcode dev install |
| **Active dev branch** | **`v4.4-dev`** — Phases 1–5 complete (July 4, 2026). **July 17, 2026:** ScheduleViewer “Share not found” fix — Share always issues a fresh `.readOnly` link; Manage → Reset Share Link. See `PSC_SHARE_LINK_FIX_July2026.md`. Still pending: device verify share accept on SV, then merge → `main` / App Store when ready |
| **Admin iPad (Lisa)** | **v4.4 (3)** installed July 4, 2026 — full test pass same day (launch, edit/save/relaunch, delete-and-relaunch, clear-then-refill); **data integrity confirmed**. Soaking in normal use |
| **Test iPad (testbed)** | **v4.4 (3)** validated July 4, 2026 — separate Apple ID (tcsdoc@mac.com), disposable data. 4-round test: (1) 20 entries verified field-by-field in CloudKit via `cktool`; (2) delete + clear-then-refill; (3) force-quit with unsaved edit survives via cache, save lands server-side; (4) **duplicate injection**: UUID-named twin injected via cktool → app detected it, Fix Now kept most-recent winner, and editing the UUID-named survivor updated in place (no new duplicate) — direct proof of the Phase 3 fix against the Oct 2024 failure mode |
| **Git tag** | **`v4.3`** on `main` |
| **ScheduleViewer** | Unchanged for this fix — PSC must issue a new workable link; paste into SV Add Share |
| **May 2026 CALL issue** | **CLOSED** July 2026 — one-time glitch, never recurred (see support handoff doc) |
| **SV share accept (July 2026)** | **In progress** — root cause was stale/dead PSC short tokens + wrong owner-only “broken share” delete logic; fix on `v4.4-dev` (not pushed) |

**Header on admin build:** `PSC v4.4 (3)`

**CloudKit CLI access (for server-side verification):** `xcrun cktool` with a user token
(`xcrun cktool save-token --type user` — interactive, token lasts hours). Team `KSFQHNX4S8`,
container `iCloud.com.gulfcoast.ProviderCalendar`, environment **production** (entitlements pin
Production even for Xcode installs), private DB, zone `ProviderScheduleZone`. Note: CloudKit web
console container picker is broken (reverts to default container) — use cktool instead.
Containers can never be deleted from an Apple developer team; ignore the strays.

---

## What has been accomplished

### v4.2 — shipped on `main` (tag `v4.2`)

**UI / keyboard (grid unchanged)**

- Removed full-screen tap that blocked focus
- **Build 6:** `scenePhase` background → active recreates calendar/note editors (overnight resume fix)
- Tab → next in-month day (OS field only)
- Auto **`1/2` → `½`** while typing

**Data integrity**

- Monthly note delete when both lines cleared + Save
- Partial Save retry — failed Cloud writes stay in pending queue
- Share decoupled from Save gate (later refined in v4.3)

**Docs:** `PSC_v4.2_WEEK_TESTING_HANDOFF.md`

---

### v4.3 — shipped on `main` (tag `v4.3`)

**Problem solved:** Cold launch with no network showed empty calendar; offline Save could lose data on force quit.

**Local cache (`ScheduleLocalCache.swift`)**

- JSON in Application Support — written on **every edit** (schedules, notes, pending keys)
- Launch: cache first, then Cloud merge
- Pending local keys **not** overwritten by Cloud on sync

**Offline reliability**

- Offline Save → saved on iPad + PDF; alert says **not saved to the Cloud**
- Force quit survives all local edits (June 4 class bug fixed)

**Network & status (`ScheduleViewModel.swift`, `ContentView.swift`)**

- `NWPathMonitor` + `isOffline` — banner clears when airplane mode off (no stale offline)
- Cloud sync on reconnect only (not every foreground)
- Clear header states:

| Header | Meaning |
|--------|---------|
| **Saved on iPad — not to Cloud** (yellow) | On iPad; tap **Save** for Cloud |
| **📴 Offline — schedule as of …** | No network |
| **Syncing with Cloud…** | Cloud merge in progress |
| **✅ Ready** | iPad and Cloud in sync |
| **⚠️ Cloud Issue** | Cloud problem |

**Master PDF (`CalendarPDFGenerator.swift`)**

- **`Provider Schedule Master.pdf`** in Documents on full Save (online or offline-only)
- Same layout as Print; stamp on first page
- **Print** does not write Documents — **Save** does
- Lisa: one trivial edit + Save after install to seed PDF

**Other**

- Share independent of daily Save workflow
- Header shows version **and build**: `v4.3 (5)`

**Docs:** `PSC_v4.3_OFFLINE_HANDOFF.md`

**Key commits (newest first):**

| Commit | Summary |
|--------|---------|
| `c5ad8d8` | Build number in header |
| `e84dd7e` | Yellow pending-sync message; build 5 |
| `7709ef0` | Network handler compile fix |
| `2ec6690` | Path monitor; stale offline banner fix |
| `9acb3bf` | Persist edits locally offline |
| `47dca45` | Master PDF to Documents |
| `70f81ac` | Decouple Share from Save |
| `be6b807` | Local schedule cache |

---

## Save model (v4.3)

| Event | Memory | JSON cache | Documents PDF | Cloud |
|-------|--------|------------|---------------|-------|
| Edit | ✓ | ✓ | — | — |
| Save online (full success) | ✓ | ✓ | ✓ | ✓ |
| Save offline | ✓ | ✓ | ✓ | ✗ |
| Force quit | Reload from cache | survives | last Save | last Save |

**Do not delete the app** when updating from Xcode — Run over existing install preserves cache.

---

## v4.4 improvement roadmap (agreed July 2026)

**Branch:** `v4.4-dev` from `main` (v4.3). `main` = working backup; no direct commits.
**Goal:** Safer, leaner foundation — not new features. Grid layout sacred.
**Per-phase approval required before any code.**

| Phase | Work | Why |
|-------|------|-----|
| **1** ✅ | **Edit-session merge guard** — DONE July 3, 2026. Merge deferred while a field is focused or keystroke within last 30s; re-check every 10s; 5-min cap. Also: `ITSAppUsesNonExemptEncryption=false` in Info.plist; deployment target 17.0 → 26.0 | Closes the last race window: reconnect-triggered sync landing mid-edit (Lisa's interruption scenario). Typed data protected by pending keys regardless; guard removes mid-session view disruption |
| **2** ✅ | **Launch scan consolidation** — DONE July 4, 2026, build 4.4 (2). One `fetchAllData()` scan per record type; most-recently-modified duplicate wins in both display and cleanup; duplicate alert driven by load result; grid re-syncs after "Fix Now" | Approved in v4.2 handoff §2; fetch loop and cleanup previously disagreed on which duplicate wins |
| **3** ✅ | **Preserve CloudKit recordName on parse** — DONE July 4, 2026, build 4.4 (3). Parsed records carry true `recordID.recordName`; deletes target captured true IDs (with deterministic fallback); clear-then-refill before Save keeps original identity. **Tested on device July 4 — all tests passed, data integrity confirmed** | Closes last known duplicate-creation path (Oct 2024 outbreak mechanism); proposed Nov 2024 in `PSC_DUPLICATE_INVESTIGATION.md` |
| **4** ✅ | **Unit tests** — DONE July 4, 2026. 19 tests in `Provider Schedule CalendarTests` (Swift Testing): model IDs incl. UTC-boundary + legacy-ID preservation, Codable round-trips, `ScheduleLocalCache` round-trip/overwrite, view-model update/clear/refill-identity, merge rules (cloud wins vs pending survives vs pending deletion stays), monthly notes. Run: `xcodebuild test -scheme "Provider Schedule Calendar" -only-testing:"Provider Schedule CalendarTests"` on any iPad simulator. Only app-code change: `mergeCloudKitData` access `private` → internal. Cache-file tests serialized via `CacheFileGate` lock (Swift Testing runs concurrently; cache is one fixed file) | Ends reliance on week-long iPad soak tests for confidence |
| **5** ✅ | **ContentView decomposition** — DONE July 4, 2026, build 4.4 (4). Mechanical split, 1,296 → 626 lines: `CalendarGridViews.swift` (grid: `MonthCalendarView`, `DayEditCell`, `ScheduleTextField`, `CalendarFocusField`), `MonthlyNotesViews.swift`, `SharingSupport.swift`, `DuplicateViews.swift`, `SupportTypes.swift`. Moved code verified byte-identical vs git HEAD (only deviation: `normalizeProviderText` lost `private` for cross-file use). All 19 unit tests green post-split. **Device-verified on testbed July 4** (6-point check incl. print/PDF) | Isolates the sacred grid; safer future edits |

Race-condition history (context for Phase 1): background CloudKit refresh used to
overwrite text Lisa was typing when interruptions left sessions open. Fixed
incrementally: pending-keys protection (committed edits safe) → v4.3 removed
foreground sync (refresh only at launch + network reconnect). Remaining window:
reconnect sync during active editing. Manual Save model is deliberate and stays.

---

## Next phase detail — launch scan consolidation (Phase 2)

### Problem: four CloudKit zone scans on every launch

| # | Query | Purpose |
|---|--------|---------|
| 1 | `fetchAllSchedules` | Load grid (parsed) |
| 2 | `fetchAllMonthlyNotes` | Load notes (parsed) |
| 3 | `fetchAllRawScheduleRecords` | Duplicate detection |
| 4 | `fetchAllRawMonthlyNoteRecords` | Duplicate detection |

Steps 3–4 re-fetch what 1–2 already pulled (`checkForDuplicatesOnLaunch` in `ContentView.swift`).

### Direction (approved in v4.2 handoff §2)

- **4 → 2 queries:** one shared fetch per record type → build UI dict **and** duplicate detection from same raw data
- **One duplicate winner rule** everywhere (load, cleanup, post-cleanup refetch): last successful Save / `modificationDate`; local `pendingChanges` keys still win for unsaved edits
- Refetch (or cache update) after “Fix Now” cleanup so UI matches Cloud

### Related docs

- `PSC_v4.2_WEEK_TESTING_HANDOFF.md` — Post v4.2 approved direction
- `PSC_DUPLICATE_INVESTIGATION.md` — historical duplicate root-cause investigation

### Not in scope (later / separate)

- ScheduleViewer offline cache
- Apple ticket **#102899427910** (CloudKit Dashboard access — observability only)

---

## Resume checklist

### v4.3 merge — complete (July 2026)

1. ~~Admin testing~~ — complete, no issues reported
2. ~~Merge `reliability-offline` → `main`~~ — done
3. ~~Tag **v4.3**~~ — done
4. **Next:** Plan App Store submission for Lisa (Xcode dev install is not long-term distribution)

### When starting next PSC dev phase

1. Open folder: `/Users/mark/Desktop/Provider Schedule Calendar`
2. New Agent or resume PSC chat — **not** ExpenseTracker chat
3. Say: *“Continue PSC — read `PSC_STATUS.md`. Start launch scan consolidation.”*
4. New branch from merged `main`; no code without explicit approval

### When switching to other projects (e.g. ExpenseTracker)

- **File → Open Folder** → other project
- **New Agent** — keep PSC context in this chat / PSC folder history
- PSC state is in this repo + GitHub `main` (tag `v4.3`)

---

## Key files

| File | Role |
|------|------|
| `ScheduleViewModel.swift` | Load, Save, cache, offline, network monitor |
| `ScheduleLocalCache.swift` | JSON cache + pending keys |
| `ContentView.swift` | Header, Save alerts, focus refresh, duplicate UI |
| `SimpleCloudKitManager.swift` | Cloud fetch/save/share, duplicate scan/cleanup |
| `CalendarPDFGenerator.swift` | Print + Documents PDF |

---

## Document index

| Document | Contents |
|----------|----------|
| **`PSC_STATUS.md`** (this file) | Master status, accomplishments, roadmap |
| `PSC_SHARE_LINK_FIX_July2026.md` | July 2026 SV “Share not found” fix — fresh `.readOnly` links |
| `PSC_v4.3_OFFLINE_HANDOFF.md` | v4.3 technical handoff |
| `PSC_v4.2_WEEK_TESTING_HANDOFF.md` | v4.2 testing + post-v4.2 direction |
| `PSC_DUPLICATE_INVESTIGATION.md` | Duplicate root-cause notes |
| `PSC_CLOUDKIT_SUPPORT_HANDOFF.md` | Apple support ticket context |
