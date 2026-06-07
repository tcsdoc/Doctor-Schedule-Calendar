# PSC v4.3 — Offline Local Cache

**Branch:** `reliability-offline`  
**Version:** 4.3 (build 1)  
**Status:** In development — install from Xcode for admin test after one online launch seeds cache

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
- Printed master = ultimate integrity reference
- Grid layout unchanged
