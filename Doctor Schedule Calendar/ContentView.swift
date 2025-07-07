//
//  ContentView.swift
//  Doctor Schedule Calendar
//
//  Created by mark on 7/5/25.
//

import SwiftUI
import CoreData

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    
    // Fetch all providers
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Provider.name, ascending: true)],
        animation: .default)
    private var providers: FetchedResults<Provider>
    
    // Fetch all locations
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Location.name, ascending: true)],
        animation: .default)
    private var locations: FetchedResults<Location>
    
    @State private var currentMonth = Date()
    @State private var isAdminMode = true // For now, default to admin mode
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Month navigation header
                monthNavigationHeader
                
                // Calendar view
                CalendarMonthView(
                    currentMonth: currentMonth,
                    providers: providers,
                    locations: locations,
                    isAdminMode: isAdminMode
                )
                .environment(\.managedObjectContext, viewContext)
                
                Spacer()
            }
            .navigationTitle("Provider Schedule")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(isAdminMode ? "Admin Mode" : "View Mode") {
                        isAdminMode.toggle()
                    }
                    .foregroundColor(isAdminMode ? .red : .blue)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink("Manage") {
                        ManagementView()
                            .environment(\.managedObjectContext, viewContext)
                    }
                }
            }
        }
    }
    
    private var monthNavigationHeader: some View {
        HStack {
            Button(action: previousMonth) {
                Image(systemName: "chevron.left")
                    .font(.title2)
            }
            .disabled(!canGoPreviousMonth)
            
            Spacer()
            
            VStack {
                Text(monthYearFormatter.string(from: currentMonth))
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("3-Month Forward View")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: nextMonth) {
                Image(systemName: "chevron.right")
                    .font(.title2)
            }
            .disabled(!canGoNextMonth)
        }
        .padding()
    }
    
    private var monthYearFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }
    
    private var canGoPreviousMonth: Bool {
        let calendar = Calendar.current
        let thisMonth = calendar.startOfDay(for: Date())
        let displayMonth = calendar.startOfDay(for: currentMonth)
        return displayMonth > thisMonth
    }
    
    private var canGoNextMonth: Bool {
        let calendar = Calendar.current
        let futureLimit = calendar.date(byAdding: .month, value: 3, to: Date()) ?? Date()
        return currentMonth < futureLimit
    }
    
    private func previousMonth() {
        let calendar = Calendar.current
        if let newMonth = calendar.date(byAdding: .month, value: -1, to: currentMonth) {
            currentMonth = newMonth
        }
    }
    
    private func nextMonth() {
        let calendar = Calendar.current
        if let newMonth = calendar.date(byAdding: .month, value: 1, to: currentMonth) {
            currentMonth = newMonth
        }
    }
}

struct CalendarMonthView: View {
    let currentMonth: Date
    let providers: FetchedResults<Provider>
    let locations: FetchedResults<Location>
    let isAdminMode: Bool
    
    @Environment(\.managedObjectContext) private var viewContext
    
    // Fetch monthly notes for current month
    @FetchRequest var monthlyNotes: FetchedResults<MonthlyNotes>
    
    // Fetch daily schedules for current month
    @FetchRequest var dailySchedules: FetchedResults<DailySchedule>
    
    init(currentMonth: Date, providers: FetchedResults<Provider>, locations: FetchedResults<Location>, isAdminMode: Bool) {
        self.currentMonth = currentMonth
        self.providers = providers
        self.locations = locations
        self.isAdminMode = isAdminMode
        
        let calendar = Calendar.current
        let month = calendar.component(.month, from: currentMonth)
        let year = calendar.component(.year, from: currentMonth)
        
        // Fetch monthly notes for this month/year
        _monthlyNotes = FetchRequest<MonthlyNotes>(
            sortDescriptors: [],
            predicate: NSPredicate(format: "month == %d AND year == %d", month, year)
        )
        
        // Fetch daily schedules for this month
        let startOfMonth = calendar.dateInterval(of: .month, for: currentMonth)?.start ?? currentMonth
        let endOfMonth = calendar.dateInterval(of: .month, for: currentMonth)?.end ?? currentMonth
        
        _dailySchedules = FetchRequest<DailySchedule>(
            sortDescriptors: [NSSortDescriptor(keyPath: \DailySchedule.date, ascending: true)],
            predicate: NSPredicate(format: "date >= %@ AND date < %@", startOfMonth as NSDate, endOfMonth as NSDate)
        )
    }
    
    var body: some View {
        VStack(spacing: 8) {
            // Monthly notes section (3 editable lines at top-left)
            monthlyNotesSection
            
            // Days of week header
            daysOfWeekHeader
            
            // Calendar grid
            calendarGrid
        }
        .padding()
    }
    
    private var monthlyNotesSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(1...3, id: \.self) { lineNumber in
                    MonthlyNoteLineView(
                        monthlyNotes: monthlyNotes.first,
                        lineNumber: lineNumber,
                        isAdminMode: isAdminMode,
                        currentMonth: currentMonth
                    )
                    .environment(\.managedObjectContext, viewContext)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer()
        }
        .padding(.bottom, 16)
    }
    
    private var daysOfWeekHeader: some View {
        HStack {
            ForEach(Calendar.current.shortWeekdaySymbols, id: \.self) { day in
                Text(day)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
        }
    }
    
    private var calendarGrid: some View {
        let calendar = Calendar.current
        let monthInterval = calendar.dateInterval(of: .month, for: currentMonth)
        let monthFirstWeekday = calendar.component(.weekday, from: monthInterval?.start ?? currentMonth)
        let daysInMonth = calendar.range(of: .day, in: .month, for: currentMonth)?.count ?? 30
        
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 7), spacing: 1) {
            // Empty cells for days before month starts
            ForEach(1..<monthFirstWeekday, id: \.self) { _ in
                Rectangle()
                    .fill(Color.clear)
                    .frame(height: 80)
            }
            
            // Days of the month
            ForEach(1...daysInMonth, id: \.self) { day in
                if let date = calendar.date(byAdding: .day, value: day - 1, to: monthInterval?.start ?? currentMonth) {
                    DayScheduleView(
                        date: date,
                        schedule: dailySchedules.first { Calendar.current.isDate($0.date ?? Date(), inSameDayAs: date) },
                        providers: providers,
                        locations: locations,
                        isAdminMode: isAdminMode
                    )
                    .environment(\.managedObjectContext, viewContext)
                }
            }
        }
    }
}

struct MonthlyNoteLineView: View {
    let monthlyNotes: MonthlyNotes?
    let lineNumber: Int
    let isAdminMode: Bool
    let currentMonth: Date
    
    @Environment(\.managedObjectContext) private var viewContext
    @State private var text: String = ""
    @State private var isEditing = false
    
    var body: some View {
        if isAdminMode {
            TextField("Monthly note line \(lineNumber)", text: $text, onCommit: saveChanges)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .font(.caption)
        } else {
            Text(text.isEmpty ? "—" : text)
                .font(.caption)
                .foregroundColor(text.isEmpty ? .secondary : .primary)
        }
    }
    
    private func saveChanges() {
        let calendar = Calendar.current
        let month = calendar.component(.month, from: currentMonth)
        let year = calendar.component(.year, from: currentMonth)
        
        let notes = monthlyNotes ?? {
            let newNotes = MonthlyNotes(context: viewContext)
            newNotes.id = UUID()
            newNotes.month = Int16(month)
            newNotes.year = Int16(year)
            return newNotes
        }()
        
        switch lineNumber {
        case 1: notes.line1 = text
        case 2: notes.line2 = text
        case 3: notes.line3 = text
        default: break
        }
        
        do {
            try viewContext.save()
        } catch {
            print("Error saving monthly notes: \(error)")
        }
    }
    
    private func loadText() {
        guard let notes = monthlyNotes else { return }
        switch lineNumber {
        case 1: text = notes.line1 ?? ""
        case 2: text = notes.line2 ?? ""
        case 3: text = notes.line3 ?? ""
        default: break
        }
    }
    
    init(monthlyNotes: MonthlyNotes?, lineNumber: Int, isAdminMode: Bool, currentMonth: Date) {
        self.monthlyNotes = monthlyNotes
        self.lineNumber = lineNumber
        self.isAdminMode = isAdminMode
        self.currentMonth = currentMonth
        
        let initialText: String
        switch lineNumber {
        case 1: initialText = monthlyNotes?.line1 ?? ""
        case 2: initialText = monthlyNotes?.line2 ?? ""
        case 3: initialText = monthlyNotes?.line3 ?? ""
        default: initialText = ""
        }
        _text = State(initialValue: initialText)
    }
}

struct DayScheduleView: View {
    let date: Date
    let schedule: DailySchedule?
    let providers: FetchedResults<Provider>
    let locations: FetchedResults<Location>
    let isAdminMode: Bool
    
    @Environment(\.managedObjectContext) private var viewContext
    
    private var dayFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter
    }
    
    private var weekdayFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        return formatter
    }
    
    private var isToday: Bool {
        Calendar.current.isDate(date, inSameDayAs: Date())
    }
    
    private var isPastDate: Bool {
        date < Calendar.current.startOfDay(for: Date())
    }
    
    var body: some View {
        VStack(spacing: 2) {
            // Day number and weekday
            VStack(spacing: 0) {
                Text(dayFormatter.string(from: date))
                    .font(.headline)
                    .fontWeight(isToday ? .bold : .medium)
                    .foregroundColor(isToday ? .white : (isPastDate ? .secondary : .primary))
                
                Text(weekdayFormatter.string(from: date))
                    .font(.caption2)
                    .foregroundColor(isToday ? .white : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(isToday ? Color.blue : Color.clear)
            .cornerRadius(4)
            
            // Three editable lines for scheduling
            VStack(spacing: 1) {
                ForEach(1...3, id: \.self) { lineNumber in
                    DayScheduleLineView(
                        schedule: schedule,
                        lineNumber: lineNumber,
                        isAdminMode: isAdminMode,
                        date: date,
                        providers: providers,
                        locations: locations
                    )
                    .environment(\.managedObjectContext, viewContext)
                }
            }
        }
        .padding(4)
        .frame(height: 80)
        .background(Color(.systemGray6))
        .cornerRadius(4)
        .opacity(isPastDate ? 0.5 : 1.0)
    }
}

struct DayScheduleLineView: View {
    let schedule: DailySchedule?
    let lineNumber: Int
    let isAdminMode: Bool
    let date: Date
    let providers: FetchedResults<Provider>
    let locations: FetchedResults<Location>
    
    @Environment(\.managedObjectContext) private var viewContext
    @State private var text: String = ""
    
    var body: some View {
        if isAdminMode {
            TextField("", text: $text, onCommit: saveChanges)
                .font(.caption2)
                .textFieldStyle(PlainTextFieldStyle())
                .frame(height: 16)
        } else {
            Text(text.isEmpty ? "—" : text)
                .font(.caption2)
                .foregroundColor(text.isEmpty ? .secondary : .primary)
                .frame(height: 16)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    private func saveChanges() {
        let dailySchedule = schedule ?? {
            let newSchedule = DailySchedule(context: viewContext)
            newSchedule.id = UUID()
            newSchedule.date = date
            return newSchedule
        }()
        
        switch lineNumber {
        case 1: dailySchedule.line1 = text
        case 2: dailySchedule.line2 = text
        case 3: dailySchedule.line3 = text
        default: break
        }
        
        do {
            try viewContext.save()
        } catch {
            print("Error saving daily schedule: \(error)")
        }
    }
    
    init(schedule: DailySchedule?, lineNumber: Int, isAdminMode: Bool, date: Date, providers: FetchedResults<Provider>, locations: FetchedResults<Location>) {
        self.schedule = schedule
        self.lineNumber = lineNumber
        self.isAdminMode = isAdminMode
        self.date = date
        self.providers = providers
        self.locations = locations
        
        let initialText: String
        switch lineNumber {
        case 1: initialText = schedule?.line1 ?? ""
        case 2: initialText = schedule?.line2 ?? ""
        case 3: initialText = schedule?.line3 ?? ""
        default: initialText = ""
        }
        _text = State(initialValue: initialText)
    }
}

struct ManagementView: View {
    @Environment(\.managedObjectContext) private var viewContext
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Provider.name, ascending: true)],
        animation: .default)
    private var providers: FetchedResults<Provider>
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Location.name, ascending: true)],
        animation: .default)
    private var locations: FetchedResults<Location>
    
    var body: some View {
        List {
            Section("Providers (\(providers.count)/9)") {
                ForEach(providers) { provider in
                    VStack(alignment: .leading) {
                        Text(provider.name ?? "Unknown")
                            .font(.headline)
                        Text(provider.specialty ?? "No specialty")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Section("Locations (\(locations.count)/2)") {
                ForEach(locations) { location in
                    VStack(alignment: .leading) {
                        Text(location.name ?? "Unknown")
                            .font(.headline)
                        if let address = location.address {
                            Text(address)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Manage")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    ContentView().environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
