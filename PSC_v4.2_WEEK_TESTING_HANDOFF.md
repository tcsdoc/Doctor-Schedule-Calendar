# PSC v4.2 — Admin Week Testing Handoff

**Updated:** May 28, 2026  
**Branch:** `fix-ui-bug` (not merged to `main` until week testing completes)  
**Git tag:** `v4.2-week-testing`  
**Version:** 4.2 (build 5)

---

## Current Production State (Admin iPad)

| Item | Status |
|------|--------|
| **Device** | Lisa's admin iPad (Magic Keyboard workflow) |
| **Install method** | Xcode Run from `fix-ui-bug` (development-signed) |
| **Header** | `PSC v4.2` confirmed |
| **CloudKit** | All data loaded on first launch |
| **Admin feedback** | Happy — behavior matches how she uses the app; especially likes auto `1/2` → `½` |
| **Rollback** | App Store reinstall → v4.1 (CloudKit data unchanged) |

**Test iPad (IPadM1):** `tcsdoc@mac.com` — full regression passed before admin install.

---

## What v4.2 Changed (Shipped on `fix-ui-bug`)

### Phase A — UI / keyboard (no layout change)

- Removed full-screen tap that called `resignFirstResponder` (idle tap / focus fix)
- **Tab** → next in-month day, **OS only** (last day of month stays put)
- Auto **`1/2` → `½`** while typing (all schedule fields + monthly notes)
- **Return** unchanged — no navigation job

### Data integrity

- **Monthly note delete:** Clearing both lines + Save now deletes CloudKit record (was silent no-op; data returned on relaunch)
- **Partial save retry:** Failed CloudKit writes stay in pending queue; Save button remains active for retry (was `removeAll()` — possible lost CALL / day data on iCloud blips)
- **Share:** Blocked if pre-share Save incomplete
- **Duplicate cleanup:** Alerts if post-cleanup Save fails

### Cleanup (no user-visible change)

- DEBUG logging trimmed to errors/warnings only (~131 → ~33 calls)
- Dead UI helpers removed
- Historical builds/docs moved to `_archive/`

### Monthly notes — two lines in UI, three in CloudKit (by design)

**UI shows Line 1 and Line 2 only.** A third line was removed so the **6-week calendar fits on iPad without scrolling** while keeping day cells legible — admin/layout decision, not an oversight.

**CloudKit / model still include `line3` (`CD_line3`):**

- Schema compatibility with existing records and ScheduleViewer
- No migration or field removal planned
- **Do not** delete `line3` from model or save/fetch in future “cleanup” work

---

## GitHub Backup

| Ref | Commit | Notes |
|-----|--------|-------|
| `pre-phase-a-2026-05-25` | `51df980` | Restore point before UI work |
| `fix-ui-bug` | `c31c062` | Latest — all v4.2 work |
| `main` | `51df980` | **Unchanged** — pre–Phase A until week test passes |
| Tag `v4.2-week-testing` | `c31c062` | Bookmark for admin week test start |

**Repo:** https://github.com/tcsdoc/Doctor-Schedule-Calendar/tree/fix-ui-bug

---

## One-Week Testing — What to Watch

Ask Lisa to notice (no special test script — normal work):

| Watch for | Was issue | v4.2 fix |
|-----------|-----------|----------|
| Tap field after app idle | Sometimes dead until reboot | Root tap gesture removed |
| Tab through month | Went OS→CL→OFF→CALL | Tab → next day OS |
| Typing `1/2` | Needed Return for `½` | Auto while typing |
| Clear both monthly note lines + Save | Came back on relaunch | CloudKit delete |
| Save during bad network | Some days lost silently | Pending retry |

**Still manual Save only.** Printed master schedule = ultimate reference.

**Console noise under Xcode:** LaunchServices -54, share sandbox URLs, CA launch metrics — system noise; ignore unless on-screen behavior breaks.

---

## After One Week — Resume Checklist

1. Any tap/Tab/`½`/Save issues reported? (Notes + dates)
2. If clean → merge `fix-ui-bug` → `main`, tag `v4.2`, plan App Store submission for Lisa (Xcode dev install is not long-term distribution)
3. If issues → stay on branch; rollback admin to App Store 4.1 if needed; fix on `fix-ui-bug` only
4. Apple ticket **#102899427910** — still open if dashboard access needed
5. SV unchanged — no SV release required for PSC v4.2 unless share/schema touched (not in this release)

---

## Key Files (v4.2)

| File | Role |
|------|------|
| `ContentView.swift` | Focus/Tab, calendar UI, Save/Share/Print |
| `ScheduleViewModel.swift` | Pending save + partial retry |
| `SimpleCloudKitManager.swift` | CloudKit + `deleteMonthlyNote()` |
| `DebugLogger.swift` | `#if DEBUG` only |

---

## Future exploration (after week test)

- **Under the hood only** — reliability/integrity (Save, launch, Share); admin wants **no new features**
- New work on a **separate branch** from `fix-ui-bug`; keep `fix-ui-bug` frozen during admin week test
- **`line3` is out of scope** for cleanup (see above)

---

- One admin, one iPad, manual Save
- No code without explicit approval
- KISS; grid layout sacred
- SV impact check for any future CloudKit schema change
