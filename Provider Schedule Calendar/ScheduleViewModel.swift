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
    @Published var isCloudKitAvailable = false
    @Published var hasChanges = false
    
    // MARK: - Private Properties
    private let cloudKitManager = SimpleCloudKitManager()
    private var pendingChanges: Set<String> = []
    
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
    
    // MARK: - Initialization
    init() {
        checkCloudKitStatus()
    }
    
    // MARK: - Public Methods
    func loadData() {
        isLoading = true
        
        Task {
            do {
                // Load both schedules and monthly notes
                let loadedSchedules = try await cloudKitManager.fetchAllSchedules()
                let loadedNotes = try await cloudKitManager.fetchAllMonthlyNotes()
                
                await MainActor.run {
                    self.schedules = loadedSchedules
                    self.monthlyNotes = loadedNotes
                    self.isLoading = false
                    self.hasChanges = false
                    self.pendingChanges.removeAll()
                }
                
                redesignLog("✅ Loaded \(loadedSchedules.count) schedules and \(loadedNotes.count) monthly notes")
                
            } catch {
                await MainActor.run {
                    self.isLoading = false
                }
                redesignLog("❌ Failed to load data: \(error)")
            }
        }
    }
    
    func updateSchedule(date: Date, field: ScheduleField, value: String) {
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
        hasChanges = !pendingChanges.isEmpty
        
        redesignLog("📝 Updated \(field) for \(dateKey) to: '\(value)'")
    }
    
    func saveChanges() async -> Bool {
        guard !pendingChanges.isEmpty else {
            redesignLog("💾 No changes to save")
            return true
        }
        
        isLoading = true
        
        do {
            // Save all pending changes
            var successCount = 0
            
            for dateKey in pendingChanges {
                if let schedule = schedules[dateKey] {
                    // Save schedule
                    try await cloudKitManager.saveSchedule(schedule)
                    successCount += 1
                } else {
                    // Delete schedule (all fields empty)
                    try await cloudKitManager.deleteSchedule(dateKey: dateKey)
                    successCount += 1
                }
            }
            
            await MainActor.run {
                self.pendingChanges.removeAll()
                self.hasChanges = false
                self.isLoading = false
            }
            
            redesignLog("✅ Successfully saved \(successCount) changes")
            return true
            
        } catch {
            await MainActor.run {
                self.isLoading = false
            }
            
            // Detailed error logging for CloudKit issues
            if let ckError = error as? CKError {
                redesignLog("❌ CloudKit Save Error: \(ckError.localizedDescription)")
                redesignLog("❌ CloudKit Error Code: \(ckError.code.rawValue)")
                redesignLog("❌ CloudKit Error Domain: \(ckError.errorUserInfo)")
            } else {
                redesignLog("❌ General Save Error: \(error.localizedDescription)")
            }
            
            return false
        }
    }
    
    // MARK: - Monthly Notes Methods (2 Lines)
    func updateMonthlyNotesLine1(for date: Date, line1: String) {
        let monthKey = monthKey(for: date)
        let calendar = Calendar.current
        let month = calendar.component(.month, from: date)
        let year = calendar.component(.year, from: date)
        
        // Get existing note or create new one
        var note = monthlyNotes[monthKey] ?? MonthlyNote(month: month, year: year)
        note.line1 = line1.isEmpty ? nil : line1
        
        // Remove note if both lines are empty
        if (note.line1?.isEmpty ?? true) && (note.line2?.isEmpty ?? true) {
            monthlyNotes.removeValue(forKey: monthKey)
        } else {
            monthlyNotes[monthKey] = note
        }
        hasChanges = true
    }
    
    func updateMonthlyNotesLine2(for date: Date, line2: String) {
        let monthKey = monthKey(for: date)
        let calendar = Calendar.current
        let month = calendar.component(.month, from: date)
        let year = calendar.component(.year, from: date)
        
        // Get existing note or create new one
        var note = monthlyNotes[monthKey] ?? MonthlyNote(month: month, year: year)
        note.line2 = line2.isEmpty ? nil : line2
        
        // Remove note if both lines are empty
        if (note.line1?.isEmpty ?? true) && (note.line2?.isEmpty ?? true) {
            monthlyNotes.removeValue(forKey: monthKey)
        } else {
            monthlyNotes[monthKey] = note
        }
        hasChanges = true
    }
    
    private func monthKey(for date: Date) -> String {
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
    
    private func dateKey(for date: Date) -> String {
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

struct MonthlyNote: Identifiable, Codable {
    let id: String
    let month: Int
    let year: Int
    var line1: String?
    var line2: String?
    var line3: String?
    
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

