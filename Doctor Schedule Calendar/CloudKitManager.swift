import Foundation
import CloudKit
import SwiftUI

class CloudKitManager: ObservableObject {
    static let shared = CloudKitManager()
    
    private let container: CKContainer
    private let publicDatabase: CKDatabase
    
    @Published var dailySchedules: [DailyScheduleRecord] = []
    @Published var monthlyNotes: [MonthlyNotesRecord] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var cloudKitAvailable = false
    
    // Enhanced tracking for preventing race conditions
    private var recentDeletionOperations: Set<String> = []
    private var recentSaveOperations: Set<String> = []
    private var lastOperationTime: Date = Date()
    private var pendingOperations: Set<String> = []
    
    // Track data versions to prevent overwrites
    private var localDataVersions: [String: Date] = [:]
    
    init() {
        container = CKContainer(identifier: "iCloud.com.gulfcoast.ProviderCalendar")
        publicDatabase = container.publicCloudDatabase
        checkCloudKitStatus()
        
        print("🚀 CloudKitManager initialized with enhanced sync protection")
    }

    
    // MARK: - CloudKit Account Status
    private func checkCloudKitStatus() {
        container.accountStatus { [weak self] status, error in
            DispatchQueue.main.async {
                switch status {
                case .available:
                    self?.cloudKitAvailable = true
                    self?.errorMessage = nil
                    print("✅ CloudKit available - sync enabled")
                case .noAccount:
                    self?.cloudKitAvailable = false
                    self?.errorMessage = "Please sign in to iCloud in Settings to sync your calendar data."
                    print("❌ CloudKit unavailable - no iCloud account")
                case .restricted:
                    self?.cloudKitAvailable = false
                    self?.errorMessage = "iCloud access is restricted. Calendar sync is disabled."
                    print("❌ CloudKit restricted")
                case .couldNotDetermine:
                    self?.cloudKitAvailable = false
                    self?.errorMessage = "Unable to determine iCloud status. Please check your connection."
                    print("❌ CloudKit status unknown")
                case .temporarilyUnavailable:
                    self?.cloudKitAvailable = false
                    self?.errorMessage = "iCloud is temporarily unavailable. Calendar sync will resume when available."
                    print("⚠️ CloudKit temporarily unavailable")
                @unknown default:
                    self?.cloudKitAvailable = false
                    self?.errorMessage = "Unknown iCloud status. Calendar sync may not work properly."
                    print("❓ CloudKit unknown status")
                }
            }
        }
    }
    
    // MARK: - Enhanced Data Protection Methods
    
    /// Check if data should be protected from CloudKit overwrites
    private func shouldProtectLocalData(for key: String) -> Bool {
        let timeSinceLastOperation = Date().timeIntervalSince(lastOperationTime)
        let hasRecentOperations = !pendingOperations.isEmpty || !recentSaveOperations.isEmpty
        let hasRecentDeletions = recentDeletionOperations.contains(key)
        
        if hasRecentOperations && timeSinceLastOperation < 3.0 {
            print("🛡️ Protecting local data for \(key) - recent operations detected (\(timeSinceLastOperation)s ago)")
            return true
        }
        
        if hasRecentDeletions {
            print("🛡️ Protecting local data for \(key) - recent deletion detected")
            return true
        }
        
        return false
    }
    
    /// Mark operation as starting to track pending state
    private func markOperationStarting(for key: String, type: String) {
        pendingOperations.insert(key)
        lastOperationTime = Date()
        print("🏁 Starting \(type) operation for \(key) - tracking as pending")
    }
    
    /// Mark operation as completed
    private func markOperationCompleted(for key: String, type: String, success: Bool) {
        pendingOperations.remove(key)
        if success {
            recentSaveOperations.insert(key)
            localDataVersions[key] = Date()
            print("✅ Completed \(type) operation for \(key) - marked as recently saved")
            
            // Clear recent save tracking after 5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                self.recentSaveOperations.remove(key)
                print("🧹 Cleared recent save tracking for \(key)")
            }
        } else {
            print("❌ Failed \(type) operation for \(key)")
        }
    }
    
    // MARK: - Fetch Data
    func fetchAllData() {
        print("🔄 fetchAllData called - checking protection conditions")
        
        // Enhanced protection against premature fetching
        let timeSinceLastOperation = Date().timeIntervalSince(lastOperationTime)
        if (timeSinceLastOperation < 3.0 && (!recentDeletionOperations.isEmpty || !pendingOperations.isEmpty)) {
            print("⏸️ Skipping fetch - recent operations detected")
            print("⏰ Time since last operation: \(timeSinceLastOperation)s")
            print("📋 Pending operations: \(pendingOperations.count)")
            print("🗑️ Recent deletions: \(recentDeletionOperations.count)")
            return
        }
        
        // Check CloudKit status first
        guard cloudKitAvailable else {
            print("❌ CloudKit not available - skipping fetch")
            checkCloudKitStatus() // Recheck status
            return
        }
        
        isLoading = true
        errorMessage = nil
        print("📊 Starting comprehensive data fetch")
        
        let group = DispatchGroup()
        
        // Fetch Daily Schedules
        group.enter()
        fetchDailySchedules {
            group.leave()
        }
        
        // Fetch Monthly Notes
        group.enter()
        fetchMonthlyNotes {
            group.leave()
        }
        
        group.notify(queue: .main) { [weak self] in
            self?.isLoading = false
            print("📊 All data fetched - dailySchedules: \(self?.dailySchedules.count ?? 0), monthlyNotes: \(self?.monthlyNotes.count ?? 0)")
            self?.cleanupExpiredOperations()
        }
    }
    
    /// Cleanup expired operations to prevent memory leaks
    private func cleanupExpiredOperations() {
        let cutoffTime = Date().addingTimeInterval(-10.0) // 10 seconds ago
        
        // Clean up old version tracking
        localDataVersions = localDataVersions.filter { _, date in
            date > cutoffTime
        }
        
        print("🧹 Cleaned up expired operation tracking")
    }
    
    /// Force fetch data bypassing deletion protection (for explicit user refresh)
    func forceRefreshAllData() {
        print("🔄 Force refresh called - clearing all protection flags")
        recentDeletionOperations.removeAll()
        recentSaveOperations.removeAll()
        pendingOperations.removeAll()
        localDataVersions.removeAll()
        fetchAllData()
    }
    
    /// Fetch data and perform cleanup of duplicates
    func fetchAllDataWithCleanup() {
        // Check CloudKit status first
        guard cloudKitAvailable else {
            checkCloudKitStatus() // Recheck status
            return
        }
        
        print("🧹 Starting fetch with duplicate cleanup")
        isLoading = true
        errorMessage = nil
        
        // First cleanup duplicates, then fetch fresh data
        cleanupDuplicateRecords { [weak self] deletedCount, error in
            if let error = error {
                print("❌ Cleanup error: \(error)")
                // Continue with fetch even if cleanup failed
            } else if deletedCount > 0 {
                print("✅ Cleaned up \(deletedCount) duplicate records")
            }
            
            // Now fetch the cleaned data
            self?.fetchAllData()
        }
    }
    
    private func fetchDailySchedules(completion: @escaping () -> Void) {
        print("📅 Fetching daily schedules from CloudKit...")
        let query = CKQuery(recordType: "CD_DailySchedule", predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "CD_date", ascending: true)]
        
        publicDatabase.fetch(withQuery: query, inZoneWith: nil, desiredKeys: nil, resultsLimit: CKQueryOperation.maximumResults) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let (matchResults, _)):
                    let records = matchResults.compactMap { _, result in
                        try? result.get()
                    }
                    
                    // Only update if we're not protecting local data
                    var protectedCount = 0
                    let newSchedules = records.map(DailyScheduleRecord.init)
                    
                    for schedule in newSchedules {
                        if self?.shouldProtectLocalData(for: schedule.id) == true {
                            protectedCount += 1
                        }
                    }
                    
                    if protectedCount == 0 {
                        self?.dailySchedules = newSchedules
                        print("✅ Daily schedules updated: \(records.count) records")
                    } else {
                        print("🛡️ Protected \(protectedCount) local daily schedule records from CloudKit overwrite")
                    }
                    
                case .failure(let error):
                    print("❌ Failed to fetch daily schedules: \(error)")
                    self?.errorMessage = "Failed to fetch schedule data: \(error.localizedDescription)"
                    self?.dailySchedules = []
                }
                completion()
            }
        }
    }
    
    private func fetchMonthlyNotes(completion: @escaping () -> Void) {
        print("📝 Fetching monthly notes from CloudKit...")
        let query = CKQuery(recordType: "CD_MonthlyNotes", predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "CD_month", ascending: true)]
        
        publicDatabase.fetch(withQuery: query, inZoneWith: nil, desiredKeys: nil, resultsLimit: CKQueryOperation.maximumResults) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let (matchResults, _)):
                    let records = matchResults.compactMap { _, result in
                        try? result.get()
                    }
                    
                    // Only update if we're not protecting local data
                    var protectedCount = 0
                    let newNotes = records.map(MonthlyNotesRecord.init)
                    
                    for note in newNotes {
                        if self?.shouldProtectLocalData(for: note.id) == true {
                            protectedCount += 1
                        }
                    }
                    
                    if protectedCount == 0 {
                        self?.monthlyNotes = newNotes
                        print("✅ Monthly notes updated: \(records.count) records")
                    } else {
                        print("🛡️ Protected \(protectedCount) local monthly note records from CloudKit overwrite")
                    }
                    
                case .failure(let error):
                    print("❌ Failed to fetch monthly notes: \(error)")
                    self?.errorMessage = "Failed to fetch notes data: \(error.localizedDescription)"
                    self?.monthlyNotes = []
                }
                completion()
            }
        }
    }
    
    // MARK: - Save Data
    func saveDailySchedule(date: Date, line1: String?, line2: String?, line3: String?, completion: @escaping (Bool, Error?) -> Void) {
        let dateKey = "\(Calendar.current.startOfDay(for: date))"
        print("💾 Creating new daily schedule record for date: \(date)")
        
        // Check CloudKit status first
        guard cloudKitAvailable else {
            print("❌ CloudKit not available for save")
            completion(false, NSError(domain: "CloudKitManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "iCloud not available"]))
            return
        }
        
        // Mark operation as starting
        markOperationStarting(for: dateKey, type: "SAVE")
        
        let record = CKRecord(recordType: "CD_DailySchedule")
        record["CD_date"] = date as CKRecordValue
        record["CD_id"] = UUID().uuidString as CKRecordValue
        record["CD_line1"] = line1 as CKRecordValue?
        record["CD_line2"] = line2 as CKRecordValue?
        record["CD_line3"] = line3 as CKRecordValue?
        
        print("💾 Saving new record with fields: line1='\(line1 ?? "nil")', line2='\(line2 ?? "nil")', line3='\(line3 ?? "nil")'")
        
        publicDatabase.save(record) { [weak self] savedRecord, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Failed to save new record: \(error.localizedDescription)")
                    self?.errorMessage = "Failed to save schedule: \(error.localizedDescription)"
                    self?.markOperationCompleted(for: dateKey, type: "SAVE", success: false)
                    completion(false, error)
                } else {
                    print("✅ Successfully saved new daily schedule record")
                    // Update local array immediately instead of full refresh
                    if let savedRecord = savedRecord {
                        let newSchedule = DailyScheduleRecord(from: savedRecord)
                        self?.dailySchedules.append(newSchedule)
                        self?.markOperationCompleted(for: savedRecord.recordID.recordName, type: "SAVE", success: true)
                    }
                    completion(true, nil)
                }
            }
        }
    }
    
    func updateDailySchedule(recordName: String, date: Date, line1: String?, line2: String?, line3: String?, completion: @escaping (Bool, Error?) -> Void) {
        print("🔄 Attempting to update record: \(recordName)")
        
        // Check CloudKit status first
        guard cloudKitAvailable else {
            completion(false, NSError(domain: "CloudKitManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "iCloud not available"]))
            return
        }
        
        // Mark operation as starting
        markOperationStarting(for: recordName, type: "UPDATE")
        
        let recordID = CKRecord.ID(recordName: recordName)
        
        publicDatabase.fetch(withRecordID: recordID) { [weak self] record, error in
            if let error = error {
                DispatchQueue.main.async {
                    print("❌ Failed to fetch record for update: \(error.localizedDescription)")
                    
                    // Check if this is a "Record not found" error - if so, create new record instead
                    if error.localizedDescription.contains("Record not found") || (error as? CKError)?.code == .unknownItem {
                        print("🔄 Record not found in CloudKit - creating new record instead")
                        self?.markOperationCompleted(for: recordName, type: "UPDATE", success: false)
                        self?.saveDailySchedule(date: date, line1: line1, line2: line2, line3: line3, completion: completion)
                    } else {
                        self?.errorMessage = "Failed to fetch record: \(error.localizedDescription)"
                        self?.markOperationCompleted(for: recordName, type: "UPDATE", success: false)
                        completion(false, error)
                    }
                }
                return
            }
            
            guard let record = record else {
                DispatchQueue.main.async {
                    print("❌ Record not found, creating new one instead")
                    // If record doesn't exist, create it instead
                    self?.markOperationCompleted(for: recordName, type: "UPDATE", success: false)
                    self?.saveDailySchedule(date: date, line1: line1, line2: line2, line3: line3, completion: completion)
                }
                return
            }
            
            print("✅ Fetched record for update, updating fields...")
            print("📝 Updating fields: line1='\(line1 ?? "nil")', line2='\(line2 ?? "nil")', line3='\(line3 ?? "nil")'")
            
            // Update the record with new values
            record["CD_date"] = date as CKRecordValue
            record["CD_line1"] = line1 as CKRecordValue?
            record["CD_line2"] = line2 as CKRecordValue?
            record["CD_line3"] = line3 as CKRecordValue?
            
            self?.publicDatabase.save(record) { savedRecord, error in
                DispatchQueue.main.async {
                    if let error = error {
                        print("❌ Failed to update record: \(error.localizedDescription)")
                        self?.errorMessage = "Failed to update schedule: \(error.localizedDescription)"
                        self?.markOperationCompleted(for: recordName, type: "UPDATE", success: false)
                        completion(false, error)
                    } else {
                        print("✅ Record updated successfully")
                        // Update local array immediately instead of full refresh
                        if let savedRecord = savedRecord, let self = self {
                            let updatedSchedule = DailyScheduleRecord(from: savedRecord)
                            if let index = self.dailySchedules.firstIndex(where: { $0.id == recordName }) {
                                self.dailySchedules[index] = updatedSchedule
                            } else {
                                self.dailySchedules.append(updatedSchedule)
                            }
                            self.markOperationCompleted(for: recordName, type: "UPDATE", success: true)
                        }
                        completion(true, nil)
                    }
                }
            }
        }
    }
    
    func deleteDailySchedule(recordName: String, completion: @escaping (Bool, Error?) -> Void) {
        // Check CloudKit status first
        guard cloudKitAvailable else {
            completion(false, NSError(domain: "CloudKitManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "iCloud not available"]))
            return
        }
        
        let recordID = CKRecord.ID(recordName: recordName)
        print("🗑️ Attempting to delete record: \(recordName)")
        
        // Mark operation as starting
        markOperationStarting(for: recordName, type: "DELETE")
        
        publicDatabase.delete(withRecordID: recordID) { [weak self] deletedRecordID, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Error deleting daily schedule: \(error)")
                    self?.errorMessage = "Failed to delete schedule: \(error.localizedDescription)"
                    self?.markOperationCompleted(for: recordName, type: "DELETE", success: false)
                    completion(false, error)
                } else {
                    print("✅ Successfully deleted daily schedule from CloudKit: \(recordName)")
                    // Remove from local array immediately instead of full refresh
                    self?.dailySchedules.removeAll { $0.id == recordName }
                    print("📱 Removed from local array. Local count now: \(self?.dailySchedules.count ?? 0)")
                    
                    // Enhanced tracking for deletion operations
                    self?.recentDeletionOperations.insert(recordName)
                    self?.lastOperationTime = Date()
                    self?.markOperationCompleted(for: recordName, type: "DELETE", success: true)
                    print("🕒 Enhanced tracking for deletion operation \(recordName) - preventing premature fetch")
                    
                    // Clear deletion tracking after 8 seconds (increased from 5)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) {
                        self?.recentDeletionOperations.remove(recordName)
                        print("🧹 Cleared deletion tracking for \(recordName)")
                    }
                    
                    completion(true, nil)
                }
            }
        }
    }
    
    /// Smart save that handles deletion when all fields are empty
    func saveOrDeleteDailySchedule(existingRecordName: String?, date: Date, line1: String?, line2: String?, line3: String?, completion: @escaping (Bool, Error?) -> Void) {
        // Check if all fields are empty
        let isEmpty = (line1?.isEmpty ?? true) && (line2?.isEmpty ?? true) && (line3?.isEmpty ?? true)
        let dateKey = "\(Calendar.current.startOfDay(for: date))"
        
        print("🤔 Smart save called for \(dateKey)")
        print("📊 isEmpty: \(isEmpty), existingRecord: \(existingRecordName ?? "none")")
        print("📝 Field values - line1: '\(line1 ?? "nil")', line2: '\(line2 ?? "nil")', line3: '\(line3 ?? "nil")'")
        
        // Check if we should prevent this operation due to recent activity
        if let recordName = existingRecordName, shouldProtectLocalData(for: recordName) {
            print("🛡️ Skipping operation - local data protection active for \(recordName)")
            completion(true, nil)
            return
        }
        
        if isEmpty && existingRecordName != nil {
            // Delete existing record if all fields are empty
            print("🗑️ All fields empty + existing record - calling DELETE for \(existingRecordName!)")
            deleteDailySchedule(recordName: existingRecordName!, completion: completion)
        } else if !isEmpty {
            // Save or update if there's content
            print("💾 Fields have content - calling SAVE/UPDATE for \(dateKey)")
            if let recordName = existingRecordName {
                updateDailySchedule(recordName: recordName, date: date, line1: line1, line2: line2, line3: line3, completion: completion)
            } else {
                saveDailySchedule(date: date, line1: line1, line2: line2, line3: line3, completion: completion)
            }
        } else {
            // No existing record and no content - do nothing
            print("⏸️ No existing record and no content - doing nothing for \(dateKey)")
            completion(true, nil)
        }
    }
    
    func saveMonthlyNotes(month: Int, year: Int, line1: String?, line2: String?, line3: String?, completion: @escaping (Bool, Error?) -> Void) {
        let monthKey = "\(year)-\(month)"
        print("💾 Saving monthly notes for \(monthKey)")
        
        // Check CloudKit status first
        guard cloudKitAvailable else {
            completion(false, NSError(domain: "CloudKitManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "iCloud not available"]))
            return
        }
        
        // Mark operation as starting
        markOperationStarting(for: monthKey, type: "SAVE_MONTHLY")
        
        // First, check if a record already exists for this month/year
        let predicate = NSPredicate(format: "CD_month == %d AND CD_year == %d", month, year)
        let query = CKQuery(recordType: "CD_MonthlyNotes", predicate: predicate)
        
        publicDatabase.fetch(withQuery: query, inZoneWith: nil, desiredKeys: nil, resultsLimit: CKQueryOperation.maximumResults) { [weak self] (result: Result<(matchResults: [(CKRecord.ID, Result<CKRecord, Error>)], queryCursor: CKQueryOperation.Cursor?), Error>) in
            let record: CKRecord
            
            switch result {
            case .success(let (matchResults, _)):
                let records = matchResults.compactMap { _, result in
                    try? result.get()
                }
                
                if let existingRecord = records.first {
                    // Update existing record
                    record = existingRecord
                    print("📝 Updating existing monthly notes record for \(monthKey)")
                } else {
                    // Create new record
                    record = CKRecord(recordType: "CD_MonthlyNotes")
                    record["CD_id"] = UUID().uuidString as CKRecordValue
                    record["CD_month"] = month as CKRecordValue
                    record["CD_year"] = year as CKRecordValue
                    print("➕ Creating new monthly notes record for \(monthKey)")
                }
                
            case .failure(let error):
                DispatchQueue.main.async {
                    print("❌ Failed to search existing monthly notes: \(error.localizedDescription)")
                    self?.errorMessage = "Failed to search existing notes: \(error.localizedDescription)"
                    self?.markOperationCompleted(for: monthKey, type: "SAVE_MONTHLY", success: false)
                    completion(false, error)
                }
                return
            }
            
            // Update/set the data fields
            record["CD_line1"] = line1 as CKRecordValue?
            record["CD_line2"] = line2 as CKRecordValue?
            record["CD_line3"] = line3 as CKRecordValue?
            
            print("📝 Saving monthly notes with fields: line1='\(line1 ?? "nil")', line2='\(line2 ?? "nil")', line3='\(line3 ?? "nil")'")
            
            self?.publicDatabase.save(record) { savedRecord, error in
                DispatchQueue.main.async {
                    if let error = error {
                        print("❌ Failed to save monthly notes: \(error.localizedDescription)")
                        self?.errorMessage = "Failed to save notes: \(error.localizedDescription)"
                        self?.markOperationCompleted(for: monthKey, type: "SAVE_MONTHLY", success: false)
                        completion(false, error)
                    } else {
                        print("✅ Successfully saved monthly notes for \(monthKey)")
                        // Update local array immediately instead of full refresh
                        if let savedRecord = savedRecord, let self = self {
                            let newNotes = MonthlyNotesRecord(from: savedRecord)
                            if let index = self.monthlyNotes.firstIndex(where: { $0.month == month && $0.year == year }) {
                                self.monthlyNotes[index] = newNotes
                            } else {
                                self.monthlyNotes.append(newNotes)
                            }
                            self.markOperationCompleted(for: savedRecord.recordID.recordName, type: "SAVE_MONTHLY", success: true)
                        }
                        completion(true, nil)
                    }
                }
            }
        }
    }
    
    // MARK: - Smart Save/Delete for Monthly Notes
    func saveOrDeleteMonthlyNotes(existingRecordName: String? = nil, month: Int, year: Int, line1: String?, line2: String?, line3: String?, completion: @escaping (Bool, Error?) -> Void) {
        // Check if all fields are empty
        let isEmpty = (line1?.isEmpty ?? true) && (line2?.isEmpty ?? true) && (line3?.isEmpty ?? true)
        let monthKey = "\(year)-\(month)"
        
        print("🤔 Smart monthly notes save called for \(monthKey)")
        print("📊 isEmpty: \(isEmpty), existingRecord: \(existingRecordName ?? "none")")
        print("📝 Monthly note values - line1: '\(line1 ?? "nil")', line2: '\(line2 ?? "nil")', line3: '\(line3 ?? "nil")'")
        
        // Check if we should prevent this operation due to recent activity
        if let recordName = existingRecordName, shouldProtectLocalData(for: recordName) {
            print("🛡️ Skipping monthly notes operation - local data protection active for \(recordName)")
            completion(true, nil)
            return
        }
        
        if isEmpty {
            // All fields are empty - delete the record if it exists
            if let recordName = existingRecordName {
                print("🗑️ All monthly note fields empty - calling DELETE for \(recordName)")
                deleteMonthlyNotes(recordName: recordName, month: month, year: year, completion: completion)
            } else {
                print("🤷‍♂️ No existing monthly notes record to delete for \(monthKey)")
                completion(true, nil)
            }
        } else {
            // Fields have content - save/update the record
            print("💾 Monthly note fields have content - calling SAVE/UPDATE for \(monthKey)")
            saveMonthlyNotes(month: month, year: year, line1: line1, line2: line2, line3: line3, completion: completion)
        }
    }
    
    func deleteMonthlyNotes(recordName: String, month: Int, year: Int, completion: @escaping (Bool, Error?) -> Void) {
        let monthKey = "\(year)-\(month)"
        print("🗑️ Attempting to delete monthly notes record: \(recordName) for \(monthKey)")
        
        // Check CloudKit status first
        guard cloudKitAvailable else {
            completion(false, NSError(domain: "CloudKitManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "iCloud not available"]))
            return
        }
        
        // Mark operation as starting
        markOperationStarting(for: recordName, type: "DELETE_MONTHLY")
        
        let recordID = CKRecord.ID(recordName: recordName)
        
        publicDatabase.delete(withRecordID: recordID) { [weak self] recordID, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Failed to delete monthly notes record: \(error.localizedDescription)")
                    self?.errorMessage = "Failed to delete notes: \(error.localizedDescription)"
                    self?.markOperationCompleted(for: recordName, type: "DELETE_MONTHLY", success: false)
                    completion(false, error)
                } else {
                    print("✅ Successfully deleted monthly notes from CloudKit: \(recordName)")
                    // Remove from local array immediately instead of full refresh
                    self?.monthlyNotes.removeAll { $0.month == month && $0.year == year }
                    print("📱 Removed from local monthly notes array. Local count now: \(self?.monthlyNotes.count ?? 0)")
                    
                    // Enhanced tracking for deletion operations
                    self?.recentDeletionOperations.insert(recordName)
                    self?.lastOperationTime = Date()
                    self?.markOperationCompleted(for: recordName, type: "DELETE_MONTHLY", success: true)
                    print("🕒 Enhanced tracking for monthly notes deletion \(recordName)")
                    
                    // Clear deletion tracking after 8 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) {
                        self?.recentDeletionOperations.remove(recordName)
                        print("🧹 Cleared monthly notes deletion tracking for \(recordName)")
                    }
                    
                    completion(true, nil)
                }
            }
        }
    }
}

// MARK: - Deduplication Functions
extension CloudKitManager {
    
    /// Removes duplicate daily schedule records, keeping the most recent one
    func deduplicateDailySchedules(completion: @escaping (Int, Error?) -> Void) {
        print("🧹 Starting daily schedule deduplication")
        
        guard cloudKitAvailable else {
            print("❌ CloudKit not available for deduplication")
            completion(0, NSError(domain: "CloudKitManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "iCloud not available"]))
            return
        }
        
        // Mark operation to prevent conflicts
        markOperationStarting(for: "DEDUP_DAILY", type: "DEDUPLICATION")
        
        let query = CKQuery(recordType: "CD_DailySchedule", predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "CD_date", ascending: true)]
        
        publicDatabase.fetch(withQuery: query, inZoneWith: nil, desiredKeys: nil, resultsLimit: CKQueryOperation.maximumResults) { [weak self] result in
            let records: [CKRecord]
            
            switch result {
            case .success(let (matchResults, _)):
                records = matchResults.compactMap { _, result in
                    try? result.get()
                }
                print("📊 Found \(records.count) daily schedule records for deduplication analysis")
            case .failure(let error):
                print("❌ Failed to fetch records for deduplication: \(error)")
                DispatchQueue.main.async {
                    self?.markOperationCompleted(for: "DEDUP_DAILY", type: "DEDUPLICATION", success: false)
                    completion(0, error)
                }
                return
            }
            
            guard !records.isEmpty else {
                print("ℹ️ No daily schedule records found - deduplication complete")
                DispatchQueue.main.async {
                    self?.markOperationCompleted(for: "DEDUP_DAILY", type: "DEDUPLICATION", success: true)
                    completion(0, nil)
                }
                return
            }
            
            // Group records by date
            let calendar = Calendar.current
            var dateGroups: [String: [CKRecord]] = [:]
            
            for record in records {
                if let date = record["CD_date"] as? Date {
                    let dateKey = calendar.startOfDay(for: date).description
                    if dateGroups[dateKey] == nil {
                        dateGroups[dateKey] = []
                    }
                    dateGroups[dateKey]?.append(record)
                }
            }
            
            // Find duplicates and delete older ones
            var recordsToDelete: [CKRecord.ID] = []
            var duplicateGroups = 0
            
            for (dateKey, groupRecords) in dateGroups {
                if groupRecords.count > 1 {
                    duplicateGroups += 1
                    print("🔍 Found \(groupRecords.count) duplicates for date \(dateKey)")
                    
                    // Sort by modification date, keep the most recent
                    let sortedRecords = groupRecords.sorted { record1, record2 in
                        let date1 = record1.modificationDate ?? Date.distantPast
                        let date2 = record2.modificationDate ?? Date.distantPast
                        return date1 < date2
                    }
                    
                    // Delete all but the most recent
                    for i in 0..<(sortedRecords.count - 1) {
                        recordsToDelete.append(sortedRecords[i].recordID)
                        print("🗑️ Marking duplicate daily schedule for deletion: \(sortedRecords[i].recordID.recordName)")
                    }
                }
            }
            
            print("📋 Daily schedule deduplication summary: \(duplicateGroups) groups with duplicates, \(recordsToDelete.count) records to delete")
            
            // Delete duplicate records
            self?.deleteDuplicateRecords(recordIDs: recordsToDelete, type: "daily schedules") { deletedCount, error in
                DispatchQueue.main.async {
                    self?.markOperationCompleted(for: "DEDUP_DAILY", type: "DEDUPLICATION", success: error == nil)
                    
                    if error == nil && deletedCount > 0 {
                        // Refresh data after cleanup
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            self?.fetchAllData()
                        }
                    }
                    completion(deletedCount, error)
                }
            }
        }
    }
    
    /// Removes duplicate monthly notes records, keeping the most recent one
    func deduplicateMonthlyNotes(completion: @escaping (Int, Error?) -> Void) {
        print("🧹 Starting monthly notes deduplication")
        
        guard cloudKitAvailable else {
            print("❌ CloudKit not available for monthly notes deduplication")
            completion(0, NSError(domain: "CloudKitManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "iCloud not available"]))
            return
        }
        
        // Mark operation to prevent conflicts
        markOperationStarting(for: "DEDUP_MONTHLY", type: "DEDUPLICATION")
        
        let query = CKQuery(recordType: "CD_MonthlyNotes", predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "CD_month", ascending: true)]
        
        publicDatabase.fetch(withQuery: query, inZoneWith: nil, desiredKeys: nil, resultsLimit: CKQueryOperation.maximumResults) { [weak self] result in
            let records: [CKRecord]
            
            switch result {
            case .success(let (matchResults, _)):
                records = matchResults.compactMap { _, result in
                    try? result.get()
                }
                print("📊 Found \(records.count) monthly notes records for deduplication analysis")
            case .failure(let error):
                print("❌ Failed to fetch monthly notes records for deduplication: \(error)")
                DispatchQueue.main.async {
                    self?.markOperationCompleted(for: "DEDUP_MONTHLY", type: "DEDUPLICATION", success: false)
                    completion(0, error)
                }
                return
            }
            
            guard !records.isEmpty else {
                print("ℹ️ No monthly notes records found - deduplication complete")
                DispatchQueue.main.async {
                    self?.markOperationCompleted(for: "DEDUP_MONTHLY", type: "DEDUPLICATION", success: true)
                    completion(0, nil)
                }
                return
            }
            
            // Group records by month/year combination
            var monthYearGroups: [String: [CKRecord]] = [:]
            
            for record in records {
                if let month = record["CD_month"] as? Int,
                   let year = record["CD_year"] as? Int {
                    let key = "\(year)-\(month)"
                    if monthYearGroups[key] == nil {
                        monthYearGroups[key] = []
                    }
                    monthYearGroups[key]?.append(record)
                }
            }
            
            // Find duplicates and delete older ones
            var recordsToDelete: [CKRecord.ID] = []
            var duplicateGroups = 0
            
            for (monthKey, groupRecords) in monthYearGroups {
                if groupRecords.count > 1 {
                    duplicateGroups += 1
                    print("🔍 Found \(groupRecords.count) duplicate monthly notes for \(monthKey)")
                    
                    // Sort by modification date, keep the most recent
                    let sortedRecords = groupRecords.sorted { record1, record2 in
                        let date1 = record1.modificationDate ?? Date.distantPast
                        let date2 = record2.modificationDate ?? Date.distantPast
                        return date1 < date2
                    }
                    
                    // Delete all but the most recent
                    for i in 0..<(sortedRecords.count - 1) {
                        recordsToDelete.append(sortedRecords[i].recordID)
                        print("🗑️ Marking duplicate monthly notes for deletion: \(sortedRecords[i].recordID.recordName)")
                    }
                }
            }
            
            print("📋 Monthly notes deduplication summary: \(duplicateGroups) groups with duplicates, \(recordsToDelete.count) records to delete")
            
            // Delete duplicate records
            self?.deleteDuplicateRecords(recordIDs: recordsToDelete, type: "monthly notes") { deletedCount, error in
                DispatchQueue.main.async {
                    self?.markOperationCompleted(for: "DEDUP_MONTHLY", type: "DEDUPLICATION", success: error == nil)
                    
                    if error == nil && deletedCount > 0 {
                        // Refresh data after cleanup
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            self?.fetchAllData()
                        }
                    }
                    completion(deletedCount, error)
                }
            }
        }
    }
    
    /// Helper function to delete multiple records
    private func deleteDuplicateRecords(recordIDs: [CKRecord.ID], type: String, completion: @escaping (Int, Error?) -> Void) {
        guard !recordIDs.isEmpty else {
            print("ℹ️ No duplicate \(type) records to delete")
            completion(0, nil)
            return
        }
        
        print("🗑️ Deleting \(recordIDs.count) duplicate \(type) records")
        
        let deleteOperation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: recordIDs)
        deleteOperation.modifyRecordsResultBlock = { (result: Result<Void, Error>) in
            switch result {
            case .success:
                let deletedCount = recordIDs.count
                print("✅ Successfully deleted \(deletedCount) duplicate \(type) records")
                
                // Track these deletions to prevent immediate refresh conflicts
                for recordID in recordIDs {
                    self.recentDeletionOperations.insert(recordID.recordName)
                }
                self.lastOperationTime = Date()
                
                completion(deletedCount, nil)
            case .failure(let error):
                print("❌ Failed to delete duplicate \(type) records: \(error)")
                completion(0, error)
            }
        }
        
        publicDatabase.add(deleteOperation)
    }
    
    /// Comprehensive cleanup function that removes all duplicates
    func cleanupDuplicateRecords(completion: @escaping (Int, Error?) -> Void) {
        print("🧹 Starting comprehensive duplicate cleanup")
        
        guard cloudKitAvailable else {
            print("❌ CloudKit not available for comprehensive cleanup")
            completion(0, NSError(domain: "CloudKitManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "iCloud not available"]))
            return
        }
        
        var totalDeleted = 0
        
        // First clean up daily schedules
        deduplicateDailySchedules { [weak self] dailyDeleted, error in
            if let error = error {
                print("❌ Daily schedule deduplication failed: \(error)")
                completion(0, error)
                return
            }
            
            totalDeleted += dailyDeleted
            print("📊 Daily schedule cleanup complete: \(dailyDeleted) duplicates removed")
            
            // Then clean up monthly notes
            self?.deduplicateMonthlyNotes { monthlyDeleted, error in
                if let error = error {
                    print("❌ Monthly notes deduplication failed: \(error)")
                    completion(totalDeleted, error)
                    return
                }
                
                totalDeleted += monthlyDeleted
                print("📊 Monthly notes cleanup complete: \(monthlyDeleted) duplicates removed")
                print("✅ Comprehensive cleanup finished: \(totalDeleted) total duplicates removed")
                completion(totalDeleted, nil)
            }
        }
    }
}

// MARK: - Data Models
struct DailyScheduleRecord: Identifiable, Equatable {
    let id: String
    let date: Date?
    let line1: String?
    let line2: String?
    let line3: String?
    let uuid: UUID?
    
    init(from record: CKRecord) {
        self.id = record.recordID.recordName
        self.date = record["CD_date"] as? Date
        self.line1 = record["CD_line1"] as? String
        self.line2 = record["CD_line2"] as? String
        self.line3 = record["CD_line3"] as? String
        if let uuidString = record["CD_id"] as? String {
            self.uuid = UUID(uuidString: uuidString)
        } else {
            self.uuid = nil
        }
    }
}

struct MonthlyNotesRecord: Identifiable, Equatable {
    let id: String
    let month: Int
    let year: Int
    let line1: String?
    let line2: String?
    let line3: String?
    let uuid: UUID?
    
    init(from record: CKRecord) {
        self.id = record.recordID.recordName
        self.month = (record["CD_month"] as? Int) ?? 0
        self.year = (record["CD_year"] as? Int) ?? 0
        self.line1 = record["CD_line1"] as? String
        self.line2 = record["CD_line2"] as? String
        self.line3 = record["CD_line3"] as? String
        if let uuidString = record["CD_id"] as? String {
            self.uuid = UUID(uuidString: uuidString)
        } else {
            self.uuid = nil
        }
    }
} 
