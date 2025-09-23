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
        NavigationView {
            VStack(spacing: 0) {
                // Fixed header (SV-inspired)
                modernHeader
                    .background(Color(UIColor.systemBackground))
                    .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 2)
                
                // Calendar content
                ScrollView {
                    VStack(spacing: 20) {
                        if let currentMonth = viewModel.availableMonths.safeGet(index: currentMonthIndex) {
                            MonthCalendarView(
                                month: currentMonth,
                                schedules: viewModel.schedules,
                                onScheduleChange: viewModel.updateSchedule
                            )
                        } else {
                            Text("No data available")
                                .foregroundColor(.gray)
                                .padding()
                        }
                    }
                    .padding()
                }
            }
            .navigationBarHidden(true)
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
    }
    
    // MARK: - Modern Header (SV-inspired)
    private var modernHeader: some View {
        VStack(spacing: 12) {
            // Main header row: App name | Version | Save/Print
            HStack {
                Text("📅 Provider Schedule")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "3.7.5")")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                HStack(spacing: 8) {
                    // Save button
                    Button(action: saveData) {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.down")
                            Text(saveButtonText)
                        }
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(saveButtonColor)
                        .cornerRadius(8)
                    }
                    .disabled(!viewModel.hasChanges)
                    
                    // Print button
                    Button(action: printCalendar) {
                        HStack(spacing: 4) {
                            Image(systemName: "printer")
                            Text("Print")
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
            }
            
            // Status row - centered
            HStack {
                Spacer()
                
                if viewModel.isLoading {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading...")
                    }
                    .foregroundColor(.blue)
                } else if !viewModel.isCloudKitAvailable {
                    Text("⚠️ CloudKit Unavailable")
                        .foregroundColor(.red)
                } else if viewModel.hasChanges {
                    Text("📝 Unsaved Changes")
                        .foregroundColor(.orange)
                } else {
                    Text("✅ Ready")
                        .foregroundColor(.green)
                }
                
                Spacer()
            }
            .font(.caption)
            
            // Month navigation row (SV-inspired)
            if !viewModel.availableMonths.isEmpty {
                HStack {
                    Button(action: previousMonth) {
                        Image(systemName: "chevron.left")
                            .foregroundColor(.blue)
                    }
                    .disabled(currentMonthIndex <= 0)
                    
                    Spacer()
                    
                    Text(currentMonthName)
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    Button(action: nextMonth) {
                        Image(systemName: "chevron.right")
                            .foregroundColor(.blue)
                    }
                    .disabled(currentMonthIndex >= viewModel.availableMonths.count - 1)
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
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
    
    private func printCalendar() {
        // TODO: Implement simplified print function
        print("Print function to be implemented")
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
            
            // Calendar grid
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(calendarDays, id: \.self) { date in
                    if calendar.isDate(date, equalTo: month, toGranularity: .month) {
                        DayEditCell(
                            date: date,
                            schedule: schedules[dateKey(for: date)],
                            onFieldChange: { field, value in
                                onScheduleChange(date, field, value)
                            }
                        )
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
            
            // Schedule fields (OS, CL, OFF, CALL)
            VStack(spacing: 1) {
                ScheduleTextField(label: "OS", text: $osText) { newValue in
                    onFieldChange(.os, newValue)
                }
                
                ScheduleTextField(label: "CL", text: $clText) { newValue in
                    onFieldChange(.cl, newValue)
                }
                
                ScheduleTextField(label: "OFF", text: $offText) { newValue in
                    onFieldChange(.off, newValue)
                }
                
                ScheduleTextField(label: "CALL", text: $callText) { newValue in
                    onFieldChange(.call, newValue)
                }
            }
        }
        .padding(4)
        .frame(height: 120)
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

// MARK: - Schedule Text Field
struct ScheduleTextField: View {
    let label: String
    @Binding var text: String
    let onCommit: (String) -> Void
    
    var body: some View {
        HStack(spacing: 2) {
            Text(label)
                .font(.system(size: 8))
                .foregroundColor(.secondary)
                .frame(width: 20, alignment: .leading)
            
            TextField("", text: $text)
                .font(.system(size: 8))
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
