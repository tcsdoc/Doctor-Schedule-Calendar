import Foundation
import SwiftUI
import CloudKit
import Network

// MARK: - Modern MVVM ViewModel for PSC
@MainActor
class ScheduleViewModel: ObservableObject {
    
    // MARK: - Published Properties
    @Published var schedules: [String: ScheduleRecord] = [:]
    @Published var monthlyNotes: [String: MonthlyNote] = [:]
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var isSyncingFromCloud = false
    @Published var isCloudKitAvailable = false
    @Published var hasChanges = false
    /// True when the device has no network path to the Cloud.
    @Published var isOffline = false
    /// Local snapshot time shown only while `isOffline` is true.
    @Published var offlineCacheDate: Date?
    
    // MARK: - Private Properties
    private let cloudKitManager = SimpleCloudKitManager()
    private var pendingChanges: Set<String> = []
    private var pendingNoteChanges: Set<String> = []
    private var isInitializing = true
    private var networkMonitor: NWPathMonitor?
    private var cloudSyncInFlight = false
    private var focusedEditors: Set<String> = []
    private var lastEditAt: Date = .distantPast
    
    // MARK: - Computed Properties
    var availableMonths: [Date] {
        // Generate 12 months starting from current month
        let calendar = Calendar.current
        let now = Date()
        guard let startOfCurrentMonth = calendar.dateInterval(of: .month, for: now)?.start else {
            return []
        }
        
        var months: [Date] = []
        for i in 0..<12 {
            if let month = calendar.date(byAdding: .month, value: i, to: startOfCurrentMonth) {
                months.append(month)
            }
        }
        return months
    }
    
    // MARK: - Initialization (Load CloudKit once)
    init() {
        startNetworkMonitoring()
        checkCloudKitStatus()
        loadInitialData()
    }
    
    // MARK: - Initial Data Load
    private func loadInitialData() {
        if let cache = ScheduleLocalCache.load() {
            schedules = cache.schedules
            monthlyNotes = cache.monthlyNotes
            pendingChanges = Set(cache.pendingScheduleKeys)
            pendingNoteChanges = Set(cache.pendingNoteKeys)
            hasChanges = !pendingChanges.isEmpty || !pendingNoteChanges.isEmpty
            isLoading = false
            isInitializing = false
            isSyncingFromCloud = true
        } else {
            isLoading = true
        }

        Task {
            do {
                let loadedSchedules = try await cloudKitManager.fetchAllSchedules()
                let loadedNotes = try await cloudKitManager.fetchAllMonthlyNotes()

                await MainActor.run {
                    self.mergeCloudKitData(loadedSchedules: loadedSchedules, loadedNotes: loadedNotes)
                    self.isInitializing = false
                    self.isLoading = false
                    self.isSyncingFromCloud = false
                }
            } catch {
                redesignLog("❌ CloudKit load failed: \(error)")
                await MainActor.run {
                    self.markOffline()
                    self.isLoading = false
                    self.isSyncingFromCloud = false
                    self.isInitializing = false
                    if self.schedules.isEmpty && self.monthlyNotes.isEmpty {
                        self.offlineCacheDate = nil
                    }
                }
            }
        }
    }

    /// Refresh from Cloud when network returns (NWPathMonitor only).
    private func syncFromCloudIfNeeded() async {
        guard !isLoading, !cloudSyncInFlight, !isInitializing else { return }
        guard isNetworkReachable() else {
            markOffline()
            return
        }

        cloudSyncInFlight = true

        var deferralIterations = 0
        while isEditSessionActive && deferralIterations < 30 {
            try? await Task.sleep(for: .seconds(10))
            deferralIterations += 1
        }

        guard isNetworkReachable() else {
            markOffline()
            cloudSyncInFlight = false
            return
        }

        isSyncingFromCloud = true

        do {
            let loadedSchedules = try await cloudKitManager.fetchAllSchedules()
            let loadedNotes = try await cloudKitManager.fetchAllMonthlyNotes()
            mergeCloudKitData(loadedSchedules: loadedSchedules, loadedNotes: loadedNotes)
            isOffline = false
            offlineCacheDate = nil
        } catch {
            redesignLog("❌ Cloud sync failed: \(error)")
            markOffline()
        }

        isSyncingFromCloud = false
        cloudSyncInFlight = false
    }

    private func mergeCloudKitData(
        loadedSchedules: [String: ScheduleRecord],
        loadedNotes: [String: MonthlyNote]
    ) {
        let localSchedules = schedules
        let localNotes = monthlyNotes
        let pendingSchedules = pendingChanges
        let pendingNotes = pendingNoteChanges

        schedules = loadedSchedules
        monthlyNotes = loadedNotes

        for key in pendingSchedules {
            if let local = localSchedules[key] {
                schedules[key] = local
            } else {
                schedules.removeValue(forKey: key)
            }
        }
        for key in pendingNotes {
            if let local = localNotes[key] {
                monthlyNotes[key] = local
            } else {
                monthlyNotes.removeValue(forKey: key)
            }
        }

        pendingChanges = pendingSchedules
        pendingNoteChanges = pendingNotes
        hasChanges = !pendingChanges.isEmpty || !pendingNoteChanges.isEmpty
        isOffline = false
        offlineCacheDate = nil
        persistLocalCache()
    }

    private func markOffline() {
        isOffline = true
        offlineCacheDate = ScheduleLocalCache.load()?.savedAt ?? offlineCacheDate ?? Date()
    }

    private func startNetworkMonitoring() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.handleNetworkPathUpdate(isConnected: path.status == .satisfied)
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.gulfcoast.psc.network"))
        networkMonitor = monitor
    }

    private func handleNetworkPathUpdate(isConnected: Bool) {
        if isConnected {
            isOffline = false
            offlineCacheDate = nil
            checkCloudKitStatus()
            Task { await syncFromCloudIfNeeded() }
        } else {
            markOffline()
        }
    }

    private func isNetworkReachable() -> Bool {
        networkMonitor?.currentPath.status == .satisfied
    }

    private var isEditSessionActive: Bool {
        !focusedEditors.isEmpty || Date().timeIntervalSince(lastEditAt) < 30
    }

    func editorFocusChanged(_ id: String, isFocused: Bool) {
        if isFocused {
            focusedEditors.insert(id)
        } else {
            focusedEditors.remove(id)
        }
    }

    private func persistLocalCache() {
        ScheduleLocalCache.save(
            schedules: schedules,
            monthlyNotes: monthlyNotes,
            pendingScheduleKeys: pendingChanges,
            pendingNoteKeys: pendingNoteChanges
        )
    }
    
    
    func updateSchedule(date: Date, field: ScheduleField, value: String) {
        guard !isInitializing else { return }
        lastEditAt = Date()
        
        let dateKey = dateKey(for: date)
        
        // Get existing schedule or create new one
        var schedule = schedules[dateKey] ?? ScheduleRecord(date: date)
        
        // Update the specific field
        switch field {
        case .os:
            schedule.os = value.isEmpty ? nil : value
        case .cl:
            schedule.cl = value.isEmpty ? nil : value
        case .off:
            schedule.off = value.isEmpty ? nil : value
        case .call:
            schedule.call = value.isEmpty ? nil : value
        }
        
        // Update local data
        if schedule.isEmpty {
            schedules.removeValue(forKey: dateKey)
        } else {
            schedules[dateKey] = schedule
        }
        
        // Track change
        pendingChanges.insert(dateKey)
        hasChanges = !pendingChanges.isEmpty || !pendingNoteChanges.isEmpty
        persistLocalCache()
    }
    
    func saveChanges() async -> (cloudSuccess: Bool, savedCount: Int, totalCount: Int, savedLocallyOnly: Bool) {
        let totalChanges = pendingChanges.count + pendingNoteChanges.count
        guard totalChanges > 0 else {
            return (true, 0, 0, false)
        }
        
        isSaving = true
        
        // Track individual successes and failures
        var successCount = 0
        var failures: [String] = []
        var savedScheduleKeys: Set<String> = []
        var savedNoteKeys: Set<String> = []
        
        // Save only changed schedules (individual error handling)
        for dateKey in pendingChanges {
            do {
                if let schedule = schedules[dateKey] {
                    try await cloudKitManager.saveSchedule(schedule)
                } else {
                    try await cloudKitManager.deleteSchedule(dateKey: dateKey)
                }
                savedScheduleKeys.insert(dateKey)
                successCount += 1
            } catch {
                failures.append("Schedule \(dateKey)")
                redesignLog("❌ Failed to save schedule \(dateKey): \(error)")
            }
        }
        
        // Save changed monthly notes (individual error handling)
        for monthKey in pendingNoteChanges {
            do {
                if let note = monthlyNotes[monthKey] {
                    try await cloudKitManager.saveMonthlyNote(note)
                } else {
                    try await cloudKitManager.deleteMonthlyNote(monthKey: monthKey)
                }
                savedNoteKeys.insert(monthKey)
                successCount += 1
            } catch {
                failures.append("Monthly note \(monthKey)")
                redesignLog("❌ Failed to save monthly note \(monthKey): \(error)")
            }
        }
        
        await MainActor.run {
            // Only clear pending changes for successful saves; keep failures for retry
            self.pendingChanges.subtract(savedScheduleKeys)
            self.pendingNoteChanges.subtract(savedNoteKeys)
            self.hasChanges = !self.pendingChanges.isEmpty || !self.pendingNoteChanges.isEmpty
            self.isSaving = false
        }
        
        let cloudSuccess = failures.isEmpty
        let savedLocallyOnly = !cloudSuccess && successCount == 0

        if cloudSuccess {
            isOffline = false
            offlineCacheDate = nil
            persistLocalCache()
            let savedAt = Date()
            CalendarPDFGenerator.writeMasterPDFToDocuments(
                schedules: schedules,
                monthlyNotes: monthlyNotes,
                months: availableMonths,
                updatedAt: savedAt
            )
        } else {
            redesignLog("⚠️ Partial save: \(successCount) success, \(failures.count) failures")
            redesignLog("❌ Failed items: \(failures.joined(separator: ", "))")
            persistLocalCache()
            if savedLocallyOnly {
                markOffline()
                CalendarPDFGenerator.writeMasterPDFToDocuments(
                    schedules: schedules,
                    monthlyNotes: monthlyNotes,
                    months: availableMonths,
                    updatedAt: Date()
                )
            }
        }

        return (cloudSuccess, successCount, totalChanges, savedLocallyOnly)
    }
    
    // MARK: - Monthly Notes Methods (2 Lines)
    func updateMonthlyNotesLine1(for date: Date, line1: String) {
        guard !isInitializing else { return }
        lastEditAt = Date()
        
        let monthKey = monthKey(for: date)
        let calendar = Calendar.current
        let month = calendar.component(.month, from: date)
        let year = calendar.component(.year, from: date)
        
        // Get existing note or create new one
        var note = monthlyNotes[monthKey] ?? MonthlyNote(month: month, year: year)
        let oldLine1 = note.line1
        note.line1 = line1.isEmpty ? nil : line1
        
        // Only mark as changed if value actually changed
        let valueChanged = oldLine1 != note.line1
        
        // Remove note if both lines are empty
        if (note.line1?.isEmpty ?? true) && (note.line2?.isEmpty ?? true) {
            monthlyNotes.removeValue(forKey: monthKey)
        } else {
            monthlyNotes[monthKey] = note
        }
        
        // Track change
        if valueChanged {
            pendingNoteChanges.insert(monthKey)
            hasChanges = !pendingChanges.isEmpty || !pendingNoteChanges.isEmpty
            persistLocalCache()
        }
    }
    
    func updateMonthlyNotesLine2(for date: Date, line2: String) {
        guard !isInitializing else { return }
        lastEditAt = Date()
        
        let monthKey = monthKey(for: date)
        let calendar = Calendar.current
        let month = calendar.component(.month, from: date)
        let year = calendar.component(.year, from: date)
        
        // Get existing note or create new one
        var note = monthlyNotes[monthKey] ?? MonthlyNote(month: month, year: year)
        let oldLine2 = note.line2
        note.line2 = line2.isEmpty ? nil : line2
        
        // Only mark as changed if value actually changed
        let valueChanged = oldLine2 != note.line2
        
        // Remove note if both lines are empty
        if (note.line1?.isEmpty ?? true) && (note.line2?.isEmpty ?? true) {
            monthlyNotes.removeValue(forKey: monthKey)
        } else {
            monthlyNotes[monthKey] = note
        }
        
        // Track change
        if valueChanged {
            pendingNoteChanges.insert(monthKey)
            hasChanges = !pendingChanges.isEmpty || !pendingNoteChanges.isEmpty
            persistLocalCache()
        }
    }
    
    func monthKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }
    
    // MARK: - Private Methods
    private func checkCloudKitStatus() {
        Task {
            let available = await cloudKitManager.checkCloudKitAvailability()
            await MainActor.run {
                self.isCloudKitAvailable = available
            }
        }
    }
    
    func dateKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }
    
    // MARK: - CloudKit Sharing
    func createShare() async throws -> CKShare {
        return try await cloudKitManager.getOrCreateZoneShare()
    }
    
    func getExistingShare() async throws -> CKShare? {
        return try await cloudKitManager.fetchExistingZoneShare()
    }
    
    // MARK: - Duplicate Detection & Cleanup
    typealias DuplicateDetectionResult = SimpleCloudKitManager.DuplicateDetectionResult
    typealias DuplicateGroup = SimpleCloudKitManager.DuplicateGroup
    
    func checkForDuplicates() async throws -> DuplicateDetectionResult {
        return try await cloudKitManager.detectDuplicates()
    }
    
    func cleanupDuplicates(_ result: DuplicateDetectionResult) async throws -> String {
        return try await cloudKitManager.cleanupDuplicates(result)
    }
}

// MARK: - Data Models
struct ScheduleRecord: Identifiable, Codable, Equatable {
    let id: String
    let date: Date
    var os: String?
    var cl: String?
    var off: String?
    var call: String?
    
    init(date: Date, os: String? = nil, cl: String? = nil, off: String? = nil, call: String? = nil) {
        self.date = date
        self.os = os
        self.cl = cl
        self.off = off
        self.call = call
        
        // Generate deterministic ID
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        self.id = "schedule_\(formatter.string(from: date))"
    }
    
    var isEmpty: Bool {
        return (os?.isEmpty ?? true) && 
               (cl?.isEmpty ?? true) && 
               (off?.isEmpty ?? true) && 
               (call?.isEmpty ?? true)
    }
}

struct MonthlyNote: Identifiable, Codable, CustomStringConvertible {
    let id: String
    let month: Int
    let year: Int
    var line1: String?
    var line2: String?
    /// Not shown in UI (grid height); still read/written for CloudKit schema compatibility.
    var line3: String?
    
    var description: String {
        return "MonthlyNote(id: \(id), month: \(month), year: \(year), line1: \(line1 ?? "nil"), line2: \(line2 ?? "nil"), line3: \(line3 ?? "nil"))"
    }
    
    init(month: Int, year: Int, line1: String? = nil, line2: String? = nil, line3: String? = nil) {
        self.month = month
        self.year = year
        self.line1 = line1
        self.line2 = line2
        self.line3 = line3
        self.id = "notes_\(year)-\(String(format: "%02d", month))"
    }
    
    var isEmpty: Bool {
        return (line1?.isEmpty ?? true) && 
               (line2?.isEmpty ?? true) && 
               (line3?.isEmpty ?? true)
    }
}

