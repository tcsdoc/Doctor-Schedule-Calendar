//
//  ContentView.swift
//  Doctor Schedule Calendar
//
//  Created by mark on 7/5/25.
//  Converted from Core Data to CloudKit Direct Implementation
//

import SwiftUI
import CloudKit

// MARK: - Next Day Navigation
extension Notification.Name {
    static let moveToNextDay = Notification.Name("moveToNextDay")
}

struct NextDayFocusRequest {
    let fromDate: Date
    let targetDate: Date
}

struct ContentView: View {
    @EnvironmentObject private var cloudKitManager: CloudKitManager
    @State private var currentDate = Date()
    @State private var showingPrintView = false
    
    var body: some View {
        NavigationView {
            VStack {
                headerSection
                
                // Show CloudKit status messages
                if let errorMessage = cloudKitManager.errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding(.horizontal)
                        .multilineTextAlignment(.center)
                }
                
                ScrollView {
                    LazyVStack(spacing: 20) {
                        ForEach(monthsToShow, id: \.self) { month in
                            MonthView(month: month)
                                .environmentObject(cloudKitManager)
                        }
                    }
                    .padding()
                }
            }
            .onAppear {
                cloudKitManager.fetchAllData()
            }
            .refreshable {
                cloudKitManager.forceRefreshAllData()
            }
        }
        .navigationViewStyle(.stack)
        .sheet(isPresented: $showingPrintView) {
            PrintView()
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 10) {
            Text("PROVIDER SCHEDULE")
                .font(.title)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity)
            
            HStack {
                Spacer()
                
                HStack(spacing: 15) {
                    Button(action: {
                        showingPrintView = true
                    }) {
                        Image(systemName: "printer")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }
                    
                    Text("Monthly Notes")
                        .font(.headline)
                    
                    Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown").\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
        }
        .padding(.top)
    }
    
    private var monthsToShow: [Date] {
        let calendar = Calendar.current
        var months: [Date] = []
        
        for i in 0..<12 {
            if let month = calendar.date(byAdding: .month, value: i, to: currentDate) {
                months.append(month)
            }
        }
        
        return months
    }
}

// MARK: - MonthView
struct MonthView: View {
    let month: Date
    @EnvironmentObject private var cloudKitManager: CloudKitManager
    
    private let calendar = Calendar.current
    private let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            monthHeader
            notesSection
            daysOfWeekHeader
            calendarGrid
            LegendView()
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(10)
    }
    
    private var monthHeader: some View {
        Text(monthFormatter.string(from: month))
            .font(.title2)
            .fontWeight(.bold)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.bottom, 5)
    }
    
    private var notesSection: some View {
        MonthlyNotesView(month: month)
            .environmentObject(cloudKitManager)
    }
    
    private var daysOfWeekHeader: some View {
        HStack {
            ForEach(Calendar.current.shortWeekdaySymbols, id: \.self) { day in
                Text(day)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 10)
    }
    
    private var calendarGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 7), spacing: 1) {
            ForEach(daysInMonth, id: \.self) { date in
                if calendar.isDate(date, equalTo: month, toGranularity: .month) {
                    DayCell(date: date)
                        .environmentObject(cloudKitManager)
                } else {
                    Rectangle()
                        .fill(Color.clear)
                        .frame(minHeight: 100)
                }
            }
        }
    }
    
    private var daysInMonth: [Date] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: month) else {
            return []
        }
        
        let startOfMonth = monthInterval.start
        guard let firstWeekday = calendar.dateInterval(of: .weekOfYear, for: startOfMonth)?.start else {
            return []
        }
        
        var days: [Date] = []
        var currentDate = firstWeekday
        
        // Generate 6 weeks worth of dates
        for _ in 0..<42 {
            days.append(currentDate)
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }
        
        return days
    }
}

// MARK: - DayCell
struct DayCell: View {
    let date: Date
    @EnvironmentObject private var cloudKitManager: CloudKitManager
    
    @State private var line1: String = ""
    @State private var line2: String = ""
    @State private var line3: String = ""
    @State private var existingRecord: DailyScheduleRecord?
    @State private var isEditing = false
    @State private var saveTimer: Timer?
    @State private var isSaving = false
    @State private var hasUnsavedChanges = false
    @State private var lastSyncVersion: Date?
    @FocusState private var focusedField: DayField?
    
    // Track local state to prevent CloudKit overwrites
    @State private var localDataProtected = false
    @State private var userInitiatedChange = false
    
    private let calendar = Calendar.current
    
    enum DayField: CaseIterable {
        case line1, line2, line3
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            dayNumber
            scheduleFields
        }
        .frame(maxWidth: .infinity, minHeight: 100)
        .background(background)
        .onAppear {
            print("📱 DayCell appeared for \(dayString) - loading schedule")
            loadSchedule()
        }
        .onChange(of: cloudKitManager.dailySchedules) { _, newSchedules in
            // Enhanced protection against CloudKit overwrites during editing
            handleCloudKitDataChange(newSchedules)
        }
        .onChange(of: existingRecord) { oldRecord, newRecord in
            // Only update if not actively editing and no unsaved changes
            if !isEditing && !hasUnsavedChanges && !localDataProtected {
                print("📋 Record changed for \(dayString) - updating from record")
                updateScheduleFromRecord()
            } else {
                print("🛡️ Skipping record update for \(dayString) - protected (editing: \(isEditing), unsaved: \(hasUnsavedChanges), protected: \(localDataProtected))")
            }
        }
        .onChange(of: focusedField) { oldField, newField in
            handleFocusChange(from: oldField, to: newField)
        }
        .onChange(of: isEditing) { _, newValue in
            // Save when editing state changes (keyboard dismiss, app backgrounding, etc.)
            if !newValue && hasUnsavedChanges {
                print("🎯 Editing ended for \(dayString) with unsaved changes - triggering save")
                saveSchedule()
            }
        }
        .onDisappear {
            // Clean up and save any pending changes
            print("📱 DayCell disappeared for \(dayString) - cleaning up")
            if hasUnsavedChanges {
                performSave()
            }
            cleanupTimersAndState()
        }
        .background(
            // Hidden color to track when cell becomes visible again
            Color.clear.onAppear {
                // Reset protection when cell reappears
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if !isEditing {
                        localDataProtected = false
                    }
                }
            }
        )
        // Listen for next day navigation requests
        .onReceive(NotificationCenter.default.publisher(for: .moveToNextDay)) { notification in
            if let request = notification.object as? NextDayFocusRequest {
                handleNextDayFocusRequest(request)
            }
        }
    }
    
    private var dayString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return formatter.string(from: date)
    }
    
    private var dayNumber: some View {
        Text("\(calendar.component(.day, from: date))")
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.primary)
            .padding(.bottom, 2)
    }
    
    private var scheduleFields: some View {
        VStack(spacing: 4) {
            scheduleTextField(prefix: "OS", text: $line1, color: .blue, field: .line1) {
                moveToNextField()
            }
            scheduleTextField(prefix: "CL", text: $line2, color: .green, field: .line2) {
                moveToNextField()
            }
            scheduleTextField(prefix: "OFF", text: $line3, color: .orange, field: .line3, submitLabel: .done) {
                finalizeEditing()
            }
        }
    }
    
    private func scheduleTextField(prefix: String, text: Binding<String>, color: Color, field: DayField, submitLabel: SubmitLabel = .next, onSubmit: @escaping () -> Void) -> some View {
        HStack {
            Text(prefix)
                .font(.caption)
                .frame(width: 25)
            TextField("", text: text)
                .font(.system(size: 14))
                .frame(height: 32)
                .padding(6)
                .background(color.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(color.opacity(0.6), lineWidth: 1.5)
                )
                .focused($focusedField, equals: field)
                .submitLabel(submitLabel)
                .textInputAutocapitalization(.characters)  // Force all uppercase
                .disableAutocorrection(true)  // Disable autocorrect for cleaner input
                .onSubmit {
                    onSubmit()
                }
                .onChange(of: text.wrappedValue) { oldValue, newValue in
                    handleTextChange(field: field, oldValue: oldValue, newValue: newValue, binding: text)
                }
        }
    }
    
    private var background: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
            )
    }
    
    // MARK: - Enhanced Data Management Methods
    
    private func handleTextChange(field: DayField, oldValue: String, newValue: String, binding: Binding<String>) {
        // Limit to 16 characters
        if newValue.count > 16 {
            binding.wrappedValue = String(newValue.prefix(16))
            return
        }
        
        // Track that this is a user-initiated change
        userInitiatedChange = true
        isEditing = true
        hasUnsavedChanges = true
        localDataProtected = true
        
        print("✏️ User editing \(dayString) field \(field) - setting protection flags")
        print("📝 Field \(field) changed from '\(oldValue)' to '\(newValue)'")
    }
    
    private func handleFocusChange(from oldField: DayField?, to newField: DayField?) {
        if oldField != nil && newField != oldField {
            print("🎯 Focus changed for \(dayString) from \(String(describing: oldField)) to \(String(describing: newField))")
            
            // If moving between fields with unsaved changes, save immediately
            if hasUnsavedChanges && !isSaving {
                print("💾 Focus change with unsaved changes - triggering immediate save")
                saveSchedule()
            }
        }
    }
    
    private func handleCloudKitDataChange(_ newSchedules: [DailyScheduleRecord]) {
        // Only update from CloudKit if we're not actively protecting local data
        if localDataProtected || isEditing || hasUnsavedChanges || isSaving {
            print("🛡️ CloudKit data changed for \(dayString) - local data protected")
            print("🔍 Protection reasons: protected=\(localDataProtected), editing=\(isEditing), unsaved=\(hasUnsavedChanges), saving=\(isSaving)")
            return
        }
        
        // Find the record for this date
        let dayStart = calendar.startOfDay(for: date)
        let updatedRecord = newSchedules.first { record in
            if let recordDate = record.date {
                return calendar.isDate(recordDate, inSameDayAs: dayStart)
            }
            return false
        }
        
        // Only update if the record actually changed
        if let newRecord = updatedRecord, newRecord.id != existingRecord?.id {
            print("📊 CloudKit data updated for \(dayString) - applying changes")
            existingRecord = newRecord
        } else if updatedRecord == nil && existingRecord != nil {
            print("🗑️ CloudKit record deleted for \(dayString) - clearing local data")
            existingRecord = nil
        }
    }
    
    private func moveToNextField() {
        switch focusedField {
        case .line1:
            focusedField = .line2
        case .line2:
            focusedField = .line3
        case .line3:
            finalizeEditing()
        case .none:
            break
        }
    }
    
    private func finalizeEditing() {
        print("🏁 Finalizing editing for \(dayString)")
        
        // Force immediate save if there are unsaved changes
        if hasUnsavedChanges && !isSaving {
            performSave()
        }
        
        // For better data entry workflow, try to move to next day's first field
        // If that fails, keep focus on current field to prevent cursor disappearing
        moveToNextDayFirstField()
        
        isEditing = false
        
        // Delay clearing protection to allow save to complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            localDataProtected = false
            print("🔓 Cleared local data protection for \(dayString)")
        }
    }
    
    private func moveToNextDayFirstField() {
        // Calculate the next day
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: date) else {
            // Fallback: stay on current day's first field
            focusedField = .line1
            print("🔄 Could not calculate next day - staying on current day's OS field")
            return
        }
        
        // Clear current focus to allow next day to take over
        focusedField = nil
        
        // Send notification to request focus on next day's first field
        let request = NextDayFocusRequest(fromDate: date, targetDate: nextDay)
        NotificationCenter.default.post(name: .moveToNextDay, object: request)
        
        print("🎯 Requesting focus move from \(dayString) to next day \(formatDate(nextDay))")
        
        // Note: Removed fallback logic that was causing focus to jump back
        // If next day navigation fails, user can manually click to regain focus
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return formatter.string(from: date)
    }
    
    private func loadSchedule() {
        let dayStart = calendar.startOfDay(for: date)
        existingRecord = cloudKitManager.dailySchedules.first { record in
            if let recordDate = record.date {
                return calendar.isDate(recordDate, inSameDayAs: dayStart)
            }
            return false
        }
        
        // Only update if not protected
        if !localDataProtected {
            updateScheduleFromRecord()
        }
    }
    
    private func updateScheduleFromRecord() {
        // Store the current state to detect if we're overwriting user changes
        let oldLine1 = line1
        let oldLine2 = line2
        let oldLine3 = line3
        
        line1 = existingRecord?.line1 ?? ""
        line2 = existingRecord?.line2 ?? ""
        line3 = existingRecord?.line3 ?? ""
        
        // If we overwrote user changes, log it
        if oldLine1 != line1 || oldLine2 != line2 || oldLine3 != line3 {
            print("📋 Updated \(dayString) from record - line1: '\(oldLine1)' → '\(line1)', line2: '\(oldLine2)' → '\(line2)', line3: '\(oldLine3)' → '\(line3)'")
        }
        
        // Update sync version
        lastSyncVersion = Date()
        hasUnsavedChanges = false
        userInitiatedChange = false
    }
    
    private func saveSchedule() {
        // Prevent duplicate saves
        guard !isSaving else {
            print("⏸️ Save already in progress for \(dayString) - skipping duplicate request")
            return
        }
        
        // Don't save if no user changes were made
        guard userInitiatedChange else {
            print("⏸️ No user changes detected for \(dayString) - skipping save")
            return
        }
        
        // Set saving flag immediately to block subsequent calls
        isSaving = true
        localDataProtected = true
        print("🔒 Setting saving flags for \(dayString)")
        
        // Cancel any existing timer
        saveTimer?.invalidate()
        
        // Set up a debounced save with 0.8 second delay (increased for stability)
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { _ in
            performSave()
        }
    }
    
    private func performSave() {
        print("🚀 Performing save for \(dayString) with protection active")
        let dayStart = calendar.startOfDay(for: date)
        
        // Log the current state
        print("📊 Saving state - line1: '\(line1)', line2: '\(line2)', line3: '\(line3)'")
        
        // Use smart save that handles deletion when all fields are empty
        cloudKitManager.saveOrDeleteDailySchedule(
            existingRecordName: existingRecord?.id,
            date: dayStart,
            line1: line1.isEmpty ? nil : line1,
            line2: line2.isEmpty ? nil : line2,
            line3: line3.isEmpty ? nil : line3
        ) { success, error in
            DispatchQueue.main.async {
                self.handleSaveCompletion(success: success, error: error)
            }
        }
    }
    
    private func handleSaveCompletion(success: Bool, error: Error?) {
        if success {
            print("✅ Save completed successfully for \(dayString)")
            hasUnsavedChanges = false
            userInitiatedChange = false
            lastSyncVersion = Date()
        } else {
            print("❌ Save failed for \(dayString): \(error?.localizedDescription ?? "Unknown error")")
        }
        
        // Clear saving flag after a delay to prevent rapid successive operations
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.isSaving = false
            print("🔓 Cleared saving flag for \(self.dayString)")
            
            // Clear protection after save completes and some time passes
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                if !self.isEditing {
                    self.localDataProtected = false
                    print("🔓 Cleared local data protection for \(self.dayString)")
                }
            }
        }
    }
    
    private func cleanupTimersAndState() {
        saveTimer?.invalidate()
        saveTimer = nil
        
        // Don't clear protection immediately to allow any pending operations to complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            isSaving = false
            if !isEditing {
                localDataProtected = false
            }
        }
    }
    
    private func handleNextDayFocusRequest(_ request: NextDayFocusRequest) {
        let targetDayStart = calendar.startOfDay(for: request.targetDate)
        let currentDayStart = calendar.startOfDay(for: date)
        
        // Check if this cell's date matches the target date
        if calendar.isDate(currentDayStart, inSameDayAs: targetDayStart) {
            // Small delay to ensure proper timing after previous day clears focus
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                // Only take focus if not currently being edited
                if !self.isEditing && !self.localDataProtected {
                    self.focusedField = .line1
                    print("🎯 Next day navigation: Focus moved to OS field on \(self.dayString)")
                }
            }
        }
    }
}

// MARK: - MonthlyNotesView
struct MonthlyNotesView: View {
    let month: Date
    @EnvironmentObject private var cloudKitManager: CloudKitManager
    
    @State private var line1: String = ""
    @State private var line2: String = ""
    @State private var line3: String = ""
    @State private var existingRecord: MonthlyNotesRecord?
    @State private var isEditing = false
    @State private var saveTimer: Timer?
    @State private var isSaving = false
    @State private var hasUnsavedChanges = false
    @State private var lastSyncVersion: Date?
    @FocusState private var focusedField: MonthlyNotesField?
    
    // Track local state to prevent CloudKit overwrites
    @State private var localDataProtected = false
    @State private var userInitiatedChange = false
    
    private let calendar = Calendar.current
    
    enum MonthlyNotesField: CaseIterable {
        case line1, line2, line3
    }
    
    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text("Notes:")
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()
            }
            
            VStack(spacing: 2) {
                noteTextField(text: $line1, placeholder: "Note 1", field: .line1)
                noteTextField(text: $line2, placeholder: "Note 2", field: .line2)
                noteTextField(text: $line3, placeholder: "Note 3", field: .line3)
            }
        }
        .padding(8)
        .background(Color.blue.opacity(0.1))
        .cornerRadius(6)
        .onAppear {
            print("📱 MonthlyNotesView appeared for \(monthString) - loading notes")
            loadNotes()
        }
        .onChange(of: cloudKitManager.monthlyNotes) { _, newNotes in
            // Enhanced protection against CloudKit overwrites during editing
            handleCloudKitDataChange(newNotes)
        }
        .onChange(of: existingRecord) { oldRecord, newRecord in
            // Only update if not actively editing and no unsaved changes
            if !isEditing && !hasUnsavedChanges && !localDataProtected {
                print("📋 Monthly notes record changed for \(monthString) - updating from record")
                updateNotesFromRecord()
            } else {
                print("🛡️ Skipping monthly notes record update for \(monthString) - protected (editing: \(isEditing), unsaved: \(hasUnsavedChanges), protected: \(localDataProtected))")
            }
        }
        .onChange(of: focusedField) { oldField, newField in
            handleFocusChange(from: oldField, to: newField)
        }
        .onChange(of: isEditing) { _, newValue in
            // Save when editing state changes (keyboard dismiss, app backgrounding, etc.)
            if !newValue && hasUnsavedChanges {
                print("🎯 Monthly notes editing ended for \(monthString) with unsaved changes - triggering save")
                saveNotes()
            }
        }
        .onDisappear {
            // Clean up and save any pending changes
            print("📱 MonthlyNotesView disappeared for \(monthString) - cleaning up")
            if hasUnsavedChanges {
                performSave()
            }
            cleanupTimersAndState()
        }
    }
    
    private var monthString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return formatter.string(from: month)
    }
    
    private func noteTextField(text: Binding<String>, placeholder: String, field: MonthlyNotesField) -> some View {
        TextField(placeholder, text: text)
            .font(.caption)
            .padding(4)
            .background(Color.white)
            .cornerRadius(4)
            .focused($focusedField, equals: field)
            .submitLabel(.done)
            .textInputAutocapitalization(.characters)  // Force all uppercase
            .disableAutocorrection(true)  // Disable autocorrect for cleaner input
            .onChange(of: text.wrappedValue) { oldValue, newValue in
                handleTextChange(field: field, oldValue: oldValue, newValue: newValue)
            }
            .onSubmit {
                finalizeEditing()
            }
    }
    
    // MARK: - Enhanced Data Management Methods
    
    private func handleTextChange(field: MonthlyNotesField, oldValue: String, newValue: String) {
        // Track that this is a user-initiated change
        userInitiatedChange = true
        isEditing = true
        hasUnsavedChanges = true
        localDataProtected = true
        
        print("✏️ User editing \(monthString) field \(field) - setting protection flags")
        print("📝 Monthly notes field \(field) changed from '\(oldValue)' to '\(newValue)'")
    }
    
    private func handleFocusChange(from oldField: MonthlyNotesField?, to newField: MonthlyNotesField?) {
        if oldField != nil && newField != oldField {
            print("🎯 Monthly notes focus changed for \(monthString) from \(String(describing: oldField)) to \(String(describing: newField))")
            
            // If moving between fields with unsaved changes, save immediately
            if hasUnsavedChanges && !isSaving {
                print("💾 Monthly notes focus change with unsaved changes - triggering immediate save")
                saveNotes()
            }
        }
    }
    
    private func handleCloudKitDataChange(_ newNotes: [MonthlyNotesRecord]) {
        // Only update from CloudKit if we're not actively protecting local data
        if localDataProtected || isEditing || hasUnsavedChanges || isSaving {
            print("🛡️ CloudKit monthly notes data changed for \(monthString) - local data protected")
            print("🔍 Protection reasons: protected=\(localDataProtected), editing=\(isEditing), unsaved=\(hasUnsavedChanges), saving=\(isSaving)")
            return
        }
        
        // Find the record for this month/year
        let monthComp = calendar.component(.month, from: month)
        let yearComp = calendar.component(.year, from: month)
        
        let updatedRecord = newNotes.first { record in
            record.month == monthComp && record.year == yearComp
        }
        
        // Only update if the record actually changed
        if let newRecord = updatedRecord, newRecord.id != existingRecord?.id {
            print("📊 CloudKit monthly notes data updated for \(monthString) - applying changes")
            existingRecord = newRecord
        } else if updatedRecord == nil && existingRecord != nil {
            print("🗑️ CloudKit monthly notes record deleted for \(monthString) - clearing local data")
            existingRecord = nil
        }
    }
    
    private func finalizeEditing() {
        print("🏁 Finalizing monthly notes editing for \(monthString)")
        
        // Force immediate save if there are unsaved changes
        if hasUnsavedChanges && !isSaving {
            performSave()
        }
        
        // For monthly notes, keep focus on current field after save
        // This prevents cursor disappearing and allows continued editing
        isEditing = false
        
        // Note: We intentionally do NOT set focusedField = nil here
        // This maintains cursor visibility for continued editing
        print("🎯 Keeping focus on current monthly notes field")
        
        // Delay clearing protection to allow save to complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            localDataProtected = false
            print("🔓 Cleared local data protection for monthly notes \(monthString)")
        }
    }
    
    private func loadNotes() {
        let monthComp = calendar.component(.month, from: month)
        let yearComp = calendar.component(.year, from: month)
        
        existingRecord = cloudKitManager.monthlyNotes.first { record in
            record.month == monthComp && record.year == yearComp
        }
        
        // Only update if not protected
        if !localDataProtected {
            updateNotesFromRecord()
        }
    }
    
    private func updateNotesFromRecord() {
        // Store the current state to detect if we're overwriting user changes
        let oldLine1 = line1
        let oldLine2 = line2
        let oldLine3 = line3
        
        line1 = existingRecord?.line1 ?? ""
        line2 = existingRecord?.line2 ?? ""
        line3 = existingRecord?.line3 ?? ""
        
        // If we overwrote user changes, log it
        if oldLine1 != line1 || oldLine2 != line2 || oldLine3 != line3 {
            print("📋 Updated monthly notes \(monthString) from record - line1: '\(oldLine1)' → '\(line1)', line2: '\(oldLine2)' → '\(line2)', line3: '\(oldLine3)' → '\(line3)'")
        }
        
        // Update sync version
        lastSyncVersion = Date()
        hasUnsavedChanges = false
        userInitiatedChange = false
    }
    
    private func saveNotes() {
        // Prevent duplicate saves
        guard !isSaving else {
            print("⏸️ Monthly notes save already in progress for \(monthString) - skipping duplicate request")
            return
        }
        
        // Don't save if no user changes were made
        guard userInitiatedChange else {
            print("⏸️ No user changes detected for monthly notes \(monthString) - skipping save")
            return
        }
        
        // Set saving flag immediately to block subsequent calls
        isSaving = true
        localDataProtected = true
        print("🔒 Setting saving flags for monthly notes \(monthString)")
        
        // Cancel any existing timer
        saveTimer?.invalidate()
        
        // Set up a debounced save with 0.8 second delay
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { _ in
            performSave()
        }
    }
    
    private func performSave() {
        print("🚀 Performing monthly notes save for \(monthString) with protection active")
        let monthComp = calendar.component(.month, from: month)
        let yearComp = calendar.component(.year, from: month)
        
        // Log the current state
        print("📊 Saving monthly notes state - line1: '\(line1)', line2: '\(line2)', line3: '\(line3)'")
        
        // Use smart save that handles deletion when all fields are empty
        cloudKitManager.saveOrDeleteMonthlyNotes(
            existingRecordName: existingRecord?.id,
            month: monthComp,
            year: yearComp,
            line1: line1.isEmpty ? nil : line1,
            line2: line2.isEmpty ? nil : line2,
            line3: line3.isEmpty ? nil : line3
        ) { success, error in
            DispatchQueue.main.async {
                self.handleSaveCompletion(success: success, error: error)
            }
        }
    }
    
    private func handleSaveCompletion(success: Bool, error: Error?) {
        if success {
            print("✅ Monthly notes save completed successfully for \(monthString)")
            hasUnsavedChanges = false
            userInitiatedChange = false
            lastSyncVersion = Date()
        } else {
            print("❌ Monthly notes save failed for \(monthString): \(error?.localizedDescription ?? "Unknown error")")
        }
        
        // Clear saving flag after a delay to prevent rapid successive operations
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.isSaving = false
            print("🔓 Cleared saving flag for monthly notes \(self.monthString)")
            
            // Clear protection after save completes and some time passes
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                if !self.isEditing {
                    self.localDataProtected = false
                    print("🔓 Cleared local data protection for monthly notes \(self.monthString)")
                }
            }
        }
    }
    
    private func cleanupTimersAndState() {
        saveTimer?.invalidate()
        saveTimer = nil
        
        // Don't clear protection immediately to allow any pending operations to complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            isSaving = false
            if !isEditing {
                localDataProtected = false
            }
        }
    }
}

// MARK: - LegendView
struct LegendView: View {
    var body: some View {
        Text("O-Siddiqui. F-Freeman. P-Dixit. K-Watts. C-Carbajal. B-Brown  G-Grant. S-Sisodraker. A-Pitocchi.")
            .font(.caption)
            .padding(8)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.gray, lineWidth: 1)
            )
            .padding(.top, 5)
    }
}

// MARK: - PrintView
struct PrintView: View {
    @EnvironmentObject private var cloudKitManager: CloudKitManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                Text("Print functionality to be implemented")
                    .padding()
            }
            .navigationTitle("Print Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Utilities
private let monthFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "MMMM yyyy"
    return formatter
}()

extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        let components = dateComponents([.year, .month], from: date)
        return self.date(from: components) ?? date
    }
}

// MARK: - Preview
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(CloudKitManager.shared)
    }
}
