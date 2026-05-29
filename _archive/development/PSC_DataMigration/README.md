# PSC Data Migration Tool

This is a **one-time migration app** to transfer Lisa's schedule data from Provider Schedule Calendar Version 2 to Version 3.

## Purpose
- **From**: Version 2 (buggy) zone: `com.apple.coredata.cloudkit.share.0E031FC4-3C64-4F34-AFEC-375AD170A0E9`
- **To**: Version 3 (stable) zone: `user_com.gulfcoast.ProviderCalendar`

## Installation Instructions

### Step 1: Create Xcode Project
1. Open Xcode
2. Create new iOS App project
3. **Product Name**: `PSC DataMigration`
4. **Bundle Identifier**: `com.gulfcoast.PSCDataMigration`
5. **Language**: Swift
6. **Interface**: SwiftUI

### Step 2: Add Files
1. Replace `ContentView.swift` with `MigrationView.swift`
2. Replace `PSC_DataMigrationApp.swift` as main app file
3. Add `MigrationManager.swift` to project
4. Replace `Info.plist` with provided version
5. Add `PSC_DataMigration.entitlements` to project

### Step 3: Configure CloudKit
1. **Signing & Capabilities** → Add CloudKit capability
2. **Container**: `iCloud.com.gulfcoast.ProviderCalendar`
3. **Entitlements**: Use provided `.entitlements` file

### Step 4: Build & Install
1. Connect Lisa's iPad
2. Build and install app (`⌘+R`)
3. **CRITICAL**: Sign in with `lisalisa_39564@yahoo.com` Apple ID

## Usage

### Migration Process
1. **Launch app** on Lisa's iPad
2. **Verify** iCloud connection shows "Ready"
3. **Tap** "Start Migration"
4. **Wait** for completion (should show all records migrated)
5. **Verify** success message

### Expected Results
- **Daily Schedules**: ~12 records (based on CloudKit Dashboard)
- **Monthly Notes**: Variable count
- **Status**: "Migration completed successfully!"

### After Migration
1. **Delete** migration app (no longer needed)
2. **Install** Provider Schedule Calendar Version 3
3. **Verify** all Lisa's data appears in Version 3
4. **Test** sharing functionality with ScheduleViewer

## Technical Details

### Data Transformation
- Copies all `CD_*` fields from legacy records
- Creates new records in Version 3 zone format
- Adds `CD_entityName` field for Version 3 compatibility
- Preserves all dates, schedule lines, and monthly notes

### Safety Features
- **Non-destructive**: Original data remains untouched
- **Verification**: Confirms all records migrated successfully
- **Batch processing**: Handles large datasets efficiently
- **Error handling**: Clear error messages if issues occur

### Zone Details
- **Legacy Zone**: `com.apple.coredata.cloudkit.share.0E031FC4-3C64-4F34-AFEC-375AD170A0E9`
- **Target Zone**: `user_com.gulfcoast.ProviderCalendar`
- **Database**: Private CloudKit Database
- **Container**: `iCloud.com.gulfcoast.ProviderCalendar`

## Troubleshooting

### "CloudKit not available"
- Ensure Lisa is signed into iCloud
- Check Settings → [Name] → iCloud → iCloud Drive is enabled

### "No data found"
- Verify correct Apple ID (`lisalisa_39564@yahoo.com`)
- Check CloudKit Dashboard shows data in legacy zone

### Migration fails
- Check network connection
- Try again (migration is safe to retry)
- Ensure sufficient iCloud storage

## Support
This is a custom migration tool. If issues occur:
1. Check console logs for detailed error messages
2. Verify Apple ID and iCloud settings
3. Contact developer with specific error details

---
**⚠️ IMPORTANT**: This app should only be used once per user. After successful migration, delete this app and use Provider Schedule Calendar Version 3.
