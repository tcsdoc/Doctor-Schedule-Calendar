# PSC Troubleshooting Guide

## Quick Reference for Common Issues

### 🚨 Emergency Data Recovery
If you suspect data loss, **STOP** and follow these steps immediately:

1. **Don't make more changes** - could overwrite recoverable data
2. **Check CloudKit dashboard** - data might still exist in duplicates
3. **Reference printed master schedule** - user has authoritative copy
4. **Look for multiple records** with same date but different content
5. **Contact user immediately** - they have the medical reference data

## Data Display Issues

### Partial Data Showing on Device
**Symptoms**: Some fields missing (e.g., OS and CL empty, but CALL has data)

**Diagnosis**:
```bash
# Check CloudKit for multiple records with same date
# In CloudKit dashboard, filter by date and look for duplicates
```

**Causes**:
1. **Multiple CloudKit records** for same date (most common)
2. **Fetch logic displaying wrong record** from multiple duplicates
3. **Local memory corruption** (less likely)

**Solution**:
1. **Clean up duplicates** in CloudKit dashboard
2. **Keep most complete record** for each date
3. **Fix save logic** to prevent future duplicates

### Data Appears on One Device But Not Another
**Symptoms**: Administrator sees data, but test device doesn't

**Diagnosis Steps**:
1. **Verify Apple ID** - both devices signed into same account?
2. **Check CloudKit status** - `cloudKitAvailable` flag
3. **Verify custom zone** - "ProviderScheduleZone" exists?
4. **Check network connectivity** - CloudKit sync working?

**Common Causes**:
- **Sync delay** - CloudKit propagation takes time
- **Unsaved data** - local memory not pushed to CloudKit yet
- **Zone issues** - custom zone not properly created
- **Duplicate records** - devices showing different duplicates

## CloudKit Issues

### Duplicate Records
**Detection**:
```sql
-- In CloudKit dashboard, look for:
-- Multiple records with same CD_date value
-- Same date but different recordIDs
SELECT recordName, CD_date, CD_line1, CD_line2, CD_line3, CD_line4 
FROM CD_DailySchedule 
ORDER BY CD_date, recordName
```

**Current Known Duplicates** (September 2025):
- **September 4th**: A73E5503-7683-4118-8... and D8E7ADD7-CF92-4089-...
- **September 5th**: Multiple records, some incomplete

**Cleanup Process**:
1. **Compare with printed master schedule**
2. **Keep record that matches master exactly**
3. **Delete all other duplicates**
4. **Test fetch on both devices**

**Prevention** (Code Fix Needed):
```swift
// Current problem:
let recordID = CKRecord.ID(recordName: UUID().uuidString, zoneID: customZone.zoneID)
// Always creates new record

// Fix needed:
// Query for existing record by date first
// If exists: update existing
// If not exists: create new
```

### Zone Issues
**Custom Zone Not Found**:
```swift
guard let customZone = userCustomZone else {
    debugLog("❌ Custom zone not available")
    // App should not operate without custom zone
    return
}
```

**Zone Setup Failure**:
- Check iCloud account status
- Verify CloudKit entitlements
- Ensure Production environment settings
- Look for permission issues

### Default Zone References (CRITICAL ERROR)
**If you see these patterns**, they're bugs that must be fixed:
```swift
// ❌ WRONG - Default zone usage
privateDatabase.fetch(withQuery: query, inZoneWith: nil, ...)

// ❌ WRONG - No zone specified
recordID = CKRecord.ID(recordName: UUID().uuidString)

// ✅ CORRECT - Custom zone only
recordID = CKRecord.ID(recordName: UUID().uuidString, zoneID: customZone.zoneID)
```

## Save/Sync Issues

### Save Button States
- **Green**: All changes saved to CloudKit ✅
- **Yellow**: Unsaved changes in local memory ⚠️
- **Red**: Save operation failed ❌

### Save Failures
**Common Error Messages**:
- "Custom zone required" - zone setup failed
- "iCloud not available" - network/account issue
- "Maximum retry attempts reached" - persistent CloudKit error

**Debug Steps**:
1. **Check debug logs** - look for "PSC DEBUG:" messages
2. **Verify CloudKit status** - account signed in?
3. **Test with simple data** - try saving single field
4. **Check for rate limiting** - too many requests?

### Data Not Syncing Between Devices
**Troubleshooting Checklist**:
- [ ] Both devices signed into same Apple ID?
- [ ] Save button showing green (data actually saved)?
- [ ] Network connectivity working on both devices?
- [ ] Custom zone exists and accessible?
- [ ] No duplicate records causing confusion?

## Code-Level Debugging

### Debug Logging
Look for these log patterns:
```
PSC DEBUG: 🔒 CUSTOM ZONE ONLY: PSC never uses default zones
PSC DEBUG: ✅ SAVE SUCCESS: CloudKit save completed
PSC DEBUG: 📥 FETCH SUCCESS: CloudKit query completed
PSC DEBUG: 🚨 FOUND ORPHANED DATA: X records exist in DEFAULT zone
```

### Key Functions to Check
```swift
// Data fetch
fetchDailySchedulesFromCustomZone()

// Save logic
saveOrDeleteDailySchedule()

// Zone management
setupUserCustomZone()

// Duplicate handling
// (Needs implementation)
```

### Memory State Inspection
```swift
// Check global memory state
debugLog("📊 Local dailySchedules count: \(dailySchedules.count)")
debugLog("📊 Modified records: \(dailySchedules.filter { $0.isModified }.count)")

// Check CloudKit state
debugLog("🔍 Zone ready: \(isZoneReady)")
debugLog("🔍 CloudKit available: \(cloudKitAvailable)")
```

## Testing Procedures

### Multi-Device Testing
1. **Primary Device (Administrator iPad)**:
   - Enter test data for future date
   - Verify save button goes green
   - Check data appears correctly

2. **Secondary Device (Test iPad)**:
   - Force refresh or restart app
   - Verify same data appears
   - Check all 4 fields display correctly

3. **CloudKit Dashboard**:
   - Verify single record for test date
   - Check all fields match entered data
   - Confirm no duplicates created

### Regression Testing
After any CloudKit changes:
- [ ] Can create new schedule data?
- [ ] Can edit existing schedule data?
- [ ] Can delete schedule data (all fields empty)?
- [ ] Data syncs between devices?
- [ ] No duplicate records created?
- [ ] Share functionality still works?

## Common Code Fixes

### Fix Duplicate Creation
```swift
// Before saving, check for existing record:
func saveOrDeleteDailySchedule(date: Date, ...) {
    // Query CloudKit for existing record with this date
    let predicate = NSPredicate(format: "CD_date == %@", date)
    let query = CKQuery(recordType: "CD_DailySchedule", predicate: predicate)
    
    privateDatabase.fetch(withQuery: query, inZoneWith: customZone.zoneID) { result in
        switch result {
        case .success(let (matchResults, _)):
            if let existingRecord = matchResults.first?.1.try?.get() {
                // Update existing record
                updateExistingRecord(existingRecord, with: newData)
            } else {
                // Create new record
                createNewRecord(with: newData)
            }
        }
    }
}
```

### Add Duplicate Detection in Fetch
```swift
func fetchDailySchedules() {
    // After fetching all records:
    let deduplicatedSchedules = removeDuplicatesByDate(fetchedSchedules)
    self.dailySchedules = deduplicatedSchedules
}

func removeDuplicatesByDate(_ records: [DailyScheduleRecord]) -> [DailyScheduleRecord] {
    var uniqueRecords: [String: DailyScheduleRecord] = [:]
    
    for record in records {
        guard let date = record.date else { continue }
        let dateKey = dateFormatter.string(from: date)
        
        if let existing = uniqueRecords[dateKey] {
            // Keep the more complete record
            uniqueRecords[dateKey] = moreCompleteRecord(existing, record)
        } else {
            uniqueRecords[dateKey] = record
        }
    }
    
    return Array(uniqueRecords.values).sorted { ($0.date ?? Date()) < ($1.date ?? Date()) }
}
```

## Emergency Contacts and Procedures

### If Data Loss Occurs
1. **Immediately contact user** - they have printed master schedule
2. **Don't make more changes** - could overwrite recoverable data
3. **Check all CloudKit zones** - data might be in unexpected places
4. **Look for recent backups** - Time Machine, etc.

### If App Crashes in Production
1. **Revert to last known good version**
2. **Check crash logs** for specific error
3. **Test on development device first**
4. **Coordinate with user** before deploying fix

---

**Last Updated**: September 18, 2025  
**Current Issues**: Duplicate CloudKit records, partial data display  
**Next Actions**: Clean up duplicates, implement date-based save logic
