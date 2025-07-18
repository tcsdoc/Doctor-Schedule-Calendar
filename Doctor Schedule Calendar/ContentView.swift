//
//  ContentView.swift
//  Doctor Schedule Calendar
//
//  Created by mark on 7/5/25.
//  Converted from Core Data to CloudKit Direct Implementation
//

import SwiftUI
import CloudKit

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
    @FocusState private var focusedField: DayField?
    
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
            loadSchedule()
        }
        .onChange(of: cloudKitManager.dailySchedules) { _, _ in
            // Only update from CloudKit if not currently editing
            if !isEditing {
                loadSchedule()
            }
        }
        .onChange(of: existingRecord) { _, _ in
            if !isEditing {
                updateScheduleFromRecord()
            }
        }
        .onChange(of: focusedField) { oldField, newField in
            // Save when user moves away from ANY field or dismisses keyboard
            if oldField != nil && newField != oldField && isEditing {
                print("🎯 Focus changed from \(String(describing: oldField)) to \(String(describing: newField)) - triggering save")
                saveSchedule()
            }
        }
        .onChange(of: isEditing) { _, newValue in
            // Save when editing state changes (keyboard dismiss, app backgrounding, etc.)
            if !newValue {
                print("🎯 Editing state changed to false - triggering save")
                saveSchedule()
            }
        }
        .onDisappear {
            // Clean up timer and reset saving state to prevent memory leaks
            saveTimer?.invalidate()
            isSaving = false
        }
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
                saveSchedule()
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
                .onSubmit {
                    onSubmit()
                }
                .onChange(of: text.wrappedValue) { _, newValue in
                    // Limit to 16 characters
                    if newValue.count > 16 {
                        text.wrappedValue = String(newValue.prefix(16))
                    }
                    isEditing = true
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
    
    private func moveToNextField() {
        switch focusedField {
        case .line1:
            focusedField = .line2
        case .line2:
            focusedField = .line3
        case .line3:
            // For final field, save immediately without debounce but check for duplicates
            guard !isSaving else {
                print("⏸️ Save already in progress - skipping final field save")
                focusedField = nil
                return
            }
            // Set saving flag immediately
            isSaving = true
            print("🔒 Final field save - setting isSaving flag to TRUE")
            saveTimer?.invalidate()
            performSave()
            focusedField = nil
        case .none:
            break
        }
    }
    
    private func loadSchedule() {
        let dayStart = calendar.startOfDay(for: date)
        existingRecord = cloudKitManager.dailySchedules.first { record in
            if let recordDate = record.date {
                return calendar.isDate(recordDate, inSameDayAs: dayStart)
            }
            return false
        }
        
        updateScheduleFromRecord()
    }
    
    private func updateScheduleFromRecord() {
        line1 = existingRecord?.line1 ?? ""
        line2 = existingRecord?.line2 ?? ""
        line3 = existingRecord?.line3 ?? ""
    }
    
    private func saveSchedule() {
        // Prevent duplicate saves if one is already in progress
        guard !isSaving else {
            print("⏸️ Save already in progress - skipping duplicate save request")
            return
        }
        
        // Set saving flag immediately to block subsequent calls
        isSaving = true
        print("🔒 Setting isSaving flag to TRUE - blocking future saves")
        
        // Cancel any existing timer
        saveTimer?.invalidate()
        
        // Set up a debounced save with 0.5 second delay (increased from 0.3)
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
            performSave()
        }
    }
    
    private func performSave() {
        print("🚀 performSave() starting - isSaving flag should be TRUE")
        let dayStart = calendar.startOfDay(for: date)
        
        // Use smart save that handles deletion when all fields are empty
        cloudKitManager.saveOrDeleteDailySchedule(
            existingRecordName: existingRecord?.id,
            date: dayStart,
            line1: line1.isEmpty ? nil : line1,
            line2: line2.isEmpty ? nil : line2,
            line3: line3.isEmpty ? nil : line3
        ) { success, error in
            DispatchQueue.main.async {
                // Add delay before clearing flag to prevent rapid successive saves
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    print("🔓 Clearing isSaving flag after CloudKit operation + 1 second delay")
                    self.isSaving = false
                }
                self.isEditing = false
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
    @FocusState private var focusedField: MonthlyNotesField?
    
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
            loadNotes()
        }
        .onChange(of: cloudKitManager.monthlyNotes) { _, _ in
            // Only update from CloudKit if not currently editing
            if !isEditing {
                loadNotes()
            }
        }
        .onChange(of: existingRecord) { _, _ in
            if !isEditing {
                updateNotesFromRecord()
            }
        }
        .onChange(of: isEditing) { _, newValue in
            if !newValue {
                saveNotes()
            }
        }
        .onChange(of: focusedField) { oldField, newField in
            // Save when user moves away from any field or dismisses keyboard
            if oldField != nil && newField == nil && isEditing {
                isEditing = false  // This will trigger the save via onChange(of: isEditing)
            }
        }
    }
    
    private func noteTextField(text: Binding<String>, placeholder: String, field: MonthlyNotesField) -> some View {
        TextField(placeholder, text: text)
            .font(.caption)
            .padding(4)
            .background(Color.white)
            .cornerRadius(4)
            .focused($focusedField, equals: field)
            .submitLabel(.done)
            .onChange(of: text.wrappedValue) { _, newValue in
                isEditing = true
            }
            .onSubmit {
                isEditing = false
            }
    }
    
    private func loadNotes() {
        let monthComp = calendar.component(.month, from: month)
        let yearComp = calendar.component(.year, from: month)
        
        existingRecord = cloudKitManager.monthlyNotes.first { record in
            record.month == monthComp && record.year == yearComp
        }
        
        updateNotesFromRecord()
    }
    
    private func updateNotesFromRecord() {
        line1 = existingRecord?.line1 ?? ""
        line2 = existingRecord?.line2 ?? ""
        line3 = existingRecord?.line3 ?? ""
    }
    
    private func saveNotes() {
        let monthComp = calendar.component(.month, from: month)
        let yearComp = calendar.component(.year, from: month)
        
        // Use saveMonthlyNotes for both creating and updating
        cloudKitManager.saveMonthlyNotes(
            month: monthComp,
            year: yearComp,
            line1: line1.isEmpty ? nil : line1,
            line2: line2.isEmpty ? nil : line2,
            line3: line3.isEmpty ? nil : line3
        ) { success, error in
            // Completion handled silently
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
