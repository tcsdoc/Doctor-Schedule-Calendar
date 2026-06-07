# PSC v4.3 — Offline Local Cache

**Branch:** `reliability-offline`  
**Version:** 4.3 (build 3)

---

## Local persistence (build 3 fix)

- **Every edit** writes the JSON cache (schedules, notes, pending keys) — survives force quit offline
- **Save offline:** saved locally on iPad; alert says **not saved to the Cloud** (no internet). JSON cache + Documents PDF path unchanged until online full Save.
- **User-facing text:** says **Cloud**, not CloudKit.
- **Save online (full success):** iCloud + cache + PDF
- **Launch CloudKit sync:** pending local edits are **not** overwritten by cloud data  
**Status:** In development — install from Xcode for admin test after one online launch seeds cache

---

## Master PDF backup (Lisa request)

On every **full successful Save**:

- Writes **`Provider Schedule Master.pdf`** to **Documents** (overwrite single file)
- Same 12-month layout as Print, with first-page stamp: **Updated June 6th, 08:32AM**
- Print button uses the same generator (stamp = time of print)
- iCloud Drive backup of Documents can sync PDF to Lisa’s other devices
- PDF failure is logged only — does not fail Save (CloudKit already succeeded)

---

## Purpose

PSC previously loaded saved schedule data **only from CloudKit**. No network on cold launch = empty calendar. Unacceptable during storms when admin must answer schedule/location calls.

**v4.3 adds an on-iPad JSON cache** in Application Support. CloudKit remains backup + share; local cache enables **offline read** (and normal editing in memory; Save still requires iCloud when online).

---

## Behavior

| Event | What happens |
|-------|----------------|
| **Launch with cache** | Grid fills **immediately** from cache; header may show “Syncing with iCloud…” |
| **CloudKit load succeeds** | Memory updated from CloudKit; cache rewritten; ✅ Ready |
| **CloudKit load fails (offline)** | Keep cache data; header **📴 Offline — schedule as of [date/time]** |
| **Launch with no cache (first install)** | Same as before — “Loading from CloudKit…” until fetch or failure |
| **Successful Save (all items)** | CloudKit + local cache updated; offline banner clears if set |
| **Partial Save** | Pending retry unchanged; cache **not** updated until full Save |

---

## First install of v4.3

Lisa should open PSC **once with network** after installing 4.3 so the cache file is created from CloudKit. After that, offline cold launch works.

---

## Files

| File | Role |
|------|------|
| `ScheduleLocalCache.swift` | Read/write `schedule_cache.json` |
| `ScheduleViewModel.swift` | Cache-first load, persist after sync/Save |
| `ContentView.swift` | Offline / syncing header states |

---

## Not in v4.3 (later)

- Launch scan consolidation (four → two CloudKit queries)
- Duplicate winner rule unification
- ScheduleViewer offline cache
- Queued Save while offline

---

## Charter

- Memory master while editing; Save pushes to CloudKit when possible
- iPad keeps local copy of last **fully saved** snapshot
- **Share / Manage:** zone access only — independent of Save (no save-before-share gate)
- Printed master = ultimate integrity reference
- Grid layout unchanged
