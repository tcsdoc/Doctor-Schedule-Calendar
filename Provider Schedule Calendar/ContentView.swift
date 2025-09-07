//
//  ContentView.swift
//  Provider Schedule Calendar
//
//  Clean CloudKit Implementation with Custom Zones for Privacy
//

import SwiftUI
import CloudKit
import LinkPresentation



// MARK: - Next Day Navigation (Preserved from Original)
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
    private let calendar = Calendar.current
    
    var body: some View {
        NavigationView {
            VStack {
                headerSection
                
                // Show CloudKit status messages
                if !cloudKitManager.cloudKitAvailable {
                    Text(cloudKitManager.errorMessage ?? "CloudKit not available")
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding(.horizontal)
                        .multilineTextAlignment(.center)
                }
                
                if cloudKitManager.isLoading {
                    ProgressView("Loading calendar data...")
                        .padding()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 20) {
                            ForEach(monthsToShow, id: \.self) { month in
                                MonthView(month: month)
                            }
                        }
                        .padding(.vertical, 16)
                        .padding(.horizontal, 8)
                    }
                }
            }
            .onAppear {
                cloudKitManager.fetchAllData()
            }
            .refreshable {
                // CRITICAL: Never refresh if any field is being edited - protects precision codes
                let isAnyFieldActive = cloudKitManager.isAnyFieldBeingEdited
                if !isAnyFieldActive {
                    debugLog("🔄 Manual refresh - safe to proceed")
                    cloudKitManager.fetchAllData()
                } else {
                    debugLog("🛡️ BLOCKED manual refresh - field being edited")
                }
            }
        }
        .navigationViewStyle(.stack)
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 10) {
            Text("PROVIDER SCHEDULE")
                .font(.title)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity)
            
            HStack {
                Spacer()
                
                HStack(spacing: 15) {
                    // Share calendar button (CloudKit custom zones with privacy)
                    if cloudKitManager.cloudKitAvailable {
                        Button(action: shareSchedule) {
                            Image(systemName: "person.2.badge.plus")
                                .font(.title2)
                                .foregroundColor(.green)
                        }
                    }
                    
                    Button(action: {
                        printAllMonths()
                    }) {
                        Image(systemName: "printer")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }
                    
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
        var months: [Date] = []
        
        for i in 0..<12 {
            if let month = calendar.date(byAdding: .month, value: i, to: currentDate) {
                months.append(month)
            }
        }
        
        return months
    }
    
    // MARK: - CloudKit Custom Zone Sharing (Privacy-Focused)
    private func shareSchedule() {
        #if DEBUG
        debugLog("🔗 Creating custom zone share for privacy-focused sharing")
        #endif
        
        cloudKitManager.createCustomZoneShare { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let share):
                    self.presentCloudKitSharingController(for: share)
                case .failure(let error):
                    debugLog("❌ Failed to create share: \(error.localizedDescription)")
                    
                    let alert = UIAlertController(
                        title: "Sharing Error",
                        message: "Failed to create share: \(error.localizedDescription)",
                        preferredStyle: .alert
                    )
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let rootViewController = windowScene.windows.first?.rootViewController {
                        rootViewController.present(alert, animated: true)
                    }
                }
            }
        }
    }
    
    private func presentCloudKitSharingController(for share: CKShare) {
        guard let shareURL = share.url else {
            debugLog("❌ No share URL available")
            showAlert(title: "Sharing Error", message: "Unable to generate sharing link. Please try again.")
            return
        }
        
        // Present sharing options with the URL
        let shareText = """
        You're invited to view my Provider Schedule Calendar.
        
        Open this link on your iOS device:
        
        \(shareURL.absoluteString)
        """
        
        // Create a custom activity item source for email subject
        let customActivityItem = ShareActivityItemSource(
            shareText: shareText,
            shareURL: shareURL,
            subject: "Provider Schedule Calendar Access Link"
        )
        
        let activityViewController = UIActivityViewController(
            activityItems: [customActivityItem],
            applicationActivities: nil
        )
        
        // Configure for iPad
        if let popover = activityViewController.popoverPresentationController {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first {
                popover.sourceView = window
                popover.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
        }
        
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            debugLog("❌ Could not find root view controller")
            return
        }
        
        rootViewController.present(activityViewController, animated: true)
        
        debugLog("✅ Sharing link generated: \(shareURL.absoluteString)")
    }
    
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(alert, animated: true)
        }
    }
    
    // MARK: - Print Functions (Preserved)
    private func printAllMonths() {
        let printController = UIPrintInteractionController.shared
        let printInfo = UIPrintInfo.printInfo()
        
        printInfo.outputType = .general
        printInfo.jobName = "Provider Schedule - 12 Months"
        printInfo.orientation = .portrait
        
        printController.printInfo = printInfo
        printController.showsNumberOfCopies = true
        
        // Create printable content
        let htmlContent = generateFullYearHTML()
        let formatter = UIMarkupTextPrintFormatter(markupText: htmlContent)
        formatter.perPageContentInsets = UIEdgeInsets(top: 30, left: 30, bottom: 30, right: 30)
        
        printController.printFormatter = formatter
        
        // Present print dialog
        printController.present(animated: true) { (controller, completed, error) in
            // Print job handled
        }
    }
    
    private func generateFullYearHTML() -> String {
        var fullHTML = """
        <!DOCTYPE html>
        <html>
        <head>
            <style>
                body { font-family: Arial, sans-serif; margin: 0; padding: 0; }
                .page { page-break-after: always; padding: 20px; height: 100vh; box-sizing: border-box; }
                .page:last-child { page-break-after: avoid; }
                .header { text-align: center; margin-bottom: 15px; }
                .title { font-size: 24px; font-weight: bold; margin-bottom: 8px; }
                .month-title { font-size: 18px; font-weight: bold; margin-bottom: 15px; }
                .notes { margin-bottom: 15px; padding: 8px; background-color: #f0f0f0; font-size: 12px; }
                .calendar { width: 100%; border-collapse: collapse; margin-bottom: 15px; }
                .calendar th, .calendar td { border: 1.5px solid #000; padding: 4px; vertical-align: top; }
                .calendar th { background-color: #e0e0e0; text-align: center; height: 25px; font-size: 12px; font-weight: bold; }
                .calendar td { height: 80px; width: 14.28%; }
                .day-number { font-weight: bold; font-size: 12px; margin-bottom: 3px; }
                .schedule-line { font-size: 9px; margin: 1px 0; line-height: 1.2; }
                @page { margin: 0.5in; }
            </style>
        </head>
        <body>
        """
        
        // Generate each month as a separate page
        for month in monthsToShow {
            let monthFormatter = DateFormatter()
            monthFormatter.dateFormat = "MMMM yyyy"
            
            let monthlyNotes = getMonthlyNotes(for: month)
            let dailySchedules = getDailySchedules(for: month)
            
            fullHTML += """
            <div class="page">
                <div class="header">
                    <div class="title">PROVIDER SCHEDULE</div>
                    <div class="month-title">\(monthFormatter.string(from: month))</div>
                </div>
            """
            
            // Add monthly notes if they exist
            if !monthlyNotes.isEmpty {
                fullHTML += "<div class=\"notes\"><strong>Notes:</strong><br>"
                for note in monthlyNotes {
                    if !note.isEmpty {
                        fullHTML += "• \(note)<br>"
                    }
                }
                fullHTML += "</div>"
            }
            
            // Add calendar table
            fullHTML += "<table class=\"calendar\">"
            
            // Days of week header
            fullHTML += "<tr>"
            for day in calendar.shortWeekdaySymbols {
                fullHTML += "<th>\(day)</th>"
            }
            fullHTML += "</tr>"
            
            // Get properly aligned calendar grid
            let calendarDays = getCalendarDaysWithAlignment(for: month)
            let weeks = calendarDays.chunked(into: 7)
            
            for week in weeks {
                fullHTML += "<tr>"
                for date in week {
                    if calendar.isDate(date, equalTo: month, toGranularity: .month) {
                        let dayNumber = calendar.component(.day, from: date)
                        let schedule = dailySchedules[date] ?? ["", "", ""]
                        
                        fullHTML += "<td>"
                        fullHTML += "<div class=\"day-number\">\(dayNumber)</div>"
                        fullHTML += "<div class=\"schedule-line\"><strong>OS:</strong> \(schedule[0])</div>"
                        fullHTML += "<div class=\"schedule-line\"><strong>CL:</strong> \(schedule[1])</div>"
                        fullHTML += "<div class=\"schedule-line\"><strong>OFF:</strong> \(schedule[2])</div>"
                        fullHTML += "</td>"
                    } else {
                        fullHTML += "<td></td>"
                    }
                }
                fullHTML += "</tr>"
            }
            
            fullHTML += "</table></div>"
        }
        
        fullHTML += "</body></html>"
        return fullHTML
    }
    
    private func getCalendarDaysWithAlignment(for month: Date) -> [Date] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: month) else {
            return []
        }
        
        let startOfMonth = monthInterval.start
        guard let firstWeekday = calendar.dateInterval(of: .weekOfYear, for: startOfMonth)?.start else {
            return []
        }
        
        var days: [Date] = []
        var currentDate = firstWeekday
        
        for _ in 0..<42 {
            days.append(currentDate)
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }
        
        return days
    }
    
    private func getMonthlyNotes(for month: Date) -> [String] {
        let monthComp = calendar.component(.month, from: month)
        let yearComp = calendar.component(.year, from: month)
        
        let note = cloudKitManager.monthlyNotes.first { note in
            note.month == monthComp && note.year == yearComp
        }
        
        return [note?.line1 ?? "", note?.line2 ?? "", note?.line3 ?? ""].filter { !$0.isEmpty }
    }
    
    private func getDailySchedules(for month: Date) -> [Date: [String]] {
        var schedules: [Date: [String]] = [:]
        
        let monthStart = calendar.dateInterval(of: .month, for: month)?.start ?? month
        let monthEnd = calendar.dateInterval(of: .month, for: month)?.end ?? month
        
        for schedule in cloudKitManager.dailySchedules {
            guard let date = schedule.date,
                  date >= monthStart && date < monthEnd else { continue }
            
            let dayStart = calendar.startOfDay(for: date)
            schedules[dayStart] = [
                schedule.line1 ?? "",
                schedule.line2 ?? "",
                schedule.line3 ?? ""
            ]
        }
        
        return schedules
    }
}

// MARK: - MonthView (Clean CloudKitManager Version)
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
        VStack(alignment: .leading, spacing: 15) {
            monthHeader
            notesSection
            daysOfWeekHeader
            calendarGrid
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .shadow(color: Color.gray.opacity(0.2), radius: 4, x: 0, y: 2)
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
    }
    
    private var daysOfWeekHeader: some View {
        HStack {
            ForEach(Calendar.current.shortWeekdaySymbols, id: \.self) { day in
                Text(day)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(8)
    }
    
    private var calendarGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
            ForEach(daysInMonth, id: \.self) { date in
                if calendar.isDate(date, equalTo: month, toGranularity: .month) {
                    DayCell(date: date, schedule: scheduleForDate(date))
                } else {
                    Rectangle()
                        .fill(Color.clear)
                        .frame(minHeight: 120)
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
        
        for _ in 0..<42 {
            days.append(currentDate)
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }
        
        return days
    }
    
    private func scheduleForDate(_ date: Date) -> DailyScheduleRecord? {
        let dayStart = calendar.startOfDay(for: date)
        return cloudKitManager.dailySchedules.first { schedule in
            guard let scheduleDate = schedule.date else { return false }
            return calendar.isDate(scheduleDate, inSameDayAs: dayStart)
        }
    }
}

// MARK: - DayCell (CloudKitManager Version)
struct DayCell: View {
    let date: Date
    let schedule: DailyScheduleRecord?
    
    @EnvironmentObject private var cloudKitManager: CloudKitManager
    @State private var line1: String = ""
    @State private var line2: String = ""
    @State private var line3: String = ""
    @FocusState private var focusedField: DayField?
    
    private let calendar = Calendar.current
    
    enum DayField: CaseIterable {
        case line1, line2, line3
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            dayNumber
            scheduleFields
                .padding(.horizontal, 2)
                .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .background(background)
        .onAppear {
            loadScheduleData()
        }
        .onChange(of: schedule) { _, _ in
            // Only reload data if user is not actively editing
            if focusedField == nil {
                loadScheduleData()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .moveToNextDay)) { notification in
            if let request = notification.object as? NextDayFocusRequest {
                handleNextDayFocusRequest(request)
            }
        }
    }
    
    private var dayNumber: some View {
        HStack {
            Text("\(calendar.component(.day, from: date))")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.primary)
                .padding(.leading, 6)
                .padding(.top, 4)
            Spacer()
        }
    }
    
    private var scheduleFields: some View {
        VStack(spacing: 2) {
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
        HStack(spacing: 2) {
            Text(prefix)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 22, alignment: .leading)
            TextField("", text: text)
                .font(.system(size: 11, weight: .medium))
                .frame(maxWidth: .infinity, minHeight: 24)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .lineLimit(1)
                .truncationMode(.tail)
                .background(color.opacity(0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(color.opacity(0.4), lineWidth: 1.0)
                )
                .focused($focusedField, equals: field)
                .onChange(of: focusedField) { oldField, newField in
                    let sessionId = "\(date)_\(field)"
                    
                    // Register/unregister editing sessions for global protection
                    if oldField != field && newField == field {
                        // Gained focus - start protecting
                        cloudKitManager.startEditingSession(for: sessionId)
                    } else if oldField == field && newField != field {
                        // Lost focus - stop protecting and save
                        cloudKitManager.endEditingSession(for: sessionId)
                        debugLog("🔄 Field completed via focus change")
                        saveToCloudKit()
                    }
                }
                .submitLabel(submitLabel)
                .textInputAutocapitalization(.characters)
                .disableAutocorrection(true)
                .autocorrectionDisabled(true)
                .onSubmit {
                    debugLog("🔄 Return pressed - moving to next field (save on focus loss)")
                    onSubmit() // Just move to next field, save happens on focus change
                }
                .onChange(of: text.wrappedValue) { oldValue, newValue in
                    let uppercaseValue = newValue.uppercased()
                    if uppercaseValue != newValue {
                        text.wrappedValue = uppercaseValue
                    }
                    handleTextChange(newValue: uppercaseValue, binding: text)
                }
        }
    }
    
    private var background: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color(.systemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary, lineWidth: 2.0)
            )
            .shadow(color: Color.gray.opacity(0.3), radius: 2, x: 1, y: 1)
    }
    
    private func handleTextChange(newValue: String, binding: Binding<String>) {
        if newValue.count > 16 {
            binding.wrappedValue = String(newValue.prefix(16))
            return
        }
        
        // DON'T save during typing - wait for user to finish editing
        // saveToCloudKit() will be called when focus changes or form is submitted
    }
    
    private func moveToNextField() {
        debugLog("➡️ Moving to next field")
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
        debugLog("✅ Completed all fields for this day")
        saveToCloudKit() // Save the current day's data first!
        moveToNextDayFirstField()
    }
    
    private func moveToNextDayFirstField() {
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: date) else {
            focusedField = .line1
            return
        }
        
        focusedField = nil
        let request = NextDayFocusRequest(fromDate: date, targetDate: nextDay)
        NotificationCenter.default.post(name: .moveToNextDay, object: request)
    }
    
    private func handleNextDayFocusRequest(_ request: NextDayFocusRequest) {
        let targetDayStart = calendar.startOfDay(for: request.targetDate)
        let currentDayStart = calendar.startOfDay(for: date)
        
        if calendar.isDate(currentDayStart, inSameDayAs: targetDayStart) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.focusedField = .line1
            }
        }
    }
    
    private func loadScheduleData() {
        if let schedule = schedule {
            line1 = (schedule.line1 ?? "").uppercased()
            line2 = (schedule.line2 ?? "").uppercased()
            line3 = (schedule.line3 ?? "").uppercased()
        } else {
            line1 = ""
            line2 = ""
            line3 = ""
        }
    }
    
    private func saveToCloudKit() {
        let dayStart = calendar.startOfDay(for: date)
        let line1Value = line1.isEmpty ? nil : line1
        let line2Value = line2.isEmpty ? nil : line2
        let line3Value = line3.isEmpty ? nil : line3
        
        debugLog("💾 Saving \(dayStart): [\(line1Value ?? ""), \(line2Value ?? ""), \(line3Value ?? "")]")
        
        // Use CloudKitManager's smart save/delete method with zone information
        let existingRecordName = schedule?.id
        let existingZoneID = schedule?.zoneID
        cloudKitManager.saveOrDeleteDailySchedule(
            existingRecordName: existingRecordName,
            existingZoneID: existingZoneID,
            date: dayStart,
            line1: line1Value,
            line2: line2Value,
            line3: line3Value
        ) { success, error in
            if let error = error {
                debugLog("❌ Save failed: \(error.localizedDescription)")
            } else {
                debugLog("✅ Save completed")
            }
        }
    }
}

// MARK: - MonthlyNotesView (CloudKitManager Version)
struct MonthlyNotesView: View {
    let month: Date
    @EnvironmentObject private var cloudKitManager: CloudKitManager
    @State private var line1: String = ""
    @State private var line2: String = ""
    @State private var line3: String = ""
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
            loadNotesData()
        }
        .onChange(of: cloudKitManager.monthlyNotes) { _, _ in
            // Only reload data if user is not actively editing
            if focusedField == nil {
                loadNotesData()
            }
        }
    }
    
    private func noteTextField(text: Binding<String>, placeholder: String, field: MonthlyNotesField) -> some View {
        TextField(placeholder, text: text)
            .font(.caption)
            .foregroundColor(.black)
            .padding(4)
            .background(Color.white)
            .cornerRadius(4)
            .focused($focusedField, equals: field)
            .submitLabel(.done)
            .textInputAutocapitalization(.characters)
            .disableAutocorrection(true)
            .autocorrectionDisabled(true)
            .onChange(of: focusedField) { oldField, newField in
                // Save when focus leaves this field
                if oldField == field && newField != field {
                    debugLog("💾 Monthly field completed via focus change")
                    saveToCloudKit()
                }
            }
            .onChange(of: text.wrappedValue) { oldValue, newValue in
                let uppercaseValue = newValue.uppercased()
                let limitedValue = String(uppercaseValue.prefix(60))
                if limitedValue != newValue {
                    text.wrappedValue = limitedValue
                }
                // DON'T save during typing - wait for user to finish editing
            }
            .onSubmit {
                debugLog("💾 Saving monthly notes")
                saveToCloudKit()
            }
    }
    
    private func loadNotesData() {
        let monthComp = calendar.component(.month, from: month)
        let yearComp = calendar.component(.year, from: month)
        
        let note = cloudKitManager.monthlyNotes.first { note in
            note.month == monthComp && note.year == yearComp
        }
        
        line1 = (note?.line1 ?? "").uppercased()
        line2 = (note?.line2 ?? "").uppercased()
        line3 = (note?.line3 ?? "").uppercased()
    }
    
    private func saveToCloudKit() {
        let monthComp = calendar.component(.month, from: month)
        let yearComp = calendar.component(.year, from: month)
        
        // Find existing record ID for this month/year
        let existingRecord = cloudKitManager.monthlyNotes.first { note in
            note.month == monthComp && note.year == yearComp
        }
        
        // Use CloudKitManager's smart save/delete method for monthly notes
        cloudKitManager.saveOrDeleteMonthlyNotes(
            existingRecordName: existingRecord?.id,
            month: monthComp,
            year: yearComp,
            line1: line1.isEmpty ? nil : line1,
            line2: line2.isEmpty ? nil : line2,
            line3: line3.isEmpty ? nil : line3
        ) { success, error in
            if let error = error {
                debugLog("❌ Failed to save monthly notes: \(error.localizedDescription)")
            } else {
                debugLog("✅ Successfully saved monthly notes for \(monthComp)/\(yearComp)")
            }
        }
    }
}

// MARK: - Array Extension for Chunking
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

// MARK: - Share Activity Item Source for Custom Email Subject
class ShareActivityItemSource: NSObject, UIActivityItemSource {
    private let shareText: String
    private let shareURL: URL
    private let subject: String
    
    init(shareText: String, shareURL: URL, subject: String) {
        self.shareText = shareText
        self.shareURL = shareURL
        self.subject = subject
        super.init()
    }
    
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return shareText
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        return shareText
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        return subject
    }
}

// MARK: - Preview
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(CloudKitManager.shared)
    }
}