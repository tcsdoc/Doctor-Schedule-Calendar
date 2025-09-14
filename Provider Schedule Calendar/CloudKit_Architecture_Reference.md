# CloudKit Architecture Reference
*Source: https://developer.apple.com/documentation/cloudkit*

## Key CloudKit Principles for Provider Schedule Calendar

### 1. Data Organization Hierarchy
```
Container (iCloud.com.gulfcoast.ProviderCalendar)
├── Private Database (our choice for medical data privacy)
│   ├── Default Zone (_defaultZone)
│   └── Custom Zones (user_com.gulfcoast.ProviderCalendar)
├── Public Database (not used)
└── Shared Database (for provider access via ScheduleViewer)
```

### 2. Fundamental CloudKit Data Persistence Rules

#### **CRITICAL: Record Identity and Updates**
- **NEW Records**: Create with `CKRecord(recordType: "RecordType")`
- **EXISTING Records**: Always use the same `recordName` and `zoneID`
- **Updates**: Fetch existing `CKRecord`, modify fields, then save
- **DON'T**: Create new UUIDs for existing data (breaks persistence)

#### **Current Implementation Problem:**
```swift
// WRONG - Creates new record every time
recordID = CKRecord.ID(recordName: UUID().uuidString, zoneID: customZone.zoneID)
record["CD_id"] = UUID().uuidString as CKRecordValue  // Another new UUID!
```

#### **Correct Pattern:**
```swift
// For existing records in global memory
if let existingRecord = globalMemoryRecord {
    let recordID = CKRecord.ID(recordName: existingRecord.id, zoneID: existingRecord.zoneID)
    // Fetch, modify, save existing CKRecord
} else {
    // Only for truly NEW records
    let recordID = CKRecord.ID(recordName: UUID().uuidString, zoneID: customZone.zoneID)
}
```

### 3. CloudKit Best Practices for Medical/Provider Data

#### **Local Caching (Our Global Memory Approach)**
- ✅ Maintain local cache of all data (our `@Published var dailySchedules`)
- ✅ Synchronize with CloudKit on user-initiated saves
- ✅ Allow offline access with eventual consistency

#### **Change Tracking**
- ✅ Use `isModified` flags to track local changes
- ✅ Implement manual save workflow (Save button approach)
- ❌ **MISSING**: Proper record identity management during saves

#### **Error Handling**
- ✅ Implement comprehensive CloudKit error analysis
- ✅ Retry mechanisms for transient failures
- ❌ **PROBLEM**: Success reporting without actual persistence

### 4. Schema Design for Provider Schedules

#### **Current Model:**
```swift
struct DailyScheduleRecord {
    let id: String              // Should be CloudKit recordName
    let date: Date?
    var line1: String?          // OS providers
    var line2: String?          // CL providers  
    var line3: String?          // OFF providers
    let zoneID: CKRecordZone.ID // CloudKit zone reference
    var isModified: Bool        // Local change tracking
}
```

#### **CloudKit Record Fields:**
```swift
record["CD_date"] = date as CKRecordValue
record["CD_line1"] = line1 as CKRecordValue?
record["CD_line2"] = line2 as CKRecordValue?
record["CD_line3"] = line3 as CKRecordValue?
record["CD_id"] = uuid as CKRecordValue  // Should match model.id
```

### 5. Synchronization Workflow (Correct Pattern)

#### **User Types Data:**
1. Update global memory (`dailySchedules` array)
2. Set `isModified = true` 
3. Save button shows yellow (unsaved changes)

#### **User Clicks Save:**
1. **Check if record exists in global memory**
2. **If exists**: Use existing `id` and `zoneID` for CloudKit update
3. **If new**: Create new CloudKit record with new UUID
4. **Save to CloudKit** with proper record identity
5. **Update global memory** with returned CloudKit data
6. Set `isModified = false`

### 6. Critical Fix Required

#### **Root Cause of 26 Failed Attempts:**
The app creates new CloudKit records for every save instead of updating existing ones, breaking the connection between global memory and CloudKit persistence.

#### **Solution:**
Implement proper record identity management where:
- Global memory record IDs match CloudKit recordNames
- Updates use existing record IDs instead of creating new ones
- New records only created when no global memory record exists

### 7. Data Reliability for Medical Use

#### **Requirements:**
- 100% data persistence reliability (patient care dependency)
- Clear visual feedback for save status
- Offline-first with eventual consistency
- Multi-device synchronization for providers

#### **Current Status:**
- ✅ Offline-first global memory works
- ✅ Visual save status implemented
- ❌ **BROKEN**: CloudKit persistence due to record identity issues
- ❌ **BROKEN**: Multi-device sync due to orphaned records

## Implementation Priority

1. **FIX**: Record identity management in save operations
2. **VERIFY**: CloudKit persistence actually works
3. **TEST**: Multi-device synchronization
4. **VALIDATE**: Data appears in CloudKit Dashboard

---
*This reference should guide all CloudKit-related coding decisions for the Provider Schedule Calendar project.*
