import SwiftUI
import CloudKit

// MARK: - Modern PSC with SV-Inspired UI + Calendar Editing
struct ContentView_New: View {
    @StateObject private var viewModel = ScheduleViewModel()
    @State private var currentMonthIndex = 0
    @State private var showingSaveAlert = false
    @State private var saveMessage = ""
    
    private let calendar = Calendar.current
    
    var body: some View {
        // FULL SCREEN iPad Layout - No NavigationView constraints
        VStack(spacing: 0) {
            // Fixed header - FULL WIDTH
            modernHeader
                .background(Color(UIColor.systemBackground))
                .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 2)
            
                // Monthly Notes Section
                if let currentMonth = viewModel.availableMonths.safeGet(index: currentMonthIndex) {
                    RedesignedMonthlyNotesView(
                        month: currentMonth,
                        line1: viewModel.monthlyNotes[monthKey(for: currentMonth)]?.line1 ?? "",
                        line2: viewModel.monthlyNotes[monthKey(for: currentMonth)]?.line2 ?? "",
                        onLine1Change: { newLine1 in
                            viewModel.updateMonthlyNotesLine1(for: currentMonth, line1: newLine1)
                        },
                        onLine2Change: { newLine2 in
                            viewModel.updateMonthlyNotesLine2(for: currentMonth, line2: newLine2)
                        }
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                }
                
                // Calendar content - FULL WIDTH
                ScrollView {
                    VStack(spacing: 20) {
                        if let currentMonth = viewModel.availableMonths.safeGet(index: currentMonthIndex) {
                            MonthCalendarView(
                                month: currentMonth,
                                schedules: viewModel.schedules,
                                onScheduleChange: viewModel.updateSchedule
                            )
                            .padding(.horizontal, 20) // Only horizontal padding for calendar
                        } else {
                            Text("No data available")
                                .foregroundColor(.gray)
                                .padding()
                        }
                    }
                    .padding(.vertical, 20)
                }
        }
        .ignoresSafeArea(.all) // FORCE full screen edge-to-edge
        .onAppear {
            viewModel.loadData()
            initializeCurrentMonth()
        }
        .alert("Save Status", isPresented: $showingSaveAlert) {
            Button("OK") {}
        } message: {
            Text(saveMessage)
        }
    }
    
    // MARK: - Compact iPad Header (with room for monthly notes)
    private var modernHeader: some View {
        VStack(spacing: 12) {
            // COMPACT: Single row with all essentials
            HStack(spacing: 20) {
                // Left: App name + Version
                HStack(spacing: 8) {
                    Text("📅 Provider Schedule Calendar v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "4.0")")
                        .font(.title2)
                        .fontWeight(.bold)
                }
                
                Spacer()
                
                // Center: Status
                if viewModel.isLoading {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.8)
                        Text("Loading")
                    }
                    .foregroundColor(.blue)
                } else if !viewModel.isCloudKitAvailable {
                    Text("⚠️ CloudKit Issue")
                        .foregroundColor(.red)
                } else if viewModel.hasChanges {
                    Text("📝 Unsaved")
                        .foregroundColor(.orange)
                } else {
                    Text("✅ Ready")
                        .foregroundColor(.green)
                }
                
                Spacer()
                
                // Right: Action buttons
                HStack(spacing: 12) {
                    Button(action: saveData) {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.down")
                            Text(saveButtonText)
                        }
                        .font(.title3)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(saveButtonColor)
                        .cornerRadius(8)
                    }
                    .disabled(!viewModel.hasChanges)
                    
                    Button(action: shareCalendar) {
                        HStack(spacing: 4) {
                            Image(systemName: "person.badge.plus")
                            Text("Share")
                        }
                        .font(.title3)
                        .foregroundColor(.green)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                    }
                    
                    Button(action: printCalendar) {
                        HStack(spacing: 4) {
                            Image(systemName: "printer")
                            Text("Print")
                        }
                        .font(.title3)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
            }
            
            // COMPACT: Month navigation
            if !viewModel.availableMonths.isEmpty {
                HStack(spacing: 20) {
                    Button(action: previousMonth) {
                        Image(systemName: "chevron.left.circle.fill")
                            .font(.title)
                            .foregroundColor(.blue)
                    }
                    .disabled(currentMonthIndex <= 0)
                    
                    Spacer()
                    
                    Text(currentMonthName)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Button(action: nextMonth) {
                        Image(systemName: "chevron.right.circle.fill")
                            .font(.title)
                            .foregroundColor(.blue)
                    }
                    .disabled(currentMonthIndex >= viewModel.availableMonths.count - 1)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(0)
    }
    
    // MARK: - Navigation Logic
    private var currentMonthName: String {
        guard let currentMonth = viewModel.availableMonths.safeGet(index: currentMonthIndex) else {
            return "No Data"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: currentMonth)
    }
    
    private func previousMonth() {
        if currentMonthIndex > 0 {
            currentMonthIndex -= 1
        }
    }
    
    private func nextMonth() {
        if currentMonthIndex < viewModel.availableMonths.count - 1 {
            currentMonthIndex += 1
        }
    }
    
    private func initializeCurrentMonth() {
        guard !viewModel.availableMonths.isEmpty else { return }
        
        let now = Date()
        // Try to find current month in available months
        if let foundIndex = viewModel.availableMonths.firstIndex(where: { month in
            calendar.isDate(month, equalTo: now, toGranularity: .month)
        }) {
            currentMonthIndex = foundIndex
        } else {
            // Default to first available month
            currentMonthIndex = 0
        }
    }
    
    // MARK: - Actions
    private var saveButtonText: String {
        return viewModel.hasChanges ? "Save" : "Saved"
    }
    
    private var saveButtonColor: Color {
        return viewModel.hasChanges ? .blue : .gray
    }
    
    private func saveData() {
        Task {
            let success = await viewModel.saveChanges()
            await MainActor.run {
                saveMessage = success ? "✅ Changes saved successfully!" : "❌ Save failed. Please try again."
                showingSaveAlert = true
            }
        }
    }
    
    private func shareCalendar() {
        // CloudKit sharing functionality - to be implemented
        redesignLog("Share calendar requested")
        // TODO: Implement CloudKit sharing
    }
    
    private func printCalendar() {
        // TODO: Implement simplified print function
        print("Print function to be implemented")
    }
    
    // MARK: - Helper Functions
    private func monthKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }
}

// MARK: - Month Calendar View (Editable Grid)
struct MonthCalendarView: View {
    let month: Date
    let schedules: [String: ScheduleRecord]
    let onScheduleChange: (Date, ScheduleField, String) -> Void
    
    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
    
    var body: some View {
        VStack(spacing: 12) {
            // Days of week header
            HStack {
                ForEach(calendar.shortWeekdaySymbols, id: \.self) { day in
                    Text(day)
                        .font(.caption)
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .foregroundColor(.secondary)
                }
            }
            
            // Calendar grid - FULL WIDTH
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(calendarDays, id: \.self) { date in
                    if calendar.isDate(date, equalTo: month, toGranularity: .month) {
                        DayEditCell(
                            date: date,
                            schedule: schedules[dateKey(for: date)],
                            onFieldChange: { field, value in
                                onScheduleChange(date, field, value)
                            }
                        )
                        .frame(minHeight: 140) // Bigger cells for iPad
                    } else {
                        // Empty cell for days outside current month
                        Rectangle()
                            .fill(Color.clear)
                            .frame(height: 120)
                    }
                }
            }
        }
    }
    
    private var calendarDays: [Date] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: month),
              let firstWeekday = calendar.dateInterval(of: .weekOfYear, for: monthInterval.start)?.start else {
            return []
        }
        
        var days: [Date] = []
        var currentDate = firstWeekday
        
        // Generate 6 weeks (42 days) to cover all possible month layouts
        for _ in 0..<42 {
            days.append(currentDate)
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }
        
        return days
    }
    
    private func dateKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }
}

// MARK: - Editable Day Cell
struct DayEditCell: View {
    let date: Date
    let schedule: ScheduleRecord?
    let onFieldChange: (ScheduleField, String) -> Void
    
    @State private var osText: String = ""
    @State private var clText: String = ""
    @State private var offText: String = ""
    @State private var callText: String = ""
    
    private let calendar = Calendar.current
    
    var body: some View {
        VStack(spacing: 2) {
            // Day number
            Text("\(calendar.component(.day, from: date))")
                .font(.caption)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Schedule fields (OS, CL, OFF, CALL) with color coding
            VStack(spacing: 1) {
                ScheduleTextField(label: "OS", fieldType: .os, text: $osText) { newValue in
                    onFieldChange(.os, newValue)
                }
                
                ScheduleTextField(label: "CL", fieldType: .cl, text: $clText) { newValue in
                    onFieldChange(.cl, newValue)
                }
                
                ScheduleTextField(label: "OFF", fieldType: .off, text: $offText) { newValue in
                    onFieldChange(.off, newValue)
                }
                
                ScheduleTextField(label: "CALL", fieldType: .call, text: $callText) { newValue in
                    onFieldChange(.call, newValue)
                }
            }
        }
        .padding(8)
        .frame(minHeight: 140) // iPad-optimized height
        .background(Color(.systemBackground))
        .overlay(
            Rectangle()
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
        .onAppear {
            loadScheduleData()
        }
        .onChange(of: schedule) { _ in
            loadScheduleData()
        }
    }
    
    private func loadScheduleData() {
        osText = schedule?.os ?? ""
        clText = schedule?.cl ?? ""
        offText = schedule?.off ?? ""
        callText = schedule?.call ?? ""
    }
}

// MARK: - Schedule Text Field with Color Coding
struct ScheduleTextField: View {
    let label: String
    let fieldType: ScheduleField
    @Binding var text: String
    let onCommit: (String) -> Void
    
    // PSC Field Colors: OS=blue, CL=red, OFF=green, CALL=yellow
    private var fieldColor: Color {
        switch fieldType {
        case .os: return .blue
        case .cl: return .red
        case .off: return .green
        case .call: return .orange // Using orange instead of yellow for better readability
        }
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(fieldColor)
                .frame(width: 35, alignment: .leading)
            
            TextField("", text: $text)
                .font(.system(size: 14))
                .foregroundColor(.black)
                .textFieldStyle(PlainTextFieldStyle())
                .autocapitalization(.allCharacters)
                .onSubmit {
                    onCommit(text.uppercased())
                }
                .onChange(of: text) { newValue in
                    text = newValue.uppercased()
                    onCommit(text)
                }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(fieldColor.opacity(0.1))
        .cornerRadius(4)
    }
}

// MARK: - Redesigned Monthly Notes View (2 Fields)
struct RedesignedMonthlyNotesView: View {
    let month: Date
    let line1: String
    let line2: String
    let onLine1Change: (String) -> Void
    let onLine2Change: (String) -> Void
    
    @State private var line1Text: String = ""
    @State private var line2Text: String = ""
    
    private var monthName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: month)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("📝 Monthly Notes for \(monthName)")
                    .font(.headline)
                    .foregroundColor(.black)
                
                Spacer()
                
                Text("Blue: OS | Red: CL | Green: OFF | Orange: CALL")
                    .font(.caption)
                    .foregroundColor(.black)
            }
            
            VStack(spacing: 6) {
                // Blue field (Line 1)
                HStack(spacing: 8) {
                    Text("Line 1:")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.blue)
                        .frame(width: 60, alignment: .leading)
                    
                    TextField("", text: $line1Text)
                        .font(.system(size: 16))
                        .foregroundColor(.black)
                        .textFieldStyle(PlainTextFieldStyle())
                        .padding(8)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                        )
                        .onChange(of: line1Text) { newValue in
                            onLine1Change(newValue)
                        }
                }
                
                // Red field (Line 2)
                HStack(spacing: 8) {
                    Text("Line 2:")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.red)
                        .frame(width: 60, alignment: .leading)
                    
                    TextField("", text: $line2Text)
                        .font(.system(size: 16))
                        .foregroundColor(.black)
                        .textFieldStyle(PlainTextFieldStyle())
                        .padding(8)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.red.opacity(0.3), lineWidth: 1)
                        )
                        .onChange(of: line2Text) { newValue in
                            onLine2Change(newValue)
                        }
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        .onAppear {
            line1Text = line1
            line2Text = line2
        }
        .onChange(of: line1) { newValue in
            line1Text = newValue
        }
        .onChange(of: line2) { newValue in
            line2Text = newValue
        }
    }
}

// MARK: - Supporting Types
enum ScheduleField {
    case os, cl, off, call
}

// MARK: - Array Extension
extension Array {
    func safeGet(index: Int) -> Element? {
        return index >= 0 && index < count ? self[index] : nil
    }
}

#Preview {
    ContentView_New()
}
