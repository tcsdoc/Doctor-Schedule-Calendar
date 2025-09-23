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
        
        redesignLog("📅 Fetching all schedules...")
        
        let query = CKQuery(recordType: "CD_DailySchedule", predicate: NSPredicate(value: true))
        let (matchResults, _) = try await privateDatabase.records(matching: query, inZoneWith: zoneID)
        
        var schedules: [String: ScheduleRecord] = [:]
        
        for (_, result) in matchResults {
            switch result {
            case .success(let record):
                if let schedule = parseScheduleRecord(record) {
                    let dateKey = dateKey(for: schedule.date)
                    schedules[dateKey] = schedule
                }
            case .failure(let error):
                redesignLog("❌ Failed to process schedule record: \(error)")
            }
        }
        
        redesignLog("✅ Fetched \(schedules.count) schedules")
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
        } catch {
            // Record doesn't exist, create new one
            record = CKRecord(recordType: "CD_DailySchedule", recordID: recordID)
            redesignLog("🆕 Creating new record: \(schedule.id)")
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
        
        redesignLog("📝 Fetching all monthly notes...")
        
        let query = CKQuery(recordType: "CD_MonthlyNotes", predicate: NSPredicate(value: true))
        let (matchResults, _) = try await privateDatabase.records(matching: query, inZoneWith: zoneID)
        
        var notes: [String: MonthlyNote] = [:]
        
        for (_, result) in matchResults {
            switch result {
            case .success(let record):
                if let note = parseMonthlyNoteRecord(record) {
                    notes[note.id] = note
                }
            case .failure(let error):
                redesignLog("❌ Failed to process monthly note record: \(error)")
            }
        }
        
        redesignLog("✅ Fetched \(notes.count) monthly notes")
        return notes
    }
    
    func saveMonthlyNote(_ note: MonthlyNote) async throws {
        try await ensureCustomZoneExists()
        
        redesignLog("💾 Saving monthly note: \(note.id)")
        
        // Create CloudKit record with deterministic ID
        let recordID = CKRecord.ID(recordName: note.id, zoneID: zoneID)
        let record = CKRecord(recordType: "CD_MonthlyNotes", recordID: recordID)
        
        // Create month date for storage
        var components = DateComponents()
        components.year = note.year
        components.month = note.month
        components.day = 1
        let monthDate = Calendar.current.date(from: components) ?? Date()
        
        // Set fields
        record["CD_id"] = note.id as CKRecordValue
        record["CD_month"] = monthDate as CKRecordValue
        record["CD_line1"] = note.line1 as CKRecordValue?
        record["CD_line2"] = note.line2 as CKRecordValue?
        record["CD_line3"] = note.line3 as CKRecordValue?
        
        // Save to CloudKit
        let _ = try await privateDatabase.save(record)
        redesignLog("✅ Monthly note saved: \(note.id)")
    }
    
    // MARK: - Sharing Operations
    func createShare() async throws -> CKShare {
        try await ensureCustomZoneExists()
        
        redesignLog("🔗 Creating share for custom zone...")
        
        // Create share for the custom zone
        let share = CKShare(recordZoneID: zoneID)
        share[CKShare.SystemFieldKey.title] = "Provider Schedule Calendar" as CKRecordValue
        share.publicPermission = .none
        
        // Save the share
        let savedRecord = try await privateDatabase.save(share)
        
        guard let savedShare = savedRecord as? CKShare else {
            throw NSError(domain: "PSC", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create share"])
        }
        
        redesignLog("✅ Share created successfully")
        return savedShare
    }
    
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
        guard let monthDate = record["CD_month"] as? Date else {
            redesignLog("❌ Invalid monthly note record - missing month date")
            return nil
        }
        
        let calendar = Calendar.current
        let month = calendar.component(.month, from: monthDate)
        let year = calendar.component(.year, from: monthDate)
        
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
}

