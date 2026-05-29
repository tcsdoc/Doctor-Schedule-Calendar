# PSC CloudKit Duplicate Investigation

**Status:** ACTIVE INVESTIGATION - Awaiting Real-World Data  
**Date Started:** November 7, 2024  
**Context:** Production app (v4.0+) experiencing intermittent CloudKit duplicate entries

---

## Executive Summary

The Provider Schedule Calendar app has experienced CloudKit duplicate entries during production use. The duplicates were successfully cleaned using the built-in repair feature, but the root cause remains unconfirmed. This document preserves the investigation for future troubleshooting when duplicates occur again.

---

## Observed Behavior

### What Happened (October 2024)

1. **September:** User entered schedule data for Sept-Nov (fields 1-3: OS, CL, OFF)
   - 3-month bulk entry
   - All saved successfully
   - No duplicates observed

2. **September:** Call schedule (field 4) entered for October
   - ~30 entries for October dates
   - All saved successfully
   - **No duplicates** - October data was clean

3. **October:** Call schedule (field 4) entered for November  
   - 26 entries for November dates
   - User verified CloudKit data was correct after save
   - **100% duplicate rate** - All 26 entries created duplicates
   - Duplicates discovered on next app launch
   - Built-in repair feature cleaned them successfully

### Key Patterns

- ✅ **October Call entries:** 0% duplicate rate (worked perfectly)
- ❌ **November Call entries:** 100% duplicate rate (all failed)
- **Workflow:** Bulk entry of fields 1-3, then later update field 4
- **Timing:** Duplicates appear when updating existing records, not creating new ones
- **Single user, single iPad** - No multi-device concurrency issues
- **Production app** - Published in App Store, v4.0.x

---

## Investigated Code

### Primary Suspect: ID Regeneration During Parse

**File:** `SimpleCloudKitManager.swift`  
**Function:** `parseScheduleRecord()` (lines 253-266)  
**Issue:** Creates new ScheduleRecord which regenerates ID instead of preserving CloudKit recordName

```swift
private func parseScheduleRecord(_ record: CKRecord) -> ScheduleRecord? {
    guard let date = record["CD_date"] as? Date else {
        redesignLog("❌ Invalid schedule record - missing date")
        return nil
    }
    
    return ScheduleRecord(
        date: date,  // ⚠️ This triggers init which regenerates ID
        os: record["CD_line1"] as? String,
        cl: record["CD_line2"] as? String,
        off: record["CD_line3"] as? String,
        call: record["CD_line4"] as? String
    )
    // ⚠️ Never reads the actual CloudKit record.recordID.recordName
}
```

**File:** `ScheduleViewModel.swift`  
**Struct:** `ScheduleRecord` (lines 278-298)  
**Issue:** Init regenerates ID from date instead of accepting CloudKit recordName

```swift
init(date: Date, os: String? = nil, cl: String? = nil, off: String? = nil, call: String? = nil) {
    self.date = date
    self.os = os
    self.cl = cl
    self.off = off
    self.call = call
    
    // Generate deterministic ID
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.timeZone = TimeZone(identifier: "UTC")
    self.id = "schedule_\(formatter.string(from: date))"  // ⚠️ Regenerates instead of preserving
}
```

### Hypothesized Failure Mechanism

**Scenario: Record ID Mismatch**

1. **Original Save (September):**
   - User enters Nov 1 data
   - Creates ScheduleRecord with id: `"schedule_2024-11-01"`
   - Saves to CloudKit with recordName: `"schedule_2024-11-01"`
   - ✅ Successful

2. **App Restart:**
   - Loads records from CloudKit
   - For each record, calls `parseScheduleRecord()`
   - Creates NEW ScheduleRecord, regenerates ID from date
   - If date parsing produces different ID (e.g., `"schedule_2024-10-31"`)
   - Stores in memory with wrong ID

3. **Update (October):**
   - User updates Call field for Nov 1
   - App has record in memory with id: `"schedule_2024-10-31"` (wrong)
   - Calls `saveSchedule()` which queries CloudKit for `"schedule_2024-10-31"`
   - CloudKit returns `.unknownItem` (actual recordName is `"schedule_2024-11-01"`)
   - App creates NEW record with recordName: `"schedule_2024-10-31"`
   - ❌ Result: Two records for same date with different recordNames

### Alternative Theories Considered

1. **Retry Logic Bug (RULED OUT)**
   - Lines 148-152 do remove all pending changes incorrectly
   - But 100% failure rate doesn't match intermittent retry issues

2. **Concurrent Save Operations (RULED OUT)**
   - Single user, single iPad eliminates multi-device race conditions
   - No evidence of rapid button clicking

3. **CloudKit Eventual Consistency (RULED OUT)**
   - Would cause intermittent failures (2-5%), not 100% failure rate

4. **Timezone/DST Issues (UNCONFIRMED)**
   - October worked, November failed
   - November 2024: DST transition Nov 3
   - Could affect date parsing, but needs verification

---

## Proposed Fix (UNIMPLEMENTED - AWAITING VERIFICATION)

### Change 1: ScheduleRecord Init

**File:** `ScheduleViewModel.swift` (lines 286-298)

```swift
// ADD optional id parameter
init(id: String? = nil, date: Date, os: String? = nil, cl: String? = nil, off: String? = nil, call: String? = nil) {
    self.date = date
    self.os = os
    self.cl = cl
    self.off = off
    self.call = call
    
    // Use provided CloudKit recordName if available
    if let existingId = id {
        self.id = existingId  // Preserve actual CloudKit recordName
    } else {
        // Generate new ID only for truly new records
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        self.id = "schedule_\(formatter.string(from: date))"
    }
}
```

### Change 2: Parse Function

**File:** `SimpleCloudKitManager.swift` (lines 253-266)

```swift
private func parseScheduleRecord(_ record: CKRecord) -> ScheduleRecord? {
    guard let date = record["CD_date"] as? Date else {
        redesignLog("❌ Invalid schedule record - missing date")
        return nil
    }
    
    // CRITICAL: Preserve actual CloudKit recordName
    let actualRecordId = record.recordID.recordName
    
    return ScheduleRecord(
        id: actualRecordId,  // Pass CloudKit's actual recordName
        date: date,
        os: record["CD_line1"] as? String,
        cl: record["CD_line2"] as? String,
        off: record["CD_line3"] as? String,
        call: record["CD_line4"] as? String
    )
}
```

### Similar Changes for MonthlyNote

Apply same pattern to `MonthlyNote` struct (lines 308-334) and `parseMonthlyNoteRecord()` (lines 268-283).

**Total Change Scope:** ~26 lines across 2 files, low complexity

---

## Critical Data to Collect When Duplicates Recur

### ⚠️ REVISED PLAN: STOP AND CONSULT BEFORE REPAIR

**When duplicate alert appears:**
1. ✋ **STOP using the app** - Do not run repair yet
2. 📱 **Open new Cursor chat** and say: "PSC duplicates occurred - read PSC_DUPLICATE_INVESTIGATION.md"
3. 🔍 **Collect data under AI guidance** - While duplicates still exist in CloudKit
4. 🔧 **Run repair with guidance** - AI will walk through the process
5. 📊 **Analyze results together** - Determine root cause and fix

---

### IMMEDIATE FIRST STEPS (When You Return to Cursor)

**Provide this information in your first message:**

```
PSC duplicates detected. Here's the initial info:

ALERT INFO:
- Duplicates detected: [number]
- Dates affected: [number]
- Type: Schedule and/or Monthly Notes

TIMELINE:
- Original data entry: [approximate date/month]
- Recent updates: [what you edited, when]
- Duplicates discovered: [today's date]

APP VERSION: [shown in header, e.g., v4.0.1]
```

Then I will guide you through:
1. Checking CloudKit Dashboard for specific records
2. Using duplicate detection UI to see recordNames
3. Running repair and examining the log
4. Validating the hypothesis with concrete evidence

---

### CloudKit Dashboard Access (For When Guided)

**URL:** https://icloud.developer.apple.com/dashboard  
**Steps I'll guide you through:**
1. Sign in with Apple Developer account
2. Select: iCloud.com.gulfcoast.ProviderCalendar
3. Navigate to: Private Database → ProviderScheduleZone
4. Query specific affected dates to see duplicate records
5. Compare recordNames, CD_date values, modification times

**What We'll Look For:**
- Exact recordNames of duplicate records
- Whether recordNames are identical or different
- Timestamps showing when each was created/modified
- Pattern across multiple affected dates

---

### App-Based Data Collection (For When Guided)

**Duplicate Detection UI:**
1. Screenshot the initial alert (count and dates)
2. Tap "Review Report" if available
3. Note any recordNames visible in the detail view
4. Do NOT tap cleanup yet - wait for guidance

**After Repair (When Instructed):**
- iPad → Files app → On My iPad → Provider Schedule Calendar → Documents
- Retrieve: `PSC_Duplicate_Cleanup_[timestamp].txt`
- This log shows exact recordNames that were duplicates

---

### Example of What We're Looking For

**Scenario A: Different RecordNames (Validates Hypothesis)**
```
CloudKit Query for Date: 2024-11-01
Record 1: schedule_2024-11-01 (created Oct 15, modified Oct 15)
Record 2: schedule_2024-10-31 (created Oct 20, modified Oct 20)
→ Conclusion: ID regeneration producing wrong dates
```

**Scenario B: Identical RecordNames (Refutes Hypothesis)**
```
CloudKit Query for Date: 2024-11-01
Record 1: schedule_2024-11-01 (created Oct 15, modified Oct 15)
Record 2: schedule_2024-11-01 (created Oct 20, modified Oct 20)
→ Conclusion: CloudKit allowed true duplicates - different root cause
```

---

## Validation Criteria

### If Hypothesis is CORRECT:

**Cleanup log will show:**
- Duplicates have DIFFERENT recordNames for same date
- Pattern like: `schedule_2024-11-XX` and `schedule_2024-10-XX`
- Suggests date parsing/formatting inconsistency

**This validates:** ID regeneration is producing different results

### If Hypothesis is INCORRECT:

**Cleanup log will show:**
- Duplicates have IDENTICAL recordNames
- Both records named `schedule_2024-11-01`
- CloudKit somehow allowed true duplicates

**This means:** Different root cause - CloudKit index issue or deeper bug

---

## Questions to Answer with Next Occurrence

1. **Are duplicate recordNames identical or different?** (from cleanup log)
2. **Is there a date offset pattern?** (e.g., all Nov dates show as Oct 31)
3. **Does October data remain clean?** (check if October records duplicated)
4. **Does December cause same issue?** (to test if November-specific)
5. **What are the exact modification timestamps?** (timing of duplicate creation)

---

## Additional Investigation Paths

### If Duplicates Have Different RecordNames

**Root Cause:** Date parsing/formatting inconsistency
- Check DST transition dates (Nov 3, 2024)
- Check device timezone settings
- Verify UTC formatting in both directions

**Fix:** Implement proposed changes above (preserve CloudKit recordName)

### If Duplicates Have Identical RecordNames

**Root Cause:** CloudKit consistency issue or unknown bug
- Check CloudKit operational status during save
- Review CloudKit zone configuration
- Consider CloudKit conflict resolution policies
- May need Apple DTS (Developer Technical Support) involvement

### If Pattern is Random/Inconsistent

**Root Cause:** Network/timing/concurrency issue
- Check for app backgrounding during save
- Check for Share button triggering concurrent saves
- Review line 910: post-cleanup save operation

---

## Code Quality Notes

The current codebase (v4.0.x) is high quality with:
- ✅ Proper fetch-before-save pattern (lines 112-130)
- ✅ Individual error handling (no cascade failures)
- ✅ CloudKit pagination implemented correctly
- ✅ Comprehensive logging throughout
- ✅ Built-in duplicate detection and repair

The issue is likely a subtle edge case that only manifests under specific conditions (date ranges, timing, workflow patterns).

---

## Version History

| Date | Event | Notes |
|------|-------|-------|
| Sept 2024 | Initial 3-month data entry | No issues |
| Sept 2024 | October Call entries | ✅ No duplicates |
| Oct 2024 | November Call entries | ❌ 26/26 duplicates |
| Oct 2024 | Duplicates cleaned | Repair feature successful |
| Nov 7, 2024 | Investigation documented | Awaiting recurrence |

---

## Next Steps

1. **Wait for next occurrence** - Do not attempt to force reproduction
2. **Collect data per checklist** - Prioritize cleanup log file
3. **Share findings** - Provide cleanup log and timeline
4. **Validate hypothesis** - RecordName comparison is key
5. **Implement fix if validated** - Make proposed code changes
6. **Test thoroughly** - Verify fix with December data entry

---

## Contact Information for Future AI Assistants

**Project:** Provider Schedule Calendar (PSC)  
**Container:** iCloud.com.gulfcoast.ProviderCalendar  
**Zone:** ProviderScheduleZone  
**Database:** Private CloudKit Database  
**Platform:** iPad-only, iOS production app  
**User Profile:** Single administrator, bulk data entry workflow  

**Key Files:**
- `SimpleCloudKitManager.swift` - CloudKit operations
- `ScheduleViewModel.swift` - Data models and business logic
- `ContentView.swift` - UI and user actions

**Critical Pattern:** Fields 1-3 entered in bulk, field 4 updated incrementally

---

**END OF INVESTIGATION DOCUMENT**

*This document should be updated when new data becomes available.*

