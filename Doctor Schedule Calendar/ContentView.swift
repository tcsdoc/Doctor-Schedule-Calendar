//
//  ContentView.swift
//  Doctor Schedule Calendar
//
//  Core Data + CloudKit Implementation with Original UI Design
//

import SwiftUI
import CoreData
import CloudKit

// MARK: - Debug Logging Helper
private func debugLog(_ message: String) {
    #if DEBUG
    print(message)
    #endif
}

// MARK: - Next Day Navigation (Preserved from Original)
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
                    .padding(.vertical, 16)
                    .padding(.horizontal, 8)  // Reduced horizontal padding for more width
                }
            }
            .onAppear {
                // Core Data automatically loads data via @FetchRequest
            }
            .refreshable {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
        .navigationViewStyle(.stack)
    }
    
    // MARK: - Original Header Design
    private var headerSection: some View {
        VStack(spacing: 10) {
            Text("PROVIDER SCHEDULE")
                .font(.title)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity)
            
            HStack {
                Spacer()
                
                                    HStack(spacing: 15) {
                        // Share button for admins (Core Data implementation)
                        if coreDataManager.isCloudKitEnabled {
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
    
    // MARK: - Sharing Methods (Core Data Implementation)
    
    private func shareSchedule() {
        let context = viewContext
        
        // Fetch ALL schedules to share (this shares the entire calendar data)
        let fetchRequest: NSFetchRequest<DailySchedule> = DailySchedule.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \DailySchedule.date, ascending: true)]
        
        do {
            let existingSchedules = try context.fetch(fetchRequest)
            
            if existingSchedules.isEmpty {
                // Create schedules for the current year to enable comprehensive sharing
                createInitialScheduleForSharing()
            } else {
                // Share ALL existing schedules (this shares the entire calendar)
                shareAllSchedules(existingSchedules)
            }
        } catch {
            // Failed to fetch schedules
        }
    }
    
    private func createInitialScheduleForSharing() {
        let context = viewContext
        
        // Create schedules for the current month to enable sharing
        let calendar = Calendar.current
        let now = Date()
        
        guard let monthInterval = calendar.dateInterval(of: .month, for: now) else { return }
        
        var date = monthInterval.start
        let endDate = monthInterval.end
        
        var schedulesToShare: [DailySchedule] = []
        
        // Create empty schedules for the current month
        while date < endDate {
            let schedule = DailySchedule(context: context)
            schedule.date = calendar.startOfDay(for: date)
            // Leave lines empty - user can fill them in later
            schedulesToShare.append(schedule)
            
            date = calendar.date(byAdding: .day, value: 1, to: date) ?? endDate
        }
        
        do {
            try context.save()
            
            // Share the first schedule (this shares the entire zone)
            if let firstSchedule = schedulesToShare.first {
                shareExistingSchedule(firstSchedule)
            }
        } catch {
            // Failed to create initial schedules
        }
    }
    
    private func shareExistingSchedule(_ schedule: DailySchedule) {
        coreDataManager.createShare(for: schedule) { result in
            switch result {
            case .success(let share):
                DispatchQueue.main.async {
                    self.presentSharingController(for: share)
                }
            case .failure(_):
                // Failed to create share
                break
            }
        }
    }
    
    private func shareAllSchedules(_ schedules: [DailySchedule]) {
        // Check if we have any schedules to share
        guard !schedules.isEmpty else {
            return
        }
        
        coreDataManager.createComprehensiveShare(for: schedules) { result in
            switch result {
            case .success(let share):
                DispatchQueue.main.async {
                    self.presentSharingController(for: share)
                }
            case .failure(_):
                // Try simple share approach as fallback
                self.trySimpleShare()
            }
        }
    }
    
    private func trySimpleShare() {
        coreDataManager.createCloudKitShare { result in
            switch result {
            case .success(let share):
                DispatchQueue.main.async {
                    self.presentSharingController(for: share)
                }
            case .failure(_):
                // All sharing methods failed
                break
            }
        }
    }

    private func presentSharingController(for share: CKShare) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            return
        }

        coreDataManager.presentSharingController(for: share, from: rootViewController)
    }
    
    // MARK: - Original Print Functions (Preserved)
    
    private func printAllMonths() {
        let printController = UIPrintInteractionController.shared
        let printInfo = UIPrintInfo.printInfo()
        
        printInfo.outputType = .general
        printInfo.jobName = "Provider Schedule - 12 Months"
        printInfo.orientation = .portrait
        
        printController.printInfo = printInfo
        printController.showsNumberOfCopies = true
        // Note: showsPageRange was deprecated in iOS 10.0, but functionality still works
        
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
                .legend { font-size: 9px; text-align: center; border: 1px solid #666; padding: 5px; }
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
    
    private func getMonthlyNotes(for month: Date) -> [String] {
        let monthComp = calendar.component(.month, from: month)
        let yearComp = calendar.component(.year, from: month)
        
        // Core Data fetch for monthly notes
        let fetchRequest: NSFetchRequest<MonthlyNotes> = MonthlyNotes.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "month == %d AND year == %d", monthComp, yearComp)
        
        do {
            let results = try viewContext.fetch(fetchRequest)
            if let notes = results.first {
                return [notes.line1 ?? "", notes.line2 ?? "", notes.line3 ?? ""].filter { !$0.isEmpty }
            }
        } catch {
            // Error fetching monthly notes
        }
        
        return []
    }
    
    private func getDailySchedules(for month: Date) -> [Date: [String]] {
        var schedules: [Date: [String]] = [:]
        
        // Core Data fetch for daily schedules
        let monthStart = calendar.dateInterval(of: .month, for: month)?.start ?? month
        let monthEnd = calendar.dateInterval(of: .month, for: month)?.end ?? month
        
        let fetchRequest: NSFetchRequest<DailySchedule> = DailySchedule.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "date >= %@ AND date < %@", monthStart as NSDate, monthEnd as NSDate)
        
        do {
            let results = try viewContext.fetch(fetchRequest)
            for schedule in results {
                if let date = schedule.date {
                    let dayStart = calendar.startOfDay(for: date)
                    schedules[dayStart] = [
                        schedule.line1 ?? "",
                        schedule.line2 ?? "",
                        schedule.line3 ?? ""
                    ]
                }
            }
        } catch {
            // Error fetching daily schedules
        }
        
        return schedules
    }
}

// MARK: - MonthView (Original Visual Design with Core Data)
struct MonthView: View {
    let month: Date
    @Environment(\.managedObjectContext) private var viewContext
    
    // Fetch daily schedules for this month using @FetchRequest
    @FetchRequest private var dailySchedules: FetchedResults<DailySchedule>
    
    // Fetch monthly notes for this month
    @FetchRequest private var monthlyNotes: FetchedResults<MonthlyNotes>
    
    init(month: Date) {
        self.month = month
        
        // Create predicates for fetching data for this specific month
        let monthStart = Calendar.current.dateInterval(of: .month, for: month)?.start ?? month
        let monthEnd = Calendar.current.dateInterval(of: .month, for: month)?.end ?? month
        
        let monthComp = Calendar.current.component(.month, from: month)
        let yearComp = Calendar.current.component(.year, from: month)
        
        // Fetch daily schedules for this month
        self._dailySchedules = FetchRequest(
            entity: DailySchedule.entity(),
            sortDescriptors: [NSSortDescriptor(keyPath: \DailySchedule.date, ascending: true)],
            predicate: NSPredicate(format: "date >= %@ AND date < %@", monthStart as NSDate, monthEnd as NSDate)
        )
        
        // Fetch monthly notes for this month
        self._monthlyNotes = FetchRequest(
            entity: MonthlyNotes.entity(),
            sortDescriptors: [NSSortDescriptor(keyPath: \MonthlyNotes.year, ascending: true)],
            predicate: NSPredicate(format: "month == %d AND year == %d", monthComp, yearComp)
        )
    }
    
    private let calendar = Calendar.current
    private let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {  // Original spacing
            monthHeader
            notesSection
            daysOfWeekHeader
            calendarGrid
            LegendView()
        }
        .padding(12)  // Reduced padding to give more space for day cells
        .background(Color(.secondarySystemBackground))  // Original background
        .cornerRadius(12)  // Original corner radius
        .shadow(color: Color.gray.opacity(0.2), radius: 4, x: 0, y: 2)  // Original shadow
    }
    
    private var monthHeader: some View {
        Text(monthFormatter.string(from: month))
            .font(.title2)
            .fontWeight(.bold)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.bottom, 5)
    }
    
    private var notesSection: some View {
        MonthlyNotesView(month: month, monthlyNotes: monthlyNotes.first)
    }
    
    private var daysOfWeekHeader: some View {
        HStack {
            ForEach(Calendar.current.shortWeekdaySymbols, id: \.self) { day in
                Text(day)
                    .font(.system(size: 14, weight: .semibold))  // Original styling
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .background(Color(.tertiarySystemBackground))  // Original background
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
                        .frame(minHeight: 120)  // Original height
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
    
    private func scheduleForDate(_ date: Date) -> DailySchedule? {
        let dayStart = calendar.startOfDay(for: date)
        return dailySchedules.first { schedule in
            guard let scheduleDate = schedule.date else { return false }
            return calendar.isDate(scheduleDate, inSameDayAs: dayStart)
        }
    }
}

// MARK: - DayCell (Original Visual Design + Focus Management with Core Data)
struct DayCell: View {
    let date: Date
    let schedule: DailySchedule?
    
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var coreDataManager: CoreDataCloudKitManager
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
                .padding(.horizontal, 2)  // Minimal padding to maximize text field space
                .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity, minHeight: 120)  // Original height
        .background(background)
        .onAppear {
            loadScheduleData()
        }
        .onChange(of: schedule) { _, _ in
            loadScheduleData()
        }
        // Listen for next day navigation requests (preserved from original)
        .onReceive(NotificationCenter.default.publisher(for: .moveToNextDay)) { notification in
            if let request = notification.object as? NextDayFocusRequest {
                handleNextDayFocusRequest(request)
            }
        }
    }
    
    // MARK: - Original Visual Components
    
    private var dayNumber: some View {
        HStack {
            Text("\(calendar.component(.day, from: date))")
                .font(.system(size: 16, weight: .bold))  // Smaller to give more space to text fields
                .foregroundColor(.primary)
                .padding(.leading, 6)
                .padding(.top, 4)
            Spacer()
        }
    }
    
    private var scheduleFields: some View {
        VStack(spacing: 2) {  // Minimal spacing for maximum field space
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
        HStack(spacing: 2) {  // Minimal spacing to maximize text space
            Text(prefix)
                .font(.system(size: 10, weight: .medium))  // Smaller prefix font
                .foregroundColor(.secondary)
                .frame(width: 22, alignment: .leading)  // Smaller prefix width for more text space
            TextField("", text: text)
                .font(.system(size: 11, weight: .medium))  // Even smaller font for more characters
                .frame(maxWidth: .infinity, minHeight: 24)  // Smaller height to match font
                .padding(.horizontal, 4)  // Minimal padding for maximum text space
                .padding(.vertical, 1)
                .lineLimit(1)  // Ensure single line
                .truncationMode(.tail)  // Truncate with ... if needed
                .background(color.opacity(0.15))  // Original background
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(color.opacity(0.4), lineWidth: 1.0)  // Original border
                )
                .focused($focusedField, equals: field)
                .submitLabel(submitLabel)
                .textInputAutocapitalization(.characters)  // Force uppercase
                .disableAutocorrection(true)  // Disable autocorrect completely
                .autocorrectionDisabled(true)  // Additional autocorrect disabling for iOS 15+
                .onSubmit {
                    onSubmit()
                }
                .onChange(of: text.wrappedValue) { oldValue, newValue in
                    // Force uppercase transformation
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
            .fill(Color(.systemBackground))  // Original background
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary, lineWidth: 2.0)  // Original border
            )
            .shadow(color: Color.gray.opacity(0.3), radius: 2, x: 1, y: 1)  // Original shadow
    }
    
    // MARK: - Original Focus Management & Navigation
    
    private func handleTextChange(newValue: String, binding: Binding<String>) {
        // Limit to 16 characters (original behavior)
        if newValue.count > 16 {
            binding.wrappedValue = String(newValue.prefix(16))
            return
        }
        
        // Auto-save with Core Data (simplified from original)
        updateSchedule()
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
        // For better data entry workflow, try to move to next day's first field (original behavior)
        moveToNextDayFirstField()
    }
    
    private func moveToNextDayFirstField() {
        // Calculate the next day (original logic)
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: date) else {
            focusedField = .line1
            return
        }
        
        // Clear current focus to allow next day to take over
        focusedField = nil
        
        // Send notification to request focus on next day's first field (original behavior)
        let request = NextDayFocusRequest(fromDate: date, targetDate: nextDay)
        NotificationCenter.default.post(name: .moveToNextDay, object: request)
    }
    
    private func handleNextDayFocusRequest(_ request: NextDayFocusRequest) {
        let targetDayStart = calendar.startOfDay(for: request.targetDate)
        let currentDayStart = calendar.startOfDay(for: date)
        
        // Check if this cell's date matches the target date (original logic)
        if calendar.isDate(currentDayStart, inSameDayAs: targetDayStart) {
            // Small delay to ensure proper timing after previous day clears focus
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.focusedField = .line1
            }
        }
    }
    
    // MARK: - Core Data Operations (Simplified)
    
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
            
            // Auto-save after a short delay with proper logging
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                debugLog("💾 Triggering Core Data save for July \(calendar.component(.day, from: dayStart))")
                coreDataManager.save()
                // Private database auto-syncs to CloudKit - no explicit sharing needed for normal saves
            }
            
        } catch {
            debugLog("❌ Error updating schedule: \(error)")
        }
    }
}

// MARK: - MonthlyNotesView (Original Visual Design with Core Data)
struct MonthlyNotesView: View {
    let month: Date
    let monthlyNotes: MonthlyNotes?
    
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var coreDataManager: CoreDataCloudKitManager
    @State private var line1: String = ""
    @State private var line2: String = ""
    @State private var line3: String = ""
    @FocusState private var focusedField: MonthlyNotesField?
    
    private let calendar = Calendar.current
    
    enum MonthlyNotesField: CaseIterable {
        case line1, line2, line3
    }
    
    var body: some View {
        VStack(spacing: 4) {  // Original spacing
            HStack {
                Text("Notes:")
                    .font(.caption)
                    .fontWeight(.medium)  // Original styling
                Spacer()
            }
            
            VStack(spacing: 2) {  // Original spacing
                noteTextField(text: $line1, placeholder: "Note 1", field: .line1)
                noteTextField(text: $line2, placeholder: "Note 2", field: .line2)
                noteTextField(text: $line3, placeholder: "Note 3", field: .line3)
            }
        }
        .padding(8)  // Original padding
        .background(Color.blue.opacity(0.1))  // Original background
        .cornerRadius(6)  // Original corner radius
        .onAppear {
            loadNotesData()
        }
        .onChange(of: monthlyNotes) { _, _ in
            loadNotesData()
        }
    }
    
    private func noteTextField(text: Binding<String>, placeholder: String, field: MonthlyNotesField) -> some View {
        TextField(placeholder, text: text)
            .font(.caption)  // Original font
            .foregroundColor(.black)  // Ensure text is visible on white background
            .padding(4)  // Original padding
            .background(Color.white)  // Original background
            .cornerRadius(4)  // Original corner radius
            .focused($focusedField, equals: field)
            .submitLabel(.done)
            .textInputAutocapitalization(.characters)  // Force uppercase
            .disableAutocorrection(true)  // Disable autocorrect completely
            .autocorrectionDisabled(true)  // Additional autocorrect disabling for iOS 15+
            .onChange(of: text.wrappedValue) { oldValue, newValue in
                // Force uppercase transformation and character limit
                let uppercaseValue = newValue.uppercased()
                let limitedValue = String(uppercaseValue.prefix(60))
                if limitedValue != newValue {
                    text.wrappedValue = limitedValue
                }
                updateNotes()
            }
    }
    
    // MARK: - Core Data Operations (Simplified)
    
    private func loadNotesData() {
        if let notes = monthlyNotes {
            line1 = (notes.line1 ?? "").uppercased()
            line2 = (notes.line2 ?? "").uppercased()
            line3 = (notes.line3 ?? "").uppercased()
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
            
            // Auto-save after a short delay with proper logging
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                debugLog("💾 Triggering Core Data save for monthly notes \(monthComp)/\(yearComp)")
                coreDataManager.save()
            }
            
        } catch {
            debugLog("❌ Error updating monthly notes: \(error)")
        }
    }
}

// MARK: - LegendView (Original Design)
struct LegendView: View {
    var body: some View {
        Text("O-Siddiqui. F-Freeman. P-Dixit. K-Watts. C-Carbajal. B-Brown  G-Grant. S-Sisodraker. A-Pitocchi.")
            .font(.caption)  // Original font
            .padding(8)  // Original padding
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.gray, lineWidth: 1)  // Original border
            )
            .padding(.top, 5)  // Original padding
    }
}

// MARK: - Array Extension for Chunking (Original Utility)
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

// MARK: - Preview
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(CoreDataCloudKitManager.shared)
    }
}
