# Instructions for AI Assistants Working on PSC

## 🚨 MANDATORY READING BEFORE ANY CHANGES

### First Steps for New AI Assistants
1. **Read `PSC_Requirements_and_Architecture.md` COMPLETELY**
2. **Review current issue context** in conversation history
3. **Understand**: This is **PRODUCTION MEDICAL SOFTWARE**
4. **Ask user to confirm understanding** before making any code changes
5. **NEVER assume** - always verify requirements with user

## Critical App Understanding

### What PSC Does
- **Medical provider scheduling** for clinic locations
- **Multi-device sharing** of schedule data via CloudKit
- **Provider codes** (letters) represent individual medical providers
- **Wrong data = patient care issues** - precision is critical

### Architecture Rules (NEVER VIOLATE)
```
✅ DO:
- Use custom CloudKit zones only
- Keep global memory as master
- Manual save only
- Work on feature branches
- Test on multiple devices

❌ NEVER:
- Use default CloudKit zones
- Add auto-save features
- Make CloudKit the master data source
- Work directly on main branch
- Make changes without user approval
```

## Common Past Mistakes (AVOID THESE)

### Previous AI Assistant Errors
1. **Added default zone fallback logic** - broke sharing functionality
2. **Implemented auto-save** - violated manual save requirement
3. **Misunderstood data flow** - made CloudKit master instead of backup
4. **Ignored provider code precision** - caused medical scheduling errors
5. **Made unauthorized changes** - user explicitly said "do not make changes"

### Code Patterns That Are Wrong
```swift
// ❌ WRONG - Creates default zone fallback
recordID = CKRecord.ID(recordName: UUID().uuidString) // No zoneID!

// ❌ WRONG - Auto-save on focus lost
.onFocusLost { saveData() }

// ❌ WRONG - Makes CloudKit master
if cloudKitData != localData {
    localData = cloudKitData // Overwrites user edits!
}
```

### Code Patterns That Are Correct
```swift
// ✅ CORRECT - Custom zone only
guard let customZone = userCustomZone else { return }
recordID = CKRecord.ID(recordName: UUID().uuidString, zoneID: customZone.zoneID)

// ✅ CORRECT - Manual save only
Button("Save") { saveToCloudKit() } // User-initiated

// ✅ CORRECT - Global memory is master
if hasLocalChanges {
    // Keep local data, don't overwrite
    protectLocalData()
}
```

## Development Process

### Before Making Changes
1. **Create feature branch**: `git checkout -b feature-name`
2. **Understand the specific issue** being solved
3. **Ask clarifying questions** if anything is unclear
4. **Get user approval** for the approach

### During Development
1. **Make minimal changes** - avoid rewrites unless absolutely necessary
2. **Test frequently** - check for regressions
3. **Add debug logging** - help with future troubleshooting
4. **Document why** decisions were made in comments

### After Changes
1. **Test on multiple devices** if CloudKit-related
2. **Check for duplicate records** in CloudKit dashboard
3. **Verify against printed master schedule** (user has reference copy)
4. **Get user confirmation** before considering complete

## Current Known Issues (September 2025)

### Active Problems
- **Duplicate CloudKit records** for same dates
- **Partial data display** - app shows incomplete records
- **Save logic always creates new** instead of updating existing

### Root Cause
```swift
// CURRENT PROBLEM in saveDailySchedule():
let recordID = CKRecord.ID(recordName: UUID().uuidString, zoneID: customZone.zoneID)
// Always creates NEW record, even for existing dates

// NEEDS TO BE:
// 1. Query CloudKit for existing record with this date
// 2. If exists: update that record
// 3. If not exists: create new record
```

### Fix Strategy
1. **Clean up existing duplicates** manually in CloudKit (user doing this)
2. **Modify save logic** to query by date before creating new records
3. **Add deduplication** in fetch logic as safeguard

## Testing Requirements

### Multi-Device Testing
- **Primary device** (Administrator iPad) - create/edit data
- **Secondary device** (Test iPad, same Apple ID) - verify data appears
- **Ensure data consistency** between devices after save

### CloudKit Verification
- **Check CloudKit dashboard** for duplicate records
- **Verify custom zone usage** - no records in default zone
- **Confirm sharing functionality** works between Apple IDs

### Data Integrity Testing
- **Compare with printed master schedule** (user has reference)
- **Test all 4 fields** (OS, CL, OFF, CALL) save and display correctly
- **Verify provider codes** maintain precision (case sensitive)

## Communication Guidelines

### When Uncertain
- **Ask specific questions** rather than making assumptions
- **Explain your understanding** and ask for confirmation
- **Propose approach** before implementing
- **Show code snippets** for complex changes

### Progress Updates
- **Explain what you're doing** and why
- **Show before/after** for significant changes
- **Highlight potential risks** or side effects
- **Ask for verification** at key milestones

## Emergency Procedures

### If You Make a Mistake
1. **Stop immediately** - don't compound the error
2. **Explain what happened** honestly
3. **Propose rollback strategy** if needed
4. **Learn from the mistake** - update documentation

### If User Reports Data Loss
1. **Don't panic** - data might be recoverable
2. **Check CloudKit dashboard** for records
3. **Look for duplicates** that might contain missing data
4. **User has printed master schedule** as reference
5. **Consider emergency data recovery** procedures

## Version Control

### Branch Strategy
- **main**: Production-ready code
- **datafix**: Current active branch for duplicate record fixes
- **feature/***: New feature development
- **hotfix/***: Critical production fixes

### Commit Messages
```
Format: [type]: brief description

Examples:
fix: prevent duplicate CloudKit record creation
feat: add date-based record querying
docs: update AI assistant instructions
refactor: simplify save logic flow
```

## Success Criteria

### A Change is Successful When:
- ✅ All tests pass on multiple devices
- ✅ No duplicate records created in CloudKit
- ✅ Data matches printed master schedule exactly
- ✅ User confirms functionality works as expected
- ✅ No regression in existing features

### A Change is NOT Ready When:
- ❌ Only tested on one device
- ❌ Creates CloudKit duplicates
- ❌ Data doesn't match master schedule
- ❌ User reports issues or concerns
- ❌ Breaks existing functionality

---

**Remember**: PSC is medical software affecting patient care. When in doubt, ask questions rather than making assumptions. The user's approval is required for all changes.

**Last Updated**: September 18, 2025  
**Current Status**: Working on duplicate record prevention in datafix branch
