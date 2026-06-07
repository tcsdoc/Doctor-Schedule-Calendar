# PSC v4.3 — Offline Local Cache

**Branch:** `reliability-offline`  
**Version:** 4.3 (build 5)  
**Status:** Test iPad validated — ready for admin iPad install before merge to `main`

---

## Test iPad results (build 4–5)

All core tests passed:

- Online Save + Documents PDF
- Edit survives force quit (local cache)
- Offline Save + force quit (June 4 scenario)
- Airplane mode on/off without closing app (banner + sync)
- Focus after background
- Cold launch offline (optional)

One month exercised; same code path for all dates/months.

---

## Status messages (build 5)

| Header | Meaning |
|--------|---------|
| **Saved on iPad — not to Cloud** (yellow) | Edits on iPad (memory + cache); tap **Save** when online for Cloud |
| **📴 Offline — schedule as of …** | No network path |
| **Syncing with Cloud…** | Cloud merge in progress |
| **✅ Ready** | iPad and Cloud in sync |
| **⚠️ Cloud Issue** | Cloud problem (red) |

User-facing text says **Cloud**, not CloudKit.

---

## Dynamic offline banner (build 4)

- **`isOffline`** tracks network path (NWPathMonitor), not cache writes
- Turning airplane mode **off** clears offline banner and **Syncing with Cloud…** runs automatically (path monitor only — no sync on every foreground)
- **`scenePhase` active:** editor refresh only when returning from background (focus fix); no Cloud sync

---

## Local persistence (build 3)

- **Every edit** writes the JSON cache (schedules, notes, pending keys) — survives force quit offline
- **Save offline:** saved locally on iPad; alert says **not saved to the Cloud** (no internet). JSON cache + Documents PDF updated.
- **Save online (full success):** Cloud + cache + PDF
- **Launch Cloud sync:** pending local edits are **not** overwritten by Cloud data

---

## Master PDF backup

On every **full successful Save** (and offline-only Save):

- Writes **`Provider Schedule Master.pdf`** to **Documents** (overwrite single file)
- Same 12-month layout as Print, with first-page stamp
- PDF failure is logged only — does not fail Save

---

## First install of v4.3

Open PSC **once with network** after installing so the cache file is created from Cloud. After that, offline cold launch works.

**Do not delete the app** when updating from Xcode — Run over existing install preserves local cache.

---

## Files

| File | Role |
|------|------|
| `ScheduleLocalCache.swift` | Read/write `schedule_cache.json` |
| `ScheduleViewModel.swift` | Cache-first load, network monitor, persist on edit/Save |
| `ContentView.swift` | Header states, Save alerts, focus refresh |
| `CalendarPDFGenerator.swift` | Print + Documents PDF |

---

## Not in v4.3 (later)

- Launch scan consolidation (four → two CloudKit queries)
- Duplicate winner rule unification
- ScheduleViewer offline cache

---

## Next step

Admin iPad install from `reliability-offline` → merge to `main` + tag **v4.3** when Lisa sign-off complete.
