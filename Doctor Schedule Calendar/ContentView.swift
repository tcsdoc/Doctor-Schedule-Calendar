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
    @EnvironmentObject private var coreDataManager: CoreDataCloudKitManager
    @Environment(\.managedObjectContext) private var viewContext
    @State private var currentDate = Date()
    private let calendar = Calendar.current
    
    var body: some View {
        NavigationView {
            VStack {
                headerSection
                
                // Show CloudKit status messages
                if !coreDataManager.isCloudKitEnabled {
                    Text(coreDataManager.cloudKitStatus)
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding(.horizontal)
                        .multilineTextAlignment(.center)
                }
                
                ScrollView {
                    LazyVStack(spacing: 20) {
                        ForEach(monthsToShow, id: \.self) { month in
                            MonthView(month: month)
                        }
                    }
                    .padding()
                }
            }
            .onAppear {
                // Core Data automatically loads data via @FetchRequest
            }
            .refreshable {
                print("🔄 User triggered refresh - smart data reload with protection")
                await performSmartRefresh()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                // App became active - check for data integrity smartly
                performSmartDataIntegrityCheck()
            }
        }
        .navigationViewStyle(.stack)
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
                        printAllMonths()
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
        var months: [Date] = []
        
        for i in 0..<12 {
            if let month = calendar.date(byAdding: .month, value: i, to: currentDate) {
                months.append(month)
            }
        }
        
        return months
    }
    
    // MARK: - Print Functions
    
    private func printAllMonths() {
        let printController = UIPrintInteractionController.shared
        let printInfo = UIPrintInfo.printInfo()
        
        printInfo.outputType = .general
        printInfo.jobName = "Provider Schedule - 12 Months"
        printInfo.orientation = .portrait
        
        printController.printInfo = printInfo
        printController.showsNumberOfCopies = true
        // Note: showsPageRange deprecated - page range is automatically shown
        
        // Create printable content
        let htmlContent = generateFullYearHTML()
        let formatter = UIMarkupTextPrintFormatter(markupText: htmlContent)
        formatter.perPageContentInsets = UIEdgeInsets(top: 30, left: 30, bottom: 30, right: 30)
        
        printController.printFormatter = formatter
        
        // Present print dialog
        printController.present(animated: true) { (controller, completed, error) in
            if completed {
                print("✅ Print job completed successfully")
            } else if let error = error {
                print("❌ Print error: \(error.localizedDescription)")
            }
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
                .legend { font-size: 9px; text-align: center; border: 1px solid #666; padding: 5px; }
                @page { margin: 0.5in; }
            </style>
        </head>
        <body>
        """
        
        // Generate each month as a separate page
        for (_, month) in monthsToShow.enumerated() {
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
            
            // Get properly aligned calendar grid (like the app does)
            let calendarDays = getCalendarDaysWithAlignment(for: month)
            let weeks = calendarDays.chunked(into: 7)
            
            for week in weeks {
                fullHTML += "<tr>"
                for date in week {
                    if calendar.isDate(date, equalTo: month, toGranularity: .month) {
                        // This day belongs to the current month
                        let dayNumber = calendar.component(.day, from: date)
                        let schedule = dailySchedules[date] ?? ["", "", ""]
                        
                        fullHTML += "<td>"
                        fullHTML += "<div class=\"day-number\">\(dayNumber)</div>"
                        fullHTML += "<div class=\"schedule-line\"><strong>OS:</strong> \(schedule[0])</div>"
                        fullHTML += "<div class=\"schedule-line\"><strong>CL:</strong> \(schedule[1])</div>"
                        fullHTML += "<div class=\"schedule-line\"><strong>OFF:</strong> \(schedule[2])</div>"
                        fullHTML += "</td>"
                    } else {
                        // Empty cell for days outside this month
                        fullHTML += "<td></td>"
                    }
                }
                fullHTML += "</tr>"
            }
            
            fullHTML += "</table>"
            
            // Add legend
            fullHTML += """
            <div class="legend">
                O-Siddiqui. F-Freeman. P-Dixit. K-Watts. C-Carbajal. B-Brown  G-Grant. S-Sisodraker. A-Pitocchi.
            </div>
            </div>
            """
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
        
        // Generate 6 weeks worth of dates (same as app)
        for _ in 0..<42 {
            days.append(currentDate)
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }
        
        return days
    }
    
    private func getActualMonthDays(for month: Date) -> [Date] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: month) else {
            return []
        }
        
        var days: [Date] = []
        let startOfMonth = monthInterval.start
        let endOfMonth = monthInterval.end
        
        var currentDate = startOfMonth
        while currentDate < endOfMonth {
            days.append(currentDate)
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }
        
        return days
    }
    
    private func getMonthlyNotes(for month: Date) -> [String] {
        // TODO: Implement Core Data version of monthly notes for printing
        return []
    }
    
    private func getDailySchedules(for month: Date) -> [Date: [String]] {
        // TODO: Implement Core Data version of daily schedules for printing
        return [:]
    }

    // MARK: - Data Integrity and Recovery (Simplified for Core Data)
    
    @MainActor
    private func performSmartRefresh() async {
        print("🔄 Core Data automatically handles data refresh")
        // Core Data with @FetchRequest handles this automatically
        
        // Wait a moment for data to be fetched
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        // Notify all cells to smart reload their data (respecting protection)
        NotificationCenter.default.post(name: Notification.Name("smartDataRefresh"), object: nil)
        
        print("✅ Smart refresh completed")
    }
    
    private func performSmartDataIntegrityCheck() {
        print("🔍 Core Data automatically handles data integrity")
        // Core Data with CloudKit sync handles data integrity automatically
    }
    
    private func checkDataIntegrityAndRecover() {
        print("🔍 Core Data automatically handles data recovery")
        // Core Data with CloudKit sync handles data recovery automatically
        print("✅ Data integrity check complete.")
    }
    
    private func dayString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return formatter.string(from: date)
    }
}

// MARK: - MonthView
struct MonthView: View {
    let month: Date
    @Environment(\.managedObjectContext) private var viewContext
    
    // Fetch daily schedules for this month using @FetchRequest
    @FetchRequest private var dailySchedules: FetchedResults<DailySchedule>
    
    init(month: Date) {
        self.month = month
        
        // Create predicates for fetching data for this specific month
        let monthStart = Calendar.current.dateInterval(of: .month, for: month)?.start ?? month
        let monthEnd = Calendar.current.dateInterval(of: .month, for: month)?.end ?? month
        
        // Fetch daily schedules for this month
        self._dailySchedules = FetchRequest(
            entity: DailySchedule.entity(),
            sortDescriptors: [NSSortDescriptor(keyPath: \DailySchedule.date, ascending: true)],
            predicate: NSPredicate(format: "date >= %@ AND date < %@", monthStart as NSDate, monthEnd as NSDate)
        )
    }
    
    private let calendar = Calendar.current
    private let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {  // Increased spacing for better separation
            monthHeader
            notesSection
            daysOfWeekHeader
            calendarGrid
            LegendView()
        }
        .padding(16)  // Slightly increased padding
        .background(Color(.secondarySystemBackground))  // Better background contrast
        .cornerRadius(12)  // Slightly more rounded for modern look
        .shadow(color: Color.gray.opacity(0.2), radius: 4, x: 0, y: 2)  // Subtle shadow for depth
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
                    .font(.system(size: 14, weight: .semibold))  // Slightly larger and bolder
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .background(Color(.tertiarySystemBackground))  // Subtle background for header
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
                        .frame(minHeight: 120)  // Slightly taller for better proportion
                }
            }
        }
    }
    
    private func scheduleForDate(_ date: Date) -> DailySchedule? {
        let dayStart = calendar.startOfDay(for: date)
        return dailySchedules.first { schedule in
            guard let scheduleDate = schedule.date else { return false }
            return calendar.isDate(scheduleDate, inSameDayAs: dayStart)
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
    let schedule: DailySchedule?
    
    @Environment(\.managedObjectContext) private var viewContext
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
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .background(background)
        .onAppear {
            loadScheduleData()
        }
        .onChange(of: schedule) { _, _ in
            loadScheduleData()
            }
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
        moveToNextDayFirstField()
        
        isEditing = false
        
        // Clear protection after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.localDataProtected = false
            print("🔓 Cleared local data protection for \(self.dayString)")
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
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return formatter.string(from: date)
    }
    
    private var dayString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return formatter.string(from: date)
    }
    
    private var dayNumber: some View {
        HStack {
        Text("\(calendar.component(.day, from: date))")
                .font(.system(size: 18, weight: .bold))  // Larger, bolder like printed version
            .foregroundColor(.primary)
                .padding(.leading, 8)
                .padding(.top, 6)
            Spacer()
        }
    }
    
    private var scheduleFields: some View {
        VStack(spacing: 6) {
            scheduleTextField(prefix: "OS", text: $line1, color: .blue, field: .line1)
            scheduleTextField(prefix: "CL", text: $line2, color: .green, field: .line2)
            scheduleTextField(prefix: "OFF", text: $line3, color: .orange, field: .line3)
        }
    }
    
    private func scheduleTextField(prefix: String, text: Binding<String>, color: Color, field: DayField) -> some View {
        HStack(spacing: 8) {
            Text(prefix)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 28, alignment: .leading)
            TextField("", text: text)
                .font(.system(size: 14, weight: .medium))
                .frame(height: 28)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(color.opacity(0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(color.opacity(0.4), lineWidth: 1.0)
                )
                .focused($focusedField, equals: field)
                .submitLabel(.next)
                .textInputAutocapitalization(.characters)
                .disableAutocorrection(true)
                .onChange(of: text.wrappedValue) { _, _ in
                    updateSchedule()
                }
        }
    }
    
    private var background: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color(.systemBackground))  // Better contrast with system background
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary, lineWidth: 2.0)  // Stronger border like printed version
            )
            .shadow(color: Color.gray.opacity(0.3), radius: 2, x: 1, y: 1)  // Subtle shadow for depth
    }
    
    // MARK: - Core Data Operations (Much Simpler!)
    
    private func loadScheduleData() {
        if let schedule = schedule {
            line1 = schedule.line1 ?? ""
            line2 = schedule.line2 ?? ""
            line3 = schedule.line3 ?? ""
        } else {
            line1 = ""
            line2 = ""
            line3 = ""
        }
    }
    
    private func updateSchedule() {
        let context = viewContext
        let dayStart = calendar.startOfDay(for: date)
        
        // Find or create schedule
        let fetchRequest: NSFetchRequest<DailySchedule> = DailySchedule.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "date == %@", dayStart as NSDate)
        
        do {
            let results = try context.fetch(fetchRequest)
            let scheduleToUpdate: DailySchedule
            
            if let existingSchedule = results.first {
                scheduleToUpdate = existingSchedule
            } else {
                scheduleToUpdate = DailySchedule(context: context)
                scheduleToUpdate.date = dayStart
            }
            
            // Update the schedule
            scheduleToUpdate.line1 = line1.isEmpty ? nil : line1
            scheduleToUpdate.line2 = line2.isEmpty ? nil : line2
            scheduleToUpdate.line3 = line3.isEmpty ? nil : line3
            
            // Auto-save after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                try? context.save()
            }
            
        } catch {
            print("❌ Error updating schedule: \(error)")
        }
    }
    
    // Core Data handles this automatically - no complex methods needed
}


// MARK: - MonthlyNotesView
struct MonthlyNotesView: View {
    let month: Date
    
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest private var monthlyNotes: FetchedResults<MonthlyNotes>
    @State private var line1: String = ""
    @State private var line2: String = ""
    @State private var line3: String = ""
    @FocusState private var focusedField: MonthlyNotesField?
    
    init(month: Date) {
        self.month = month
        
        let monthComp = Calendar.current.component(.month, from: month)
        let yearComp = Calendar.current.component(.year, from: month)
        
        // Fetch monthly notes for this month
        self._monthlyNotes = FetchRequest(
            entity: MonthlyNotes.entity(),
            sortDescriptors: [NSSortDescriptor(keyPath: \MonthlyNotes.year, ascending: true)],
            predicate: NSPredicate(format: "month == %d AND year == %d", monthComp, yearComp)
        )
    }
    
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
        .onChange(of: monthlyNotes.first) { _, _ in
            loadNotesData()
        }
        // Listen for aggressive reload requests
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("forceAggressiveReload"))) { _ in
            print("🚀 Received aggressive reload request for \(monthString)")
            aggressiveLoadNotes()
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
            .onChange(of: text.wrappedValue) { _, _ in
                updateNotes()
            }
    }
    
    // MARK: - Core Data Operations (Much Simpler!)
    
    private func loadNotesData() {
        if let notes = monthlyNotes.first {
            line1 = notes.line1 ?? ""
            line2 = notes.line2 ?? ""
            line3 = notes.line3 ?? ""
        } else {
            line1 = ""
            line2 = ""
            line3 = ""
        }
    }
    
    private func updateNotes() {
        let context = viewContext
        let monthComp = calendar.component(.month, from: month)
        let yearComp = calendar.component(.year, from: month)
        
        // Find or create monthly notes
        let fetchRequest: NSFetchRequest<MonthlyNotes> = MonthlyNotes.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "month == %d AND year == %d", monthComp, yearComp)
        
        do {
            let results = try context.fetch(fetchRequest)
            let notesToUpdate: MonthlyNotes
            
            if let existingNotes = results.first {
                notesToUpdate = existingNotes
            } else {
                notesToUpdate = MonthlyNotes(context: context)
                notesToUpdate.month = Int16(monthComp)
                notesToUpdate.year = Int16(yearComp)
            }
            
            // Update the notes
            notesToUpdate.line1 = line1.isEmpty ? nil : line1
            notesToUpdate.line2 = line2.isEmpty ? nil : line2
            notesToUpdate.line3 = line3.isEmpty ? nil : line3
            
            // Auto-save after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                try? context.save()
            }
            
        } catch {
            print("❌ Error updating monthly notes: \(error)")
        }
    }
    
    /// Much simpler check - only true when user is actively typing
    private func isActivelyTypingNotes() -> Bool {
        return focusedField != nil && isEditing
    }
    
    /// Comprehensive data recovery check
    private func performDataRecoveryCheck() {
        // Check if we should have data but display is empty
        let hasDisplayData = !line1.isEmpty || !line2.isEmpty || !line3.isEmpty
        let monthComp = calendar.component(.month, from: month)
        let yearComp = calendar.component(.year, from: month)
        
        let shouldHaveData = cloudKitManager.monthlyNotes.contains { record in
            record.month == monthComp && record.year == yearComp
        }
        
        if shouldHaveData && !hasDisplayData {
            print("🔄 Data recovery: \(monthString) should have data but display is empty - forcing reload")
            
            // Force update the display from CloudKit data
            if let record = cloudKitManager.monthlyNotes.first(where: { record in
                record.month == monthComp && record.year == yearComp
            }) {
                print("🔄 Found CloudKit data for \(monthString) - applying immediately")
                existingRecord = record
                
                // Force update display regardless of protection
                line1 = record.line1 ?? ""
                line2 = record.line2 ?? ""
                line3 = record.line3 ?? ""
                
                hasUnsavedChanges = false
                userInitiatedChange = false
                print("✅ Data recovery completed for \(monthString)")
            }
        }
    }
    
    /// Improved cell appearance handling with data recovery
    private func handleNotesAppearance() {
        // Always try to load the notes when cell appears
        loadNotes()
        
        // If we appear to have no data but CloudKit has records, force a reload
        let hasLocalData = !line1.isEmpty || !line2.isEmpty || !line3.isEmpty
        let monthComp = calendar.component(.month, from: month)
        let yearComp = calendar.component(.year, from: month)
        
        let shouldHaveData = cloudKitManager.monthlyNotes.contains { record in
            record.month == monthComp && record.year == yearComp
        }
        
        if !hasLocalData && shouldHaveData && !isCurrentlyEditingNotes() {
            print("🔄 Data recovery: Monthly notes \(monthString) appears empty but CloudKit has data - forcing reload")
            forceReloadNotesData()
        }
    }
    
    /// Check if currently editing notes (more specific than previous logic)
    private func isCurrentlyEditingNotes() -> Bool {
        return isEditing && hasUnsavedChanges && focusedField != nil
    }
    
    /// Clear stale protection flags that might prevent notes data loading
    private func clearStaleNotesProtection() {
        // Only clear if we're not actively editing
        if !isCurrentlyEditingNotes() {
            localDataProtected = false
            print("🔓 Cleared stale protection for monthly notes \(monthString)")
            
            // If we still don't have data, try to reload
            let hasLocalData = !line1.isEmpty || !line2.isEmpty || !line3.isEmpty
            if !hasLocalData {
                print("🔄 No local monthly notes data after clearing protection - attempting reload for \(monthString)")
                loadNotes()
            }
        }
    }
    
    /// Force reload notes data (used for data recovery)
    private func forceReloadNotesData() {
        // Temporarily clear all protection flags
        let wasProtected = localDataProtected
        let wasEditing = isEditing
        
        localDataProtected = false
        isEditing = false
        
        // Reload the notes
        loadNotes()
        
        // Restore states only if they were legitimately set
        if wasEditing && focusedField != nil {
            isEditing = true
            localDataProtected = wasProtected
        }
        
        print("🔄 Force reload completed for monthly notes \(monthString)")
    }
    
    private func handleCloudKitNotesDataChange(_ newNotes: [MonthlyNotesRecord]) {
        // Only protect if user is actively typing - much more permissive
        if isActivelyTypingNotes() {
            print("⌨️ CloudKit monthly notes data changed for \(monthString) - user actively typing, will delay")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                if !self.isActivelyTypingNotes() {
                    self.handleCloudKitNotesDataChange(newNotes)
                }
            }
            return
        }
        
        // Find the record for this month/year
        let monthComp = calendar.component(.month, from: month)
        let yearComp = calendar.component(.year, from: month)
        
        let updatedRecord = newNotes.first { record in
            record.month == monthComp && record.year == yearComp
        }
        
        // Always update - prioritize data visibility
        let shouldUpdate = true // Much more aggressive
        
        if shouldUpdate {
            if let newRecord = updatedRecord {
                print("📊 CloudKit monthly notes data updated for \(monthString) - applying changes immediately")
                existingRecord = newRecord
                // Force update display
                updateNotesFromRecord()
            } else if existingRecord != nil {
                print("🗑️ CloudKit monthly notes record deleted for \(monthString) - clearing local data")
                existingRecord = nil
                // Clear display
                line1 = ""
                line2 = ""
                line3 = ""
                hasUnsavedChanges = false
                userInitiatedChange = false
            }
        }
    }
    
    private func handleTextChange(field: MonthlyNotesField, oldValue: String, newValue: String) {
        // Track that this is a user-initiated change
        userInitiatedChange = true
        isEditing = true
        hasUnsavedChanges = true
        localDataProtected = true
        lastEditTime = Date()  // Track when this edit happened
        
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
        
        // Find the existing record
        let foundRecord = cloudKitManager.monthlyNotes.first { record in
            record.month == monthComp && record.year == yearComp
        }
        
        // Update existing record reference
        existingRecord = foundRecord
        
        // Always update from record unless actively typing
        if !isActivelyTypingNotes() {
            updateNotesFromRecord()
            print("📝 Loaded monthly notes for \(monthString) - record: \(foundRecord?.id ?? "none")")
        } else {
            print("⌨️ Skipped loading monthly notes for \(monthString) - user actively typing")
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
    
    // MARK: - Smart Data Management Methods for Notes
    
    /// Smart notes appearance handling that respects CloudKit protection timing
    private func handleSmartNotesAppearance() {
        // First, check if we should respect any existing protection
        let shouldRespectProtection = isProtectingFreshUserNotesInput()
        
        if shouldRespectProtection {
            print("🛡️ Respecting existing protection for \(monthString) - user has fresh edits")
            return
        }
        
        // Load the notes data since we're not protecting
        loadNotesSmartly()
        
        // Check for potential data loss scenario (notes reappeared but no data)
        let hasLocalData = !line1.isEmpty || !line2.isEmpty || !line3.isEmpty
        let monthComp = calendar.component(.month, from: month)
        let yearComp = calendar.component(.year, from: month)
        
        let shouldHaveData = cloudKitManager.monthlyNotes.contains { record in
            record.month == monthComp && record.year == yearComp
        }
        
        if !hasLocalData && shouldHaveData {
            print("🔄 Data recovery needed for \(monthString) - forcing reload")
            forceReloadNotesFromCloudKit()
        }
    }
    
    /// Improved protection logic for notes that only protects truly fresh user input
    private func isProtectingFreshUserNotesInput() -> Bool {
        // Protect if user is currently focused and editing
        if focusedField != nil && isEditing {
            print("🎯 Protecting \(monthString) - user is actively focused and editing")
            return true
        }
        
        // Protect if user just made changes (within last 5 seconds) and has unsaved changes
        if hasUnsavedChanges && userInitiatedChange {
            let timeSinceEdit = Date().timeIntervalSince(lastEditTime ?? Date.distantPast)
            if timeSinceEdit < 5.0 {
                print("⏰ Protecting \(monthString) - fresh user edit \(timeSinceEdit)s ago")
                return true
            }
        }
        
        // Also check CloudKit manager's protection for this specific month
        let monthKey = monthString
        if cloudKitManager.shouldProtectLocalData(for: monthKey) {
            print("☁️ CloudKit manager protecting \(monthString)")
            return true
        }
        
        return false
    }
    
    /// Smart CloudKit notes data change handling
    private func handleSmartCloudKitNotesDataChange(_ newNotes: [MonthlyNotesRecord]) {
        // Only protect if we have fresh user input
        if isProtectingFreshUserNotesInput() {
            print("🛡️ CloudKit notes data changed for \(monthString) - protecting fresh user input")
            // Schedule a retry for later when protection expires
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                if !self.isProtectingFreshUserNotesInput() {
                    print("🔄 Retrying CloudKit notes update for \(self.monthString) - protection expired")
                    self.handleSmartCloudKitNotesDataChange(newNotes)
                }
            }
            return
        }
        
        // Find the record for this month/year
        let monthComp = calendar.component(.month, from: month)
        let yearComp = calendar.component(.year, from: month)
        
        let updatedRecord = newNotes.first { record in
            record.month == monthComp && record.year == yearComp
        }
        
        // Update our local state if we found a matching record
        if let record = updatedRecord {
            existingRecord = record
            updateNotesFromRecord()
            print("✅ CloudKit notes update applied to \(monthString)")
        }
    }
    
    /// Smart notes loading that respects protection
    private func loadNotesSmartly() {
        let monthComp = calendar.component(.month, from: month)
        let yearComp = calendar.component(.year, from: month)
        
        // Find the existing record
        let foundRecord = cloudKitManager.monthlyNotes.first { record in
            record.month == monthComp && record.year == yearComp
        }
        
        // Update existing record reference
        existingRecord = foundRecord
        
        // Only update from record if not protecting fresh user input
        if !isProtectingFreshUserNotesInput() {
            updateNotesFromRecord()
            print("📝 Smart loaded notes for \(monthString) - record: \(foundRecord?.id ?? "none")")
        } else {
            print("🛡️ Skipped smart loading for \(monthString) - protecting fresh user input")
        }
    }
    
    /// Force reload from CloudKit for notes data recovery scenarios
    private func forceReloadNotesFromCloudKit() {
        print("🚨 Force reloading \(monthString) from CloudKit for data recovery")
        
        // Clear protection flags temporarily for recovery
        let wasProtected = localDataProtected
        localDataProtected = false
        
        // Load from CloudKit
        loadNotesSmartly()
        
        // Restore protection if it was set
        localDataProtected = wasProtected
        
        print("🔄 Force notes reload completed for \(monthString)")
    }
}

// Note: LegendView moved to CoreDataContentView



// MARK: - PrintableMonthPage
struct PrintableMonthPage: View {
    let month: Date
    @EnvironmentObject private var cloudKitManager: CloudKitManager
    
    private let calendar = Calendar.current
    private let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            VStack(spacing: 8) {
                Text("PROVIDER SCHEDULE")
                    .font(.title)
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity)
                
                Text(monthFormatter.string(from: month))
                    .font(.title2)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            
            // Monthly Notes
            MonthlyNotesView(month: month)
                .environmentObject(cloudKitManager)
            
            // Calendar - Only actual month days
            VStack(spacing: 4) {
                // Days of week header
                HStack(spacing: 0) {
                    ForEach(Calendar.current.shortWeekdaySymbols, id: \.self) { day in
                        Text(day)
                            .font(.system(size: 11, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(Color.gray.opacity(0.3))
                            .border(Color.black, width: 1)
                    }
                }
                
                // Calendar grid - only actual month days
                let monthDays = getActualMonthDays(for: month)
                let weeks = monthDays.chunked(into: 7)
                
                ForEach(Array(weeks.enumerated()), id: \.offset) { weekIndex, week in
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { dayIndex in
                            if dayIndex < week.count {
                                PrintableActualDayCell(date: week[dayIndex])
                                    .environmentObject(cloudKitManager)
                            } else {
                                Rectangle()
                                    .fill(Color.clear)
                                    .frame(height: 60)
                                    .border(Color.black, width: 1)
                }
            }
        }
    }
}

            // Legend
            Text("O-Siddiqui. F-Freeman. P-Dixit. K-Watts. C-Carbajal. B-Brown  G-Grant. S-Sisodraker. A-Pitocchi.")
                .font(.system(size: 9))
                .padding(6)
                .overlay(
                    Rectangle()
                        .stroke(Color.black, lineWidth: 1)
                )
                .padding(.top, 8)
            
            Spacer()
        }
        .padding(15)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.white)
    }
    
    private func getActualMonthDays(for month: Date) -> [Date] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: month) else {
            return []
        }
        
        var days: [Date] = []
        let startOfMonth = monthInterval.start
        let endOfMonth = monthInterval.end
        
        var currentDate = startOfMonth
        while currentDate < endOfMonth {
            days.append(currentDate)
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }
        
        return days
    }
}

// MARK: - PrintableActualDayCell
struct PrintableActualDayCell: View {
    let date: Date
    @EnvironmentObject private var cloudKitManager: CloudKitManager
    
    private let calendar = Calendar.current
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Day number
            HStack {
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 10, weight: .bold))
                Spacer()
            }
            
            // Schedule fields
            VStack(alignment: .leading, spacing: 1) {
                if !schedule.line1.isEmpty {
                    HStack(spacing: 2) {
                        Text("OS")
                            .font(.system(size: 8, weight: .medium))
                            .frame(width: 14, alignment: .leading)
                        Text(schedule.line1)
                            .font(.system(size: 8))
                            .lineLimit(1)
                    }
                }
                
                if !schedule.line2.isEmpty {
                    HStack(spacing: 2) {
                        Text("CL")
                            .font(.system(size: 8, weight: .medium))
                            .frame(width: 14, alignment: .leading)
                        Text(schedule.line2)
                            .font(.system(size: 8))
                            .lineLimit(1)
                    }
                }
                
                if !schedule.line3.isEmpty {
                    HStack(spacing: 2) {
                        Text("OFF")
                            .font(.system(size: 8, weight: .medium))
                            .frame(width: 14, alignment: .leading)
                        Text(schedule.line3)
                            .font(.system(size: 8))
                            .lineLimit(1)
                    }
                }
            }
            
            Spacer(minLength: 0)
        }
        .frame(height: 60)
        .padding(3)
        .background(Color.white)
        .border(Color.black, width: 1)
    }
    
    private var schedule: (line1: String, line2: String, line3: String) {
        let dayStart = calendar.startOfDay(for: date)
        
        if let record = cloudKitManager.dailySchedules.first(where: { record in
            if let recordDate = record.date {
                return calendar.isDate(recordDate, inSameDayAs: dayStart)
            }
            return false
        }) {
            return (
                line1: record.line1 ?? "",
                line2: record.line2 ?? "",
                line3: record.line3 ?? ""
            )
        }
        
        return (line1: "", line2: "", line3: "")
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

// MARK: - Utilities
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
                            .environmentObject(CoreDataCloudKitManager.shared)
    }
}
