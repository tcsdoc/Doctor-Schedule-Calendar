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
        
    }
    
    // MARK: - CloudKit Availability
    func checkCloudKitAvailability() async -> Bool {
        do {
            let status = try await container.accountStatus()
            let available = status == .available
            return available
        } catch {
            redesignLog("❌ CloudKit status check failed: \(error)")
            return false
        }
    }
    
    // MARK: - Zone Management
    private func ensureCustomZoneExists() async throws {
        
        do {
            // Try to fetch the zone
            let zones = try await privateDatabase.allRecordZones()
            
            if zones.contains(where: { $0.zoneID == zoneID }) {
            } else {
                let _ = try await privateDatabase.save(customZone)
            }
        } catch {
            redesignLog("❌ Zone management failed: \(error)")
            throw error
        }
    }
    
    // MARK: - Schedule Operations
    func saveSchedule(_ schedule: ScheduleRecord) async throws {
        try await ensureCustomZoneExists()
        
        
        let recordID = CKRecord.ID(recordName: schedule.id, zoneID: zoneID)
        
        // Try to fetch existing record first, create new if doesn't exist
        let record: CKRecord
        do {
            // Try to fetch existing record to update it
            record = try await privateDatabase.record(for: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            // ONLY create new record if it truly doesn't exist
            record = CKRecord(recordType: "CD_DailySchedule", recordID: recordID)
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
    }
    
    func deleteSchedule(recordName: String) async throws {
        
        let recordID = CKRecord.ID(recordName: recordName, zoneID: zoneID)
        
        do {
            let _ = try await privateDatabase.deleteRecord(withID: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            // Record doesn't exist - that's fine
        } catch {
            redesignLog("❌ Delete failed: \(error)")
            throw error
        }
    }
    
    // MARK: - Monthly Notes Operations
    func saveMonthlyNote(_ note: MonthlyNote) async throws {
        try await ensureCustomZoneExists()
        
        
        let recordID = CKRecord.ID(recordName: note.id, zoneID: zoneID)
        
        // Try to fetch existing record first, create new if doesn't exist
        let record: CKRecord
        do {
            // Try to fetch existing record to update it
            record = try await privateDatabase.record(for: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            // ONLY create new record if it truly doesn't exist
            record = CKRecord(recordType: "CD_MonthlyNotes", recordID: recordID)
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
    }
    
    func deleteMonthlyNote(recordName: String) async throws {
        
        let recordID = CKRecord.ID(recordName: recordName, zoneID: zoneID)
        
        do {
            let _ = try await privateDatabase.deleteRecord(withID: recordID)
        } catch let error as CKError where error.code == .unknownItem {
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
            id: record.recordID.recordName,
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
            id: record.recordID.recordName,
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
        
        do {
            let predicate = NSPredicate(format: "TRUEPREDICATE")
            let query = CKQuery(recordType: "cloudkit.share", predicate: predicate)
            
            let result = try await privateDatabase.records(matching: query, inZoneWith: zoneID)
            
            for (_, recordResult) in result.matchResults {
                switch recordResult {
                case .success(let record):
                    if let share = record as? CKShare {
                        let deleteResult = try await privateDatabase.modifyRecords(saving: [], deleting: [share.recordID])
                        
                        for (deletedID, deleteResult) in deleteResult.deleteResults {
                            switch deleteResult {
                            case .success:
                                break
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
            
        } catch {
            redesignLog("❌ Error during share deletion: \(error)")
            throw error
        }
    }
    func createCustomZoneShare() async throws -> CKShare {
        
        // Ensure custom zone exists
        try await ensureCustomZoneExists()
        
        // Create zone-level share for ScheduleViewer (anyone with the link can read)
        let share = CKShare(recordZoneID: zoneID)
        let currentYear = Calendar.current.component(.year, from: Date())
        share[CKShare.SystemFieldKey.title] = "Provider Schedule \(currentYear)" as CKRecordValue
        share.publicPermission = .readOnly
        
        let savedRecords = try await privateDatabase.modifyRecords(saving: [share], deleting: [])
        
        for (_, result) in savedRecords.saveResults {
            switch result {
            case .success(let record):
                if let shareRecord = record as? CKShare {
                    guard let shareURL = shareRecord.url else {
                        redesignLog("❌ Share saved but CloudKit returned no URL")
                        throw NSError(
                            domain: "CloudKitManager",
                            code: -3,
                            userInfo: [NSLocalizedDescriptionKey: "Share was created but CloudKit did not return a URL. Please try again."]
                        )
                    }
                    redesignLog("✅ Created workable link share")
                    redesignLog("   URL: \(shareURL.absoluteString)")
                    redesignLog("   publicPermission: readOnly, participants: \(shareRecord.participants.count)")
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
        
        do {
            // Query for share records in the zone (correct approach)
            let predicate = NSPredicate(format: "TRUEPREDICATE")
            let query = CKQuery(recordType: "cloudkit.share", predicate: predicate)
            
            let result = try await privateDatabase.records(matching: query, inZoneWith: zoneID)
            
            // Look for the first share record
            for (recordID, recordResult) in result.matchResults {
                switch recordResult {
                case .success(let record):
                    if let share = record as? CKShare {
                        return share
                    } else {
                        redesignLog("⚠️ Found cloudkit.share record but not CKShare type: \(type(of: record))")
                    }
                case .failure(let error):
                    redesignLog("❌ Error fetching share record \(recordID.recordName): \(error)")
                }
            }
            
            return nil
            
        } catch {
            if let ckError = error as? CKError, ckError.code == .unknownItem {
            }
            return nil
        }
    }
    
    func getOrCreateZoneShare() async throws -> CKShare {
        // First try to fetch existing share
        if let existingShare = try await fetchExistingZoneShare() {
            let currentYear = Calendar.current.component(.year, from: Date())
            let title = existingShare[CKShare.SystemFieldKey.title] as? String ?? ""
            let isLinkShare = existingShare.publicPermission == .readOnly
            let hasURL = existingShare.url != nil
            let isCurrentYear = title.contains(String(currentYear))
            
            // Link shares normally have only the owner as a participant.
            // Do NOT treat owner-only as broken — that was deleting valid shares
            // and leaving recipients with dead "Share not found" URLs.
            if isLinkShare && hasURL && isCurrentYear {
                redesignLog("✅ Reusing existing link share: \(existingShare.url?.absoluteString ?? "nil")")
                redesignLog("   participants=\(existingShare.participants.count), publicPermission=readOnly")
                return existingShare
            }
            
            // Invite-only, missing URL, or stale prior-year share — replace with a fresh link share
            redesignLog("🚨 Replacing unusable share (link=\(isLinkShare), url=\(hasURL), yearOK=\(isCurrentYear), participants=\(existingShare.participants.count), title=\(title))")
            try await deleteBrokenShare()
            return try await createCustomZoneShare()
        }
        
        // Create new share if none exists
        return try await createCustomZoneShare()
    }
    
    /// Force-delete any existing zone share and create a fresh .readOnly link share.
    func recreateZoneShare() async throws -> CKShare {
        redesignLog("🔄 Force recreating zone share for ScheduleViewer...")
        do {
            try await deleteBrokenShare()
        } catch {
            // Continue — stale/missing shares should not block issuing a new link
            redesignLog("⚠️ Share cleanup before recreate reported: \(error.localizedDescription)")
        }
        return try await createCustomZoneShare()
    }
    
    // MARK: - Duplicate Detection & Cleanup (Option B)
    
    struct ZoneFetchResult {
        let schedules: [String: ScheduleRecord]
        let monthlyNotes: [String: MonthlyNote]
        let duplicates: DuplicateDetectionResult
    }
    
    static func winningRecord(of records: [CKRecord]) -> CKRecord? {
        records.max(by: {
            (($0.modificationDate ?? $0.creationDate) ?? Date.distantPast) <
            (($1.modificationDate ?? $1.creationDate) ?? Date.distantPast)
        })
    }
    
    /// Represents a duplicate record set for a specific date
    struct DuplicateGroup {
        let dateKey: String
        let records: [CKRecord]
        
        var recordCount: Int { records.count }
        
        /// Returns the record to keep (most recently modified)
        var recordToKeep: CKRecord? {
            SimpleCloudKitManager.winningRecord(of: records)
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
    
    func fetchAllData() async throws -> ZoneFetchResult {
        try await ensureCustomZoneExists()
        
        let rawSchedules = try await fetchAllRawScheduleRecords()
        let rawNotes = try await fetchAllRawMonthlyNoteRecords()
        
        var schedules: [String: ScheduleRecord] = [:]
        var scheduleGroups: [String: [CKRecord]] = [:]
        
        for record in rawSchedules {
            guard let date = record["CD_date"] as? Date else {
                redesignLog("❌ Invalid schedule record - missing date")
                continue
            }
            let key = dateKey(for: date)
            scheduleGroups[key, default: []].append(record)
        }
        
        for (key, group) in scheduleGroups {
            guard let winner = Self.winningRecord(of: group),
                  let schedule = parseScheduleRecord(winner) else { continue }
            schedules[key] = schedule
        }
        
        var monthlyNotes: [String: MonthlyNote] = [:]
        var noteGroups: [String: [CKRecord]] = [:]
        
        for record in rawNotes {
            guard let month = record["CD_month"] as? Int,
                  let year = record["CD_year"] as? Int else {
                redesignLog("❌ Invalid monthly note record - missing month/year integers")
                continue
            }
            let key = String(format: "%04d-%02d", year, month)
            noteGroups[key, default: []].append(record)
        }
        
        for (key, group) in noteGroups {
            guard let winner = Self.winningRecord(of: group),
                  let note = parseMonthlyNoteRecord(winner) else { continue }
            monthlyNotes[key] = note
        }
        
        let scheduleDuplicates = findDuplicatesInSchedules(rawSchedules)
        let monthlyNoteDuplicates = findDuplicatesInMonthlyNotes(rawNotes)
        let duplicates = DuplicateDetectionResult(
            scheduleDuplicates: scheduleDuplicates,
            monthlyNoteDuplicates: monthlyNoteDuplicates
        )
        
        if duplicates.hasDuplicates {
            redesignLog("⚠️ Found \(duplicates.totalDuplicateCount) duplicate records across \(duplicates.totalAffectedDates) dates")
        }
        
        return ZoneFetchResult(
            schedules: schedules,
            monthlyNotes: monthlyNotes,
            duplicates: duplicates
        )
    }
    
    /// Delete duplicate records, keeping the most recent ones
    func cleanupDuplicates(_ result: DuplicateDetectionResult) async throws -> String {
        
        var deletedCount = 0
        var logEntries: [String] = []
        logEntries.append("=== DUPLICATE CLEANUP LOG ===")
        logEntries.append("Date: \(Date())")
        logEntries.append("")
        
        // Clean up schedule duplicates
        for duplicateGroup in result.scheduleDuplicates {
            
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
                } catch {
                    logEntries.append("  ✗ Failed to delete: \(recordToDelete.recordID.recordName) - \(error.localizedDescription)")
                    redesignLog("  ❌ Failed to delete: \(error)")
                }
            }
            logEntries.append("")
        }
        
        // Clean up monthly note duplicates
        for duplicateGroup in result.monthlyNoteDuplicates {
            
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
                } catch {
                    logEntries.append("  ✗ Failed to delete: \(recordToDelete.recordID.recordName) - \(error.localizedDescription)")
                    redesignLog("  ❌ Failed to delete: \(error)")
                }
            }
            logEntries.append("")
        }
        
        logEntries.append("=== CLEANUP COMPLETE ===")
        logEntries.append("Total records deleted: \(deletedCount)")
        
        
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
    }
}

