//
//  ContentView.swift
//  Doctor Schedule Calendar
//
//  Created by mark on 7/5/25.
//

import SwiftUI
import CoreData
import UIKit

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \DailySchedule.date, ascending: true)],
        animation: .default)
    private var dailySchedules: FetchedResults<DailySchedule>
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \MonthlyNotes.month, ascending: true)],
        animation: .default)
    private var monthlyNotes: FetchedResults<MonthlyNotes>
    
    @State private var currentDate = Date()
    
    var body: some View {
        NavigationView {
            VStack {
                VStack(spacing: 10) {
                    Text("PROVIDER SCHEDULE")
                        .font(.title)
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                    
                    HStack {
                        Spacer()
                        
                        HStack(spacing: 15) {
                            Button(action: {
                                printCalendar()
                            }) {
                                Image(systemName: "printer")
                                    .font(.title2)
                                    .foregroundColor(.blue)
                            }
                            
                            Text("Monthly Notes")
                                .font(.headline)
                            
                            Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown").\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown")")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                }
                .padding()
                
                ScrollView {
                    LazyVStack(spacing: 20) {
                        ForEach(months, id: \.self) { month in
                            MonthView(month: month, 
                                    dailySchedules: dailySchedules, 
                                    monthlyNotes: monthlyNotes,
                                    viewContext: viewContext)
                        }
                    }
                    .padding()
                }
            }
            .navigationBarHidden(true)
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
    
    private var months: [Date] {
        let calendar = Calendar.current
        let currentMonth = calendar.dateInterval(of: .month, for: currentDate)!.start
        
        return (0..<12).compactMap { offset in
            calendar.date(byAdding: .month, value: offset, to: currentMonth)
        }
    }
    
    private func printCalendar() {
        // Create a print info
        let printInfo = UIPrintInfo(dictionary: nil)
        printInfo.outputType = .general
        printInfo.jobName = "Provider Schedule Calendar"
        
        let printController = UIPrintInteractionController.shared
        printController.printInfo = printInfo
        
        // Create HTML content for printing
        let htmlContent = generateHTMLContent()
        let formatter = UIMarkupTextPrintFormatter(markupText: htmlContent)
        
        printController.printFormatter = formatter
        
        // Present the print dialog
        printController.present(animated: true) { controller, completed, error in
            if let error = error {
                print("Print error: \(error)")
            }
        }
    }
    
    private func generateHTMLContent() -> String {
        let calendar = Calendar.current
        let currentMonth = calendar.dateInterval(of: .month, for: currentDate)!.start
        let months = (0..<12).compactMap { offset in
            calendar.date(byAdding: .month, value: offset, to: currentMonth)
        }
        
        var html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <style>
                body { font-family: Arial, sans-serif; margin: 20px; }
                .title { font-size: 24px; font-weight: bold; text-align: center; margin-bottom: 30px; }
                .month { page-break-before: always; margin-bottom: 20px; }
                .month:first-child { page-break-before: avoid; }
                .month:last-child { page-break-after: avoid; }
                .month-title { font-size: 18px; font-weight: bold; margin-bottom: 10px; text-align: center; }
                .month-notes { margin-bottom: 15px; font-size: 12px; }
                .calendar { border-collapse: collapse; width: 100%; }
                .calendar th { border: 1px solid #000; padding: 8px; text-align: center; background-color: #f0f0f0; font-size: 12px; }
                .calendar td { border: 1px solid #000; padding: 5px; height: 60px; vertical-align: top; font-size: 10px; }
                .day-number { font-weight: bold; margin-bottom: 5px; }
                .schedule-line { margin: 2px 0; }
                @media print {
                    .month { page-break-before: always; }
                    .month:first-child { page-break-before: avoid; }
                    .month:last-child { page-break-after: avoid; }
                }
            </style>
        </head>
        <body>
        """
        
        for month in months {
            let monthFormatter = DateFormatter()
            monthFormatter.dateFormat = "MMMM yyyy"
            let monthString = monthFormatter.string(from: month)
            
            html += "<div class='month'>"
            html += "<div class='title'>PROVIDER SCHEDULE</div>"
            html += "<div class='month-title'>\(monthString)</div>"
            
            // Monthly notes
            let monthValue = Int32(calendar.component(.month, from: month))
            let yearValue = Int32(calendar.component(.year, from: month))
            if let notes = monthlyNotes.first(where: { $0.month == monthValue && $0.year == yearValue }) {
                html += "<div class='month-notes'>"
                if let line1 = notes.line1, !line1.isEmpty {
                    html += "• \(line1)<br>"
                }
                if let line2 = notes.line2, !line2.isEmpty {
                    html += "• \(line2)<br>"
                }
                if let line3 = notes.line3, !line3.isEmpty {
                    html += "• \(line3)<br>"
                }
                html += "</div>"
            }
            
            // Calendar table
            html += "<table class='calendar'>"
            html += "<tr><th>Sun</th><th>Mon</th><th>Tue</th><th>Wed</th><th>Thu</th><th>Fri</th><th>Sat</th></tr>"
            
            let daysInMonth = getDaysInMonth(for: month)
            var currentRow = 0
            
            for (index, date) in daysInMonth.enumerated() {
                let column = index % 7
                let row = index / 7
                
                if row != currentRow {
                    if currentRow > 0 {
                        html += "</tr>"
                    }
                    html += "<tr>"
                    currentRow = row
                }
                
                let dayNumber = calendar.component(.day, from: date)
                let dayStart = calendar.startOfDay(for: date)
                let schedule = dailySchedules.first { schedule in
                    guard let scheduleDate = schedule.date else { return false }
                    return calendar.isDate(scheduleDate, inSameDayAs: dayStart)
                }
                
                html += "<td>"
                html += "<div class='day-number'>\(dayNumber)</div>"
                
                if let schedule = schedule {
                    if let line1 = schedule.line1, !line1.isEmpty {
                        html += "<div class='schedule-line'>\(line1)</div>"
                    }
                    if let line2 = schedule.line2, !line2.isEmpty {
                        html += "<div class='schedule-line'>\(line2)</div>"
                    }
                    if let line3 = schedule.line3, !line3.isEmpty {
                        html += "<div class='schedule-line'>\(line3)</div>"
                    }
                }
                
                html += "</td>"
            }
            
            if currentRow >= 0 {
                html += "</tr>"
            }
            
            html += "</table>"
            html += "</div>"
        }
        
        html += "</body></html>"
        return html
    }
    
    private func getDaysInMonth(for month: Date) -> [Date] {
        let calendar = Calendar.current
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

struct MonthView: View {
    let month: Date
    let dailySchedules: FetchedResults<DailySchedule>
    let monthlyNotes: FetchedResults<MonthlyNotes>
    let viewContext: NSManagedObjectContext
    
    private let calendar = Calendar.current
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            monthHeader
            notesSection
            daysOfWeekHeader
            calendarGrid
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
        MonthlyNotesView(month: month, monthlyNotes: monthlyNotes, viewContext: viewContext)
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
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 0) {
            ForEach(daysInMonth, id: \.self) { date in
                if calendar.isDate(date, equalTo: month, toGranularity: .month) {
                    DayCell(date: date, 
                           dailySchedules: dailySchedules, 
                           viewContext: viewContext)
                } else {
                    Rectangle()
                        .fill(Color.clear)
                        .frame(minHeight: 250)
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

struct DayCell: View {
    let date: Date
    let dailySchedules: FetchedResults<DailySchedule>
    let viewContext: NSManagedObjectContext
    
    @State private var schedule: DailySchedule?
    
    // Per-day focus management with simple 3-state enum
    @FocusState private var focusedField: DayField?
    
    enum DayField {
        case line1, line2, line3
    }
    
    private let calendar = Calendar.current
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            dayNumber
            scheduleFields
        }
        .frame(maxWidth: .infinity, minHeight: 250)
        .background(background)
        .onAppear {
            loadSchedule()
        }
    }
    
    private var dayNumber: some View {
        Text("\(calendar.component(.day, from: date))")
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(calendar.isDate(date, inSameDayAs: Date()) ? .red : .primary)
            .padding(.bottom, 2)
    }
    
    private var scheduleFields: some View {
        VStack(spacing: 8) {
            scheduleTextField(
                prefix: "OS",
                text: Binding(
                    get: { schedule?.line1 ?? "" },
                    set: { newValue in
                        updateSchedule()
                        schedule?.line1 = newValue
                        saveContext()
                    }
                ),
                color: .blue,
                field: .line1,
                onSubmit: { focusedField = .line2 },
                onChange: { newValue in
                    if newValue.count > 16 {
                        schedule?.line1 = String(newValue.prefix(16))
                        saveContext()
                    }
                }
            )
            scheduleTextField(
                prefix: "CL",
                text: Binding(
                    get: { schedule?.line2 ?? "" },
                    set: { newValue in
                        updateSchedule()
                        schedule?.line2 = newValue
                        saveContext()
                    }
                ),
                color: .green,
                field: .line2,
                onSubmit: { focusedField = .line3 },
                onChange: { newValue in
                    if newValue.count > 16 {
                        schedule?.line2 = String(newValue.prefix(16))
                        saveContext()
                    }
                }
            )
            scheduleTextField(
                prefix: "OFF",
                text: Binding(
                    get: { schedule?.line3 ?? "" },
                    set: { newValue in
                        updateSchedule()
                        schedule?.line3 = newValue
                        saveContext()
                    }
                ),
                color: .orange,
                field: .line3,
                onSubmit: { focusedField = nil },
                onChange: { newValue in
                    if newValue.count > 16 {
                        schedule?.line3 = String(newValue.prefix(16))
                        saveContext()
                    }
                }
            )
        }
    }
    
    private func scheduleTextField(prefix: String, text: Binding<String>, color: Color, field: DayField, onSubmit: @escaping () -> Void, onChange: @escaping (String) -> Void) -> some View {
        HStack {
            Text(prefix)
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
                .onSubmit(onSubmit)
                .onChange(of: text.wrappedValue, perform: onChange)
        }
    }
    
    private var background: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(calendar.isDate(date, inSameDayAs: Date()) ? Color.red.opacity(0.1) : Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
            )
    }
    
    private func loadSchedule() {
        let dayStart = calendar.startOfDay(for: date)
        schedule = dailySchedules.first { schedule in
            guard let scheduleDate = schedule.date else { return false }
            return calendar.isDate(scheduleDate, inSameDayAs: dayStart)
        }
    }
    
    private func updateSchedule() {
        if schedule == nil {
            schedule = DailySchedule(context: viewContext)
            schedule?.date = calendar.startOfDay(for: date)
            schedule?.line1 = ""
            schedule?.line2 = ""
            schedule?.line3 = ""
        }
    }
    
    private func saveContext() {
        do {
            try viewContext.save()
        } catch {
            print("Error saving context: \(error)")
        }
    }
}

struct MonthlyNotesView: View {
    let month: Date
    let monthlyNotes: FetchedResults<MonthlyNotes>
    let viewContext: NSManagedObjectContext
    
    @State private var notes: MonthlyNotes?
    
    private let calendar = Calendar.current
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(0..<3, id: \.self) { index in
                TextField("Monthly note \(index + 1)", text: Binding(
                    get: {
                        switch index {
                        case 0: return notes?.line1 ?? ""
                        case 1: return notes?.line2 ?? ""
                        case 2: return notes?.line3 ?? ""
                        default: return ""
                        }
                    },
                    set: { newValue in
                        updateNotes()
                        switch index {
                        case 0: notes?.line1 = newValue
                        case 1: notes?.line2 = newValue
                        case 2: notes?.line3 = newValue
                        default: break
                        }
                        saveContext()
                    }
                ))
                .font(.system(size: 14))
                .frame(height: 32)
                .padding(6)
                .background(backgroundColor(for: index))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(borderColor(for: index), lineWidth: 1.5)
                )

            }
        }
        .onAppear {
            loadNotes()
        }
    }
    
    private func backgroundColor(for index: Int) -> Color {
        switch index {
        case 0: return Color.purple.opacity(0.1)
        case 1: return Color.pink.opacity(0.1)
        case 2: return Color.indigo.opacity(0.1)
        default: return Color.white
        }
    }
    
    private func borderColor(for index: Int) -> Color {
        switch index {
        case 0: return Color.purple.opacity(0.6)
        case 1: return Color.pink.opacity(0.6)
        case 2: return Color.indigo.opacity(0.6)
        default: return Color.gray.opacity(0.4)
        }
    }
    
    private func loadNotes() {
        let monthValue = Int32(calendar.component(.month, from: month))
        let yearValue = Int32(calendar.component(.year, from: month))
        notes = monthlyNotes.first { $0.month == monthValue && $0.year == yearValue }
    }
    
    private func updateNotes() {
        if notes == nil {
            notes = MonthlyNotes(context: viewContext)
            notes?.month = Int32(calendar.component(.month, from: month))
            notes?.year = Int32(calendar.component(.year, from: month))
            notes?.line1 = ""
            notes?.line2 = ""
            notes?.line3 = ""
        }
    }
    
    private func saveContext() {
        do {
            try viewContext.save()
        } catch {
            print("Error saving context: \(error)")
        }
    }
}

private let monthFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "MMMM yyyy"
    return formatter
}()









struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView().environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    }
}
