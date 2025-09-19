import Foundation
import CloudKit
import SwiftUI

// MARK: - Debug Logging Helper
func debugLog(_ message: String) {
    #if DEBUG
    print("PSC DEBUG: \(message)")
    #endif
}

@MainActor
class CloudKitManager: ObservableObject {
    static let shared = CloudKitManager()
    
    private let container: CKContainer
    private let privateDatabase: CKDatabase
    private(set) var userCustomZone: CKRecordZone?
    var userZoneID: CKRecordZone.ID
    
    @Published var dailySchedules: [DailyScheduleRecord] = []
    @Published var monthlyNotes: [MonthlyNotesRecord] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var cloudKitAvailable = false
    @Published var isZoneReady = false
    
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
    private(set) var pendingOperations: Set<String> = []
    

    
    // Track data versions to prevent overwrites
    private var localDataVersions: [String: Date] = [:]
    
    init() {
        container = CKContainer(identifier: "iCloud.com.gulfcoast.ProviderCalendar")
        privateDatabase = container.privateCloudDatabase  // Use private database with sharing for privacy
        
        // Initialize with temporary zone ID until we get the real user ID
        userZoneID = CKRecordZone.ID(zoneName: "temp_zone")
        
        debugLog("🚀 CloudKitManager INIT - Privacy-focused custom zones enabled")
        
        // CRITICAL: Setup proper zone FIRST, then check CloudKit status
        Task {
            await setupUserSpecificZone()
            // Only check CloudKit status AFTER zone setup is complete
            await MainActor.run {
                self.checkCloudKitStatus()
            }
        }
        
        debugLog("🚀 CloudKitManager initialized - zone setup in progress")
    }
    
    // MARK: - User-Specific Zone Setup
    private func setupUserSpecificZone() async {
        do {
            // Get the actual user record ID for privacy-focused zone naming  
            let _ = try await container.userRecordID() // Verify user is authenticated
            
            // Create clean custom zone name without special characters
            userZoneID = CKRecordZone.ID(zoneName: "ProviderScheduleZone")
            
            debugLog("🔒 User zone set to: \(userZoneID.zoneName) for Apple ID isolation")
            
            // Set up the custom zone
            await MainActor.run {
                setupUserCustomZone()
            }
            
        } catch {
            debugLog("❌ Failed to get user record ID: \(error)")
            // Fallback to container-based naming if user ID fails
            let fallbackIdentifier = "user_\(container.containerIdentifier?.replacingOccurrences(of: "iCloud.", with: "") ?? "unknown")"
            userZoneID = CKRecordZone.ID(zoneName: fallbackIdentifier)
            debugLog("⚠️ Using fallback zone: \(userZoneID.zoneName)")
            
            await MainActor.run {
                setupUserCustomZone()
            }
        }
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
                    
                    // If CloudKit just became available, zone setup will trigger data fetch when ready
                    if wasUnavailable {
                        debugLog("🔄 CloudKit just became available - zone setup will handle data fetching")
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
                let existingZones = try await privateDatabase.allRecordZones()
                
                debugLog("🔒 SETUP: Found \(existingZones.count) existing zones")
                
                
                if existingZones.contains(where: { $0.zoneID == userZoneID }) {
                    debugLog("✅ Custom zone \(userZoneID.zoneName) already exists")
                    userCustomZone = existingZones.first { $0.zoneID == userZoneID }
                    
                    // Zone is ready, trigger initial data fetch if CloudKit is available
                DispatchQueue.main.async {
                        self.isZoneReady = true
                        debugLog("✅ Zone marked as ready - UI can now create records safely")
                        if self.cloudKitAvailable && self.dailySchedules.isEmpty && self.monthlyNotes.isEmpty {
                            debugLog("🔄 Custom zone ready - triggering initial data fetch")
                            self.fetchAllData()
                }
            }
                } else {
                    // Create new custom zone with proper ownership
                debugLog("🔧 Creating new custom zone with proper ownership...")
                let newZone = CKRecordZone(zoneID: userZoneID)
                    let result = try await privateDatabase.modifyRecordZones(saving: [newZone], deleting: [])
                    userCustomZone = try result.saveResults[userZoneID]?.get()
                    debugLog("✅ SETUP: Created new custom zone: \(userZoneID.zoneName) with current user ownership")
                    
                    // Mark zone as ready after successful creation
                    await MainActor.run {
                        self.isZoneReady = true
                        debugLog("✅ New zone marked as ready - UI can now create records safely")
                        if self.cloudKitAvailable {
                            debugLog("🔄 New zone ready - triggering initial data fetch")
                            self.fetchAllData()
                        }
                    }
                }
            } catch {
                debugLog("❌ SETUP: Failed to setup custom zone: \(error)")
                if let ckError = error as? CKError {
                    debugLog("❌ SETUP: CKError code: \(ckError.code.rawValue)")
                    debugLog("❌ SETUP: CKError description: \(ckError.localizedDescription)")
                    switch ckError.code {
                    case .notAuthenticated:
                        debugLog("❌ SETUP: Not signed into iCloud")
                    case .permissionFailure:
                        debugLog("❌ SETUP: CloudKit permissions issue")
                    case .networkFailure:
                        debugLog("❌ SETUP: Network connectivity problem")
                    case .quotaExceeded:
                        debugLog("❌ SETUP: iCloud storage quota exceeded")
                    case .zoneNotFound:
                        debugLog("❌ SETUP: Zone operation failed")
                    default:
                        debugLog("❌ SETUP: Other CloudKit error")
                    }
                }
                debugLog("❌ CRITICAL: Custom zone setup failed - PSC requires custom zones for sharing")
                // Don't mark zone as ready if setup fails - app should not operate without custom zone
                await MainActor.run {
                    self.isZoneReady = false
                    self.errorMessage = "Custom zone setup failed. PSC requires custom zones for sharing functionality."
                    debugLog("❌ Zone marked as NOT ready - custom zone required")
                }
            }
        }
    }
    
    
    // MARK: - Enhanced Data Protection Methods
    
    /// Verify a record actually exists in CloudKit after save
    private func verifyRecordExists(recordID: CKRecord.ID) {
        debugLog("🔍 VERIFICATION: Attempting to fetch record \(recordID.recordName) from CloudKit...")
        
        privateDatabase.fetch(withRecordID: recordID) { record, error in
            DispatchQueue.main.async {
                if let error = error {
                    debugLog("❌ VERIFICATION FAILED: Record \(recordID.recordName) NOT found in CloudKit!")
                    debugLog("❌ VERIFICATION ERROR: \(error.localizedDescription)")
                    debugLog("🚨 THIS PROVES THE SAVE WAS FAKE - CloudKit lied about success!")
                    
                    if let ckError = error as? CKError {
                        debugLog("❌ CKError code: \(ckError.code.rawValue)")
                        if ckError.code == .unknownItem {
                            debugLog("🚨 SMOKING GUN: Record does not exist in CloudKit despite 'successful' save!")
                        }
                    }
                } else if let record = record {
                    debugLog("✅ VERIFICATION SUCCESS: Record \(recordID.recordName) confirmed in CloudKit")
                    debugLog("✅ VERIFIED DATA: \(record["CD_line1"] as? String ?? "nil"), \(record["CD_line2"] as? String ?? "nil"), \(record["CD_line3"] as? String ?? "nil")")
                } else {
                    debugLog("⚠️ VERIFICATION WEIRD: No error but no record returned")
                }
            }
        }
    }
    
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
            
            // Note: Save tracking will be cleared by cleanup operations
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
            
            // CloudKit will be retried when status changes
            return
        }
        
        // Check zone readiness - CRITICAL: Don't fetch before zone is ready
        guard isZoneReady else {
            debugLog("❌ Custom zone not ready - skipping fetch until zone setup completes")
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
    
    // EMERGENCY: Reset custom zone to fix ownership issues
    func emergencyZoneReset() {
        debugLog("🚨 EMERGENCY: Resetting custom zone to fix ownership issues...")
        debugLog("🔍 Current userZoneID: \(userZoneID.zoneName)")
        
        Task {
            do {
                // ENHANCED DEBUGGING: List ALL zones first
                let existingZones = try await privateDatabase.allRecordZones()
                debugLog("🔍 BEFORE RESET - Found \(existingZones.count) total zones:")
                for zone in existingZones {
                    debugLog("   Zone: \(zone.zoneID.zoneName) (owner: \(zone.zoneID.ownerName))")
                }
                
                // Delete existing zone if it exists
                if existingZones.contains(where: { $0.zoneID == userZoneID }) {
                    debugLog("🗑️ Deleting zone: \(userZoneID.zoneName)...")
                    _ = try await privateDatabase.modifyRecordZones(saving: [], deleting: [userZoneID])
                    debugLog("✅ Deleted zone: \(userZoneID.zoneName)")
                } else {
                    debugLog("⚠️ Zone \(userZoneID.zoneName) not found in existing zones!")
                }
                
                // Create fresh zone with current user ownership
                debugLog("🆕 Creating fresh zone with current user ownership...")
                let newZone = CKRecordZone(zoneID: userZoneID)
                let result = try await privateDatabase.modifyRecordZones(saving: [newZone], deleting: [])
                
                await MainActor.run {
                    self.userCustomZone = try? result.saveResults[userZoneID]?.get()
                    debugLog("✅ EMERGENCY: Fresh zone created with proper ownership")
                    
                    // CRITICAL: Clear all local data arrays after zone reset
                    let oldScheduleCount = self.dailySchedules.count
                    let oldNotesCount = self.monthlyNotes.count
                    self.dailySchedules = []
                    self.monthlyNotes = []
                    debugLog("🗑️ Cleared local data: \(oldScheduleCount) schedules, \(oldNotesCount) notes")
                    
                    debugLog("🔄 Zone reset complete - memory cleared, ready for clean saves")
                    debugLog("🔍 Current dailySchedules count: \(self.dailySchedules.count)")
                    debugLog("🔍 Current monthlyNotes count: \(self.monthlyNotes.count)")
                    
                    // CRITICAL: Fetch fresh data from the reset zone
                    debugLog("🔄 Fetching fresh data from reset zone...")
                    self.fetchAllData()
                }
                
            } catch {
                debugLog("❌ EMERGENCY: Zone reset failed: \(error)")
            }
        }
    }
    
    // EMERGENCY: Force refresh from custom zone only
    func emergencyDataRecovery() {
        debugLog("🚨 EMERGENCY: Starting custom zone data recovery...")
        debugLog("🔒 CUSTOM ZONE ONLY: PSC never uses default zones - custom zones required for sharing")
        
        // Force refresh from custom zone only
        forceRefreshAllData()
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
    
    
    private func fetchDailySchedules(completion: @escaping () -> Void) {
        debugLog("📅 Fetching daily schedules from custom zone only...")
        
        // Fetch only from custom zone for clean, single-source data
        fetchDailySchedulesFromCustomZone(completion: completion)
    }
    
    /// Fetch daily schedules from custom zone only (single source of truth)
    private func fetchDailySchedulesFromCustomZone(completion: @escaping () -> Void) {
        debugLog("📥 FETCH START: Querying CloudKit for daily schedules")
        
        let query = CKQuery(recordType: "CD_DailySchedule", predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "CD_date", ascending: true)]
        
        guard let customZone = userCustomZone else {
            debugLog("❌ FETCH ERROR: Custom zone not available - no data to fetch")
            DispatchQueue.main.async { [weak self] in
                self?.dailySchedules = []
                completion()
            }
            return
        }
        
        debugLog("📥 FETCH DEBUG: Querying zone '\(customZone.zoneID.zoneName)' for CD_DailySchedule records")
        debugLog("📥 FETCH DEBUG: Zone owner: \(customZone.zoneID.ownerName)")
        debugLog("📥 FETCH DEBUG: Query predicate: \(query.predicate)")
        debugLog("📥 FETCH DEBUG: Sort descriptors: \(query.sortDescriptors?.description ?? "none")")
        
        let operation = CKQueryOperation(query: query)
        operation.zoneID = customZone.zoneID
        operation.resultsLimit = CKQueryOperation.maximumResults
        
        var allRecords: [CKRecord] = []
        
        operation.recordFetchedBlock = { record in
            allRecords.append(record)
            debugLog("📥 FETCH RECORD: \(record.recordID.recordName) - Success")
        }
        
        operation.queryCompletionBlock = { [weak self] cursor, error in
            DispatchQueue.main.async {
                if let error = error {
                    debugLog("❌ FETCH FAILED: CloudKit query failed")
                    debugLog("📥 FETCH ERROR DETAILS:")
                    debugLog("   Error: \(error.localizedDescription)")
                    debugLog("   Domain: \((error as NSError).domain)")
                    debugLog("   Code: \((error as NSError).code)")
                    
                    if let ckError = error as? CKError {
                        debugLog("   CKError code: \(ckError.code.rawValue)")
                        debugLog("   CKError type: \(ckError.code)")
                        let underlying = (ckError as NSError).userInfo[NSUnderlyingErrorKey] as? Error
                        debugLog("   Underlying: \(underlying?.localizedDescription ?? "none")")
                    }
                    
                    self?.errorMessage = "Failed to fetch schedule data: \(error.localizedDescription)"
                    self?.dailySchedules = []
                    completion()
                    return
                }
                
                debugLog("📥 FETCH SUCCESS: CloudKit query completed")
                debugLog("📥 FETCH DEBUG: Raw match results count: \(allRecords.count)")
                debugLog("📥 FETCH DEBUG: Query cursor: \(cursor?.description ?? "none")")
                
                let records = allRecords
                
                debugLog("📥 FETCH DEBUG: Successfully parsed \(records.count) records from \(allRecords.count) results")
                    
                    // Log detailed information about each fetched record
                    for (index, record) in records.enumerated() {
                        debugLog("📥 RECORD \(index + 1):")
                        debugLog("   RecordID: \(record.recordID.recordName)")
                        debugLog("   Zone: \(record.recordID.zoneID.zoneName)")
                        debugLog("   CD_date: \(record["CD_date"] as? Date ?? Date())")
                        debugLog("   CD_line1: '\(record["CD_line1"] as? String ?? "nil")'")
                        debugLog("   CD_line2: '\(record["CD_line2"] as? String ?? "nil")'")
                        debugLog("   CD_line3: '\(record["CD_line3"] as? String ?? "nil")'")
                        debugLog("   CD_line4: '\(record["CD_line4"] as? String ?? "nil")'")
                        debugLog("   Creation: \(record.creationDate ?? Date())")
                        debugLog("   Modified: \(record.modificationDate ?? Date())")
                    }
                    
                debugLog("🔄 CONVERSION DEBUG: About to convert \(records.count) CKRecords")
                
                // CRITICAL: Convert records with enhanced debugging to catch data swapping
                var fetchedSchedules: [DailyScheduleRecord] = []
                for (index, record) in records.enumerated() {
                    let schedule = DailyScheduleRecord(from: record)
                    fetchedSchedules.append(schedule)
                    
                    // Debug Sept 4th and 5th conversions specifically
                    if let date = record["CD_date"] as? Date {
                        let formatter = DateFormatter()
                        formatter.dateFormat = "yyyy-MM-dd"
                        formatter.timeZone = TimeZone(identifier: "UTC")  // FIX: Use UTC to match CloudKit
                        let dateString = formatter.string(from: date)
                        if dateString == "2025-09-04" || dateString == "2025-09-05" {
                            debugLog("🔄 INDEX \(index): CKRecord \(record.recordID.recordName) (\(dateString) UTC) → DailyScheduleRecord \(schedule.id)")
                            debugLog("   CK line1: '\(record["CD_line1"] as? String ?? "nil")' → Model line1: '\(schedule.line1 ?? "nil")'")
                            debugLog("   CK line4: '\(record["CD_line4"] as? String ?? "nil")' → Model line4: '\(schedule.line4 ?? "nil")'")
                        }
                    }
                }
                
                debugLog("📥 FETCH DEBUG: Converted to \(fetchedSchedules.count) DailyScheduleRecord objects")
                
                // DEDUPLICATION: Remove duplicate records by date, keeping the most recent one
                let deduplicatedSchedules = deduplicateSchedulesByDate(fetchedSchedules)
                debugLog("🧹 DEDUPLICATION: Reduced from \(fetchedSchedules.count) to \(deduplicatedSchedules.count) records")
                
                // Debug: Log all Sept 4th and 5th records after deduplication
                for schedule in deduplicatedSchedules {
                    if let date = schedule.date {
                        let formatter = DateFormatter()
                        formatter.dateFormat = "yyyy-MM-dd"
                        formatter.timeZone = TimeZone(identifier: "UTC")
                        let dateString = formatter.string(from: date)
                        if dateString == "2025-09-04" || dateString == "2025-09-05" {
                            debugLog("🧹 DEDUP RESULT \(dateString): ID=\(schedule.id), line1='\(schedule.line1 ?? "nil")', line4='\(schedule.line4 ?? "nil")'")
                        }
                    }
                }
                
                // Debug: Check if Sept 5th data survived deduplication
                for schedule in deduplicatedSchedules {
                    if let date = schedule.date {
                        let formatter = DateFormatter()
                        formatter.dateFormat = "yyyy-MM-dd"
                        formatter.timeZone = TimeZone(identifier: "UTC")
                        let dateString = formatter.string(from: date)
                        if dateString == "2025-09-05" {
                            debugLog("🧹 POST-DEDUP Sept 5: line1='\(schedule.line1 ?? "nil")', line2='\(schedule.line2 ?? "nil")', line3='\(schedule.line3 ?? "nil")', line4='\(schedule.line4 ?? "nil")', ID=\(schedule.id)")
                        }
                    }
                }
                    
                // Debug: Log what we fetched from CloudKit
                for schedule in deduplicatedSchedules {
                    if let date = schedule.date {
                        let formatter = DateFormatter()
                        formatter.dateFormat = "yyyy-MM-dd"
                        formatter.timeZone = TimeZone(identifier: "UTC")
                        let dateString = formatter.string(from: date)
                        if dateString == "2025-09-05" {
                            debugLog("🔍 FETCHED Sept 5: line1='\(schedule.line1 ?? "nil")', line2='\(schedule.line2 ?? "nil")', line3='\(schedule.line3 ?? "nil")', line4='\(schedule.line4 ?? "nil")'")
                        }
                    }
                }
                    
                // CRITICAL: Preserve unsaved edits in global memory during fetch
                var mergedSchedules = deduplicatedSchedules
                
                // Debug: Check Sept 5th data before merge  
                for schedule in mergedSchedules {
                    if let date = schedule.date {
                        let formatter = DateFormatter()
                        formatter.dateFormat = "yyyy-MM-dd"
                        formatter.timeZone = TimeZone(identifier: "UTC")
                        let dateString = formatter.string(from: date)
                        if dateString == "2025-09-05" {
                            debugLog("🔄 PRE-MERGE Sept 5: line1='\(schedule.line1 ?? "nil")', line2='\(schedule.line2 ?? "nil")', line3='\(schedule.line3 ?? "nil")', line4='\(schedule.line4 ?? "nil")', ID=\(schedule.id)")
                        }
                    }
                }
                    
                    // Debug: Check current local memory state
                    debugLog("🧠 LOCAL MEMORY: \(self?.dailySchedules.count ?? 0) records, \(self?.dailySchedules.filter { $0.isModified }.count ?? 0) modified")
                    
                    // Add any modified records from global memory that aren't in CloudKit yet
                    for existingRecord in self?.dailySchedules ?? [] {
                        if existingRecord.isModified {
                            // Debug: Log what local record we're trying to protect
                            if let date = existingRecord.date {
                                let formatter = DateFormatter()
                                formatter.dateFormat = "yyyy-MM-dd"
                                formatter.timeZone = TimeZone(identifier: "UTC")
                                let dateString = formatter.string(from: date)
                                if dateString == "2025-09-05" {
                                    debugLog("🛡️ LOCAL Sept 5 (modified): line1='\(existingRecord.line1 ?? "nil")', line2='\(existingRecord.line2 ?? "nil")', line3='\(existingRecord.line3 ?? "nil")', line4='\(existingRecord.line4 ?? "nil")'")
                                }
                            }
                            // CRITICAL FIX: Don't restore records that are in the recent deletion list
                            if self?.recentDeletionOperations.contains(existingRecord.id) == true {
                                debugLog("🚫 BLOCKED: Preventing restoration of recently deleted record \(existingRecord.id)")
                                continue
                            }
                            
                            // This record has unsaved changes - keep it instead of CloudKit version
                            if let index = mergedSchedules.firstIndex(where: { 
                                Calendar.current.isDate($0.date ?? Date(), inSameDayAs: existingRecord.date ?? Date()) 
                            }) {
                                mergedSchedules[index] = existingRecord // Keep the modified version
                                debugLog("🛡️ PROTECTED: Kept unsaved edits for \(existingRecord.date?.description ?? "unknown")")
                            } else {
                                mergedSchedules.append(existingRecord) // Add new unsaved record
                                debugLog("➕ PROTECTED: Kept new unsaved record for \(existingRecord.date?.description ?? "unknown")")
                            }
                        }
                    }
                    
                    // Use merged schedules that preserve unsaved edits during fetch
                    self?.dailySchedules = mergedSchedules.sorted { ($0.date ?? Date()) < ($1.date ?? Date()) }
                    let protectedCount = mergedSchedules.filter { $0.isModified }.count
                    debugLog("✅ FETCH COMPLETE: \(fetchedSchedules.count) from CloudKit + \(protectedCount) unsaved edits = \(mergedSchedules.count) total")
                    debugLog("📥 FINAL COUNT: dailySchedules array now contains \(self?.dailySchedules.count ?? 0) records")
                    
                    // Debug: Log final merged result for Sept 5
                    for schedule in mergedSchedules {
                        if let date = schedule.date {
                            let formatter = DateFormatter()
                            formatter.dateFormat = "yyyy-MM-dd"
                            formatter.timeZone = TimeZone(identifier: "UTC")
                            let dateString = formatter.string(from: date)
                            if dateString == "2025-09-05" {
                                debugLog("📱 FINAL Sept 5: line1='\(schedule.line1 ?? "nil")', line2='\(schedule.line2 ?? "nil")', line3='\(schedule.line3 ?? "nil")', line4='\(schedule.line4 ?? "nil")' (modified: \(schedule.isModified))")
                            }
                        }
                    }
                    
                completion()
            }
        }
        
        privateDatabase.add(operation)
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
        
        privateDatabase.fetch(withQuery: query, inZoneWith: customZone.zoneID, desiredKeys: nil, resultsLimit: CKQueryOperation.maximumResults) { [weak self] result in
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
    
    
    
    // MARK: - Save Data
    func saveDailySchedule(date: Date, line1: String?, line2: String?, line3: String?, line4: String?, completion: @escaping (Bool, Error?) -> Void) {
        saveDailySchedule(date: date, line1: line1, line2: line2, line3: line3, line4: line4, retryCount: 0, completion: completion)
    }
    
    private func saveDailySchedule(date: Date, line1: String?, line2: String?, line3: String?, line4: String?, retryCount: Int, completion: @escaping (Bool, Error?) -> Void) {
        let dateKey = "\(Calendar.current.startOfDay(for: date))"
        debugLog("💾 FIND-OR-CREATE: Checking for existing record for date: \(date) (retry: \(retryCount))")
        
        // Check CloudKit status first
        guard cloudKitAvailable else {
            debugLog("❌ CloudKit not available for save")
            completion(false, NSError(domain: "CloudKitManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "iCloud not available"]))
            return
        }
        
        // Limit retries to prevent infinite loops
        guard retryCount < 3 else {
            debugLog("❌ Maximum retry attempts reached (\(retryCount)) - failing save operation")
            completion(false, NSError(domain: "CloudKitManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Maximum retry attempts reached"]))
            return
        }
        
        // CUSTOM ZONE ONLY - Never use default zone
        guard let customZone = userCustomZone else {
            debugLog("❌ SAVE FAILED: Custom zone required - PSC never uses default zones")
            completion(false, NSError(domain: "CloudKitManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Custom zone required for sharing functionality"]))
            return
        }
        
        // CRITICAL FIX: Query for existing record by date BEFORE creating new one
        let startOfDay = Calendar.current.startOfDay(for: date)
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!
        let datePredicate = NSPredicate(format: "CD_date >= %@ AND CD_date < %@", startOfDay as NSDate, endOfDay as NSDate)
        let query = CKQuery(recordType: "CD_DailySchedule", predicate: datePredicate)
        
        debugLog("🔍 QUERYING for existing records on \(dateKey)...")
        
        let operation = CKQueryOperation(query: query)
        operation.zoneID = customZone.zoneID
        operation.resultsLimit = 10  // Should only be 1, but handle duplicates
        
        var foundRecords: [CKRecord] = []
        
        operation.recordFetchedBlock = { record in
            foundRecords.append(record)
            debugLog("🔍 FOUND existing record: \(record.recordID.recordName)")
        }
        
        operation.queryCompletionBlock = { [weak self] cursor, error in
            DispatchQueue.main.async {
                if let error = error {
                    debugLog("❌ QUERY FAILED: \(error.localizedDescription) - creating new record")
                    self?.createNewDailyScheduleRecord(customZone: customZone, dateKey: dateKey, date: date, line1: line1, line2: line2, line3: line3, line4: line4, retryCount: retryCount, completion: completion)
                    return
                }
                
                if foundRecords.isEmpty {
                    debugLog("✅ No existing record found - creating new one")
                    self?.createNewDailyScheduleRecord(customZone: customZone, dateKey: dateKey, date: date, line1: line1, line2: line2, line3: line3, line4: line4, retryCount: retryCount, completion: completion)
                } else {
                    debugLog("⚠️ FOUND \(foundRecords.count) existing records - updating the first one")
                    let recordToUpdate = foundRecords[0]
                    self?.updateExistingRecord(recordToUpdate, line1: line1, line2: line2, line3: line3, line4: line4, dateKey: dateKey, retryCount: retryCount, completion: completion)
                    
                    // Clean up duplicates if found
                    if foundRecords.count > 1 {
                        debugLog("🧹 CLEANING UP \(foundRecords.count - 1) duplicate records...")
                        for i in 1..<foundRecords.count {
                            self?.privateDatabase.delete(withRecordID: foundRecords[i].recordID) { _, error in
                                if let error = error {
                                    debugLog("⚠️ Failed to delete duplicate: \(error.localizedDescription)")
                                } else {
                                    debugLog("🗑️ Deleted duplicate record: \(foundRecords[i].recordID.recordName)")
                                }
                            }
                        }
                    }
                }
            }
        }
        
        privateDatabase.add(operation)
    }
    
    private func createNewDailyScheduleRecord(customZone: CKRecordZone, dateKey: String, date: Date, line1: String?, line2: String?, line3: String?, line4: String?, retryCount: Int, completion: @escaping (Bool, Error?) -> Void) {
        let recordID = CKRecord.ID(recordName: UUID().uuidString, zoneID: customZone.zoneID)
        debugLog("➕ CREATING NEW RECORD in CUSTOM zone \(customZone.zoneID.zoneName) (attempt \(retryCount + 1))")
        
        // Mark operation as starting
        markOperationStarting(for: dateKey, type: "SAVE")
        
        // Create record with the determined zone ID
        let record = CKRecord(recordType: "CD_DailySchedule", recordID: recordID)
        record["CD_date"] = date as CKRecordValue
        record["CD_id"] = UUID().uuidString as CKRecordValue
        record["CD_line1"] = line1 as CKRecordValue?
        record["CD_line2"] = line2 as CKRecordValue?
        record["CD_line3"] = line3 as CKRecordValue?
        record["CD_line4"] = line4 as CKRecordValue?
        
        debugLog("💾 CREATING NEW CLOUDKIT RECORD:")
        debugLog("   RecordID: \(recordID.recordName)")
        debugLog("   Zone: \(recordID.zoneID.zoneName)")
        debugLog("   CD_line1: '\(line1 ?? "nil")' (length: \(line1?.count ?? 0))")
        debugLog("   CD_line2: '\(line2 ?? "nil")' (length: \(line2?.count ?? 0))")
        debugLog("   CD_line3: '\(line3 ?? "nil")' (length: \(line3?.count ?? 0))")
        debugLog("   CD_line4: '\(line4 ?? "nil")' (length: \(line4?.count ?? 0))")
        
        // Save directly to CloudKit
        debugLog("   About to save NEW record to CloudKit...")
        saveRecordWithCompletion(record, dateKey: dateKey, date: date, line1: line1, line2: line2, line3: line3, line4: line4, retryCount: retryCount, completion: completion)
    }
    
    private func updateExistingRecord(_ record: CKRecord, line1: String?, line2: String?, line3: String?, line4: String?, dateKey: String, retryCount: Int, completion: @escaping (Bool, Error?) -> Void) {
        debugLog("🔄 UPDATING EXISTING RECORD:")
        debugLog("   RecordID: \(record.recordID.recordName)")
        debugLog("   Zone: \(record.recordID.zoneID.zoneName)")
        debugLog("   NEW line1: '\(line1 ?? "nil")' (length: \(line1?.count ?? 0))")
        debugLog("   NEW line2: '\(line2 ?? "nil")' (length: \(line2?.count ?? 0))")
        debugLog("   NEW line3: '\(line3 ?? "nil")' (length: \(line3?.count ?? 0))")
        debugLog("   NEW line4: '\(line4 ?? "nil")' (length: \(line4?.count ?? 0))")
        
        // Update record fields
        record["CD_line1"] = line1 as CKRecordValue?
        record["CD_line2"] = line2 as CKRecordValue?
        record["CD_line3"] = line3 as CKRecordValue?
        record["CD_line4"] = line4 as CKRecordValue?
        
        // Mark operation as starting
        markOperationStarting(for: dateKey, type: "UPDATE")
        
        debugLog("   About to save UPDATED record to CloudKit...")
        saveRecordWithCompletion(record, dateKey: dateKey, date: record["CD_date"] as? Date ?? Date(), line1: line1, line2: line2, line3: line3, line4: line4, retryCount: retryCount, completion: completion)
    }
    
    private func saveRecordWithCompletion(_ record: CKRecord, dateKey: String, date: Date, line1: String?, line2: String?, line3: String?, line4: String?, retryCount: Int, completion: @escaping (Bool, Error?) -> Void) {
        debugLog("💾 SAVE ATTEMPT \(retryCount + 1): Starting CloudKit save operation")
        debugLog("💾 SAVE DEBUG: Record to save:")
        debugLog("   RecordID: \(record.recordID.recordName)")
        debugLog("   Zone: \(record.recordID.zoneID.zoneName)")
        debugLog("   CD_line1: '\(record["CD_line1"] as? String ?? "nil")'")
        debugLog("   CD_line2: '\(record["CD_line2"] as? String ?? "nil")'")
        debugLog("   CD_line3: '\(record["CD_line3"] as? String ?? "nil")'")
        debugLog("   CD_date: \(record["CD_date"] as? Date ?? Date())")
        
        privateDatabase.save(record) { [weak self] savedRecord, error in
            DispatchQueue.main.async {
                if let error = error {
                    debugLog("❌ SAVE FAILED (attempt \(retryCount + 1)): \(error.localizedDescription)")
                    debugLog("💾 SAVE ERROR DETAILS:")
                    debugLog("   Error domain: \((error as NSError).domain)")
                    debugLog("   Error code: \((error as NSError).code)")
                    debugLog("   Error userInfo: \((error as NSError).userInfo)")
                    
                    if let ckError = error as? CKError {
                        debugLog("   CKError code: \(ckError.code.rawValue)")
                        debugLog("   CKError type: \(ckError.code)")
                        let underlying = (ckError as NSError).userInfo[NSUnderlyingErrorKey] as? Error
                        debugLog("   Underlying error: \(underlying?.localizedDescription ?? "none")")
                        
                        // Enhanced error analysis for save reliability
                        switch ckError.code {
                        case .zoneNotFound:
                            debugLog("💾 SAVE ISSUE: Custom zone not found - zone may have been deleted")
                        case .unknownItem:
                            debugLog("💾 SAVE ISSUE: Record or zone doesn't exist")
                        case .networkFailure:
                            debugLog("💾 SAVE ISSUE: Network connectivity problem")
                        case .serverRecordChanged:
                            debugLog("💾 SAVE ISSUE: Record was modified by another device")
                        case .notAuthenticated:
                            debugLog("💾 SAVE ISSUE: Not signed into iCloud")
                        case .permissionFailure:
                            debugLog("💾 SAVE ISSUE: CloudKit permissions problem")
                        case .quotaExceeded:
                            debugLog("💾 SAVE ISSUE: iCloud storage quota exceeded")
                        case .serverRejectedRequest:
                            debugLog("💾 SAVE ISSUE: CloudKit server rejected the save request")
                        default:
                            debugLog("💾 SAVE ISSUE: Unknown CloudKit error")
                        }
                    }
                    
                    // Check if this is a retryable error (zone, network, or oplock conflict)
                    if let ckError = error as? CKError,
                       (ckError.code == .zoneNotFound || ckError.code == .unknownItem || ckError.code == .networkFailure || ckError.code == .serverRecordChanged),
                       retryCount < 2 {
                        debugLog("🔄 RETRYABLE ERROR: Will retry save operation (attempt \(retryCount + 2))")
                        self?.markOperationCompleted(for: dateKey, type: "SAVE", success: false)
                        // Retry with incremented count
                        self?.saveDailySchedule(date: date, line1: line1, line2: line2, line3: line3, line4: line4, retryCount: retryCount + 1, completion: completion)
                        return
                    } else {
                        debugLog("💾 NON-RETRYABLE ERROR: Save operation failed permanently")
                    }
                    
                    self?.errorMessage = "Failed to save schedule: \(error.localizedDescription)"
                    self?.markOperationCompleted(for: dateKey, type: "SAVE", success: false)
                    completion(false, error)
                } else {
                    debugLog("✅ SAVE SUCCESS (attempt \(retryCount + 1)): CloudKit save completed")
                    
                    // Comprehensive verification of what was actually saved
                    if let savedRecord = savedRecord {
                        debugLog("💾 CLOUDKIT SAVE VERIFICATION:")
                        debugLog("   ✅ Saved RecordID: \(savedRecord.recordID.recordName)")
                        debugLog("   ✅ Saved Zone: \(savedRecord.recordID.zoneID.zoneName)")
                        debugLog("   ✅ Saved CD_date: \(savedRecord["CD_date"] as? Date ?? Date())")
                        debugLog("   ✅ Saved CD_line1: '\(savedRecord["CD_line1"] as? String ?? "nil")' (length: \((savedRecord["CD_line1"] as? String)?.count ?? 0))")
                        debugLog("   ✅ Saved CD_line2: '\(savedRecord["CD_line2"] as? String ?? "nil")' (length: \((savedRecord["CD_line2"] as? String)?.count ?? 0))")
                        debugLog("   ✅ Saved CD_line3: '\(savedRecord["CD_line3"] as? String ?? "nil")' (length: \((savedRecord["CD_line3"] as? String)?.count ?? 0))")
                        debugLog("   ✅ Record modification date: \(savedRecord.modificationDate ?? Date())")
                        debugLog("   ✅ Record creation date: \(savedRecord.creationDate ?? Date())")
                        
                        // Verify the record can be converted back to our model
                        let newSchedule = DailyScheduleRecord(from: savedRecord)
                        debugLog("💾 MODEL CONVERSION CHECK:")
                        debugLog("   Model line1: '\(newSchedule.line1 ?? "nil")'")
                        debugLog("   Model line2: '\(newSchedule.line2 ?? "nil")'")
                        debugLog("   Model line3: '\(newSchedule.line3 ?? "nil")'")
                        debugLog("   Model date: \(newSchedule.date ?? Date())")
                        
                        self?.dailySchedules.append(newSchedule)
                        debugLog("💾 LOCAL MEMORY: Added record to dailySchedules array (count now: \(self?.dailySchedules.count ?? 0))")
                        
                        // CRITICAL: Verify the record actually exists in CloudKit
                        debugLog("🔍 POST-SAVE VERIFICATION: Checking if record actually exists in CloudKit...")
                        self?.verifyRecordExists(recordID: savedRecord.recordID)
                        
                        self?.markOperationCompleted(for: savedRecord.recordID.recordName, type: "SAVE", success: true)
                    } else {
                        debugLog("⚠️ SAVE WARNING: CloudKit returned success but no savedRecord object")
                    }
                    completion(true, nil)
                }
            }
        }
    }
    
    private func saveMonthlyRecordWithCompletion(_ record: CKRecord, monthKey: String, month: Int, year: Int, retryCount: Int, completion: @escaping (Bool, Error?) -> Void) {
        privateDatabase.save(record) { [weak self] savedRecord, error in
            DispatchQueue.main.async {
                if let error = error {
                    debugLog("❌ Failed to save monthly notes record (attempt \(retryCount + 1)): \(error.localizedDescription)")
                    
                    // Check if this is a zone-related error and we can retry
                    if let ckError = error as? CKError,
                       (ckError.code == .zoneNotFound || ckError.code == .unknownItem || ckError.code == .networkFailure),
                       retryCount < 2 {
                        debugLog("🔄 Zone/network error detected for monthly notes - retrying with attempt \(retryCount + 1)")
                        self?.markOperationCompleted(for: monthKey, type: "SAVE_MONTHLY", success: false)
                        // Retry with incremented count - need to pass line1, line2, line3 from the record
                        let line1 = record["CD_line1"] as? String
                        let line2 = record["CD_line2"] as? String
                        let line3 = record["CD_line3"] as? String
                        self?.saveMonthlyNotes(month: month, year: year, line1: line1, line2: line2, line3: line3, retryCount: retryCount + 1, completion: completion)
                        return
                    }
                    
                    self?.errorMessage = "Failed to save notes: \(error.localizedDescription)"
                    self?.markOperationCompleted(for: monthKey, type: "SAVE_MONTHLY", success: false)
                    completion(false, error)
                } else {
                    debugLog("✅ Successfully saved monthly notes record (attempt \(retryCount + 1))")
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
    
    func updateDailySchedule(recordName: String, zoneID: CKRecordZone.ID, date: Date, line1: String?, line2: String?, line3: String?, line4: String?, completion: @escaping (Bool, Error?) -> Void) {
        debugLog("🔄 Attempting to update record: \(recordName) in zone: \(zoneID.zoneName)")
        
        // Check CloudKit status first
        guard cloudKitAvailable else {
            completion(false, NSError(domain: "CloudKitManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "iCloud not available"]))
            return
        }
        
        // Mark operation as starting
        markOperationStarting(for: recordName, type: "UPDATE")
        
        let recordID = CKRecord.ID(recordName: recordName, zoneID: zoneID)
        
        privateDatabase.fetch(withRecordID: recordID) { [weak self] record, error in
                            if let error = error {
                DispatchQueue.main.async {
                    debugLog("❌ Failed to fetch record for update: \(error.localizedDescription)")
                    debugLog("🔍 DEBUG: Error details - recordID: \(recordID), zoneID: \(recordID.zoneID.zoneName)")
                    debugLog("🔍 DEBUG: Error code: \((error as? CKError)?.code.rawValue ?? -1)")
                    
                    // Check if this is a "Record not found" error - if so, create new record instead
                    if error.localizedDescription.contains("Record not found") || (error as? CKError)?.code == .unknownItem {
                        debugLog("🔄 Record not found in CloudKit - creating new record instead")
                        self?.markOperationCompleted(for: recordName, type: "UPDATE", success: false)
                        self?.saveDailySchedule(date: date, line1: line1, line2: line2, line3: line3, line4: line4, completion: completion)
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
                    self?.saveDailySchedule(date: date, line1: line1, line2: line2, line3: line3, line4: line4, completion: completion)
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
            debugLog("   NEW line4: '\(line4 ?? "nil")' (length: \(line4?.count ?? 0))")
            
            // Update the record with new values
            record["CD_date"] = date as CKRecordValue
            record["CD_line1"] = line1 as CKRecordValue?
            record["CD_line2"] = line2 as CKRecordValue?
            record["CD_line3"] = line3 as CKRecordValue?
            record["CD_line4"] = line4 as CKRecordValue?
            
            debugLog("   About to update CloudKit record...")
            
            self?.privateDatabase.save(record) { savedRecord, error in
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
        
        privateDatabase.delete(withRecordID: recordID) { [weak self] deletedRecordID, error in
                DispatchQueue.main.async {
                if let error = error {
                    debugLog("❌ Error deleting daily schedule: \(error)")
                    self?.errorMessage = "Failed to delete schedule: \(error.localizedDescription)"
                    self?.markOperationCompleted(for: recordName, type: "DELETE", success: false)
                    completion(false, error)
                } else {
                    debugLog("✅ Successfully deleted daily schedule from CloudKit: \(recordName)")
                    
                    // CRITICAL FIX: Find the deleted record's date BEFORE removing it
                    // This prevents stale data from being restored during fetch operations
                    let deletedRecord = self?.dailySchedules.first(where: { $0.id == recordName })
                    let deletedDate = deletedRecord?.date
                    
                    // Remove from local array immediately instead of full refresh
                    self?.dailySchedules.removeAll { $0.id == recordName }
                    debugLog("📱 Removed from local array. Local count now: \(self?.dailySchedules.count ?? 0)")
                    
                    // Also remove any other records for the same DATE from memory
                    if let deletedDate = deletedDate {
                        let beforeCount = self?.dailySchedules.count ?? 0
                        self?.dailySchedules.removeAll { record in
                            guard let recordDate = record.date else { return false }
                            return Calendar.current.isDate(recordDate, inSameDayAs: deletedDate)
                        }
                        let afterCount = self?.dailySchedules.count ?? 0
                        if beforeCount != afterCount {
                            debugLog("🧹 MEMORY CLEANUP: Removed \(beforeCount - afterCount) additional records for date \(deletedDate) from local memory")
                        }
                    }
                    
                    // Enhanced tracking for deletion operations
                    self?.recentDeletionOperations.insert(recordName)
                    self?.lastOperationTime = Date()
                    self?.markOperationCompleted(for: recordName, type: "DELETE", success: true)
                    debugLog("🕒 Enhanced tracking for deletion operation \(recordName) - preventing premature fetch")
                    
                    // Deletion tracking will be cleared by cleanup operations
                    
                    completion(true, nil)
                }
            }
        }
    }
    
    /// Smart save that handles deletion when all fields are empty
    func saveOrDeleteDailySchedule(existingRecordName: String?, existingZoneID: CKRecordZone.ID?, date: Date, line1: String?, line2: String?, line3: String?, line4: String?, completion: @escaping (Bool, Error?) -> Void) {
        // Check if all fields are empty
        let isEmpty = (line1?.isEmpty ?? true) && (line2?.isEmpty ?? true) && (line3?.isEmpty ?? true) && (line4?.isEmpty ?? true)
        let dateKey = "\(Calendar.current.startOfDay(for: date))"
        
        debugLog("🤔 Smart save called for \(dateKey)")
        debugLog("📊 isEmpty: \(isEmpty), existingRecord: \(existingRecordName ?? "none")")
        debugLog("🔍 CLOUDKIT MANAGER RECEIVED:")
        debugLog("   line1: '\(line1 ?? "nil")' (length: \(line1?.count ?? 0))")
        debugLog("   line2: '\(line2 ?? "nil")' (length: \(line2?.count ?? 0))")
        debugLog("   line3: '\(line3 ?? "nil")' (length: \(line3?.count ?? 0))")
        debugLog("   line4: '\(line4 ?? "nil")' (length: \(line4?.count ?? 0))")
        debugLog("   existingZoneID: '\(existingZoneID?.zoneName ?? "nil")'")
        
        // NOTE: Removed data protection check for user-initiated saves
        // Protection should only apply to incoming CloudKit updates, not user saves
        
        if isEmpty && existingRecordName != nil && existingZoneID != nil {
            // Delete existing record if all fields are empty
            debugLog("🗑️ All fields empty + existing record - calling DELETE for \(existingRecordName!) in zone \(existingZoneID!.zoneName)")
            
            
            deleteDailySchedule(recordName: existingRecordName!, zoneID: existingZoneID!, completion: completion)
        } else if !isEmpty {
            // Save or update if there's content
            debugLog("💾 Fields have content - calling SAVE for \(dateKey)")
            
            if existingRecordName != nil && existingZoneID != nil {
                // UPDATE existing record - use fetch-modify-save pattern
                debugLog("🔄 Updating existing record \(existingRecordName!) in zone \(existingZoneID!.zoneName)")
                updateDailySchedule(recordName: existingRecordName!, zoneID: existingZoneID!, date: date, line1: line1, line2: line2, line3: line3, line4: line4, completion: completion)
            } else {
                // CREATE new record - global memory has no existing record
                debugLog("➕ Creating new record for \(dateKey)")
                saveDailySchedule(date: date, line1: line1, line2: line2, line3: line3, line4: line4, completion: completion)
            }
        } else {
            // No existing record and no content - do nothing
            debugLog("⏸️ No existing record and no content - doing nothing for \(dateKey)")
            completion(true, nil)
        }
    }
    
    func saveMonthlyNotes(month: Int, year: Int, line1: String?, line2: String?, line3: String?, completion: @escaping (Bool, Error?) -> Void) {
        saveMonthlyNotes(month: month, year: year, line1: line1, line2: line2, line3: line3, retryCount: 0, completion: completion)
    }
    
    private func saveMonthlyNotes(month: Int, year: Int, line1: String?, line2: String?, line3: String?, retryCount: Int, completion: @escaping (Bool, Error?) -> Void) {
        let monthKey = "\(year)-\(month)"
        debugLog("💾 Saving monthly notes for \(monthKey) (retry: \(retryCount))")
        
        // Check CloudKit status first
        guard cloudKitAvailable else {
            completion(false, NSError(domain: "CloudKitManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "iCloud not available"]))
            return
        }
        
        // Limit retries to prevent infinite loops
        guard retryCount < 3 else {
            debugLog("❌ Maximum retry attempts reached (\(retryCount)) for monthly notes - failing save operation")
            completion(false, NSError(domain: "CloudKitManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Maximum retry attempts reached"]))
            return
        }
        
        // Mark operation as starting
        markOperationStarting(for: monthKey, type: "SAVE_MONTHLY")
        
        // First, check if a record already exists for this month/year
        let predicate = NSPredicate(format: "CD_month == %d AND CD_year == %d", month, year)
        let query = CKQuery(recordType: "CD_MonthlyNotes", predicate: predicate)
        
        // CUSTOM ZONE ONLY - Never use default zone
        guard let customZone = userCustomZone else {
            debugLog("❌ MONTHLY NOTES SAVE FAILED: Custom zone required - PSC never uses default zones")
            DispatchQueue.main.async {
                self.markOperationCompleted(for: monthKey, type: "SAVE_MONTHLY", success: false)
                completion(false, NSError(domain: "CloudKitManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Custom zone required for sharing functionality"]))
            }
            return
        }
        
        privateDatabase.fetch(withQuery: query, inZoneWith: customZone.zoneID, desiredKeys: nil, resultsLimit: CKQueryOperation.maximumResults) { [weak self, retryCount, monthKey, month, year, line1, line2, line3, completion] (result: Result<(matchResults: [(CKRecord.ID, Result<CKRecord, Error>)], queryCursor: CKQueryOperation.Cursor?), Error>) in
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
                    // Create new record in custom zone only
                    let recordID = CKRecord.ID(recordName: UUID().uuidString, zoneID: customZone.zoneID)
                    debugLog("➕ Creating new monthly notes record for \(monthKey) in CUSTOM zone")
                    
                    record = CKRecord(recordType: "CD_MonthlyNotes", recordID: recordID)
                    record["CD_id"] = UUID().uuidString as CKRecordValue
                    record["CD_month"] = month as CKRecordValue
                    record["CD_year"] = year as CKRecordValue
                    
                    // For new records, create without container link to avoid async issues
                    debugLog("➕ Creating new monthly notes record for \(monthKey) without container link (performance optimization)")
                    // Note: Container linking removed to avoid concurrency issues - data will still sync properly
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
            
            DispatchQueue.main.async {
                self?.saveMonthlyRecordWithCompletion(record, monthKey: monthKey, month: month, year: year, retryCount: retryCount, completion: completion)
            }
        }
    }
    
    // MARK: - Smart Save/Delete for Monthly Notes
    func saveOrDeleteMonthlyNotes(existingRecordName: String? = nil, existingZoneID: CKRecordZone.ID? = nil, month: Int, year: Int, line1: String?, line2: String?, line3: String?, completion: @escaping (Bool, Error?) -> Void) {
        // Check if all fields are empty
        let isEmpty = (line1?.isEmpty ?? true) && (line2?.isEmpty ?? true) && (line3?.isEmpty ?? true)
        let monthKey = "\(year)-\(month)"
        
        debugLog("🤔 Smart monthly notes save called for \(monthKey)")
        debugLog("📊 isEmpty: \(isEmpty), existingRecord: \(existingRecordName ?? "none")")
        debugLog("📝 Monthly note values - line1: '\(line1 ?? "nil")', line2: '\(line2 ?? "nil")', line3: '\(line3 ?? "nil")'")
        debugLog("🔍 Monthly notes zone: '\(existingZoneID?.zoneName ?? "nil")'")
        
        // NOTE: Removed data protection check for user-initiated saves
        // Protection should only apply to incoming CloudKit updates, not user saves
        
        if isEmpty && existingRecordName != nil && existingZoneID != nil {
            // Delete existing record if all fields are empty - MATCH DAILY SCHEDULE PATTERN
            debugLog("🗑️ All monthly note fields empty + existing record - calling DELETE for \(existingRecordName!) in zone \(existingZoneID!.zoneName)")
            
            
            deleteMonthlyNotes(recordName: existingRecordName!, zoneID: existingZoneID!, month: month, year: year, completion: completion)
        } else if !isEmpty {
            // Fields have content - save/update the record
            debugLog("💾 Monthly note fields have content - calling SAVE/UPDATE for \(monthKey)")
            saveMonthlyNotes(month: month, year: year, line1: line1, line2: line2, line3: line3, completion: completion)
        } else {
            // No existing record and no content - do nothing (matching daily schedule pattern)
            debugLog("⏸️ No existing monthly notes record and no content - doing nothing for \(monthKey)")
            completion(true, nil)
        }
    }
    
    func deleteMonthlyNotes(recordName: String, zoneID: CKRecordZone.ID, month: Int, year: Int, completion: @escaping (Bool, Error?) -> Void) {
        let monthKey = "\(year)-\(month)"
        debugLog("🗑️ Attempting to delete monthly notes record: \(recordName) for \(monthKey) in zone: \(zoneID.zoneName)")
        
        // Check CloudKit status first
        guard cloudKitAvailable else {
            completion(false, NSError(domain: "CloudKitManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "iCloud not available"]))
            return
        }
        
        // Mark operation as starting
        markOperationStarting(for: recordName, type: "DELETE_MONTHLY")
        
        // CRITICAL FIX: Use the correct zone ID for deletion (matching daily schedule pattern)
        let recordID = CKRecord.ID(recordName: recordName, zoneID: zoneID)
        
        privateDatabase.delete(withRecordID: recordID) { [weak self] recordID, error in
                        DispatchQueue.main.async {
                            if let error = error {
                    debugLog("❌ Failed to delete monthly notes record: \(error.localizedDescription)")
                    self?.errorMessage = "Failed to delete notes: \(error.localizedDescription)"
                    self?.markOperationCompleted(for: recordName, type: "DELETE_MONTHLY", success: false)
                                completion(false, error)
                            } else {
                    debugLog("✅ Successfully deleted monthly notes from CloudKit: \(recordName)")
                    
                    // CRITICAL FIX: Enhanced memory cleanup matching daily schedule pattern
                    // Remove from local array immediately instead of full refresh
                    let beforeCount = self?.monthlyNotes.count ?? 0
                    self?.monthlyNotes.removeAll { $0.month == month && $0.year == year }
                    let afterCount = self?.monthlyNotes.count ?? 0
                    debugLog("📱 Removed from local monthly notes array. Local count: \(beforeCount) → \(afterCount)")
                    
                    // Also remove any records with the same recordName (prevents stale data restoration)
                    self?.monthlyNotes.removeAll { $0.id == recordName }
                    debugLog("🧹 MEMORY CLEANUP: Ensured complete removal of monthly notes record \(recordName)")
                    
                    // Enhanced tracking for deletion operations
                    self?.recentDeletionOperations.insert(recordName)
                    self?.lastOperationTime = Date()
                    self?.markOperationCompleted(for: recordName, type: "DELETE_MONTHLY", success: true)
                    debugLog("🕒 Enhanced tracking for monthly notes deletion \(recordName)")
                    
                    // Deletion tracking will be cleared by cleanup operations
                    
                                completion(true, nil)
                            }
                        }
                    }
    }
    
    // MARK: - Enhanced Debugging
    func debugAllZonesAndData() {
        debugLog("🔍 COMPREHENSIVE DEBUG: Analyzing all zones and data...")
        
        Task {
            do {
                let allZones = try await privateDatabase.allRecordZones()
                debugLog("📊 Found \(allZones.count) total zones in private database:")
                
                for zone in allZones {
                    debugLog("   🗂️ Zone: \(zone.zoneID.zoneName) (owner: \(zone.zoneID.ownerName))")
                    
                    // Count records in each zone
                    let query = CKQuery(recordType: "CD_DailySchedule", predicate: NSPredicate(value: true))
                    do {
                        let (matchResults, _) = try await privateDatabase.records(matching: query, inZoneWith: zone.zoneID)
                        let count = matchResults.count
                        debugLog("     📅 Daily schedules in this zone: \(count)")
                        
                        if count > 0 {
                            debugLog("     🔍 Sample records:")
                            let records = matchResults.compactMap { _, result in try? result.get() }
                            for (index, record) in records.prefix(3).enumerated() {
                                let date = record["CD_date"] as? Date ?? Date()
                                let line1 = record["CD_line1"] as? String ?? ""
                                debugLog("       [\(index+1)] \(date): '\(line1)'")
                            }
                        }
                    } catch {
                        debugLog("     ❌ Error querying zone: \(error)")
                    }
                }
                
                await MainActor.run {
                    debugLog("📱 Current app state:")
                    debugLog("   Current userZoneID: \(self.userZoneID.zoneName)")
                    debugLog("   Current userCustomZone: \(self.userCustomZone?.zoneID.zoneName ?? "nil")")
                    debugLog("   Local dailySchedules count: \(self.dailySchedules.count)")
                    debugLog("   Local monthlyNotes count: \(self.monthlyNotes.count)")
                }
                
            } catch {
                debugLog("❌ Failed to debug zones: \(error)")
            }
        }
    }
    
    // MARK: - Global Memory Editing Methods
    
    /// Get existing record index for a date (read-only, safe for view rendering)
    func getRecordIndex(for date: Date) -> Int? {
        // FIX: Use UTC calendar to match CloudKit data timestamps
        var utcCalendar = Calendar.current
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!
        let dayStart = utcCalendar.startOfDay(for: date)
        
        return dailySchedules.firstIndex(where: { schedule in
            guard let scheduleDate = schedule.date else { return false }
            return utcCalendar.isDate(scheduleDate, inSameDayAs: dayStart)
        })
    }
    
    /// Create a record for editing (separate from view rendering to avoid publishing errors)
    func createRecordForEditing(date: Date) {
        // FIX: Use UTC calendar to match CloudKit data timestamps
        var utcCalendar = Calendar.current
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!
        let dayStart = utcCalendar.startOfDay(for: date)
        
        // Check if record already exists
        if dailySchedules.contains(where: { schedule in
            guard let scheduleDate = schedule.date else { return false }
            return utcCalendar.isDate(scheduleDate, inSameDayAs: dayStart)
        }) {
            return // Already exists
        }
        
        // CRITICAL FIX: Don't create records if zone isn't ready yet
        guard isZoneReady, let customZone = userCustomZone else {
            debugLog("⏸️ Zone not ready yet - cannot create record for \(dayStart)")
            return
        }
        
        let newRecord = DailyScheduleRecord(date: dayStart, zoneID: customZone.zoneID)
        dailySchedules.append(newRecord)
        debugLog("➕ Created new record for editing: \(dayStart)")
    }
    
    /// Update a field in global memory
    func updateField(at index: Int, field: String, value: String) {
        guard index >= 0 && index < dailySchedules.count else {
            debugLog("❌ Invalid index for field update: \(index)")
            return
        }
        
        var record = dailySchedules[index]
        let oldValue: String?
        
        switch field {
        case "line1":
            oldValue = record.line1
            record.line1 = value.isEmpty ? nil : value
        case "line2":
            oldValue = record.line2
            record.line2 = value.isEmpty ? nil : value
        case "line3":
            oldValue = record.line3
            record.line3 = value.isEmpty ? nil : value
        case "line4":
            oldValue = record.line4
            record.line4 = value.isEmpty ? nil : value
        default:
            debugLog("❌ Unknown field: \(field)")
            return
        }
        
        // Mark as modified if value actually changed
        let newValue = value.isEmpty ? nil : value
        if oldValue != newValue {
            // Check if the record has any actual content now
            let hasContent = !((record.line1 ?? "").isEmpty && (record.line2 ?? "").isEmpty && (record.line3 ?? "").isEmpty && (record.line4 ?? "").isEmpty)
            
            // CRITICAL FIX: Empty fields with existing CloudKit record = deletion needed = modified!
            // This means we need to check if this record came from CloudKit (has existing data to delete)
            let isExistingRecord = record.id.count > 0 && !record.id.hasPrefix("temp") // Simple check for existing vs new record
            let needsDeletion = !hasContent && isExistingRecord
            
            record.isModified = hasContent || needsDeletion
            
            if needsDeletion {
                debugLog("✏️ Updated \(field) for \(record.date?.description ?? "unknown date"): '\(value)' (DELETION NEEDED - modified: true)")
            } else {
                debugLog("✏️ Updated \(field) for \(record.date?.description ?? "unknown date"): '\(value)' (modified: \(hasContent))")
            }
        }
        
        dailySchedules[index] = record
    }
    
    /// Get current value for a field
    func getFieldValue(date: Date, field: String) -> String {
        // FIX: Use UTC calendar to match CloudKit data timestamps
        var utcCalendar = Calendar.current
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!
        let dayStart = utcCalendar.startOfDay(for: date)
        
        guard let record = dailySchedules.first(where: { schedule in
            guard let scheduleDate = schedule.date else { return false }
            return utcCalendar.isDate(scheduleDate, inSameDayAs: dayStart)
        }) else {
            return ""
        }
        
        switch field {
        case "line1": return record.line1 ?? ""
        case "line2": return record.line2 ?? ""
        case "line3": return record.line3 ?? ""
        case "line4": return record.line4 ?? ""
        default: return ""
        }
    }
    
    /// Check if there are any unsaved changes
    var hasUnsavedChanges: Bool {
        return dailySchedules.contains { $0.isModified } || monthlyNotes.contains { $0.isModified }
    }
    
    // MARK: - Custom Zone Sharing for Privacy
    
    /// Fetch existing share for a zone using the proper CloudKit API
    private func fetchExistingZoneShare(_ zoneID: CKRecordZone.ID, completion: @escaping (Result<CKShare, Error>) -> Void) {
        debugLog("🔍 SHARE FETCH: Attempting to fetch existing zone share for: \(zoneID.zoneName)")
        debugLog("🔍 SHARE FETCH: Zone owner: \(zoneID.ownerName)")
        debugLog("🔍 SHARE FETCH: Share record name will be: cloudkit.zoneshare")

        Task {
            do {
                // Use the correct CloudKit API to fetch zone share
                let shareRecordID = CKRecord.ID(recordName: "cloudkit.zoneshare", zoneID: zoneID)
                debugLog("🔍 SHARE FETCH: Looking for record: \(shareRecordID.recordName) in zone: \(shareRecordID.zoneID.zoneName)")
                let record = try await privateDatabase.record(for: shareRecordID)

                debugLog("🔍 SHARE FETCH: Record retrieved successfully")
                debugLog("🔍 SHARE FETCH: Record type: \(record.recordType)")
                debugLog("🔍 SHARE FETCH: Record ID: \(record.recordID.recordName)")

                if let share = record as? CKShare {
                    debugLog("✅ SHARE FETCH: Found existing zone share")
                    debugLog("🔗 SHARE URL: \(share.url?.absoluteString ?? "NO URL")")
                    debugLog("🔗 SHARE PARTICIPANTS: \(share.participants.count)")
                    debugLog("🔗 SHARE OWNER: \(share.owner.userIdentity.userRecordID?.recordName ?? "nil")")
                    completion(.success(share))
                } else {
                    debugLog("❌ SHARE FETCH: Record found but not a CKShare: \(type(of: record))")
                    completion(.failure(NSError(domain: "CloudKitManager", code: -4, userInfo: [NSLocalizedDescriptionKey: "Found record but not a CKShare"])))
                }

            } catch {
                debugLog("❌ SHARE FETCH: Failed to fetch zone share - \(error)")
                if let ckError = error as? CKError {
                    debugLog("🔍 SHARE FETCH: CKError code: \(ckError.code.rawValue)")
                    debugLog("🔍 SHARE FETCH: CKError type: \(ckError.code)")
                    if ckError.code == .unknownItem {
                        debugLog("🔍 SHARE FETCH: No share exists for this zone")
                    }
                }
                completion(.failure(error))
            }
        }
    }
    
    /// Create a share for user data with extensive debugging for Production reliability issues
    func createCustomZoneShare(completion: @escaping (Result<CKShare, Error>) -> Void) {
        debugLog("🔗 SHARE CREATION START: Creating ZONE-BASED share for all schedule records")
        debugLog("🔗 SHARE DEBUG: Current Apple ID will be used for sharing")
        debugLog("🔗 SHARE DEBUG: Container: \(container.containerIdentifier ?? "unknown")")
        debugLog("🔗 SHARE DEBUG: Database type: Private")
        
        guard let customZone = userCustomZone else {
            debugLog("❌ SHARE ERROR: Custom zone not available")
            debugLog("🔍 SHARE DEBUG: userCustomZone is nil")
            debugLog("🔍 SHARE DEBUG: userZoneID: \(userZoneID.zoneName)")
            debugLog("🔍 SHARE DEBUG: isZoneReady: \(isZoneReady)")
            completion(.failure(NSError(domain: "CloudKitManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Custom zone not available for sharing"])))
            return
        }
        
        debugLog("🔗 SHARE DEBUG: Using zone: \(customZone.zoneID.zoneName)")
        debugLog("🔗 SHARE DEBUG: Zone owner: \(customZone.zoneID.ownerName)")
        debugLog("🔗 SHARE DEBUG: Records to share: \(dailySchedules.count) daily + \(monthlyNotes.count) monthly")
        
        Task { @MainActor in
            do {
                debugLog("🔗 SHARE STEP 1: Creating CKShare object...")
                
                // Create zone-level share (simpler and more reliable than record-based)
                let share = CKShare(recordZoneID: customZone.zoneID)
                let currentYear = Calendar.current.component(.year, from: Date())
                share[CKShare.SystemFieldKey.title] = "Provider Schedule \(currentYear)" as CKRecordValue
                share.publicPermission = .readOnly // Allow read access for shared users
                
                debugLog("🔗 SHARE DEBUG: Share object created")
                debugLog("🔗 SHARE DEBUG: Share recordID: \(share.recordID.recordName)")
                debugLog("🔗 SHARE DEBUG: Share zoneID: \(share.recordID.zoneID.zoneName)")
                debugLog("🔗 SHARE DEBUG: Share title: Provider Schedule \(currentYear)")
                debugLog("🔗 SHARE DEBUG: Public permission: readOnly")
                debugLog("🔗 SHARE DEBUG: Share owner: \(share.owner.userIdentity.userRecordID?.recordName ?? "nil")")
                debugLog("🔗 SHARE DEBUG: Share participants count: \(share.participants.count)")
                
                debugLog("🔗 SHARE STEP 2: Saving share to CloudKit...")
                debugLog("🔗 SHARE DEBUG: Saving to private database with zone: \(customZone.zoneID.zoneName)")
                let savedRecords = try await privateDatabase.modifyRecords(saving: [share], deleting: [])

                debugLog("🔗 SHARE DEBUG: Save operation completed")
                debugLog("🔗 SHARE DEBUG: Save results count: \(savedRecords.saveResults.count)")
                debugLog("🔗 SHARE DEBUG: Delete results count: \(savedRecords.deleteResults.count)")
                
                for (recordID, result) in savedRecords.saveResults {
                    debugLog("🔗 SHARE DEBUG: Result for \(recordID.recordName):")
                    switch result {
                    case .success(let record):
                        debugLog("🔗 SHARE DEBUG: ✅ Success - Record type: \(type(of: record))")
                        if let shareRecord = record as? CKShare {
                            debugLog("🔗 SHARE DEBUG: ✅ Found CKShare in results!")
                            debugLog("🔗 SHARE DEBUG: Share URL: \(shareRecord.url?.absoluteString ?? "NO URL")")
                            debugLog("🔗 SHARE DEBUG: Share URL exists: \(shareRecord.url != nil)")
                            debugLog("🔗 SHARE DEBUG: Share participants: \(shareRecord.participants.count)")
                            debugLog("🔗 SHARE DEBUG: Share owner: \(shareRecord.owner)")
                            debugLog("🔗 SHARE DEBUG: Share zone: \(shareRecord.recordID.zoneID.zoneName)")
                            completion(.success(shareRecord))
                            return
                        }
                    case .failure(let error):
                        debugLog("🔗 SHARE DEBUG: ❌ Failure - Error: \(error)")
                    }
                }
                
                // If we get here, no CKShare was found in results - try to fetch it directly
                debugLog("⚠️ SHARE WARNING: No CKShare found in save results - attempting direct fetch")
                debugLog("🔍 SHARE DEBUG: This may be a CloudKit consistency delay")
                
                // Fallback: Try to fetch the existing zone share
                debugLog("🔄 SHARE FALLBACK: Attempting to fetch existing zone share")
                self.fetchExistingZoneShare(customZone.zoneID) { result in
                    switch result {
                    case .success(let existingShare):
                        debugLog("✅ SHARE RECOVERY: Found existing zone share")
                        debugLog("🔗 SHARE RECOVERY: URL: \(existingShare.url?.absoluteString ?? "NO URL")")
                        debugLog("🔗 SHARE RECOVERY: Participants: \(existingShare.participants.count)")
                        completion(.success(existingShare))
                    case .failure(let error):
                        debugLog("❌ SHARE ERROR: Could not find share even with direct fetch: \(error.localizedDescription)")
                        completion(.failure(NSError(domain: "CloudKitManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "Share created but not returned by CloudKit"])))
                    }
                }
                
            } catch {
                debugLog("❌ SHARE ERROR: Exception during share creation: \(error)")
                debugLog("🔍 SHARE DEBUG: Error type: \(type(of: error))")
                debugLog("🔍 SHARE DEBUG: Error domain: \((error as NSError).domain)")
                debugLog("🔍 SHARE DEBUG: Error code: \((error as NSError).code)")
                debugLog("🔍 SHARE DEBUG: Error userInfo: \((error as NSError).userInfo)")
                
                if let ckError = error as? CKError {
                    debugLog("🔍 SHARE DEBUG: CKError code: \(ckError.code.rawValue)")
                    debugLog("🔍 SHARE DEBUG: CKError description: \(ckError.localizedDescription)")
                    let underlying = (ckError as NSError).userInfo[NSUnderlyingErrorKey] as? Error
                    debugLog("🔍 SHARE DEBUG: CKError underlying: \(underlying?.localizedDescription ?? "none")")
                    
                    // Handle the case where share already exists
                    if ckError.code == .serverRecordChanged {
                        debugLog("🔄 SHARE EXISTS: Share already exists for zone - fetching existing share")
                        self.fetchExistingZoneShare(customZone.zoneID, completion: completion)
                        return
                    }
                }
                
                completion(.failure(error))
            }
        }
    }
    
    
    /// Helper function to create share from a specific record
    private func createShareFromRecord(_ rootRecord: CKRecord, completion: @escaping (Result<CKShare, Error>) -> Void) async {
        do {
            // Create share with the root record (from any zone)
            let share = CKShare(rootRecord: rootRecord)
            share[CKShare.SystemFieldKey.title] = "Provider Schedule \(Calendar.current.component(.year, from: Date()))"
            share.publicPermission = .none // Invite-only for privacy (consistent with zone sharing)
            
            debugLog("🔗 Creating share from record in zone: \(rootRecord.recordID.zoneID.zoneName)")
            
            // CRITICAL: Save BOTH the root record AND the share in the same operation
            // This is required by CloudKit when creating shares
            let savedRecords = try await privateDatabase.modifyRecords(saving: [rootRecord, share], deleting: [])
            
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
    
    // MARK: - Monthly Notes Field Updates (ContentView Interface)
    func createOrUpdateMonthlyNotes(month: Int, year: Int, fieldType: MonthlyNotesField, value: String) async {
        // Find existing record if any
        let existingRecord = self.monthlyNotes.first { $0.month == month && $0.year == year }
        
        // Get current values for all fields
        var line1 = existingRecord?.line1 ?? ""
        var line2 = existingRecord?.line2 ?? ""  
        var line3 = existingRecord?.line3 ?? ""
        
        // Update the specific field
        switch fieldType {
        case .line1:
            line1 = value
        case .line2:
            line2 = value
        case .line3:
            line3 = value
        }
        
        // Use existing CloudKit function
        await withCheckedContinuation { continuation in
            self.saveOrDeleteMonthlyNotes(
                existingRecordName: existingRecord?.id,
                existingZoneID: existingRecord?.zoneID,
                month: month,
                year: year,
                line1: line1.isEmpty ? nil : line1,
                line2: line2.isEmpty ? nil : line2,
                line3: line3.isEmpty ? nil : line3
            ) { success, error in
                continuation.resume()
            }
        }
    }
}

// MARK: - Data Models
struct DailyScheduleRecord: Identifiable, Equatable, Hashable {
    let id: String
    let date: Date?
    var line1: String?  // Now mutable for editing
    var line2: String?  // Now mutable for editing
    var line3: String?  // Now mutable for editing
    var line4: String?  // Now mutable for editing - CALL field
    let uuid: UUID?
    let zoneID: CKRecordZone.ID  // Track which zone this record belongs to
    var isModified: Bool = false  // Track if record has unsaved changes
    
    init(from record: CKRecord) {
        self.id = record.recordID.recordName
        self.date = record["CD_date"] as? Date
        
        // Debug: Log raw CloudKit field values during conversion
        let rawLine1 = record["CD_line1"]
        let rawLine2 = record["CD_line2"] 
        let rawLine3 = record["CD_line3"]
        let rawLine4 = record["CD_line4"]
        
        // Debug: Check if we're converting Sept 4 or 5 data
        if let date = record["CD_date"] as? Date {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = TimeZone(identifier: "UTC")  // FIX: Use UTC to match CloudKit
            let dateString = formatter.string(from: date)
            if dateString == "2025-09-04" || dateString == "2025-09-05" {
                debugLog("🔄 CONVERTING \(dateString) UTC (RecordID: \(record.recordID.recordName)):")
                debugLog("   CloudKit CD_date: \(date)")
                debugLog("   Raw CD_line1: \(String(describing: rawLine1)) (type: \(type(of: rawLine1)))")
                debugLog("   Raw CD_line2: \(String(describing: rawLine2)) (type: \(type(of: rawLine2)))")
                debugLog("   Raw CD_line3: \(String(describing: rawLine3)) (type: \(type(of: rawLine3)))")
                debugLog("   Raw CD_line4: \(String(describing: rawLine4)) (type: \(type(of: rawLine4)))")
            }
        }
        
        // Fix: Convert empty CKRecordValues to nil instead of empty strings
        self.line1 = Self.extractStringValue(from: record["CD_line1"])
        self.line2 = Self.extractStringValue(from: record["CD_line2"])
        self.line3 = Self.extractStringValue(from: record["CD_line3"])
        self.line4 = Self.extractStringValue(from: record["CD_line4"])
        self.zoneID = record.recordID.zoneID  // Store the zone ID
        self.isModified = false  // Data from CloudKit is not modified
        
        // Debug: Log converted values
        if let date = record["CD_date"] as? Date {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = TimeZone(identifier: "UTC")  // FIX: Use UTC to match CloudKit
            let dateString = formatter.string(from: date)
            if dateString == "2025-09-04" || dateString == "2025-09-05" {
                debugLog("   Converted \(dateString) UTC (RecordID: \(record.recordID.recordName)):")
                debugLog("     line1: '\(self.line1 ?? "nil")'")
                debugLog("     line2: '\(self.line2 ?? "nil")'")
                debugLog("     line3: '\(self.line3 ?? "nil")'")
                debugLog("     line4: '\(self.line4 ?? "nil")'")
            }
        }
        
        if let uuidString = record["CD_id"] as? String {
            self.uuid = UUID(uuidString: uuidString)
        } else {
            self.uuid = nil
        }
    }
    
    /// Helper function to properly extract string values from CKRecordValue
    /// Converts empty CKRecordValues to nil instead of empty strings
    static func extractStringValue(from recordValue: CKRecordValue?) -> String? {
        guard let recordValue = recordValue else { return nil }
        
        // Cast to string and check if it's meaningful
        if let stringValue = recordValue as? String {
            return stringValue.isEmpty ? nil : stringValue
        }
        
        return nil
    }
    
    /// Remove duplicate records by date, keeping the most complete record
    private func removeDuplicatesByDate(_ records: [DailyScheduleRecord]) -> [DailyScheduleRecord] {
        var bestRecords: [String: DailyScheduleRecord] = [:]
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        for record in records {
            guard let date = record.date else { continue }
            let dateKey = dateFormatter.string(from: date)
            
            if let existing = bestRecords[dateKey] {
                // Choose the better record (more complete data)
                bestRecords[dateKey] = chooseBetterRecord(existing, record)
                debugLog("🔄 DUPLICATE FOUND for \(dateKey): Kept better record")
            } else {
                bestRecords[dateKey] = record
            }
        }
        
        return Array(bestRecords.values).sorted { ($0.date ?? Date()) < ($1.date ?? Date()) }
    }
    
    /// Choose which record is "better" (has more complete data)
    private func chooseBetterRecord(_ record1: DailyScheduleRecord, _ record2: DailyScheduleRecord) -> DailyScheduleRecord {
        let score1 = calculateRecordCompleteness(record1)
        let score2 = calculateRecordCompleteness(record2)
        
        // If scores are equal, prefer the more recently modified record
        if score1 == score2 {
            // Compare modification dates if available (would need to track this)
            return record1 // Default to first record if equal
        }
        
        return score1 > score2 ? record1 : record2
    }
    
    /// Calculate how "complete" a record is (higher score = more data)
    private func calculateRecordCompleteness(_ record: DailyScheduleRecord) -> Int {
        var score = 0
        
        // Add points for non-nil, non-empty fields
        if let line1 = record.line1, !line1.isEmpty { score += 1 }
        if let line2 = record.line2, !line2.isEmpty { score += 1 }
        if let line3 = record.line3, !line3.isEmpty { score += 1 }
        if let line4 = record.line4, !line4.isEmpty { score += 1 }
        
        return score
    }
    
    // Custom initializer for creating new records for editing
    init(date: Date, zoneID: CKRecordZone.ID) {
        self.id = UUID().uuidString
        self.date = date
        self.line1 = ""
        self.line2 = ""
        self.line3 = ""
        self.line4 = ""
        self.uuid = UUID()
        self.zoneID = zoneID
        self.isModified = false  // New empty records are not modified until data is entered
    }
}

// MARK: - Deduplication Helper
private func deduplicateSchedulesByDate(_ schedules: [DailyScheduleRecord]) -> [DailyScheduleRecord] {
    var uniqueSchedules: [String: DailyScheduleRecord] = [:]
    
    for schedule in schedules {
        guard let date = schedule.date else { continue }
        
        // FIX: Use UTC calendar to match CloudKit dates instead of device timezone
        var utcCalendar = Calendar.current
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!
        let dateKey = utcCalendar.startOfDay(for: date).timeIntervalSince1970.description
        
        // Debug: Log date key generation for Sept 4th and 5th
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        let dateString = formatter.string(from: date)
        if dateString == "2025-09-04" || dateString == "2025-09-05" {
            debugLog("🔑 DEDUP KEY for \(dateString): Record \(schedule.id) → dateKey \(dateKey)")
        }
        
        if let existing = uniqueSchedules[dateKey] {
            // Keep the record with more data or the most recent one
            let newCompleteness = calculateCompleteness(schedule)
            let existingCompleteness = calculateCompleteness(existing)
            
            if newCompleteness > existingCompleteness {
                debugLog("🔄 Replacing record for \(dateKey): new has \(newCompleteness) fields vs \(existingCompleteness)")
                uniqueSchedules[dateKey] = schedule
            } else if newCompleteness == existingCompleteness {
                // Same completeness - keep the one with more recent modification
                let newTime = schedule.isModified ? Date().timeIntervalSince1970 : 0
                let existingTime = existing.isModified ? Date().timeIntervalSince1970 : 0
                
                if newTime > existingTime {
                    debugLog("🔄 Replacing record for \(dateKey): newer modification time")
                    uniqueSchedules[dateKey] = schedule
                }
            }
        } else {
            uniqueSchedules[dateKey] = schedule
        }
    }
    
    return Array(uniqueSchedules.values).sorted { schedule1, schedule2 in
        guard let date1 = schedule1.date, let date2 = schedule2.date else { return false }
        return date1 < date2
    }
}

private func calculateCompleteness(_ schedule: DailyScheduleRecord) -> Int {
    var count = 0
    if !(schedule.line1?.isEmpty ?? true) { count += 1 }
    if !(schedule.line2?.isEmpty ?? true) { count += 1 }
    if !(schedule.line3?.isEmpty ?? true) { count += 1 }
    if !(schedule.line4?.isEmpty ?? true) { count += 1 }
    return count
}

struct MonthlyNotesRecord: Identifiable, Equatable, Hashable {
    let id: String
    let month: Int
    let year: Int
    var line1: String?  // Now mutable for editing
    var line2: String?  // Now mutable for editing
    var line3: String?  // Now mutable for editing
    let uuid: UUID?
    let zoneID: CKRecordZone.ID  // Track which zone this record belongs to
    var isModified: Bool = false  // Track if record has unsaved changes
    
    init(from record: CKRecord) {
        self.id = record.recordID.recordName
        self.month = (record["CD_month"] as? Int) ?? 0
        self.year = (record["CD_year"] as? Int) ?? 0
        // Fix: Convert empty CKRecordValues to nil instead of empty strings  
        self.line1 = DailyScheduleRecord.extractStringValue(from: record["CD_line1"])
        self.line2 = DailyScheduleRecord.extractStringValue(from: record["CD_line2"])
        self.line3 = DailyScheduleRecord.extractStringValue(from: record["CD_line3"])
        self.zoneID = record.recordID.zoneID  // Store the zone ID
        self.isModified = false  // Data from CloudKit is not modified
        if let uuidString = record["CD_id"] as? String {
            self.uuid = UUID(uuidString: uuidString)
        } else {
            self.uuid = nil
        }
    }
    
    /// Helper function to properly extract string values from CKRecordValue
    /// Converts empty CKRecordValues to nil instead of empty strings
    static func extractStringValue(from recordValue: CKRecordValue?) -> String? {
        guard let recordValue = recordValue else { return nil }
        
        // Cast to string and check if it's meaningful
        if let stringValue = recordValue as? String {
            return stringValue.isEmpty ? nil : stringValue
        }
        
        return nil
    }
    
    // Custom initializer for creating new records for editing
    init(month: Int, year: Int, zoneID: CKRecordZone.ID) {
        self.id = UUID().uuidString
        self.month = month
        self.year = year
        self.line1 = ""
        self.line2 = ""
        self.line3 = ""
        self.uuid = UUID()
        self.zoneID = zoneID
        self.isModified = false  // New empty records are not modified until data is entered
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
