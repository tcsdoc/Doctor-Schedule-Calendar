import Foundation
import CloudKit

// MARK: - Simplified CloudKit Manager (200 lines vs 2000+)
actor SimpleCloudKitManager {
    
    // MARK: - Properties
    private let container: CKContainer
    private let privateDatabase: CKDatabase
    private let customZone: CKRecordZone
    private let zoneID: CKRecordZone.ID
    
    // MARK: - Initialization
    init() {
        // Initialize CloudKit container
        container = CKContainer(identifier: "iCloud.com.gulfcoast.ProviderCalendar")
        privateDatabase = container.privateCloudDatabase
        
        // Create custom zone for sharing
        zoneID = CKRecordZone.ID(zoneName: "ProviderScheduleZone")
        customZone = CKRecordZone(zoneID: zoneID)
        
        redesignLog("🔧 SimpleCloudKitManager initialized")
    }
    
    // MARK: - CloudKit Availability
    func checkCloudKitAvailability() async -> Bool {
        do {
            let status = try await container.accountStatus()
            let available = status == .available
            redesignLog(available ? "✅ CloudKit available" : "❌ CloudKit unavailable: \(status)")
            return available
        } catch {
            redesignLog("❌ CloudKit status check failed: \(error)")
            return false
        }
    }
    
    // MARK: - Zone Management
    private func ensureCustomZoneExists() async throws {
        redesignLog("🔍 Checking if custom zone exists...")
        
        do {
            // Try to fetch the zone
            let zones = try await privateDatabase.allRecordZones()
            
            if zones.contains(where: { $0.zoneID == zoneID }) {
                redesignLog("✅ Custom zone already exists")
            } else {
                redesignLog("➕ Creating custom zone...")
                let _ = try await privateDatabase.save(customZone)
                redesignLog("✅ Custom zone created successfully")
            }
        } catch {
            redesignLog("❌ Zone management failed: \(error)")
            throw error
        }
    }
    
    // MARK: - Schedule Operations
    func fetchAllSchedules() async throws -> [String: ScheduleRecord] {
        try await ensureCustomZoneExists()
        
        redesignLog("📅 Fetching all schedules with pagination...")
        
        let query = CKQuery(recordType: "CD_DailySchedule", predicate: NSPredicate(value: true))
        var schedules: [String: ScheduleRecord] = [:]
        var cursor: CKQueryOperation.Cursor? = nil
        var totalFetched = 0
        var batchCount = 0
        
        repeat {
            batchCount += 1
            redesignLog("📦 Fetching batch \(batchCount)...")
            
            let (matchResults, moreComing) = cursor == nil 
                ? try await privateDatabase.records(matching: query, inZoneWith: zoneID)
                : try await privateDatabase.records(continuingMatchFrom: cursor!)
            
            // Process this batch of results
            for (_, result) in matchResults {
                switch result {
                case .success(let record):
                    if let schedule = parseScheduleRecord(record) {
                        let dateKey = dateKey(for: schedule.date)
                        schedules[dateKey] = schedule
                        totalFetched += 1
                    }
                case .failure(let error):
                    redesignLog("❌ Failed to process schedule record: \(error)")
                }
            }
            
            redesignLog("📦 Batch \(batchCount): \(matchResults.count) records, \(totalFetched) total so far")
            
            // Update cursor for next batch
            cursor = moreComing
            
        } while cursor != nil
        
        redesignLog("✅ Fetched ALL \(schedules.count) schedules across \(batchCount) batches")
        return schedules
    }
    
    func saveSchedule(_ schedule: ScheduleRecord) async throws {
        try await ensureCustomZoneExists()
        
        redesignLog("💾 Saving schedule for \(schedule.id)")
        
        let recordID = CKRecord.ID(recordName: schedule.id, zoneID: zoneID)
        
        // Try to fetch existing record first, create new if doesn't exist
        let record: CKRecord
        do {
            // Try to fetch existing record to update it
            record = try await privateDatabase.record(for: recordID)
            redesignLog("📝 Updating existing record: \(schedule.id)")
        } catch let error as CKError where error.code == .unknownItem {
            // ONLY create new record if it truly doesn't exist
            record = CKRecord(recordType: "CD_DailySchedule", recordID: recordID)
            redesignLog("🆕 Creating new record: \(schedule.id)")
        } catch {
            // For all other errors (network, throttling, zone busy, etc), propagate the error
            // This prevents duplicate creation when CloudKit has transient issues
            redesignLog("❌ Failed to fetch record \(schedule.id) for update: \(error)")
            if let ckError = error as? CKError {
                redesignLog("❌ CloudKit error code: \(ckError.code.rawValue) - \(ckError.localizedDescription)")
            }
            throw error
        }
        
        // Set/update fields
        record["CD_date"] = schedule.date as CKRecordValue
        record["CD_id"] = schedule.id as CKRecordValue
        record["CD_line1"] = schedule.os as CKRecordValue?
        record["CD_line2"] = schedule.cl as CKRecordValue?
        record["CD_line3"] = schedule.off as CKRecordValue?
        record["CD_line4"] = schedule.call as CKRecordValue?
        
        // Save to CloudKit
        let _ = try await privateDatabase.save(record)
        redesignLog("✅ Schedule saved: \(schedule.id)")
    }
    
    func deleteSchedule(dateKey: String) async throws {
        redesignLog("🗑️ Deleting schedule: \(dateKey)")
        
        let recordID = CKRecord.ID(recordName: "schedule_\(dateKey)", zoneID: zoneID)
        
        do {
            let _ = try await privateDatabase.deleteRecord(withID: recordID)
            redesignLog("✅ Schedule deleted: \(dateKey)")
        } catch let error as CKError where error.code == .unknownItem {
            // Record doesn't exist - that's fine
            redesignLog("ℹ️ Schedule already deleted or never existed: \(dateKey)")
        } catch {
            redesignLog("❌ Delete failed: \(error)")
            throw error
        }
    }
    
    // MARK: - Monthly Notes Operations
    func fetchAllMonthlyNotes() async throws -> [String: MonthlyNote] {
        try await ensureCustomZoneExists()
        
        redesignLog("📝 Fetching all monthly notes with pagination...")
        
        let query = CKQuery(recordType: "CD_MonthlyNotes", predicate: NSPredicate(value: true))
        var notes: [String: MonthlyNote] = [:]
        var cursor: CKQueryOperation.Cursor? = nil
        var totalFetched = 0
        var batchCount = 0
        
        repeat {
            batchCount += 1
            redesignLog("📦 Monthly notes batch \(batchCount)...")
            
            let (matchResults, moreComing) = cursor == nil 
                ? try await privateDatabase.records(matching: query, inZoneWith: zoneID)
                : try await privateDatabase.records(continuingMatchFrom: cursor!)
            
            // Process this batch of results
            for (_, result) in matchResults {
                switch result {
                case .success(let record):
                    if let note = parseMonthlyNoteRecord(record) {
                        // Store using monthKey format (yyyy-MM) instead of note.id (notes_yyyy-MM)
                        let monthKey = String(format: "%04d-%02d", note.year, note.month)
                        notes[monthKey] = note
                        totalFetched += 1
                    }
                case .failure(let error):
                    redesignLog("❌ Failed to process monthly note record: \(error)")
                }
            }
            
            redesignLog("📦 Monthly notes batch \(batchCount): \(matchResults.count) records, \(totalFetched) total so far")
            
            // Update cursor for next batch
            cursor = moreComing
            
        } while cursor != nil
        
        redesignLog("✅ Fetched ALL \(notes.count) monthly notes across \(batchCount) batches")
        return notes
    }
    
    func saveMonthlyNote(_ note: MonthlyNote) async throws {
        try await ensureCustomZoneExists()
        
        redesignLog("💾 Saving monthly note: \(note.id)")
        
        let recordID = CKRecord.ID(recordName: note.id, zoneID: zoneID)
        
        // Try to fetch existing record first, create new if doesn't exist
        let record: CKRecord
        do {
            // Try to fetch existing record to update it
            record = try await privateDatabase.record(for: recordID)
            redesignLog("📝 Updating existing monthly note: \(note.id)")
        } catch let error as CKError where error.code == .unknownItem {
            // ONLY create new record if it truly doesn't exist
            record = CKRecord(recordType: "CD_MonthlyNotes", recordID: recordID)
            redesignLog("🆕 Creating new monthly note: \(note.id)")
        } catch {
            // For all other errors (network, throttling, zone busy, etc), propagate the error
            // This prevents duplicate creation when CloudKit has transient issues
            redesignLog("❌ Failed to fetch monthly note \(note.id) for update: \(error)")
            if let ckError = error as? CKError {
                redesignLog("❌ CloudKit error code: \(ckError.code.rawValue) - \(ckError.localizedDescription)")
            }
            throw error
        }
        
        // Set/update fields - use integers for month/year as expected by CloudKit schema
        record["CD_id"] = note.id as CKRecordValue
        record["CD_month"] = note.month as CKRecordValue  // Send integer, not Date
        record["CD_year"] = note.year as CKRecordValue    // Send integer, not Date
        record["CD_line1"] = note.line1 as CKRecordValue?
        record["CD_line2"] = note.line2 as CKRecordValue?
        record["CD_line3"] = note.line3 as CKRecordValue?
        
        // Save to CloudKit
        let _ = try await privateDatabase.save(record)
        redesignLog("✅ Monthly note saved: \(note.id)")
    }
    
    func deleteMonthlyNote(monthKey: String) async throws {
        redesignLog("🗑️ Deleting monthly note: \(monthKey)")
        
        let recordID = CKRecord.ID(recordName: "notes_\(monthKey)", zoneID: zoneID)
        
        do {
            let _ = try await privateDatabase.deleteRecord(withID: recordID)
            redesignLog("✅ Monthly note deleted: \(monthKey)")
        } catch let error as CKError where error.code == .unknownItem {
            redesignLog("ℹ️ Monthly note already deleted or never existed: \(monthKey)")
        } catch {
            redesignLog("❌ Monthly note delete failed: \(error)")
            throw error
        }
    }
    
    // MARK: - Sharing Operations - REMOVED DUPLICATE
    // createShare() function removed - was conflicting with createCustomZoneShare()
    // All sharing now uses createCustomZoneShare() via getOrCreateZoneShare()
    
    // MARK: - Helper Methods
    private func parseScheduleRecord(_ record: CKRecord) -> ScheduleRecord? {
        guard let date = record["CD_date"] as? Date else {
            redesignLog("❌ Invalid schedule record - missing date")
            return nil
        }
        
        return ScheduleRecord(
            date: date,
            os: record["CD_line1"] as? String,
            cl: record["CD_line2"] as? String,
            off: record["CD_line3"] as? String,
            call: record["CD_line4"] as? String
        )
    }
    
    private func parseMonthlyNoteRecord(_ record: CKRecord) -> MonthlyNote? {
        guard let month = record["CD_month"] as? Int,
              let year = record["CD_year"] as? Int else {
            redesignLog("❌ Invalid monthly note record - missing month/year integers")
            return nil
        }
        
        return MonthlyNote(
            month: month,
            year: year,
            line1: record["CD_line1"] as? String,
            line2: record["CD_line2"] as? String,
            line3: record["CD_line3"] as? String
        )
    }
    
    private func dateKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }
    
    // MARK: - CloudKit Sharing
    
    func deleteBrokenShare() async throws {
        redesignLog("🗑️ Deleting broken share...")
        
        do {
            let predicate = NSPredicate(format: "TRUEPREDICATE")
            let query = CKQuery(recordType: "cloudkit.share", predicate: predicate)
            
            let result = try await privateDatabase.records(matching: query, inZoneWith: zoneID)
            
            for (_, recordResult) in result.matchResults {
                switch recordResult {
                case .success(let record):
                    if let share = record as? CKShare {
                        redesignLog("🗑️ Deleting share: \(share.recordID.recordName)")
                        let deleteResult = try await privateDatabase.modifyRecords(saving: [], deleting: [share.recordID])
                        
                        for (deletedID, deleteResult) in deleteResult.deleteResults {
                            switch deleteResult {
                            case .success:
                                redesignLog("✅ Successfully deleted share: \(deletedID.recordName)")
                            case .failure(let error):
                                redesignLog("❌ Failed to delete share \(deletedID.recordName): \(error)")
                                throw error
                            }
                        }
                    }
                case .failure(let error):
                    redesignLog("❌ Error fetching share for deletion: \(error)")
                    throw error
                }
            }
            
            redesignLog("✅ Broken share cleanup completed")
        } catch {
            redesignLog("❌ Error during share deletion: \(error)")
            throw error
        }
    }
    func createCustomZoneShare() async throws -> CKShare {
        redesignLog("🔗 Creating zone share...")
        redesignLog("🔗 Target zone: \(zoneID.zoneName)")
        redesignLog("🔗 Zone owner: \(zoneID.ownerName)")
        
        // Ensure custom zone exists
        try await ensureCustomZoneExists()
        
        // Create zone-level share with secure permissions
        let share = CKShare(recordZoneID: zoneID)
        let currentYear = Calendar.current.component(.year, from: Date())
        share[CKShare.SystemFieldKey.title] = "Provider Schedule \(currentYear)" as CKRecordValue
        
        // CRITICAL: Set permission for SV compatibility
        share.publicPermission = .readOnly // Anyone with link can read (original working mode)
        
        redesignLog("🔗 Share object created for zone: \(zoneID.zoneName)")
        redesignLog("🔗 Share title: Provider Schedule \(currentYear)")
        redesignLog("🔗 Share recordID: \(share.recordID)")
        redesignLog("🔗 Share publicPermission: \(share.publicPermission.rawValue)")
        redesignLog("🔗 Share participants count (before save): \(share.participants.count)")
        
        // Save using the original working pattern
        let savedRecords = try await privateDatabase.modifyRecords(saving: [share], deleting: [])
        
        redesignLog("🔗 Save operation completed")
        redesignLog("🔗 Save results count: \(savedRecords.saveResults.count)")
        
        for (_, result) in savedRecords.saveResults {
            switch result {
            case .success(let record):
                if let shareRecord = record as? CKShare {
                    redesignLog("✅ Zone share created successfully")
                    redesignLog("🔗 Share URL: \(shareRecord.url?.absoluteString ?? "NO URL")")
                    redesignLog("🔗 Share recordID (after save): \(shareRecord.recordID)")
                    redesignLog("🔗 Share publicPermission (after save): \(shareRecord.publicPermission.rawValue)")
                    redesignLog("🔗 Share participants count (after save): \(shareRecord.participants.count)")
                    
                    // Log participant details
                    for (index, participant) in shareRecord.participants.enumerated() {
                        redesignLog("🔗 Participant \(index): \(participant.userIdentity.userRecordID?.recordName ?? "UNKNOWN")")
                        redesignLog("🔗   Role: \(participant.role.rawValue), Permission: \(participant.permission.rawValue)")
                        redesignLog("🔗   Status: \(participant.acceptanceStatus.rawValue)")
                    }
                    
                    return shareRecord
                }
            case .failure(let error):
                redesignLog("❌ Failed to save share: \(error)")
                throw error
            }
        }
        
        throw NSError(domain: "CloudKitManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "Share created but not returned by CloudKit"])
    }
    
    func fetchExistingZoneShare() async throws -> CKShare? {
        redesignLog("🔍 Looking for existing zone share...")
        
        do {
            // Query for share records in the zone (correct approach)
            let predicate = NSPredicate(format: "TRUEPREDICATE")
            let query = CKQuery(recordType: "cloudkit.share", predicate: predicate)
            
            redesignLog("🔍 Querying for shares in zone: \(zoneID.zoneName)")
            let result = try await privateDatabase.records(matching: query, inZoneWith: zoneID)
            
            // Look for the first share record
            redesignLog("🔍 Query returned \(result.matchResults.count) results")
            for (recordID, recordResult) in result.matchResults {
                redesignLog("🔍 Processing record: \(recordID.recordName)")
                switch recordResult {
                case .success(let record):
                    if let share = record as? CKShare {
                        redesignLog("✅ Found existing zone share")
                        redesignLog("🔗 Share URL: \(share.url?.absoluteString ?? "NO URL")")
                        redesignLog("🔗 Share record name: \(share.recordID.recordName)")
                        redesignLog("🔗 Share publicPermission: \(share.publicPermission.rawValue)")
                        redesignLog("🔗 Share participants count: \(share.participants.count)")
                        
                        // Log participant details for existing share
                        for (index, participant) in share.participants.enumerated() {
                            redesignLog("🔗 Existing Participant \(index): \(participant.userIdentity.userRecordID?.recordName ?? "UNKNOWN")")
                            redesignLog("🔗   Role: \(participant.role.rawValue), Permission: \(participant.permission.rawValue)")
                            redesignLog("🔗   Status: \(participant.acceptanceStatus.rawValue)")
                        }
                        
                        return share
                    } else {
                        redesignLog("⚠️ Found cloudkit.share record but not CKShare type: \(type(of: record))")
                    }
                case .failure(let error):
                    redesignLog("❌ Error fetching share record \(recordID.recordName): \(error)")
                }
            }
            
            redesignLog("ℹ️ No share records found in zone")
            return nil
            
        } catch {
            redesignLog("ℹ️ No existing zone share found: \(error)")
            if let ckError = error as? CKError, ckError.code == .unknownItem {
                redesignLog("🔍 No share exists for this zone")
            }
            return nil
        }
    }
    
    func getOrCreateZoneShare() async throws -> CKShare {
        // First try to fetch existing share
        if let existingShare = try await fetchExistingZoneShare() {
            // Check if share is broken (has readOnly permission but only owner participant)
            // This indicates it was created as invitation-only but never properly shared
            if existingShare.participants.count <= 1 {
                redesignLog("🚨 Found broken share with only owner participant - deleting...")
                try await deleteBrokenShare()
                redesignLog("🔄 Creating fresh share with public access...")
                return try await createCustomZoneShare()
            }
            return existingShare
        }
        
        // Create new share if none exists
        return try await createCustomZoneShare()
    }
    
    // MARK: - Duplicate Detection & Cleanup (Option B)
    
    /// Represents a duplicate record set for a specific date
    struct DuplicateGroup {
        let dateKey: String
        let records: [CKRecord]
        
        var recordCount: Int { records.count }
        
        /// Returns the record to keep (most recently modified)
        var recordToKeep: CKRecord? {
            records.max(by: { ($0.modificationDate ?? $0.creationDate) ?? Date.distantPast < ($1.modificationDate ?? $1.creationDate) ?? Date.distantPast })
        }
        
        /// Returns records to delete (all except the most recent)
        var recordsToDelete: [CKRecord] {
            guard let keepRecord = recordToKeep else { return records }
            return records.filter { $0.recordID != keepRecord.recordID }
        }
    }
    
    /// Result of duplicate detection scan
    struct DuplicateDetectionResult {
        let scheduleDuplicates: [DuplicateGroup]
        let monthlyNoteDuplicates: [DuplicateGroup]
        
        var totalDuplicateCount: Int {
            scheduleDuplicates.reduce(0) { $0 + $1.recordsToDelete.count } +
            monthlyNoteDuplicates.reduce(0) { $0 + $1.recordsToDelete.count }
        }
        
        var totalAffectedDates: Int {
            scheduleDuplicates.count + monthlyNoteDuplicates.count
        }
        
        var hasDuplicates: Bool {
            !scheduleDuplicates.isEmpty || !monthlyNoteDuplicates.isEmpty
        }
    }
    
    /// Scan CloudKit for duplicate records
    func detectDuplicates() async throws -> DuplicateDetectionResult {
        redesignLog("🔍 Starting duplicate detection scan...")
        
        // Fetch all raw records from CloudKit (not parsed into models)
        let scheduleRecords = try await fetchAllRawScheduleRecords()
        let monthlyNoteRecords = try await fetchAllRawMonthlyNoteRecords()
        
        redesignLog("🔍 Analyzing \(scheduleRecords.count) schedule records...")
        let scheduleDuplicates = findDuplicatesInSchedules(scheduleRecords)
        
        redesignLog("🔍 Analyzing \(monthlyNoteRecords.count) monthly note records...")
        let monthlyNoteDuplicates = findDuplicatesInMonthlyNotes(monthlyNoteRecords)
        
        let result = DuplicateDetectionResult(
            scheduleDuplicates: scheduleDuplicates,
            monthlyNoteDuplicates: monthlyNoteDuplicates
        )
        
        if result.hasDuplicates {
            redesignLog("⚠️ Found \(result.totalDuplicateCount) duplicate records across \(result.totalAffectedDates) dates")
        } else {
            redesignLog("✅ No duplicates detected")
        }
        
        return result
    }
    
    /// Delete duplicate records, keeping the most recent ones
    func cleanupDuplicates(_ result: DuplicateDetectionResult) async throws -> String {
        redesignLog("🧹 Starting duplicate cleanup...")
        
        var deletedCount = 0
        var logEntries: [String] = []
        logEntries.append("=== DUPLICATE CLEANUP LOG ===")
        logEntries.append("Date: \(Date())")
        logEntries.append("")
        
        // Clean up schedule duplicates
        for duplicateGroup in result.scheduleDuplicates {
            redesignLog("🧹 Cleaning duplicates for schedule: \(duplicateGroup.dateKey)")
            
            guard let keepRecord = duplicateGroup.recordToKeep else {
                redesignLog("⚠️ Cannot determine which record to keep for \(duplicateGroup.dateKey)")
                continue
            }
            
            logEntries.append("Date: \(duplicateGroup.dateKey) (Schedule)")
            logEntries.append("  Records found: \(duplicateGroup.recordCount)")
            logEntries.append("  Keeping: \(keepRecord.recordID.recordName) (modified: \(keepRecord.modificationDate ?? keepRecord.creationDate ?? Date()))")
            
            for recordToDelete in duplicateGroup.recordsToDelete {
                do {
                    _ = try await privateDatabase.deleteRecord(withID: recordToDelete.recordID)
                    deletedCount += 1
                    logEntries.append("  ✓ Deleted: \(recordToDelete.recordID.recordName) (modified: \(recordToDelete.modificationDate ?? recordToDelete.creationDate ?? Date()))")
                    redesignLog("  ✓ Deleted record: \(recordToDelete.recordID.recordName)")
                } catch {
                    logEntries.append("  ✗ Failed to delete: \(recordToDelete.recordID.recordName) - \(error.localizedDescription)")
                    redesignLog("  ❌ Failed to delete: \(error)")
                }
            }
            logEntries.append("")
        }
        
        // Clean up monthly note duplicates
        for duplicateGroup in result.monthlyNoteDuplicates {
            redesignLog("🧹 Cleaning duplicates for monthly note: \(duplicateGroup.dateKey)")
            
            guard let keepRecord = duplicateGroup.recordToKeep else {
                redesignLog("⚠️ Cannot determine which record to keep for \(duplicateGroup.dateKey)")
                continue
            }
            
            logEntries.append("Month: \(duplicateGroup.dateKey) (Monthly Note)")
            logEntries.append("  Records found: \(duplicateGroup.recordCount)")
            logEntries.append("  Keeping: \(keepRecord.recordID.recordName) (modified: \(keepRecord.modificationDate ?? keepRecord.creationDate ?? Date()))")
            
            for recordToDelete in duplicateGroup.recordsToDelete {
                do {
                    _ = try await privateDatabase.deleteRecord(withID: recordToDelete.recordID)
                    deletedCount += 1
                    logEntries.append("  ✓ Deleted: \(recordToDelete.recordID.recordName) (modified: \(recordToDelete.modificationDate ?? recordToDelete.creationDate ?? Date()))")
                    redesignLog("  ✓ Deleted record: \(recordToDelete.recordID.recordName)")
                } catch {
                    logEntries.append("  ✗ Failed to delete: \(recordToDelete.recordID.recordName) - \(error.localizedDescription)")
                    redesignLog("  ❌ Failed to delete: \(error)")
                }
            }
            logEntries.append("")
        }
        
        logEntries.append("=== CLEANUP COMPLETE ===")
        logEntries.append("Total records deleted: \(deletedCount)")
        
        redesignLog("✅ Cleanup complete: \(deletedCount) duplicates removed")
        
        let logText = logEntries.joined(separator: "\n")
        try saveCleanupLog(logText)
        
        return logText
    }
    
    // MARK: - Private Helper Methods
    
    private func fetchAllRawScheduleRecords() async throws -> [CKRecord] {
        let query = CKQuery(recordType: "CD_DailySchedule", predicate: NSPredicate(value: true))
        var allRecords: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor? = nil
        
        repeat {
            let (matchResults, moreComing) = cursor == nil
                ? try await privateDatabase.records(matching: query, inZoneWith: zoneID)
                : try await privateDatabase.records(continuingMatchFrom: cursor!)
            
            for (_, result) in matchResults {
                if case .success(let record) = result {
                    allRecords.append(record)
                }
            }
            
            cursor = moreComing
        } while cursor != nil
        
        return allRecords
    }
    
    private func fetchAllRawMonthlyNoteRecords() async throws -> [CKRecord] {
        let query = CKQuery(recordType: "CD_MonthlyNotes", predicate: NSPredicate(value: true))
        var allRecords: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor? = nil
        
        repeat {
            let (matchResults, moreComing) = cursor == nil
                ? try await privateDatabase.records(matching: query, inZoneWith: zoneID)
                : try await privateDatabase.records(continuingMatchFrom: cursor!)
            
            for (_, result) in matchResults {
                if case .success(let record) = result {
                    allRecords.append(record)
                }
            }
            
            cursor = moreComing
        } while cursor != nil
        
        return allRecords
    }
    
    private func findDuplicatesInSchedules(_ records: [CKRecord]) -> [DuplicateGroup] {
        // Group records by their date key (schedule_yyyy-MM-dd)
        var groupedRecords: [String: [CKRecord]] = [:]
        
        for record in records {
            if let date = record["CD_date"] as? Date {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                formatter.timeZone = TimeZone(identifier: "UTC")
                let dateKey = formatter.string(from: date)
                
                if groupedRecords[dateKey] == nil {
                    groupedRecords[dateKey] = []
                }
                groupedRecords[dateKey]?.append(record)
            }
        }
        
        // Find groups with more than one record (duplicates)
        return groupedRecords.compactMap { dateKey, records in
            records.count > 1 ? DuplicateGroup(dateKey: dateKey, records: records) : nil
        }.sorted { $0.dateKey < $1.dateKey }
    }
    
    private func findDuplicatesInMonthlyNotes(_ records: [CKRecord]) -> [DuplicateGroup] {
        // Group records by their month key (notes_yyyy-MM)
        var groupedRecords: [String: [CKRecord]] = [:]
        
        for record in records {
            if let month = record["CD_month"] as? Int,
               let year = record["CD_year"] as? Int {
                let monthKey = String(format: "%04d-%02d", year, month)
                
                if groupedRecords[monthKey] == nil {
                    groupedRecords[monthKey] = []
                }
                groupedRecords[monthKey]?.append(record)
            }
        }
        
        // Find groups with more than one record (duplicates)
        return groupedRecords.compactMap { monthKey, records in
            records.count > 1 ? DuplicateGroup(dateKey: monthKey, records: records) : nil
        }.sorted { $0.dateKey < $1.dateKey }
    }
    
    private func saveCleanupLog(_ logText: String) throws {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        let logFileName = "PSC_Duplicate_Cleanup_\(timestamp).txt"
        let logFileURL = documentsPath.appendingPathComponent(logFileName)
        
        try logText.write(to: logFileURL, atomically: true, encoding: .utf8)
        redesignLog("📄 Cleanup log saved to: \(logFileURL.path)")
    }
}

