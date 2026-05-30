# PSC CloudKit Support Handoff

**Created:** May 25, 2026  
**Purpose:** Resume PSC/SV work when Apple Developer Support responds, or when admin iPad check is done.

---

## Apple Developer Support Ticket

| Field | Value |
|-------|--------|
| **Ticket #** | **102899427910** |
| **Submitted** | May 25, 2026 |
| **Topic** | Development and Technical (email) |
| **Issue** | CloudKit Console will not switch containers |

### Message sent (summary)

CloudKit Console stuck on `iCloud.com.gulfcoast.Calendar`; cannot select `iCloud.com.gulfcoast.ProviderCalendar`. Direct URL returns Forbidden. Act As iCloud Account drops when changing containers. Need Production private DB query for admin data.

**Developer account:** `tcsdoc@mac.com`  
**Team:** Marlix Holdings, LLC (Team ID `KSFQHNX4S8`)  
**Admin iCloud (Act As):** `lisalisa_39564@yahoo.com`  
**App bundle IDs:** `com.gulfcoast.ProviderCalendar`, `com.gulfcoast.ScheduleViewer`

### Already tried (before ticket)

- Sign out/in; private browser window; cleared website data for icloud.developer.apple.com
- Direct URL (Forbidden):  
  `https://icloud.developer.apple.com/dashboard/database/teams/KSFQHNX4S8/containers/iCloud.com.gulfcoast.ProviderCalendar/environments/production`
- Xcode → Signing & Capabilities → CloudKit Console button
- Manage Containers hide/show (stuck session on hidden `.Calendar`)
- **App ID cleanup (done):** Both apps now assigned **only** `iCloud.com.gulfcoast.ProviderCalendar` (removed `.Calendar` and `.ProviderCalendar.dev`)

### If Apple asks for screenshots

- Container dropdown showing `ProviderCalendar` vs header still showing `.Calendar`
- "No Containers" when personal Mark Harvey team selected (wrong team — need Marlix)
- Only `_defaultZone` visible before correct container selected

---

## Correct CloudKit Configuration (Reference)

| Setting | Value |
|---------|--------|
| **Console URL** | https://icloud.developer.apple.com/dashboard/ |
| **Login** | `tcsdoc@mac.com` (NOT Lisa's email for main login) |
| **Team** | Marlix Holdings, LLC — NOT personal "Mark Harvey" team |
| **Container** | `iCloud.com.gulfcoast.ProviderCalendar` |
| **NOT used** | `.Calendar`, `.Calendar2024`, `.ProviderCalendar.dev`, other legacy containers |
| **Environment** | **Production** (App Store PSC) |
| **Database** | Private Database |
| **Zone** | `ProviderScheduleZone` (legacy v3: `user_com.gulfcoast.ProviderCalendar`) |
| **Daily records** | `CD_DailySchedule` — OS=`CD_line1`, CL=`CD_line2`, OFF=`CD_line3`, CALL=`CD_line4` |
| **Monthly notes** | `CD_MonthlyNotes` — `CD_line1`, `CD_line2`, `CD_line3` |

### Act As workflow (when console works)

1. Select container + **Production** FIRST (before Act As)
2. Act As → `lisalisa_39564@yahoo.com`
3. Do NOT change container/environment after Act As (drops session)
4. Query Records → zone `ProviderScheduleZone` → type `CD_DailySchedule`

---

## Open Investigation: Missing CALL Data

**Reported:** May 2026 CALL empty on May 29–30 in screenshot; May 31 may be off-screen (scroll).

**Leading hypotheses (discussion only — no code changes approved):**

1. Duplicate records — wrong duplicate wins on fetch
2. Save overwrote CALL with empty
3. Partial save bug — **fixed in v4.2** (pending retry); was hypothesis for missing CALL
4. Display/scroll vs true CloudKit loss

**Critical check (no dashboard needed):** PSC on admin iPad → May 2026 → CALL on May 29–31.

| iPad shows CALL | Dashboard empty | Conclusion |
|-----------------|-----------------|------------|
| Yes | Yes | Dashboard/access issue |
| No | No | Real data issue |
| Yes | — | SV/share/display issue if SV differs |

**Printed master schedule** = ultimate integrity reference per charter.

---

## PSC Foundation (Confirmed — Do Not Change Without Approval)

- One admin, one iPad, manual Save only, CloudKit on Save
- Memory is master while editing; CloudKit is backup + share
- Zone share `.readOnly` to ScheduleViewer
- No code changes without explicit user approval
- Any PSC CloudKit change must consider SV impact

---

## Other Known PSC Issue (Deferred)

**Idle tap failure:** ~~After days idle, TextFields won't accept tap~~ **Addressed in v4.2** — removed full-screen `onTapGesture`. **Watch during one-week admin test** (May 28, 2026 start). Rollback: App Store v4.1.

---

## v4.2 Status (May 28, 2026)

**Branch:** `fix-ui-bug` | **Tag:** `v4.2-week-testing` | **Admin:** Xcode install, data OK, admin approved UX

See **`PSC_v4.2_WEEK_TESTING_HANDOFF.md`** for full notes, Git refs, and post-week checklist.

**Fixed in v4.2:** focus/Tab/`½`, monthly note CloudKit delete, partial save retry, debug/repo cleanup.

**`main`:** not merged until week testing completes.

---

## When Apple Responds — Next Steps

1. Note what they asked you to try; reference ticket **102899427910**
2. Confirm console opens `ProviderCalendar` + Production
3. Act As Lisa → query `CD_DailySchedule` in `ProviderScheduleZone`
4. Check `CD_line4` for May 29–31, 2026; look for duplicate records same date
5. Resume discussion with agent; no PSC code until user approves

## If Console Never Fixed — Alternatives

- Admin iPad PSC as source of truth
- Printed master schedule
- `cktool` with management token (CloudKit Console → profile Settings) — future option

---

## Key File Paths

**PSC:** `/Users/mark/Desktop/Provider Schedule Calendar/`  
- `SimpleCloudKitManager.swift` — CloudKit fetch/save, zone `ProviderScheduleZone`  
- `ScheduleViewModel.swift` — manual save  
- `ContentView.swift` — UI, focus/Tab, Save/Share/Print  

**SV:** `/Users/mark/Desktop/ScheduleViewer/`  
- `CloudKitManager.swift` — read-only shared zone  
