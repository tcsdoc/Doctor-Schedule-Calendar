# PSC Share Link Fix — July 2026

**Date:** July 17, 2026  
**Branch:** `v4.4-dev`  
**Apps:** Provider Schedule Calendar (owner) → ScheduleViewer (participant)  
**Symptom:** ScheduleViewer showed **Share not found** when pasting a PSC share URL (different Apple ID iPad).

---

## Problem

SV failed at `CKFetchShareMetadataOperation` with CloudKit server error `notFound` / “Share not found”, for URLs such as:

```text
https://www.icloud.com/share/044-9TFr7cA6JXQNVHABRmOEw#Provider_Schedule_2025
```

The `#Provider_Schedule_2025` fragment showed PSC was still issuing (or reusing) a **stale 2025** zone share whose CloudKit short token was no longer valid. Pasting via Notes was not the cause.

### Root cause

1. **Wrong “broken share” heuristic** in `getOrCreateZoneShare()` treated **owner-only** shares as broken and deleted them. For `.readOnly` **link** shares, owner-only is normal — ScheduleViewer is designed for anyone-with-the-link access.
2. That delete/recreate cycle (and reuse of old multi-participant / prior-year shares) left recipients holding **dead short tokens**.
3. An older doc (`_archive/docs/CLOUDKIT_SHARING_FIX_DOCUMENTATION.md`, Sept 2025) recommended deleting owner-only shares; that guidance is **superseded** for the link-share model.

---

## Fix (PSC)

### Behavior (final — permanent link model, July 17, 2026)

| Action | Behavior |
|--------|----------|
| **Share** | **Reuses the permanent link** — returns the existing `.readOnly` zone share's URL every time (creates one only if none exists, or replaces one that is invite-only/URL-less). Tapping Share never breaks existing viewers. Shows “Preparing…” while CloudKit works. |
| **Manage → Reset Share Link** | The **only** destructive path: deletes the share, issues a fresh link, permanently disables all previously distributed URLs. |
| **Manage → Manage Existing Share** | Opens `UICloudSharingController` for the current share (unchanged). |

> Earlier on July 17 the fix briefly made **Share** always recreate the link. That
> was reversed the same day: one stable link forever, Reset is the only kill switch.
> The title-year check (which would have silently invalidated the link every
> January) was also removed; the share title is now year-less
> (“Provider Schedule Calendar”). Security posture is deliberate: the link grants
> read-only schedule access and distribution is tightly controlled by the clinic —
> aggressive link rotation is unnecessary and was causing the breakage.

Share message text now tells the recipient to paste the link into ScheduleViewer **Add Share**.

### Code

| File | Change |
|------|--------|
| `SimpleCloudKitManager.swift` | `createCustomZoneShare()` requires a non-nil URL and logs permission/URL. `getOrCreateZoneShare()` keeps only current-year `.readOnly` shares with a URL (owner-only OK). Added `recreateZoneShare()`. |
| `ScheduleViewModel.swift` | `createShare()` / `recreateShare()` call `recreateZoneShare()`. |
| `ContentView.swift` | Share preparation UI; Manage confirmation dialog with Reset; validate `.readOnly` before presenting the share sheet. |

### Intended share model (unchanged product intent)

- Container: `iCloud.com.gulfcoast.ProviderCalendar` (Production)
- Zone: `ProviderScheduleZone`
- Share: zone-level `CKShare` with `publicPermission = .readOnly`
- SV: paste `https://www.icloud.com/share/...` into Add Share (different Apple ID OK)

---

## How to verify

1. Rebuild/run updated PSC on the admin device.
2. Tap **Share** once; wait for Preparing… then the system share sheet.
3. Confirm URL fragment is current year (e.g. `#Provider_Schedule_2026`), not 2025.
4. Copy that **new** URL only (discard old Notes links).
5. On ScheduleViewer (other Apple ID): **Add Share** → paste → accept succeeds and schedule data loads.

If SV still says Share not found: use **Manage → Reset Share Link**, then paste the newest URL only.

---

## Notes for operators

- Each **Share** / **Reset** invalidates the previous link; existing SV users must paste the new URL once.
- Do not reuse old Notes/email links after Reset.
- iCloud Drive being on is not required for this path; both devices need an active iCloud account and network.
- User-facing copy in the app should continue to say **Cloud**, not CloudKit (charter).

---

## Related docs

- `PSC_STATUS.md` — project status / roadmap
- `PSC_CLOUDKIT_SUPPORT_HANDOFF.md` — container / console / support ticket context
- `_archive/docs/CLOUDKIT_SHARING_FIX_DOCUMENTATION.md` — historical; owner-only ≠ broken for link shares
