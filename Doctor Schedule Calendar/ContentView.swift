//
//  ContentView.swift
//  Doctor Schedule Calendar
//
//  Core Data + CloudKit Implementation
//

import SwiftUI
import CoreData
import CloudKit

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
                print("🔄 User triggered refresh - Core Data handles automatically")
                try? await Task.sleep(nanoseconds: 500_000_000)
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
                    // Share button for admins
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
    
    // MARK: - Sharing Methods

    private func shareSchedule() {
        // For now, create a sample schedule to share
        let context = viewContext

        // Create a sample schedule if none exists
        let sampleSchedule = DailySchedule(context: context)
        sampleSchedule.date = Date()
        sampleSchedule.line1 = "Sample Schedule"

        do {
            try context.save()

            // Create share for this schedule
            coreDataManager.createShare(for: sampleSchedule) { result in
                switch result {
                case .success(let share):
                    DispatchQueue.main.async {
                        self.presentSharingController(for: share)
                    }
                case .failure(let error):
                    print("❌ Failed to create share: \(error)")
                }
            }
        } catch {
            print("❌ Failed to save sample schedule: \(error)")
        }
    }

    private func presentSharingController(for share: CKShare) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            return
        }

        coreDataManager.presentSharingController(for: share, from: rootViewController)
    }

    // MARK: - Print Functions (simplified)

    private func printAllMonths() {
        print("📄 Print functionality - simplified for Core Data")
        // TODO: Implement Core Data version of printing
    }
}

// MARK: - MonthView
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
        VStack(alignment: .leading, spacing: 15) {
            monthHeader
            notesSection
            daysOfWeekHeader
            calendarGrid
            LegendView()
        }
        .padding(16)
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
        MonthlyNotesView(month: month, monthlyNotes: monthlyNotes.first)
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

// MARK: - DayCell (Clean Core Data Implementation!)
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
    
    private var dayNumber: some View {
        HStack {
            Text("\(calendar.component(.day, from: date))")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(isToday ? .white : .primary)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }
    
    private var isToday: Bool {
        calendar.isDate(date, inSameDayAs: Date())
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
            .fill(isToday ? Color.blue : Color(.systemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary, lineWidth: 2.0)
            )
            .shadow(color: Color.gray.opacity(0.3), radius: 2, x: 1, y: 1)
    }
    
    // MARK: - Core Data Operations (Simple & Clean!)
    
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
}

// MARK: - MonthlyNotesView (Clean Core Data Implementation!)
struct MonthlyNotesView: View {
    let month: Date
    let monthlyNotes: MonthlyNotes?
    
    @Environment(\.managedObjectContext) private var viewContext
    @State private var line1: String = ""
    @State private var line2: String = ""
    @State private var line3: String = ""
    @FocusState private var focusedField: MonthlyNotesField?
    
    private let calendar = Calendar.current
    
    enum MonthlyNotesField: CaseIterable {
        case line1, line2, line3
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Notes:")
                .font(.caption)
                .fontWeight(.semibold)
            
            VStack(spacing: 2) {
                TextField("Note 1", text: $line1)
                    .font(.system(size: 10))
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .focused($focusedField, equals: .line1)
                    .onChange(of: line1) { _, _ in updateNotes() }
                
                TextField("Note 2", text: $line2)
                    .font(.system(size: 10))
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .focused($focusedField, equals: .line2)
                    .onChange(of: line2) { _, _ in updateNotes() }
                
                TextField("Note 3", text: $line3)
                    .font(.system(size: 10))
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .focused($focusedField, equals: .line3)
                    .onChange(of: line3) { _, _ in updateNotes() }
            }
        }
        .padding(8)
        .background(Color.blue.opacity(0.1))
        .cornerRadius(6)
        .onAppear {
            loadNotesData()
        }
        .onChange(of: monthlyNotes) { _, _ in
            loadNotesData()
        }
    }
    
    // MARK: - Core Data Operations (Simple & Clean!)
    
    private func loadNotesData() {
        if let notes = monthlyNotes {
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

// MARK: - Preview
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(CoreDataCloudKitManager.shared)
    }
}
