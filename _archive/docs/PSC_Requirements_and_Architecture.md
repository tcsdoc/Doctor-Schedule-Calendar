# Provider Schedule Calendar (PSC) - Master Documentation

## 🚨 CRITICAL RULES (READ FIRST!)

### CloudKit Architecture - NEVER VIOLATE
- **NEVER use default CloudKit zones** - PSC must ONLY use custom zones
- **Default zones cannot be shared** - this breaks the core app purpose
- **Custom zones are required** for CloudKit sharing functionality
- **No fallback to default zones** under any circumstances

### Data Flow Architecture - MASTER/BACKUP RELATIONSHIP
- **Global memory (@Published var dailySchedules) is MASTER** - authoritative source
- **CloudKit is BACKUP/SYNC** - persistent storage for multi-device access
- **Save button pushes** global memory → CloudKit for backup
- **Conflicts**: Global memory wins, never overwrite local edits

### Save System - MANUAL ONLY
- **Manual save only** - no auto-save triggers
- **Save button shows status**: Green=saved, Yellow=changes, Red=error
- **User controls when** data goes to CloudKit
- **Never save without user consent**

## App Purpose and Usage

### Medical Provider Scheduling
- **Ocean Springs (OS)** clinic location
- **Cedar Lake (CL)** clinic location  
- **OFF** = off duty
- **CALL** = on-call duty

### Provider Code System 🏥
- **Letter codes = providers** (usually first initial of last name)
- **Examples**: "OS O.C.D.F." = providers O, C, D, F work Ocean Springs
- **Data integrity is CRITICAL** - wrong codes cause scheduling confusion
- **Provider codes are medical data** - precision required

### Sharing Model
- **Administrator creates** schedules on primary iPad
- **Staff members access** via CloudKit sharing (read-only or edit)
- **Multiple devices** can use same Apple ID safely (one at a time)
- **Custom zones enable** sharing between different Apple IDs

## Current App Status (September 18, 2025)

### Version Information
- **Current Version**: 3.7.5
- **Status**: Apple App Store approved, Production mode
- **Architecture**: Custom zones only, sharing enabled

### Data Structure
```swift
// Daily Schedule (4 fields)
struct DailyScheduleRecord {
    let id: String              // CloudKit recordName
    let date: Date?
    var line1: String?          // OS (Ocean Springs)
    var line2: String?          // CL (Cedar Lake)
    var line3: String?          // OFF (off duty)
    var line4: String?          // CALL (on-call)
    let zoneID: CKRecordZone.ID // Custom zone reference
    var isModified: Bool        // Local change tracking
}

// Monthly Notes (3 fields)
struct MonthlyNotesRecord {
    let id: String
    let month: Int
    let year: Int
    var line1: String?          // Note 1
    var line2: String?          // Note 2
    var line3: String?          // Note 3
    let zoneID: CKRecordZone.ID
    var isModified: Bool
}
```

## Known Issues and Fixes

### Fixed in datafix Branch
- ✅ **Removed all default zone references** - app now custom zones only
- ✅ **Eliminated fallback logic** - no backward compatibility with default zones
- ✅ **Zone setup failure handling** - app refuses to operate without custom zone

### Current Issue (September 2025)
- 🔄 **Duplicate CloudKit records** - same date has multiple records
- 🔄 **Partial data display** - app shows incomplete records from duplicates
- 🔄 **Save logic creates new records** instead of updating existing ones

### Root Cause Analysis
```swift
// PROBLEM: Always creates new records
let recordID = CKRecord.ID(recordName: UUID().uuidString, zoneID: customZone.zoneID)

// SOLUTION NEEDED: Query by date first, update if exists
```

## Development Guidelines

### For AI Assistants
1. **Read this document completely** before making any changes
2. **Understand**: This is production medical software affecting patient care
3. **Ask for confirmation** of understanding before coding
4. **Always work on feature branches**, never directly on main
5. **Test on multiple devices** before considering complete

### Forbidden Actions
- ❌ Adding default zone references or fallbacks
- ❌ Implementing auto-save functionality  
- ❌ Changing master/backup data relationship
- ❌ Modifying provider code precision handling
- ❌ Making changes without user approval

### Required Verification Steps
- ✅ Test data entry and save on primary device
- ✅ Verify data appears correctly on secondary device
- ✅ Check CloudKit dashboard for duplicate records
- ✅ Validate against printed master schedule
- ✅ Confirm no data loss during sync

## Project Structure

### Key Files
```
Provider Schedule Calendar/
├── Provider_Schedule_CalendarApp.swift     # App entry point
├── ContentView.swift                       # Main UI and save logic
├── CloudKitManager.swift                   # CloudKit operations
├── CloudKit_Architecture_Reference.md     # Technical CloudKit docs
└── Provider Schedule Calendar.entitlements # CloudKit permissions
```

### CloudKit Configuration
```xml
<!-- Provider Schedule Calendar.entitlements -->
<key>com.apple.developer.icloud-container-environment</key>
<string>Production</string>
<key>com.apple.developer.icloud-container-identifiers</key>
<array>
    <string>iCloud.com.gulfcoast.ProviderCalendar</string>
</array>
```

## Troubleshooting Common Issues

### Data Not Appearing on Secondary Device
1. **Check CloudKit status** - ensure signed into same Apple ID
2. **Verify custom zone exists** - PSC creates "ProviderScheduleZone"
3. **Look for duplicates** - multiple records for same date
4. **Check fetch logic** - ensure fetching from correct zone

### Duplicate Records in CloudKit
1. **Caused by**: Save logic creating new instead of updating
2. **Detection**: Multiple records with same CD_date field
3. **Cleanup**: Keep most complete/recent record, delete others
4. **Prevention**: Fix save logic to query by date first

### Save Button Issues
- **Yellow (unsaved changes)**: Normal - data in local memory only
- **Red (error)**: Check CloudKit connectivity and zone status
- **Green (saved)**: Data successfully backed up to CloudKit

## Version History

### v3.0.28 (Archived)
- Major CloudKit save system overhaul
- Removed auto-save triggers
- Implemented manual-save-only system

### v3.7.5 (Current Production)
- Apple App Store approved
- Production CloudKit environment
- 4-field daily schedule (added CALL field)
- Custom zones only architecture

---

**Last Updated**: September 18, 2025
**Status**: Active Development (datafix branch)
**Next Steps**: Fix duplicate record creation, implement date-based querying
