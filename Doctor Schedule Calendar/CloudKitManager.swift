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
    
    init() {
        container = CKContainer(identifier: "iCloud.com.gulfcoast.ProviderCalendar")
        publicDatabase = container.publicCloudDatabase
        checkCloudKitStatus()
    }

    
    // MARK: - CloudKit Account Status
    private func checkCloudKitStatus() {
        container.accountStatus { [weak self] status, error in
            DispatchQueue.main.async {
                switch status {
                case .available:
                    self?.cloudKitAvailable = true
                    self?.errorMessage = nil
                case .noAccount:
                    self?.cloudKitAvailable = false
                    self?.errorMessage = "Please sign in to iCloud in Settings to sync your calendar data."
                case .restricted:
                    self?.cloudKitAvailable = false
                    self?.errorMessage = "iCloud access is restricted. Calendar sync is disabled."
                case .couldNotDetermine:
                    self?.cloudKitAvailable = false
                    self?.errorMessage = "Unable to determine iCloud status. Please check your connection."
                case .temporarilyUnavailable:
                    self?.cloudKitAvailable = false
                    self?.errorMessage = "iCloud is temporarily unavailable. Calendar sync will resume when available."
                @unknown default:
                    self?.cloudKitAvailable = false
                    self?.errorMessage = "Unknown iCloud status. Calendar sync may not work properly."
                }
            }
        }
    }
    
    // MARK: - Fetch Data
    func fetchAllData() {
        // Check CloudKit status first
        guard cloudKitAvailable else {
            checkCloudKitStatus() // Recheck status
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        let group = DispatchGroup()
        
        // Fetch Daily Schedules
        group.enter()
        fetchDailySchedules { [weak self] in
            group.leave()
        }
        
        // Fetch Monthly Notes
        group.enter()
        fetchMonthlyNotes { [weak self] in
            group.leave()
        }
        
        group.notify(queue: .main) { [weak self] in
            self?.isLoading = false
        }
    }
    
    /// Fetch data and perform cleanup of duplicates
    func fetchAllDataWithCleanup() {
        // Check CloudKit status first
        guard cloudKitAvailable else {
            checkCloudKitStatus() // Recheck status
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        // First cleanup duplicates, then fetch fresh data
        cleanupDuplicateRecords { [weak self] deletedCount, error in
            if let error = error {
                print("Cleanup error: \(error)")
                // Continue with fetch even if cleanup failed
            } else if deletedCount > 0 {
                print("Cleaned up \(deletedCount) duplicate records")
            }
            
            // Now fetch the cleaned data
            self?.fetchAllData()
        }
    }
    
    private func fetchDailySchedules(completion: @escaping () -> Void) {
        let query = CKQuery(recordType: "CD_DailySchedule", predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "CD_date", ascending: true)]
        
        publicDatabase.fetch(withQuery: query, inZoneWith: nil, desiredKeys: nil, resultsLimit: CKQueryOperation.maximumResults) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let (matchResults, _)):
                    let records = matchResults.compactMap { _, result in
                        try? result.get()
                    }
                    self?.dailySchedules = records.map(DailyScheduleRecord.init)
                case .failure(let error):
                    self?.errorMessage = "Failed to fetch schedule data: \(error.localizedDescription)"
                    self?.dailySchedules = []
                }
                completion()
            }
        }
    }
    
    private func fetchMonthlyNotes(completion: @escaping () -> Void) {
        let query = CKQuery(recordType: "CD_MonthlyNotes", predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "CD_month", ascending: true)]
        
        publicDatabase.fetch(withQuery: query, inZoneWith: nil, desiredKeys: nil, resultsLimit: CKQueryOperation.maximumResults) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let (matchResults, _)):
                    let records = matchResults.compactMap { _, result in
                        try? result.get()
                    }
                    self?.monthlyNotes = records.map(MonthlyNotesRecord.init)
                case .failure(let error):
                    self?.errorMessage = "Failed to fetch notes data: \(error.localizedDescription)"
                    self?.monthlyNotes = []
                }
                completion()
            }
        }
    }
    
    // MARK: - Save Data
    func saveDailySchedule(date: Date, line1: String?, line2: String?, line3: String?, completion: @escaping (Bool, Error?) -> Void) {
        // Check CloudKit status first
        guard cloudKitAvailable else {
            completion(false, NSError(domain: "CloudKitManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "iCloud not available"]))
            return
        }
        
        let record = CKRecord(recordType: "CD_DailySchedule")
        record["CD_date"] = date as CKRecordValue
        record["CD_id"] = UUID().uuidString as CKRecordValue
        record["CD_line1"] = line1 as CKRecordValue?
        record["CD_line2"] = line2 as CKRecordValue?
        record["CD_line3"] = line3 as CKRecordValue?
        
        publicDatabase.save(record) { [weak self] savedRecord, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.errorMessage = "Failed to save schedule: \(error.localizedDescription)"
                    completion(false, error)
                } else {
                    self?.fetchAllData() // Refresh data
                    completion(true, nil)
                }
            }
        }
    }
    
    func updateDailySchedule(recordName: String, date: Date, line1: String?, line2: String?, line3: String?, completion: @escaping (Bool, Error?) -> Void) {
        // Check CloudKit status first
        guard cloudKitAvailable else {
            completion(false, NSError(domain: "CloudKitManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "iCloud not available"]))
            return
        }
        
        let recordID = CKRecord.ID(recordName: recordName)
        
        publicDatabase.fetch(withRecordID: recordID) { [weak self] record, error in
            if let error = error {
                DispatchQueue.main.async {
                    self?.errorMessage = "Failed to update schedule: \(error.localizedDescription)"
                    completion(false, error)
                }
                return
            }
            
            guard let record = record else {
                DispatchQueue.main.async {
                    completion(false, NSError(domain: "CloudKitManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Record not found"]))
                }
                return
            }
            
            // Update the record
            record["CD_date"] = date as CKRecordValue
            record["CD_line1"] = line1 as CKRecordValue?
            record["CD_line2"] = line2 as CKRecordValue?
            record["CD_line3"] = line3 as CKRecordValue?
            
            self?.publicDatabase.save(record) { savedRecord, error in
                DispatchQueue.main.async {
                    if let error = error {
                        self?.errorMessage = "Failed to update schedule: \(error.localizedDescription)"
                        completion(false, error)
                    } else {
                        self?.fetchAllData() // Refresh data
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
        
        publicDatabase.delete(withRecordID: recordID) { [weak self] deletedRecordID, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Error deleting daily schedule: \(error)")
                    self?.errorMessage = "Failed to delete schedule: \(error.localizedDescription)"
                    completion(false, error)
                } else {
                    print("Successfully deleted daily schedule")
                    self?.fetchAllData() // Refresh data
                    completion(true, nil)
                }
            }
        }
    }
    
    func saveMonthlyNotes(month: Int, year: Int, line1: String?, line2: String?, line3: String?, completion: @escaping (Bool, Error?) -> Void) {
        // Check CloudKit status first
        guard cloudKitAvailable else {
            completion(false, NSError(domain: "CloudKitManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "iCloud not available"]))
            return
        }
        
        // First, check if a record already exists for this month/year
        let predicate = NSPredicate(format: "CD_month == %d AND CD_year == %d", month, year)
        let query = CKQuery(recordType: "CD_MonthlyNotes", predicate: predicate)
        
        publicDatabase.fetch(withQuery: query, inZoneWith: nil, desiredKeys: nil, resultsLimit: CKQueryOperation.maximumResults) { [weak self] result in
            let record: CKRecord
            
            switch result {
            case .success(let (matchResults, _)):
                let records = matchResults.compactMap { _, result in
                    try? result.get()
                }
                
                if let existingRecord = records.first {
                    // Update existing record
                    record = existingRecord
                } else {
                    // Create new record
                    record = CKRecord(recordType: "CD_MonthlyNotes")
                    record["CD_id"] = UUID().uuidString as CKRecordValue
                    record["CD_month"] = month as CKRecordValue
                    record["CD_year"] = year as CKRecordValue
                }
                
            case .failure(let error):
                DispatchQueue.main.async {
                    self?.errorMessage = "Failed to search existing notes: \(error.localizedDescription)"
                    completion(false, error)
                }
                return
            }
            
            // Update/set the data fields
            record["CD_line1"] = line1 as CKRecordValue?
            record["CD_line2"] = line2 as CKRecordValue?
            record["CD_line3"] = line3 as CKRecordValue?
            
            self?.publicDatabase.save(record) { savedRecord, error in
                DispatchQueue.main.async {
                    if let error = error {
                        self?.errorMessage = "Failed to save notes: \(error.localizedDescription)"
                        completion(false, error)
                    } else {
                        self?.fetchAllData() // Refresh data
                        completion(true, nil)
                    }
                }
            }
        }
    }
}

// MARK: - Deduplication Functions
extension CloudKitManager {
    
    /// Removes duplicate daily schedule records, keeping the most recent one
    func deduplicateDailySchedules(completion: @escaping (Int, Error?) -> Void) {
        guard cloudKitAvailable else {
            completion(0, NSError(domain: "CloudKitManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "iCloud not available"]))
            return
        }
        
        let query = CKQuery(recordType: "CD_DailySchedule", predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "CD_date", ascending: true)]
        
        publicDatabase.fetch(withQuery: query, inZoneWith: nil, desiredKeys: nil, resultsLimit: CKQueryOperation.maximumResults) { [weak self] result in
            let records: [CKRecord]
            
            switch result {
            case .success(let (matchResults, _)):
                records = matchResults.compactMap { _, result in
                    try? result.get()
                }
            case .failure(let error):
                DispatchQueue.main.async {
                    completion(0, error)
                }
                return
            }
            
            guard !records.isEmpty else {
                DispatchQueue.main.async {
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
            
            for (_, groupRecords) in dateGroups {
                if groupRecords.count > 1 {
                    // Sort by modification date, keep the most recent
                    let sortedRecords = groupRecords.sorted { record1, record2 in
                        let date1 = record1.modificationDate ?? Date.distantPast
                        let date2 = record2.modificationDate ?? Date.distantPast
                        return date1 < date2
                    }
                    
                    // Delete all but the most recent
                    for i in 0..<(sortedRecords.count - 1) {
                        recordsToDelete.append(sortedRecords[i].recordID)
                    }
                }
            }
            
            // Delete duplicate records
            self?.deleteDuplicateRecords(recordIDs: recordsToDelete) { deletedCount, error in
                DispatchQueue.main.async {
                    if error == nil {
                        self?.fetchAllData() // Refresh data after cleanup
                    }
                    completion(deletedCount, error)
                }
            }
        }
    }
    
    /// Removes duplicate monthly notes records, keeping the most recent one
    func deduplicateMonthlyNotes(completion: @escaping (Int, Error?) -> Void) {
        guard cloudKitAvailable else {
            completion(0, NSError(domain: "CloudKitManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "iCloud not available"]))
            return
        }
        
        let query = CKQuery(recordType: "CD_MonthlyNotes", predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "CD_month", ascending: true)]
        
        publicDatabase.fetch(withQuery: query, inZoneWith: nil, desiredKeys: nil, resultsLimit: CKQueryOperation.maximumResults) { [weak self] result in
            let records: [CKRecord]
            
            switch result {
            case .success(let (matchResults, _)):
                records = matchResults.compactMap { _, result in
                    try? result.get()
                }
            case .failure(let error):
                DispatchQueue.main.async {
                    completion(0, error)
                }
                return
            }
            
            guard !records.isEmpty else {
                DispatchQueue.main.async {
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
            
            for (_, groupRecords) in monthYearGroups {
                if groupRecords.count > 1 {
                    // Sort by modification date, keep the most recent
                    let sortedRecords = groupRecords.sorted { record1, record2 in
                        let date1 = record1.modificationDate ?? Date.distantPast
                        let date2 = record2.modificationDate ?? Date.distantPast
                        return date1 < date2
                    }
                    
                    // Delete all but the most recent
                    for i in 0..<(sortedRecords.count - 1) {
                        recordsToDelete.append(sortedRecords[i].recordID)
                    }
                }
            }
            
            // Delete duplicate records
            self?.deleteDuplicateRecords(recordIDs: recordsToDelete) { deletedCount, error in
                DispatchQueue.main.async {
                    if error == nil {
                        self?.fetchAllData() // Refresh data after cleanup
                    }
                    completion(deletedCount, error)
                }
            }
        }
    }
    
    /// Helper function to delete multiple records
    private func deleteDuplicateRecords(recordIDs: [CKRecord.ID], completion: @escaping (Int, Error?) -> Void) {
        guard !recordIDs.isEmpty else {
            completion(0, nil)
            return
        }
        
        let deleteOperation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: recordIDs)
        deleteOperation.modifyRecordsResultBlock = { (result: Result<Void, Error>) in
            switch result {
            case .success:
                let deletedCount = recordIDs.count
                completion(deletedCount, nil)
            case .failure(let error):
                completion(0, error)
            }
        }
        
        publicDatabase.add(deleteOperation)
    }
    
    /// Comprehensive cleanup function that removes all duplicates
    func cleanupDuplicateRecords(completion: @escaping (Int, Error?) -> Void) {
        guard cloudKitAvailable else {
            completion(0, NSError(domain: "CloudKitManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "iCloud not available"]))
            return
        }
        
        var totalDeleted = 0
        
        // First clean up daily schedules
        deduplicateDailySchedules { [weak self] dailyDeleted, error in
            if let error = error {
                completion(0, error)
                return
            }
            
            totalDeleted += dailyDeleted
            
            // Then clean up monthly notes
            self?.deduplicateMonthlyNotes { monthlyDeleted, error in
                if let error = error {
                    completion(totalDeleted, error)
                    return
                }
                
                totalDeleted += monthlyDeleted
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
