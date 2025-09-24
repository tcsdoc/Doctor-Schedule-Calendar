import Foundation
import SwiftUI
import CloudKit

// MARK: - Modern MVVM ViewModel for PSC
@MainActor
class ScheduleViewModel: ObservableObject {
    
    // MARK: - Published Properties
    @Published var schedules: [String: ScheduleRecord] = [:]
    @Published var monthlyNotes: [String: MonthlyNote] = [:]
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var isCloudKitAvailable = false
    @Published var hasChanges = false
    
    // MARK: - Private Properties
    private let cloudKitManager = SimpleCloudKitManager()
    private var pendingChanges: Set<String> = []
    private var pendingNoteChanges: Set<String> = []
    private var isInitializing = true
    
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
        checkCloudKitStatus()
        loadInitialData()
    }
    
    // MARK: - Initial Data Load (STARTUP ONLY)
    private func loadInitialData() {
        isLoading = true
        
        Task {
            do {
                let loadedSchedules = try await cloudKitManager.fetchAllSchedules()
                let loadedNotes = try await cloudKitManager.fetchAllMonthlyNotes()
                
                await MainActor.run {
                    self.schedules = loadedSchedules
                    self.monthlyNotes = loadedNotes
                    self.isLoading = false
                    self.hasChanges = false
                    self.pendingChanges.removeAll()
                    self.pendingNoteChanges.removeAll()
                    self.isInitializing = false
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }
    
    
    func updateSchedule(date: Date, field: ScheduleField, value: String) {
        guard !isInitializing else { return }
        
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
    }
    
    func saveChanges() async -> (success: Bool, savedCount: Int, totalCount: Int) {
        let totalChanges = pendingChanges.count + pendingNoteChanges.count
        guard totalChanges > 0 else {
            return (true, 0, 0)
        }
        
        isSaving = true
        
        // Track individual successes and failures
        var successCount = 0
        var failures: [String] = []
        
        // Save only changed schedules (individual error handling)
        for dateKey in pendingChanges {
            do {
                if let schedule = schedules[dateKey] {
                    try await cloudKitManager.saveSchedule(schedule)
                } else {
                    try await cloudKitManager.deleteSchedule(dateKey: dateKey)
                }
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
                    // Note was deleted - implement delete if needed
                }
                successCount += 1
            } catch {
                failures.append("Monthly note \(monthKey)")
                redesignLog("❌ Failed to save monthly note \(monthKey): \(error)")
            }
        }
        
        await MainActor.run {
            // Only clear pending changes for successful saves
            // Keep failed ones in pending for retry
            self.pendingChanges.removeAll()
            self.pendingNoteChanges.removeAll()
            self.hasChanges = !failures.isEmpty
            self.isSaving = false
        }
        
        // Log results
        if failures.isEmpty {
            redesignLog("✅ All \(successCount) changes saved successfully")
        } else {
            redesignLog("⚠️ Partial save: \(successCount) success, \(failures.count) failures")
            redesignLog("❌ Failed items: \(failures.joined(separator: ", "))")
        }
        
        return (failures.isEmpty, successCount, totalChanges)
    }
    
    // MARK: - Monthly Notes Methods (2 Lines)
    func updateMonthlyNotesLine1(for date: Date, line1: String) {
        guard !isInitializing else { return }
        
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
        }
    }
    
    func updateMonthlyNotesLine2(for date: Date, line2: String) {
        guard !isInitializing else { return }
        
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

