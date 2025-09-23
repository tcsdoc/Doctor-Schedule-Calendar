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
    
    // MARK: - iPad-Optimized Header
    private var modernHeader: some View {
        VStack(spacing: 16) {
            // Main header row: FULL WIDTH iPad layout
            HStack(spacing: 20) {
                // Left section: App branding
                HStack(spacing: 12) {
                    Text("📅 Provider Schedule Calendar")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "4.0")")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(6)
                }
                
                Spacer()
                
                // Right section: Action buttons - LARGER for iPad
                HStack(spacing: 16) {
                    // Save button - BIGGER
                    Button(action: saveData) {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.down")
                                .font(.title3)
                            Text(saveButtonText)
                                .font(.title3)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(saveButtonColor)
                        .cornerRadius(10)
                    }
                    .disabled(!viewModel.hasChanges)
                    
                    // Print button - BIGGER
                    Button(action: printCalendar) {
                        HStack(spacing: 8) {
                            Image(systemName: "printer")
                                .font(.title3)
                            Text("Print")
                                .font(.title3)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.blue)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(10)
                    }
                }
            }
            
            // Status indicator - LARGER for iPad
            HStack {
                Spacer()
                
                if viewModel.isLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Loading...")
                            .font(.title2)
                    }
                    .foregroundColor(.blue)
                } else if !viewModel.isCloudKitAvailable {
                    Text("⚠️ CloudKit Unavailable")
                        .font(.title2)
                        .foregroundColor(.red)
                } else if viewModel.hasChanges {
                    Text("📝 Unsaved Changes")
                        .font(.title2)
                        .foregroundColor(.orange)
                } else {
                    Text("✅ Ready")
                        .font(.title2)
                        .foregroundColor(.green)
                }
                
                Spacer()
            }
            .padding(.vertical, 8)
            
            // Month navigation - BIGGER for iPad
            if !viewModel.availableMonths.isEmpty {
                HStack(spacing: 30) {
                    // Previous month button - MUCH BIGGER
                    Button(action: previousMonth) {
                        HStack(spacing: 8) {
                            Image(systemName: "chevron.left")
                                .font(.title)
                            Text("Previous")
                                .font(.title2)
                        }
                        .foregroundColor(.blue)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(10)
                    }
                    .disabled(currentMonthIndex <= 0)
                    
                    Spacer()
                    
                    // Current month - MUCH LARGER
                    Text(currentMonthName)
                        .font(.system(size: 36, weight: .bold, design: .default))
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    // Next month button - MUCH BIGGER
                    Button(action: nextMonth) {
                        HStack(spacing: 8) {
                            Text("Next")
                                .font(.title2)
                            Image(systemName: "chevron.right")
                                .font(.title)
                        }
                        .foregroundColor(.blue)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(10)
                    }
                    .disabled(currentMonthIndex >= viewModel.availableMonths.count - 1)
                }
                .padding(.horizontal, 40)
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

// MARK: - Schedule Text Field
struct ScheduleTextField: View {
    let label: String
    @Binding var text: String
    let onCommit: (String) -> Void
    
    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 12, weight: .medium)) // Bigger for iPad
                .foregroundColor(.secondary)
                .frame(width: 35, alignment: .leading)
            
            TextField("", text: $text)
                .font(.system(size: 14)) // Much bigger for iPad
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
