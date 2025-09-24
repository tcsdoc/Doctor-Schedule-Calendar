import SwiftUI
import CloudKit
import UIKit

// MARK: - Modern PSC with SV-Inspired UI + Calendar Editing
struct ContentView: View {
    @StateObject private var viewModel = ScheduleViewModel()
    @State private var currentMonthIndex = 0
    @State private var showingSaveAlert = false
    @State private var saveMessage = ""
    @State private var showingShareSheet = false
    @State private var shareItem: Any?
    
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
                    MonthlyNotesContainer(
                        currentMonth: currentMonth,
                        viewModel: viewModel,
                        monthKey: monthKey(for: currentMonth)
                    )
                    .id("\(monthKey(for: currentMonth))-\(viewModel.monthlyNotes.count)") // Force refresh when data changes
                }
                
                // Calendar content - FULL WIDTH with keyboard awareness
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
        // Respect safe area to avoid status bar overlap
        .onTapGesture {
            // Dismiss keyboard when tapping outside text fields
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        .onAppear {
            initializeCurrentMonth()
        }
        .alert("Save Status", isPresented: $showingSaveAlert) {
            Button("OK") {}
        } message: {
            Text(saveMessage)
        }
        .sheet(isPresented: $showingShareSheet) {
            if let share = shareItem as? CKShare {
                CloudKitSharingView(share: share)
            }
        }
    }
    
    // MARK: - Ultra-Compact iPad Header (minimal height for 6-week months)
    private var modernHeader: some View {
        VStack(spacing: 6) {
            // ULTRA-COMPACT: Single row with essentials only
            HStack(spacing: 16) {
                // Left: App name only
                Text("📅 PSC v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "4.0")")
                    .font(.headline)
                    .fontWeight(.bold)
                
                Spacer()
                
                // Center: Status (compact)
                if viewModel.isSaving {
                    HStack(spacing: 4) {
                        ProgressView().scaleEffect(0.7)
                        Text("Saving").font(.caption)
                    }
                    .foregroundColor(.orange)
                } else if viewModel.isLoading {
                    HStack(spacing: 4) {
                        ProgressView().scaleEffect(0.7)
                        Text("Loading").font(.caption)
                    }
                    .foregroundColor(.blue)
                } else if !viewModel.isCloudKitAvailable {
                    Text("⚠️ CloudKit Issue").font(.caption)
                        .foregroundColor(.red)
                } else if viewModel.hasChanges {
                    Text("⚠️ UNSAVED")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.red)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.red.opacity(0.8), lineWidth: 2)
                        )
                } else {
                    Text("✅ Ready").font(.caption)
                        .foregroundColor(.green)
                }
                
                Spacer()
                
                // Right: Compact action buttons (with edge spacing)
                HStack(spacing: 8) {
                    Button(action: saveData) {
                        HStack(spacing: 3) {
                            Image(systemName: "square.and.arrow.down")
                            Text(saveButtonText)
                        }
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(saveButtonColor)
                        .cornerRadius(6)
                    }
                    
                    Button(action: shareCalendar) {
                        HStack(spacing: 3) {
                            Image(systemName: "person.badge.plus")
                            Text("Share")
                        }
                        .font(.caption)
                        .foregroundColor(.green)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(6)
                    }
                    
                    Button(action: printCalendar) {
                        HStack(spacing: 3) {
                            Image(systemName: "printer")
                            Text("Print")
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(6)
                    }
                }
                .padding(.trailing, 60) // EVEN MORE padding - move buttons further from navigation area
            }
            
            // ULTRA-COMPACT: Month navigation inline
            if !viewModel.availableMonths.isEmpty {
                HStack(spacing: 16) {
                    Button(action: previousMonth) {
                        Image(systemName: "chevron.left.circle.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }
                    .disabled(currentMonthIndex <= 0)
                    
                    Spacer()
                    
                    Text(currentMonthName)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Button(action: nextMonth) {
                        Image(systemName: "chevron.right.circle.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }
                    .disabled(currentMonthIndex >= viewModel.availableMonths.count - 1)
                }
            }
        }
        .padding(.horizontal, 50) // MUCH MORE padding to move buttons away from edges
        .padding(.vertical, 8)
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
        return viewModel.hasChanges ? .blue : .blue
    }
    
    private func saveData() {
        Task {
            if viewModel.hasChanges {
                let (success, savedCount, totalCount) = await viewModel.saveChanges()
                await MainActor.run {
                    if success {
                        saveMessage = "✅ All \(totalCount) changes saved successfully!"
                    } else {
                        let failedCount = totalCount - savedCount
                        if savedCount > 0 {
                            saveMessage = "⚠️ Partial save: \(savedCount)/\(totalCount) saved\n\(failedCount) records failed - please retry"
                        } else {
                            saveMessage = "❌ Save failed: All \(totalCount) records failed"
                        }
                    }
                    showingSaveAlert = true
                }
            } else {
                await MainActor.run {
                    saveMessage = "✅ No changes to save"
                    showingSaveAlert = true
                }
            }
        }
    }
    
    private func shareCalendar() {
        Task {
            do {
                redesignLog("🔗 Starting CloudKit share creation...")
                let share = try await viewModel.createShare()
                
                await MainActor.run {
                    shareItem = share
                    showingShareSheet = true
                    redesignLog("✅ Share sheet will be presented")
                }
                
            } catch {
                await MainActor.run {
                    saveMessage = "❌ Share creation failed: \(error.localizedDescription)"
                    showingSaveAlert = true
                    redesignLog("❌ Share creation error: \(error)")
                }
            }
        }
    }
    
    private func printCalendar() {
        guard let currentMonth = viewModel.availableMonths.safeGet(index: currentMonthIndex) else { return }
        
        let printInfo = UIPrintInfo.printInfo()
        printInfo.outputType = .general
        printInfo.jobName = "Provider Schedule - \(currentMonthName)"
        
        let printController = UIPrintInteractionController.shared
        printController.printInfo = printInfo
        
        // Create simple print content
        let htmlContent = generatePrintHTML(for: currentMonth)
        let printFormatter = UIMarkupTextPrintFormatter(markupText: htmlContent)
        printFormatter.perPageContentInsets = UIEdgeInsets(top: 72, left: 72, bottom: 72, right: 72)
        
        printController.printFormatter = printFormatter
        
        printController.present(animated: true) { (controller, completed, error) in
            if let error = error {
                DispatchQueue.main.async {
                    self.saveMessage = "❌ Print failed: \(error.localizedDescription)"
                    self.showingSaveAlert = true
                }
            } else if completed {
                DispatchQueue.main.async {
                    self.saveMessage = "🖨️ Schedule printed successfully!"
                    self.showingSaveAlert = true
                }
            }
        }
    }
    
    private func generatePrintHTML(for month: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        let monthName = formatter.string(from: month)
        
        var html = """
        <html>
        <head>
            <title>Provider Schedule - \(monthName)</title>
            <style>
                body { font-family: Arial, sans-serif; margin: 20px; }
                h1 { text-align: center; color: #333; }
                table { width: 100%; border-collapse: collapse; margin-top: 20px; }
                th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
                th { background-color: #f2f2f2; font-weight: bold; }
                .weekend { background-color: #f9f9f9; }
                .os { color: blue; }
                .cl { color: red; }
                .off { color: green; }
                .call { color: orange; }
            </style>
        </head>
        <body>
            <h1>Provider Schedule Calendar</h1>
            <h2>\(monthName)</h2>
            <table>
                <tr>
                    <th>Date</th>
                    <th>Day</th>
                    <th>OS</th>
                    <th>CL</th>
                    <th>OFF</th>
                    <th>CALL</th>
                </tr>
        """
        
        let calendar = Calendar.current
        let range = calendar.range(of: .day, in: .month, for: month)!
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEEE"
        
        for day in 1...range.count {
            let date = calendar.date(byAdding: .day, value: day - 1, to: calendar.startOfDay(for: month))!
            let dayName = dayFormatter.string(from: date)
            let isWeekend = calendar.isDateInWeekend(date)
            let weekendClass = isWeekend ? " class=\"weekend\"" : ""
            
            let schedule = viewModel.schedules[viewModel.dateKey(for: date)]
            
            html += """
                <tr\(weekendClass)>
                    <td>\(day)</td>
                    <td>\(dayName)</td>
                    <td class="os">\(schedule?.os ?? "")</td>
                    <td class="cl">\(schedule?.cl ?? "")</td>
                    <td class="off">\(schedule?.off ?? "")</td>
                    <td class="call">\(schedule?.call ?? "")</td>
                </tr>
            """
        }
        
        // Add monthly notes if they exist
        if let monthlyNote = viewModel.monthlyNotes[viewModel.monthKey(for: month)] {
            html += """
                <tr>
                    <td colspan="6" style="background-color: #e8f4fd; font-weight: bold;">
                        Monthly Notes:<br>
                        Line 1: \(monthlyNote.line1 ?? "")<br>
                        Line 2: \(monthlyNote.line2 ?? "")
                    </td>
                </tr>
            """
        }
        
        html += """
            </table>
        </body>
        </html>
        """
        
        return html
    }
    
    // MARK: - Helper Functions
    private func monthKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }
}

// MARK: - CloudKit Sharing View
struct CloudKitSharingView: UIViewControllerRepresentable {
    let share: CKShare
    
    func makeUIViewController(context: Context) -> UICloudSharingController {
        let sharingController = UICloudSharingController(share: share, container: CKContainer(identifier: "iCloud.com.gulfcoast.ProviderCalendar"))
        sharingController.delegate = CloudKitSharingDelegate.shared
        return sharingController
    }
    
    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {
        // No updates needed
    }
}

// MARK: - CloudKit Sharing Delegate (from original working implementation)
class CloudKitSharingDelegate: NSObject, UICloudSharingControllerDelegate {
    static let shared = CloudKitSharingDelegate()
    
    func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
        redesignLog("❌ Failed to save share: \(error.localizedDescription)")
        redesignLog("❌ SHARING ERROR: \(error)")
    }
    
    func itemTitle(for csc: UICloudSharingController) -> String? {
        return "Provider Schedule Calendar"
    }
    
    func itemType(for csc: UICloudSharingController) -> String? {
        return "Calendar Schedule"
    }
    
    func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
        redesignLog("✅ Share saved successfully")
        redesignLog("✅ SHARING SUCCESS - Share URL should be available in the controller")
        if let share = csc.share {
            redesignLog("🔗 Final share URL: \(share.url?.absoluteString ?? "Still no URL")")
        }
    }
    
    func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
        redesignLog("🔗 Sharing stopped")
        redesignLog("🔗 User stopped sharing")
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
                        .frame(minHeight: 140, maxHeight: .infinity) // Flexible height for iPad
                    } else {
                        // Empty cell for days outside current month
                        Rectangle()
                            .fill(Color.clear)
                            .frame(minHeight: 120, maxHeight: .infinity)
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
        .frame(minHeight: 140, maxHeight: .infinity) // iPad-optimized flexible height
        .background(Color(.systemBackground))
        .overlay(
            Rectangle()
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
        .onAppear {
            loadScheduleData()
        }
        .onChange(of: schedule) { _, _ in
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
    
    @State private var lastKnownText = ""
    @FocusState private var isFocused: Bool
    
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
                .frame(minWidth: 35, maxWidth: 35, alignment: .leading)
            
            TextField("", text: $text)
                .font(.system(size: 14))
                .foregroundColor(.black)
                .textFieldStyle(PlainTextFieldStyle())
                .autocapitalization(.allCharacters)
                .focused($isFocused)
                .onSubmit {
                    onCommit(text.uppercased())
                }
                .onChange(of: text) { _, newValue in
                    let uppercased = newValue.uppercased()
                    if text != uppercased {
                        text = uppercased
                    }
                    // Call onCommit when text actually changes from user input
                    // Skip if this is just the initial load (lastKnownText will be empty)
                    if !lastKnownText.isEmpty || isFocused {
                        onCommit(uppercased)
                    }
                    lastKnownText = uppercased
                }
                .onAppear {
                    lastKnownText = text
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
    @State private var initialized: Bool = false
    @State private var line1LastKnown: String = ""
    @State private var line2LastKnown: String = ""
    @FocusState private var line1Focused: Bool
    @FocusState private var line2Focused: Bool
    
    private var monthName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: month)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            VStack(spacing: 2) {
                // Blue field (Line 1)
                HStack(spacing: 8) {
                    Text("Line 1:")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.blue)
                        .frame(minWidth: 60, maxWidth: 60, alignment: .leading)
                    
                    TextField("", text: $line1Text)
                        .font(.system(size: 14))
                        .foregroundColor(.black)
                        .textFieldStyle(PlainTextFieldStyle())
                        .autocapitalization(.allCharacters)
                        .focused($line1Focused)
                        .padding(4)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                        )
                        .onSubmit {
                            onLine1Change(line1Text.uppercased())
                        }
                        .onChange(of: line1Text) { _, newValue in
                            let uppercased = newValue.uppercased()
                            if line1Text != uppercased {
                                line1Text = uppercased
                            }
                            // Real-time change detection like daily schedule fields
                            if !line1LastKnown.isEmpty || line1Focused {
                                onLine1Change(uppercased)
                            }
                            line1LastKnown = uppercased
                        }
                }
                
                // Red field (Line 2)
                HStack(spacing: 8) {
                    Text("Line 2:")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.red)
                        .frame(minWidth: 60, maxWidth: 60, alignment: .leading)
                    
                    TextField("", text: $line2Text)
                        .font(.system(size: 14))
                        .foregroundColor(.black)
                        .textFieldStyle(PlainTextFieldStyle())
                        .autocapitalization(.allCharacters)
                        .focused($line2Focused)
                        .padding(4)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.red.opacity(0.3), lineWidth: 1)
                        )
                        .onSubmit {
                            onLine2Change(line2Text.uppercased())
                        }
                        .onChange(of: line2Text) { _, newValue in
                            let uppercased = newValue.uppercased()
                            if line2Text != uppercased {
                                line2Text = uppercased
                            }
                            // Real-time change detection like daily schedule fields
                            if !line2LastKnown.isEmpty || line2Focused {
                                onLine2Change(uppercased)
                            }
                            line2LastKnown = uppercased
                        }
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color(.systemBackground))
        .cornerRadius(8)
        .shadow(color: Color.black.opacity(0.05), radius: 1, x: 0, y: 1)
        .onAppear {
            if !initialized {
                line1Text = line1
                line2Text = line2
                line1LastKnown = line1
                line2LastKnown = line2
                initialized = true
            }
        }
        .onChange(of: month) { _, _ in
            // Reset when month changes
            line1Text = line1
            line2Text = line2
            line1LastKnown = line1
            line2LastKnown = line2
        }
        .onChange(of: line1) { _, newValue in
            // Update display when data changes from external source
            if initialized && newValue != line1Text {
                line1Text = newValue
            }
        }
        .onChange(of: line2) { _, newValue in
            // Update display when data changes from external source
            if initialized && newValue != line2Text {
                line2Text = newValue
            }
        }
    }
}

// MARK: - Monthly Notes Container
struct MonthlyNotesContainer: View {
    let currentMonth: Date
    @ObservedObject var viewModel: ScheduleViewModel
    let monthKey: String
    
    var body: some View {
        let note = viewModel.monthlyNotes[monthKey]
        
        RedesignedMonthlyNotesView(
            month: currentMonth,
            line1: note?.line1 ?? "",
            line2: note?.line2 ?? "",
            onLine1Change: { newLine1 in
                viewModel.updateMonthlyNotesLine1(for: currentMonth, line1: newLine1)
            },
            onLine2Change: { newLine2 in
                viewModel.updateMonthlyNotesLine2(for: currentMonth, line2: newLine2)
            }
        )
        .padding(.horizontal, 20)
        .padding(.top, 4)
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
    ContentView()
}
