import Foundation
import CloudKit
import SwiftUI

// MARK: - Debug Logging Helper
func debugLog(_ message: String) {
    #if DEBUG
    print(message)
    #endif
}

@MainActor
class CloudKitManager: ObservableObject {
    static let shared = CloudKitManager()
    
    private let container: CKContainer
    private let publicDatabase: CKDatabase
    private var userCustomZone: CKRecordZone?
    private let userZoneID: CKRecordZone.ID
    
    @Published var dailySchedules: [DailyScheduleRecord] = []
    @Published var monthlyNotes: [MonthlyNotesRecord] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var cloudKitAvailable = false
    
    // CRITICAL: Global protection for precision codes during editing
    private var activeEditingSessions: Set<String> = []
    var isAnyFieldBeingEdited: Bool {
        return !activeEditingSessions.isEmpty
    }
    
    /// Register an active editing session - prevents ALL refresh operations
    func startEditingSession(for identifier: String) {
        activeEditingSessions.insert(identifier)
        debugLog("🛡️ EDIT SESSION STARTED: \(identifier) (active: \(activeEditingSessions.count))")
    }
    
    /// End an editing session - allows refresh when no sessions active
    func endEditingSession(for identifier: String) {
        activeEditingSessions.remove(identifier)
        debugLog("🛡️ EDIT SESSION ENDED: \(identifier) (active: \(activeEditingSessions.count))")
    }
    
    // Enhanced tracking for preventing race conditions
    private var recentDeletionOperations: Set<String> = []
    private var recentSaveOperations: Set<String> = []
    private(set) var lastOperationTime: Date = Date()
    private var pendingOperations: Set<String> = []
    

    
    // Track data versions to prevent overwrites
    private var localDataVersions: [String: Date] = [:]
    
    init() {
        container = CKContainer(identifier: "iCloud.com.gulfcoast.ProviderCalendar")
        publicDatabase = container.privateCloudDatabase  // Use private database with sharing for privacy
        
        // Create user-specific zone for privacy and sharing
        let userIdentifier = "user_\(container.containerIdentifier?.replacingOccurrences(of: "iCloud.", with: "") ?? "unknown")"
        userZoneID = CKRecordZone.ID(zoneName: userIdentifier)
        
        debugLog("🚀 CloudKitManager INIT - Privacy-focused custom zones enabled")
        debugLog("🔒 User zone will be: \(userZoneID.zoneName)")
        
        checkCloudKitStatus()
        setupUserCustomZone()
        
        debugLog("🚀 CloudKitManager initialized with privacy-focused custom zones")
        debugLog("🔒 User zone: \(userZoneID.zoneName) for data isolation")
    }

    
    // MARK: - CloudKit Account Status
    private func checkCloudKitStatus() {
        container.accountStatus { [weak self] status, error in
            DispatchQueue.main.async {
                switch status {
                case .available:
                    let wasUnavailable = !(self?.cloudKitAvailable ?? false)
                    self?.cloudKitAvailable = true
                    self?.errorMessage = nil
                    debugLog("✅ CloudKit available - sync enabled")
                    
                    // If CloudKit just became available, automatically fetch data
                    if wasUnavailable {
                        debugLog("🔄 CloudKit just became available - auto-fetching data")
                        self?.fetchAllData()
                    }
                case .noAccount:
                    self?.cloudKitAvailable = false
                    self?.errorMessage = "Please sign in to iCloud in Settings to sync your calendar data."
                    debugLog("❌ CloudKit unavailable - no iCloud account")
                case .restricted:
                    self?.cloudKitAvailable = false
                    self?.errorMessage = "iCloud access is restricted. Calendar sync is disabled."
                    debugLog("❌ CloudKit restricted")
                case .couldNotDetermine:
                    self?.cloudKitAvailable = false
                    self?.errorMessage = "Unable to determine iCloud status. Please check your connection."
                    debugLog("❌ CloudKit status unknown")
                case .temporarilyUnavailable:
                    self?.cloudKitAvailable = false
                    self?.errorMessage = "iCloud is temporarily unavailable. Calendar sync will resume when available."
                    debugLog("⚠️ CloudKit temporarily unavailable")
                @unknown default:
                    self?.cloudKitAvailable = false
                    self?.errorMessage = "Unknown iCloud status. Calendar sync may not work properly."
                    debugLog("❓ CloudKit unknown status")
                }
            }
        }
    }
    
    // MARK: - Custom Zone Setup for Privacy
    
    /// Setup user-specific zone for data isolation and sharing
    private func setupUserCustomZone() {
        debugLog("🔒 Setting up custom zone for user data isolation...")
        
        Task {
            do {
                debugLog("🔒 SETUP: Checking for existing zones...")
                
                // Check if zone already exists
                let existingZones = try await publicDatabase.allRecordZones()
                
                debugLog("🔒 SETUP: Found \(existingZones.count) existing zones")
                
                
                if existingZones.contains(where: { $0.zoneID == userZoneID }) {
                    debugLog("✅ Custom zone \(userZoneID.zoneName) already exists")
                    userCustomZone = existingZones.first { $0.zoneID == userZoneID }
                    
                    // Zone is ready, trigger initial data fetch if CloudKit is available
                DispatchQueue.main.async {
                        if self.cloudKitAvailable && self.dailySchedules.isEmpty && self.monthlyNotes.isEmpty {
                            debugLog("🔄 Custom zone ready - triggering initial data fetch")
                            self.fetchAllData()
                }
            }
            } else {
                    // Create new custom zone
                let newZone = CKRecordZone(zoneID: userZoneID)
                    let result = try await publicDatabase.modifyRecordZones(saving: [newZone], deleting: [])
                    userCustomZone = try result.saveResults[userZoneID]?.get()
                    debugLog("✅ SETUP: Created new custom zone: \(userZoneID.zoneName) for data isolation")
                }
            } catch {
                debugLog("❌ SETUP: Failed to setup custom zone: \(error)")
                debugLog("⚠️ Will continue with default zone for backward compatibility")
            }
        }
    }
    
    
    // MARK: - Enhanced Data Protection Methods
    
    /// Check if data should be protected from CloudKit overwrites
    func shouldProtectLocalData(for key: String) -> Bool {
        let timeSinceLastOperation = Date().timeIntervalSince(lastOperationTime)
        let hasRecentOperations = !pendingOperations.isEmpty || !recentSaveOperations.isEmpty
        let hasRecentDeletions = recentDeletionOperations.contains(key)
        
        if hasRecentOperations && timeSinceLastOperation < 3.0 {
            debugLog("🛡️ Protecting local data for \(key) - recent operations detected (\(timeSinceLastOperation)s ago)")
            return true
        }
        
        if hasRecentDeletions {
            debugLog("🛡️ Protecting local data for \(key) - recent deletion detected")
            return true
        }
        
        return false
    }
    
    /// Mark operation as starting to track pending state
    private func markOperationStarting(for key: String, type: String) {
        pendingOperations.insert(key)
        lastOperationTime = Date()
        debugLog("🏁 Starting \(type) operation for \(key) - tracking as pending")
    }
    
    /// Mark operation as completed
    private func markOperationCompleted(for key: String, type: String, success: Bool) {
        pendingOperations.remove(key)
        if success {
            recentSaveOperations.insert(key)
            localDataVersions[key] = Date()
            debugLog("✅ Completed \(type) operation for \(key) - marked as recently saved")
            
            // Clear recent save tracking after 5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                self.recentSaveOperations.remove(key)
                debugLog("🧹 Cleared recent save tracking for \(key)")
            }
        } else {
            debugLog("❌ Failed \(type) operation for \(key)")
        }
    }
    
    // MARK: - Fetch Data
    func fetchAllData() {
        debugLog("🔄 fetchAllData called - checking protection conditions")
        
        // CRITICAL: Never fetch while precision codes are being edited
        if isAnyFieldBeingEdited {
            debugLog("🛡️ BLOCKED fetchAllData - precision codes being edited (sessions: \(activeEditingSessions.count))")
            return
        }
        
        // Enhanced protection against premature fetching
        let timeSinceLastOperation = Date().timeIntervalSince(lastOperationTime)
        if (timeSinceLastOperation < 3.0 && (!recentDeletionOperations.isEmpty || !pendingOperations.isEmpty)) {
            debugLog("⏸️ Skipping fetch - recent operations detected")
            debugLog("⏰ Time since last operation: \(timeSinceLastOperation)s")
            debugLog("📋 Pending operations: \(pendingOperations.count)")
            debugLog("🗑️ Recent deletions: \(recentDeletionOperations.count)")
            return
        }
        
        // Check CloudKit status first
        guard cloudKitAvailable else {
            debugLog("❌ CloudKit not available - will retry when available")
            checkCloudKitStatus() // Recheck status and auto-fetch when ready
            
            // Add a backup retry after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                if self.cloudKitAvailable && self.dailySchedules.isEmpty && self.monthlyNotes.isEmpty {
                    debugLog("🔄 Backup retry - CloudKit now available, fetching data")
                    self.fetchAllData()
                }
            }
            return
        }
        
        isLoading = true
        errorMessage = nil
        debugLog("📊 Starting comprehensive data fetch")
        
        let group = DispatchGroup()
        
        // Fetch Daily
        // 
        // 
        // Schedules
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
            debugLog("📊 All data fetched - dailySchedules: \(self?.dailySchedules.count ?? 0), monthlyNotes: \(self?.monthlyNotes.count ?? 0)")
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
        
        debugLog("🧹 Cleaned up expired operation tracking")
    }
    
    /// Force fetch data bypassing deletion protection (for explicit user refresh)
    func forceRefreshAllData() {
        debugLog("🔄 Force refresh called - clearing all protection flags")
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
        
        debugLog("🧹 Starting fetch with duplicate cleanup")
        isLoading = true
        errorMessage = nil
        
        // First cleanup duplicates, then fetch fresh data
        cleanupDuplicateRecords { [weak self] deletedCount, error in
            if let error = error {
                debugLog("❌ Cleanup error: \(error)")
                // Continue with fetch even if cleanup failed
            } else if deletedCount > 0 {
                debugLog("✅ Cleaned up \(deletedCount) duplicate records")
            }
            
            // Now fetch the cleaned data
            self?.fetchAllData()
        }
    }
    
    private func fetchDailySchedules(completion: @escaping () -> Void) {
        debugLog("📅 Fetching daily schedules from custom zone only...")
        
        // Fetch only from custom zone for clean, single-source data
        fetchDailySchedulesFromCustomZone(completion: completion)
    }
    
    /// Fetch daily schedules from custom zone only (single source of truth)
    private func fetchDailySchedulesFromCustomZone(completion: @escaping () -> Void) {
        let query = CKQuery(recordType: "CD_DailySchedule", predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "CD_date", ascending: true)]
        
        guard let customZone = userCustomZone else {
            debugLog("❌ Custom zone not available - no data to fetch")
            DispatchQueue.main.async { [weak self] in
                self?.dailySchedules = []
                completion()
            }
            return
        }
        
        publicDatabase.fetch(withQuery: query, inZoneWith: customZone.zoneID, desiredKeys: nil, resultsLimit: CKQueryOperation.maximumResults) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let (matchResults, _)):
                    let records = matchResults.compactMap { _, result in try? result.get() }
                    let schedules = records.map(DailyScheduleRecord.init)
                    
                    var protectedCount = 0
                    for schedule in schedules {
                        if self?.shouldProtectLocalData(for: schedule.id) == true {
                            protectedCount += 1
                        }
                    }
                    
                    if protectedCount == 0 {
                        self?.dailySchedules = schedules.sorted { ($0.date ?? Date()) < ($1.date ?? Date()) }
                        debugLog("✅ Daily schedules updated from CUSTOM zone: \(schedules.count) records")
                    } else {
                        debugLog("🛡️ Protected \(protectedCount) local daily schedule records from CloudKit overwrite")
                        debugLog("🔍 PROTECTION DEBUG:")
                        debugLog("   Total records fetched: \(schedules.count)")
                        debugLog("   Protected records: \(protectedCount)")
                        debugLog("   Current local count: \(self?.dailySchedules.count ?? 0)")
                        debugLog("   Recent operations: \(self?.recentSaveOperations.count ?? 0)")
                        debugLog("   Pending operations: \(self?.pendingOperations.count ?? 0)")
                        debugLog("   Recent deletions: \(self?.recentDeletionOperations.count ?? 0)")
                    }
                    
                case .failure(let error):
                    debugLog("❌ Failed to fetch daily schedules from custom zone: \(error)")
                    self?.errorMessage = "Failed to fetch schedule data: \(error.localizedDescription)"
                    self?.dailySchedules = []
                }
                completion()
            }
        }
    }
    
    /// Legacy method - Fetch from both default zone (existing data) and custom zone (new data) to preserve all data
    private func fetchDailySchedulesFromBothZones(completion: @escaping () -> Void) {
        let query = CKQuery(recordType: "CD_DailySchedule", predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "CD_date", ascending: true)]
        
        var allSchedules: [DailyScheduleRecord] = []
        let dispatchGroup = DispatchGroup()
        
        // Fetch from default zone (existing data)
        dispatchGroup.enter()
        publicDatabase.fetch(withQuery: query, inZoneWith: nil, desiredKeys: nil, resultsLimit: CKQueryOperation.maximumResults) { result in
            switch result {
            case .success(let (matchResults, _)):
                let records = matchResults.compactMap { _, result in try? result.get() }
                let schedules = records.map(DailyScheduleRecord.init)
                allSchedules.append(contentsOf: schedules)
                debugLog("✅ Found \(records.count) daily schedules in DEFAULT zone (existing data)")
            case .failure(let error):
                debugLog("❌ Failed to fetch from default zone: \(error)")
            }
            dispatchGroup.leave()
        }
        
        // Fetch from custom zone (new data) if available
        if let customZone = userCustomZone {
            dispatchGroup.enter()
            publicDatabase.fetch(withQuery: query, inZoneWith: customZone.zoneID, desiredKeys: nil, resultsLimit: CKQueryOperation.maximumResults) { result in
                switch result {
                case .success(let (matchResults, _)):
                    let records = matchResults.compactMap { _, result in try? result.get() }
                    let schedules = records.map(DailyScheduleRecord.init)
                    allSchedules.append(contentsOf: schedules)
                    debugLog("✅ Found \(records.count) daily schedules in CUSTOM zone \(customZone.zoneID.zoneName)")
                case .failure(let error):
                    debugLog("❌ Failed to fetch from custom zone: \(error)")
                }
                dispatchGroup.leave()
            }
        }
        
        // Combine results from both zones
        dispatchGroup.notify(queue: .main) { [weak self] in
            // Remove duplicates by ID and update
            let uniqueSchedules = Array(Set(allSchedules))
            
            var protectedCount = 0
            for schedule in uniqueSchedules {
                if self?.shouldProtectLocalData(for: schedule.id) == true {
                    protectedCount += 1
                }
            }
            
            if protectedCount == 0 {
                self?.dailySchedules = uniqueSchedules.sorted { ($0.date ?? Date()) < ($1.date ?? Date()) }
                debugLog("✅ Combined daily schedules updated: \(uniqueSchedules.count) total records")
            } else {
                debugLog("🛡️ Protected \(protectedCount) local daily schedule records from CloudKit overwrite")
            }
            
                    completion()
                }
    }
    
    /// Original fetch method for backward compatibility
    private func fetchDailySchedulesLegacy(completion: @escaping () -> Void) {
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
                        debugLog("✅ Daily schedules updated: \(records.count) records")
                    } else {
                        debugLog("🛡️ Protected \(protectedCount) local daily schedule records from CloudKit overwrite")
                    }
                    
            case .failure(let error):
                debugLog("❌ Failed to fetch daily schedules: \(error)")
                    self?.errorMessage = "Failed to fetch schedule data: \(error.localizedDescription)"
                    self?.dailySchedules = []
                }
                    completion()
            }
        }
    }
    
    private func fetchMonthlyNotes(completion: @escaping () -> Void) {
        debugLog("📝 Fetching monthly notes from custom zone only...")
        
        // Fetch only from custom zone for clean, single-source data
        fetchMonthlyNotesFromCustomZone(completion: completion)
    }
    
    /// Fetch monthly notes from custom zone only (single source of truth)
    private func fetchMonthlyNotesFromCustomZone(completion: @escaping () -> Void) {
        let query = CKQuery(recordType: "CD_MonthlyNotes", predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "CD_month", ascending: true)]
        
        guard let customZone = userCustomZone else {
            debugLog("❌ Custom zone not available - no monthly notes to fetch")
            DispatchQueue.main.async { [weak self] in
                self?.monthlyNotes = []
                completion()
            }
            return
        }
        
        publicDatabase.fetch(withQuery: query, inZoneWith: customZone.zoneID, desiredKeys: nil, resultsLimit: CKQueryOperation.maximumResults) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let (matchResults, _)):
                    let records = matchResults.compactMap { _, result in try? result.get() }
                    let notes = records.map(MonthlyNotesRecord.init)
                    
                    var protectedCount = 0
                    for note in notes {
                        if self?.shouldProtectLocalData(for: note.id) == true {
                            protectedCount += 1
                        }
                    }
                    
                    if protectedCount == 0 {
                        self?.monthlyNotes = notes.sorted { $0.year < $1.year || ($0.year == $1.year && $0.month < $1.month) }
                        debugLog("✅ Monthly notes updated from CUSTOM zone: \(notes.count) records")
                    } else {
                        debugLog("🛡️ Protected \(protectedCount) local monthly note records from CloudKit overwrite")
                        debugLog("🔍 MONTHLY NOTES PROTECTION DEBUG:")
                        debugLog("   Total notes fetched: \(notes.count)")
                        debugLog("   Protected notes: \(protectedCount)")
                        debugLog("   Current local count: \(self?.monthlyNotes.count ?? 0)")
                    }
                    
                case .failure(let error):
                    debugLog("❌ Failed to fetch monthly notes from custom zone: \(error)")
                    self?.errorMessage = "Failed to fetch notes data: \(error.localizedDescription)"
                    self?.monthlyNotes = []
                }
                completion()
            }
        }
    }
    
    /// Legacy method - Fetch monthly notes from both default zone (existing data) and custom zone (new data)
    private func fetchMonthlyNotesFromBothZones(completion: @escaping () -> Void) {
        let query = CKQuery(recordType: "CD_MonthlyNotes", predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "CD_month", ascending: true)]
        
        var allNotes: [MonthlyNotesRecord] = []
        let dispatchGroup = DispatchGroup()
        
        // Fetch from default zone (existing data)
        dispatchGroup.enter()
        publicDatabase.fetch(withQuery: query, inZoneWith: nil, desiredKeys: nil, resultsLimit: CKQueryOperation.maximumResults) { result in
            switch result {
            case .success(let (matchResults, _)):
                let records = matchResults.compactMap { _, result in try? result.get() }
                let notes = records.map(MonthlyNotesRecord.init)
                allNotes.append(contentsOf: notes)
                debugLog("✅ Found \(records.count) monthly notes in DEFAULT zone (existing data)")
            case .failure(let error):
                debugLog("❌ Failed to fetch monthly notes from default zone: \(error)")
            }
            dispatchGroup.leave()
        }
        
        // Fetch from custom zone (new data) if available
        if let customZone = userCustomZone {
            dispatchGroup.enter()
            publicDatabase.fetch(withQuery: query, inZoneWith: customZone.zoneID, desiredKeys: nil, resultsLimit: CKQueryOperation.maximumResults) { result in
                switch result {
                case .success(let (matchResults, _)):
                    let records = matchResults.compactMap { _, result in try? result.get() }
                    let notes = records.map(MonthlyNotesRecord.init)
                    allNotes.append(contentsOf: notes)
                    debugLog("✅ Found \(records.count) monthly notes in CUSTOM zone \(customZone.zoneID.zoneName)")
                case .failure(let error):
                    debugLog("❌ Failed to fetch monthly notes from custom zone: \(error)")
                }
                dispatchGroup.leave()
            }
        }
        
        // Combine results from both zones
        dispatchGroup.notify(queue: .main) { [weak self] in
            let uniqueNotes = Array(Set(allNotes))
            
            var protectedCount = 0
            for note in uniqueNotes {
                if self?.shouldProtectLocalData(for: note.id) == true {
                    protectedCount += 1
                }
            }
            
            if protectedCount == 0 {
                self?.monthlyNotes = uniqueNotes.sorted { $0.year < $1.year || ($0.year == $1.year && $0.month < $1.month) }
                debugLog("✅ Combined monthly notes updated: \(uniqueNotes.count) total records")
            } else {
                debugLog("🛡️ Protected \(protectedCount) local monthly note records from CloudKit overwrite")
            }
            
                    completion()
                }
    }
    
    /// Original fetch method for backward compatibility
    private func fetchMonthlyNotesLegacy(completion: @escaping () -> Void) {
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
                        debugLog("✅ Monthly notes updated: \(records.count) records")
                    } else {
                        debugLog("🛡️ Protected \(protectedCount) local monthly note records from CloudKit overwrite")
                    }
                    
            case .failure(let error):
                debugLog("❌ Failed to fetch monthly notes: \(error)")
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
        debugLog("💾 Creating new daily schedule record for date: \(date)")
        
        // Check CloudKit status first
        guard cloudKitAvailable else {
            debugLog("❌ CloudKit not available for save")
            completion(false, NSError(domain: "CloudKitManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "iCloud not available"]))
            return
        }
        
        // Mark operation as starting
        markOperationStarting(for: dateKey, type: "SAVE")
        
        // Create record in custom zone for privacy and sharing (new data)
        let recordID: CKRecord.ID
        if let customZone = userCustomZone {
            recordID = CKRecord.ID(recordName: UUID().uuidString, zoneID: customZone.zoneID)
            debugLog("🔒 Saving to CUSTOM zone \(customZone.zoneID.zoneName) for privacy and sharing")
        } else {
            recordID = CKRecord.ID(recordName: UUID().uuidString)
            debugLog("⚠️ Saving to DEFAULT zone (custom zone not available)")
        }
        
        let record = CKRecord(recordType: "CD_DailySchedule", recordID: recordID)
        record["CD_date"] = date as CKRecordValue
        record["CD_id"] = UUID().uuidString as CKRecordValue
        record["CD_line1"] = line1 as CKRecordValue?
        record["CD_line2"] = line2 as CKRecordValue?
        record["CD_line3"] = line3 as CKRecordValue?
        
        debugLog("💾 CREATING CLOUDKIT RECORD:")
        debugLog("   RecordID: \(recordID.recordName)")
        debugLog("   Zone: \(recordID.zoneID.zoneName)")
        debugLog("   CD_line1: '\(line1 ?? "nil")' (length: \(line1?.count ?? 0))")
        debugLog("   CD_line2: '\(line2 ?? "nil")' (length: \(line2?.count ?? 0))")
        debugLog("   CD_line3: '\(line3 ?? "nil")' (length: \(line3?.count ?? 0))")
        
        // Link to container for sharing before saving
        Task {
            do {
                let container = try await getOrCreateContainer()
                record.parent = CKRecord.Reference(recordID: container.recordID, action: .none)
                debugLog("🔗 Linked daily schedule to container for sharing")
            } catch {
                debugLog("⚠️ Failed to link to container: \(error)")
            }
            
            debugLog("   About to save to CloudKit with container link...")
            self.saveRecordWithCompletion(record, dateKey: dateKey, completion: completion)
        }
    }
    
    private func saveRecordWithCompletion(_ record: CKRecord, dateKey: String, completion: @escaping (Bool, Error?) -> Void) {
        publicDatabase.save(record) { [weak self] savedRecord, error in
            DispatchQueue.main.async {
                if let error = error {
                    debugLog("❌ Failed to save new record: \(error.localizedDescription)")
                    self?.errorMessage = "Failed to save schedule: \(error.localizedDescription)"
                    self?.markOperationCompleted(for: dateKey, type: "SAVE", success: false)
                    completion(false, error)
                } else {
                    debugLog("✅ Successfully saved new daily schedule record")
                    // Verify what was actually saved to CloudKit
                    if let savedRecord = savedRecord {
                        debugLog("🔍 CLOUDKIT SAVE VERIFICATION:")
                        debugLog("   Saved RecordID: \(savedRecord.recordID.recordName)")
                        debugLog("   Saved Zone: \(savedRecord.recordID.zoneID.zoneName)")
                        debugLog("   Saved CD_line1: '\(savedRecord["CD_line1"] as? String ?? "nil")'")
                        debugLog("   Saved CD_line2: '\(savedRecord["CD_line2"] as? String ?? "nil")'")
                        debugLog("   Saved CD_line3: '\(savedRecord["CD_line3"] as? String ?? "nil")'")
                        
                        let newSchedule = DailyScheduleRecord(from: savedRecord)
                        self?.dailySchedules.append(newSchedule)
                        self?.markOperationCompleted(for: savedRecord.recordID.recordName, type: "SAVE", success: true)
                    }
                    completion(true, nil)
                }
            }
        }
    }
    
    private func saveMonthlyRecordWithCompletion(_ record: CKRecord, monthKey: String, month: Int, year: Int, completion: @escaping (Bool, Error?) -> Void) {
        publicDatabase.save(record) { [weak self] savedRecord, error in
            DispatchQueue.main.async {
                if let error = error {
                    debugLog("❌ Failed to save monthly notes record: \(error.localizedDescription)")
                    self?.errorMessage = "Failed to save notes: \(error.localizedDescription)"
                    self?.markOperationCompleted(for: monthKey, type: "SAVE_MONTHLY", success: false)
                    completion(false, error)
                } else {
                    debugLog("✅ Successfully saved monthly notes record")
                    if let savedRecord = savedRecord {
                        debugLog("🔍 MONTHLY NOTES SAVE VERIFICATION:")
                        debugLog("   Saved RecordID: \(savedRecord.recordID.recordName)")
                        debugLog("   Saved Zone: \(savedRecord.recordID.zoneID.zoneName)")
                        debugLog("   Saved CD_line1: '\(savedRecord["CD_line1"] as? String ?? "nil")'")
                        debugLog("   Saved CD_line2: '\(savedRecord["CD_line2"] as? String ?? "nil")'")
                        debugLog("   Saved CD_line3: '\(savedRecord["CD_line3"] as? String ?? "nil")'")
                        
                        // Update local array
                        let newNote = MonthlyNotesRecord(from: savedRecord)
                        self?.monthlyNotes.append(newNote)
                        self?.markOperationCompleted(for: savedRecord.recordID.recordName, type: "SAVE_MONTHLY", success: true)
                    }
                    completion(true, nil)
                }
            }
        }
    }
    
    func updateDailySchedule(recordName: String, zoneID: CKRecordZone.ID, date: Date, line1: String?, line2: String?, line3: String?, completion: @escaping (Bool, Error?) -> Void) {
        debugLog("🔄 Attempting to update record: \(recordName) in zone: \(zoneID.zoneName)")
        
        // Check CloudKit status first
        guard cloudKitAvailable else {
            completion(false, NSError(domain: "CloudKitManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "iCloud not available"]))
            return
        }
        
        // Mark operation as starting
        markOperationStarting(for: recordName, type: "UPDATE")
        
        let recordID = CKRecord.ID(recordName: recordName, zoneID: zoneID)
        
        publicDatabase.fetch(withRecordID: recordID) { [weak self] record, error in
                            if let error = error {
                DispatchQueue.main.async {
                    debugLog("❌ Failed to fetch record for update: \(error.localizedDescription)")
                    
                    // Check if this is a "Record not found" error - if so, create new record instead
                    if error.localizedDescription.contains("Record not found") || (error as? CKError)?.code == .unknownItem {
                        debugLog("🔄 Record not found in CloudKit - creating new record instead")
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
                    debugLog("❌ Record not found, creating new one instead")
                    // If record doesn't exist, create it instead
                    self?.markOperationCompleted(for: recordName, type: "UPDATE", success: false)
                    self?.saveDailySchedule(date: date, line1: line1, line2: line2, line3: line3, completion: completion)
                }
                return
            }
            
            debugLog("✅ Fetched record for update, updating fields...")
            debugLog("🔍 UPDATE OPERATION:")
            debugLog("   RecordID: \(recordName)")
            debugLog("   Zone: \(zoneID.zoneName)")
            debugLog("   NEW line1: '\(line1 ?? "nil")' (length: \(line1?.count ?? 0))")
            debugLog("   NEW line2: '\(line2 ?? "nil")' (length: \(line2?.count ?? 0))")
            debugLog("   NEW line3: '\(line3 ?? "nil")' (length: \(line3?.count ?? 0))")
            
            // Update the record with new values
            record["CD_date"] = date as CKRecordValue
            record["CD_line1"] = line1 as CKRecordValue?
            record["CD_line2"] = line2 as CKRecordValue?
            record["CD_line3"] = line3 as CKRecordValue?
            
            debugLog("   About to update CloudKit record...")
            
            self?.publicDatabase.save(record) { savedRecord, error in
                        DispatchQueue.main.async {
                            if let error = error {
                        debugLog("❌ Failed to update record: \(error.localizedDescription)")
                        self?.errorMessage = "Failed to update schedule: \(error.localizedDescription)"
                        self?.markOperationCompleted(for: recordName, type: "UPDATE", success: false)
                                completion(false, error)
                            } else {
                        debugLog("✅ Record updated successfully")
                        // Verify what was actually updated in CloudKit
                        if let savedRecord = savedRecord, let self = self {
                            debugLog("🔍 CLOUDKIT UPDATE VERIFICATION:")
                            debugLog("   Updated RecordID: \(savedRecord.recordID.recordName)")
                            debugLog("   Updated Zone: \(savedRecord.recordID.zoneID.zoneName)")
                            debugLog("   Updated CD_line1: '\(savedRecord["CD_line1"] as? String ?? "nil")'")
                            debugLog("   Updated CD_line2: '\(savedRecord["CD_line2"] as? String ?? "nil")'")
                            debugLog("   Updated CD_line3: '\(savedRecord["CD_line3"] as? String ?? "nil")'")
                            
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
    
    func deleteDailySchedule(recordName: String, zoneID: CKRecordZone.ID, completion: @escaping (Bool, Error?) -> Void) {
        // Check CloudKit status first
        guard cloudKitAvailable else {
            completion(false, NSError(domain: "CloudKitManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "iCloud not available"]))
            return
        }
        
        let recordID = CKRecord.ID(recordName: recordName, zoneID: zoneID)
        debugLog("🗑️ Attempting to delete record: \(recordName)")
        
        // Mark operation as starting
        markOperationStarting(for: recordName, type: "DELETE")
        
        publicDatabase.delete(withRecordID: recordID) { [weak self] deletedRecordID, error in
                DispatchQueue.main.async {
                if let error = error {
                    debugLog("❌ Error deleting daily schedule: \(error)")
                    self?.errorMessage = "Failed to delete schedule: \(error.localizedDescription)"
                    self?.markOperationCompleted(for: recordName, type: "DELETE", success: false)
                    completion(false, error)
                } else {
                    debugLog("✅ Successfully deleted daily schedule from CloudKit: \(recordName)")
                    // Remove from local array immediately instead of full refresh
                    self?.dailySchedules.removeAll { $0.id == recordName }
                    debugLog("📱 Removed from local array. Local count now: \(self?.dailySchedules.count ?? 0)")
                    
                    // Enhanced tracking for deletion operations
                    self?.recentDeletionOperations.insert(recordName)
                    self?.lastOperationTime = Date()
                    self?.markOperationCompleted(for: recordName, type: "DELETE", success: true)
                    debugLog("🕒 Enhanced tracking for deletion operation \(recordName) - preventing premature fetch")
                    
                    // Clear deletion tracking after 8 seconds (increased from 5)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) {
                        self?.recentDeletionOperations.remove(recordName)
                        debugLog("🧹 Cleared deletion tracking for \(recordName)")
                    }
                    
                    completion(true, nil)
                }
            }
        }
    }
    
    /// Smart save that handles deletion when all fields are empty
    func saveOrDeleteDailySchedule(existingRecordName: String?, existingZoneID: CKRecordZone.ID?, date: Date, line1: String?, line2: String?, line3: String?, completion: @escaping (Bool, Error?) -> Void) {
        // Check if all fields are empty
        let isEmpty = (line1?.isEmpty ?? true) && (line2?.isEmpty ?? true) && (line3?.isEmpty ?? true)
        let dateKey = "\(Calendar.current.startOfDay(for: date))"
        
        debugLog("🤔 Smart save called for \(dateKey)")
        debugLog("📊 isEmpty: \(isEmpty), existingRecord: \(existingRecordName ?? "none")")
        debugLog("🔍 CLOUDKIT MANAGER RECEIVED:")
        debugLog("   line1: '\(line1 ?? "nil")' (length: \(line1?.count ?? 0))")
        debugLog("   line2: '\(line2 ?? "nil")' (length: \(line2?.count ?? 0))")
        debugLog("   line3: '\(line3 ?? "nil")' (length: \(line3?.count ?? 0))")
        debugLog("   existingZoneID: '\(existingZoneID?.zoneName ?? "nil")'")
        
        // Check if we should prevent this operation due to recent activity
        // BUT allow delete operations when all fields are empty (user intentionally clearing data)
        if let recordName = existingRecordName, shouldProtectLocalData(for: recordName) && !isEmpty {
            debugLog("🛡️ Skipping save operation - local data protection active for \(recordName)")
            completion(true, nil)
            return
        }
        
        if isEmpty && existingRecordName != nil && existingZoneID != nil {
            // Delete existing record if all fields are empty
            debugLog("🗑️ All fields empty + existing record - calling DELETE for \(existingRecordName!) in zone \(existingZoneID!.zoneName)")
            deleteDailySchedule(recordName: existingRecordName!, zoneID: existingZoneID!, completion: completion)
        } else if !isEmpty {
            // Save or update if there's content
            debugLog("💾 Fields have content - calling SAVE/UPDATE for \(dateKey)")
            if let recordName = existingRecordName, let zoneID = existingZoneID {
                updateDailySchedule(recordName: recordName, zoneID: zoneID, date: date, line1: line1, line2: line2, line3: line3, completion: completion)
            } else {
                saveDailySchedule(date: date, line1: line1, line2: line2, line3: line3, completion: completion)
            }
        } else {
            // No existing record and no content - do nothing
            debugLog("⏸️ No existing record and no content - doing nothing for \(dateKey)")
            completion(true, nil)
        }
    }
    
    func saveMonthlyNotes(month: Int, year: Int, line1: String?, line2: String?, line3: String?, completion: @escaping (Bool, Error?) -> Void) {
        let monthKey = "\(year)-\(month)"
        debugLog("💾 Saving monthly notes for \(monthKey)")
        
        // Check CloudKit status first
        guard cloudKitAvailable else {
            completion(false, NSError(domain: "CloudKitManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "iCloud not available"]))
            return
        }
        
        // Mark operation as starting
        markOperationStarting(for: monthKey, type: "SAVE_MONTHLY")
        
        // First, check if a record already exists for this month/year in CUSTOM ZONE ONLY
        let predicate = NSPredicate(format: "CD_month == %d AND CD_year == %d", month, year)
        let query = CKQuery(recordType: "CD_MonthlyNotes", predicate: predicate)
        
        guard let customZone = userCustomZone else {
            debugLog("❌ Custom zone not available for monthly notes save")
            completion(false, NSError(domain: "CloudKitManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Custom zone not available"]))
            return
        }
        
        publicDatabase.fetch(withQuery: query, inZoneWith: customZone.zoneID, desiredKeys: nil, resultsLimit: CKQueryOperation.maximumResults) { [weak self] (result: Result<(matchResults: [(CKRecord.ID, Result<CKRecord, Error>)], queryCursor: CKQueryOperation.Cursor?), Error>) in
            let record: CKRecord
            
            switch result {
            case .success(let (matchResults, _)):
                let records = matchResults.compactMap { _, result in
                    try? result.get()
                }
                
                if let existingRecord = records.first {
                    // Update existing record
                    record = existingRecord
                    debugLog("📝 Updating existing monthly notes record for \(monthKey)")
                } else {
                    // Create new record in CUSTOM ZONE
                    let recordID = CKRecord.ID(recordName: UUID().uuidString, zoneID: customZone.zoneID)
                    record = CKRecord(recordType: "CD_MonthlyNotes", recordID: recordID)
                    record["CD_id"] = UUID().uuidString as CKRecordValue
                    record["CD_month"] = month as CKRecordValue
                    record["CD_year"] = year as CKRecordValue
                    debugLog("➕ Creating new monthly notes record for \(monthKey) in CUSTOM zone")
                    
                    // For new records, link to container for sharing before saving
                    Task { @MainActor in
                        do {
                            guard let self = self else { return }
                            let container = try await self.getOrCreateContainer()
                            record.parent = CKRecord.Reference(recordID: container.recordID, action: .none)
                            debugLog("🔗 Linked new monthly notes to container for sharing")
                        } catch {
                            debugLog("⚠️ Failed to link monthly notes to container: \(error)")
                        }
                        
                        // Set data fields and save
                        record["CD_line1"] = line1 as CKRecordValue?
                        record["CD_line2"] = line2 as CKRecordValue?
                        record["CD_line3"] = line3 as CKRecordValue?
                        
                        debugLog("📝 Saving NEW monthly notes with container link and fields: line1='\(line1 ?? "nil")', line2='\(line2 ?? "nil")', line3='\(line3 ?? "nil")'")
                        
                        guard let self = self else { return }
                        self.saveMonthlyRecordWithCompletion(record, monthKey: monthKey, month: month, year: year, completion: completion)
                    }
                    return // Exit early for new records - they are handled in the Task above
                }
                
            case .failure(let error):
                DispatchQueue.main.async {
                    debugLog("❌ Failed to search existing monthly notes: \(error.localizedDescription)")
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
            
            debugLog("📝 Saving monthly notes with fields: line1='\(line1 ?? "nil")', line2='\(line2 ?? "nil")', line3='\(line3 ?? "nil")'")
            
            self?.publicDatabase.save(record) { savedRecord, error in
                        DispatchQueue.main.async {
                            if let error = error {
                        debugLog("❌ Failed to save monthly notes: \(error.localizedDescription)")
                        self?.errorMessage = "Failed to save notes: \(error.localizedDescription)"
                        self?.markOperationCompleted(for: monthKey, type: "SAVE_MONTHLY", success: false)
                                completion(false, error)
                            } else {
                        debugLog("✅ Successfully saved monthly notes for \(monthKey)")
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
        
        debugLog("🤔 Smart monthly notes save called for \(monthKey)")
        debugLog("📊 isEmpty: \(isEmpty), existingRecord: \(existingRecordName ?? "none")")
        debugLog("📝 Monthly note values - line1: '\(line1 ?? "nil")', line2: '\(line2 ?? "nil")', line3: '\(line3 ?? "nil")'")
        
        // Check if we should prevent this operation due to recent activity
        if let recordName = existingRecordName, shouldProtectLocalData(for: recordName) {
            debugLog("🛡️ Skipping monthly notes operation - local data protection active for \(recordName)")
            completion(true, nil)
            return
        }
        
        if isEmpty {
            // All fields are empty - delete the record if it exists
            if let recordName = existingRecordName {
                debugLog("🗑️ All monthly note fields empty - calling DELETE for \(recordName)")
                deleteMonthlyNotes(recordName: recordName, month: month, year: year, completion: completion)
            } else {
                debugLog("🤷‍♂️ No existing monthly notes record to delete for \(monthKey)")
                completion(true, nil)
            }
        } else {
            // Fields have content - save/update the record
            debugLog("💾 Monthly note fields have content - calling SAVE/UPDATE for \(monthKey)")
            saveMonthlyNotes(month: month, year: year, line1: line1, line2: line2, line3: line3, completion: completion)
        }
    }
    
    func deleteMonthlyNotes(recordName: String, month: Int, year: Int, completion: @escaping (Bool, Error?) -> Void) {
        let monthKey = "\(year)-\(month)"
        debugLog("🗑️ Attempting to delete monthly notes record: \(recordName) for \(monthKey)")
        
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
                    debugLog("❌ Failed to delete monthly notes record: \(error.localizedDescription)")
                    self?.errorMessage = "Failed to delete notes: \(error.localizedDescription)"
                    self?.markOperationCompleted(for: recordName, type: "DELETE_MONTHLY", success: false)
                                completion(false, error)
                            } else {
                    debugLog("✅ Successfully deleted monthly notes from CloudKit: \(recordName)")
                    // Remove from local array immediately instead of full refresh
                    self?.monthlyNotes.removeAll { $0.month == month && $0.year == year }
                    debugLog("📱 Removed from local monthly notes array. Local count now: \(self?.monthlyNotes.count ?? 0)")
                    
                    // Enhanced tracking for deletion operations
                    self?.recentDeletionOperations.insert(recordName)
                    self?.lastOperationTime = Date()
                    self?.markOperationCompleted(for: recordName, type: "DELETE_MONTHLY", success: true)
                    debugLog("🕒 Enhanced tracking for monthly notes deletion \(recordName)")
                    
                    // Clear deletion tracking after 8 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) {
                        self?.recentDeletionOperations.remove(recordName)
                        debugLog("🧹 Cleared monthly notes deletion tracking for \(recordName)")
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
        debugLog("🧹 Starting daily schedule deduplication")
        
        guard cloudKitAvailable else {
            debugLog("❌ CloudKit not available for deduplication")
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
                debugLog("📊 Found \(records.count) daily schedule records for deduplication analysis")
            case .failure(let error):
                debugLog("❌ Failed to fetch records for deduplication: \(error)")
                DispatchQueue.main.async {
                    self?.markOperationCompleted(for: "DEDUP_DAILY", type: "DEDUPLICATION", success: false)
                    completion(0, error)
                }
                return
            }
            
            guard !records.isEmpty else {
                debugLog("ℹ️ No daily schedule records found - deduplication complete")
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
                    debugLog("🔍 Found \(groupRecords.count) duplicates for date \(dateKey)")
                    
                    // Sort by modification date, keep the most recent
                    let sortedRecords = groupRecords.sorted { record1, record2 in
                        let date1 = record1.modificationDate ?? Date.distantPast
                        let date2 = record2.modificationDate ?? Date.distantPast
                        return date1 < date2
                    }
                    
                    // Delete all but the most recent
                    for i in 0..<(sortedRecords.count - 1) {
                        recordsToDelete.append(sortedRecords[i].recordID)
                        debugLog("🗑️ Marking duplicate daily schedule for deletion: \(sortedRecords[i].recordID.recordName)")
                    }
                }
            }
            
            debugLog("📋 Daily schedule deduplication summary: \(duplicateGroups) groups with duplicates, \(recordsToDelete.count) records to delete")
            
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
        debugLog("🧹 Starting monthly notes deduplication")
        
        guard cloudKitAvailable else {
            debugLog("❌ CloudKit not available for monthly notes deduplication")
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
                debugLog("📊 Found \(records.count) monthly notes records for deduplication analysis")
            case .failure(let error):
                debugLog("❌ Failed to fetch monthly notes records for deduplication: \(error)")
                DispatchQueue.main.async {
                    self?.markOperationCompleted(for: "DEDUP_MONTHLY", type: "DEDUPLICATION", success: false)
                    completion(0, error)
                }
                            return
                        }
            
            guard !records.isEmpty else {
                debugLog("ℹ️ No monthly notes records found - deduplication complete")
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
                    debugLog("🔍 Found \(groupRecords.count) duplicate monthly notes for \(monthKey)")
                    
                    // Sort by modification date, keep the most recent
                    let sortedRecords = groupRecords.sorted { record1, record2 in
                        let date1 = record1.modificationDate ?? Date.distantPast
                        let date2 = record2.modificationDate ?? Date.distantPast
                        return date1 < date2
                    }
                    
                    // Delete all but the most recent
                    for i in 0..<(sortedRecords.count - 1) {
                        recordsToDelete.append(sortedRecords[i].recordID)
                        debugLog("🗑️ Marking duplicate monthly notes for deletion: \(sortedRecords[i].recordID.recordName)")
                    }
                }
            }
            
            debugLog("📋 Monthly notes deduplication summary: \(duplicateGroups) groups with duplicates, \(recordsToDelete.count) records to delete")
            
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
    nonisolated private func deleteDuplicateRecords(recordIDs: [CKRecord.ID], type: String, completion: @escaping (Int, Error?) -> Void) {
        guard !recordIDs.isEmpty else {
            debugLog("ℹ️ No duplicate \(type) records to delete")
            completion(0, nil)
            return
        }
        
        debugLog("🗑️ Deleting \(recordIDs.count) duplicate \(type) records")
        
        let deleteOperation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: recordIDs)
        deleteOperation.modifyRecordsResultBlock = { (result: Result<Void, Error>) in
            switch result {
            case .success:
                let deletedCount = recordIDs.count
                debugLog("✅ Successfully deleted \(deletedCount) duplicate \(type) records")
                
                // Track these deletions to prevent immediate refresh conflicts
                Task { @MainActor in
                    for recordID in recordIDs {
                        self.recentDeletionOperations.insert(recordID.recordName)
                    }
                    self.lastOperationTime = Date()
                }
                
                completion(deletedCount, nil)
            case .failure(let error):
                debugLog("❌ Failed to delete duplicate \(type) records: \(error)")
                completion(0, error)
            }
        }
        
        publicDatabase.add(deleteOperation)
    }
    
    /// Comprehensive cleanup function that removes all duplicates
    func cleanupDuplicateRecords(completion: @escaping (Int, Error?) -> Void) {
        debugLog("🧹 Starting comprehensive duplicate cleanup")
        
        guard cloudKitAvailable else {
            debugLog("❌ CloudKit not available for comprehensive cleanup")
            completion(0, NSError(domain: "CloudKitManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "iCloud not available"]))
            return
        }
        
        var totalDeleted = 0
        
        // First clean up daily schedules
        deduplicateDailySchedules { [weak self] dailyDeleted, error in
            if let error = error {
                debugLog("❌ Daily schedule deduplication failed: \(error)")
                completion(0, error)
                return
            }
            
            totalDeleted += dailyDeleted
            debugLog("📊 Daily schedule cleanup complete: \(dailyDeleted) duplicates removed")
            
            // Then clean up monthly notes
            self?.deduplicateMonthlyNotes { monthlyDeleted, error in
            if let error = error {
                    debugLog("❌ Monthly notes deduplication failed: \(error)")
                    completion(totalDeleted, error)
                    return
                }
                
                totalDeleted += monthlyDeleted
                debugLog("📊 Monthly notes cleanup complete: \(monthlyDeleted) duplicates removed")
                debugLog("✅ Comprehensive cleanup finished: \(totalDeleted) total duplicates removed")
                completion(totalDeleted, nil)
            }
        }
    }
    
    // MARK: - Custom Zone Sharing for Privacy
    
    /// Create a share for user data (backward-compatible: checks both default and custom zones)
    func createCustomZoneShare(completion: @escaping (Result<CKShare, Error>) -> Void) {
        debugLog("🔗 Creating CONTAINER-BASED share for all schedule records")
        debugLog("👤 Current Apple ID will be used for sharing")
        
        Task { @MainActor in
            do {
                // Get or create the container record (this will force delete/recreate)
                let container = try await getOrCreateContainer()
                debugLog("✅ Container ready - creating share from container")
                
                // Create share from the container record (async function with completion handler)
                await createShareFromRecord(container, completion: completion)
                
            } catch {
                debugLog("❌ Error searching for data to share: \(error)")
                completion(.failure(error))
            }
        }
    }
    
    
    /// Get or create a container record for sharing all schedules and notes
    private func getOrCreateContainer() async throws -> CKRecord {
        let containerID = CKRecord.ID(recordName: "ScheduleContainer", zoneID: userZoneID)
        
        // FORCE DELETE any existing container to prevent Apple ID confusion
        do {
            _ = try await publicDatabase.record(for: containerID)
            debugLog("🗑️ Found existing container - deleting to ensure fresh creation")
            try await publicDatabase.deleteRecord(withID: containerID)
            debugLog("✅ Deleted existing container record")
        } catch {
            debugLog("📝 No existing container found (this is good)")
        }
        
        // Always create fresh container
        debugLog("📦 Creating fresh container record for sharing (Apple ID: current user)")
        let container = CKRecord(recordType: "ScheduleContainer", recordID: containerID)
        container["title"] = "Provider Schedule \(Calendar.current.component(.year, from: Date()))" as CKRecordValue
        container["created"] = Date() as CKRecordValue
        
        let savedContainer = try await publicDatabase.save(container)
        debugLog("✅ Fresh container record created successfully")
        return savedContainer
    }
    
    /// Create a new CloudKit record that can be shared (not Core Data managed)
    private func createShareableRecord(completion: @escaping (Result<CKShare, Error>) -> Void) async {
        do {
            debugLog("🔗 Creating new shareable CloudKit record...")
            
            // Create a new record in the CUSTOM ZONE for sharing (required for CloudKit sharing)
            let recordID = CKRecord.ID(recordName: "ShareableSchedule-\(UUID().uuidString)", zoneID: userZoneID)
            let shareableRecord = CKRecord(recordType: "CD_DailySchedule", recordID: recordID)
            
            // Add some sample data (short text to avoid Core Data validation errors)
            shareableRecord["CD_date"] = Date() as CKRecordValue
            shareableRecord["CD_line1"] = "SHARED" as CKRecordValue
            shareableRecord["CD_line2"] = "tcsdoc" as CKRecordValue
            shareableRecord["CD_line3"] = "Test" as CKRecordValue
            shareableRecord["CD_entityName"] = "DailySchedule" as CKRecordValue
            
            debugLog("🔗 Saving new shareable record to CUSTOM ZONE...")
            
            // Save the record first to PRIVATE database (shares must be in custom zones in private database)
            let savedRecords = try await publicDatabase.modifyRecords(saving: [shareableRecord], deleting: [])
            
            if let savedRecord = try savedRecords.saveResults[recordID]?.get() {
                debugLog("✅ Created new shareable record successfully")
                debugLog("🔗 Record zone: \(savedRecord.recordID.zoneID.zoneName)")
                
                // Now create a share from this new record
                await createShareFromRecord(savedRecord, completion: completion)
                } else {
                debugLog("❌ Failed to save new shareable record")
                completion(.failure(NSError(domain: "CloudKitManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create shareable record"])))
            }
        } catch {
            debugLog("❌ Error creating shareable record: \(error)")
            completion(.failure(error))
        }
    }
    
    /// Helper function to create share from a specific record
    private func createShareFromRecord(_ rootRecord: CKRecord, completion: @escaping (Result<CKShare, Error>) -> Void) async {
        do {
            // Create share with the root record (from any zone)
            let share = CKShare(rootRecord: rootRecord)
            share[CKShare.SystemFieldKey.title] = "Provider Schedule \(Calendar.current.component(.year, from: Date()))"
            share.publicPermission = .readOnly // Allow cross-Apple ID sharing with read-only access
            
            debugLog("🔗 Creating share from record in zone: \(rootRecord.recordID.zoneID.zoneName)")
            
            // CRITICAL: Save BOTH the root record AND the share in the same operation
            // This is required by CloudKit when creating shares
            let savedRecords = try await publicDatabase.modifyRecords(saving: [rootRecord, share], deleting: [])
            
            debugLog("🔍 DEBUG: Saved \(savedRecords.saveResults.count) records")
            for (recordID, result) in savedRecords.saveResults {
                debugLog("🔍 Record ID: \(recordID)")
                switch result {
                case .success(let record):
                    debugLog("🔍 Saved record type: \(type(of: record))")
                    if let shareRecord = record as? CKShare {
                        debugLog("✅ Found CKShare in results!")
                        debugLog("🔗 Share URL: \(shareRecord.url?.absoluteString ?? "Not available")")
                        debugLog("🔒 Share covers zone: \(rootRecord.recordID.zoneID.zoneName)")
                        completion(.success(shareRecord))
                        return
                }
            case .failure(let error):
                    debugLog("❌ Failed to save record \(recordID): \(error)")
                }
            }
            
            // If we get here, no CKShare was found
            debugLog("❌ No CKShare found in save results")
            completion(.failure(NSError(domain: "CloudKitManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "No share found in save results"])))
        } catch {
            debugLog("❌ Error creating share from record: \(error)")
            completion(.failure(error))
        }
    }
}

// MARK: - Data Models
struct DailyScheduleRecord: Identifiable, Equatable, Hashable {
    let id: String
    let date: Date?
    let line1: String?
    let line2: String?
    let line3: String?
    let uuid: UUID?
    let zoneID: CKRecordZone.ID  // Track which zone this record belongs to
    
    init(from record: CKRecord) {
        self.id = record.recordID.recordName
        self.date = record["CD_date"] as? Date
        self.line1 = record["CD_line1"] as? String
        self.line2 = record["CD_line2"] as? String
        self.line3 = record["CD_line3"] as? String
        self.zoneID = record.recordID.zoneID  // Store the zone ID
        if let uuidString = record["CD_id"] as? String {
            self.uuid = UUID(uuidString: uuidString)
        } else {
            self.uuid = nil
        }
    }
}

struct MonthlyNotesRecord: Identifiable, Equatable, Hashable {
    let id: String
    let month: Int
    let year: Int
    let line1: String?
    let line2: String?
    let line3: String?
    let uuid: UUID?
    let zoneID: CKRecordZone.ID  // Track which zone this record belongs to
    
    init(from record: CKRecord) {
        self.id = record.recordID.recordName
        self.month = (record["CD_month"] as? Int) ?? 0
        self.year = (record["CD_year"] as? Int) ?? 0
        self.line1 = record["CD_line1"] as? String
        self.line2 = record["CD_line2"] as? String
        self.line3 = record["CD_line3"] as? String
        self.zoneID = record.recordID.zoneID  // Store the zone ID
        if let uuidString = record["CD_id"] as? String {
            self.uuid = UUID(uuidString: uuidString)
        } else {
            self.uuid = nil
        }
    }
}


// MARK: - CloudKit Sharing Delegate
class CloudKitSharingDelegate: NSObject, UICloudSharingControllerDelegate {
    static let shared = CloudKitSharingDelegate()
    
    func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
        debugLog("❌ Failed to save share: \(error.localizedDescription)")
        debugLog("❌ SHARING ERROR: \(error)")
    }
    
    func itemTitle(for csc: UICloudSharingController) -> String? {
        return "Provider Schedule Calendar"
    }
    
    func itemType(for csc: UICloudSharingController) -> String? {
        return "Calendar Schedule"
    }
    
    func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
        debugLog("✅ Share saved successfully")
        debugLog("✅ SHARING SUCCESS - Share URL should be available in the controller")
        if let share = csc.share {
            debugLog("🔗 Final share URL: \(share.url?.absoluteString ?? "Still no URL")")
        }
    }
    
    func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
        debugLog("🔗 Sharing stopped")
        debugLog("🔗 User stopped sharing")
    }
}
