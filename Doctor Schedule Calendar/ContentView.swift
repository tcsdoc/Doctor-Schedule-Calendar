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
    @State private var currentMonth = Date()
    @State private var scaleFactor: CGFloat = 1.0
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Month Navigation Header
                HStack {
                    Button(action: previousMonth) {
                        Image(systemName: "chevron.left")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }
                    .disabled(!canGoToPreviousMonth())
                    
                    Spacer()
                    
                    Text(monthYearString(from: currentMonth))
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Spacer()
                    
                    // Print Button
                    Button(action: printCalendar) {
                        Image(systemName: "printer")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }
                    .padding(.trailing, 10)
                    
                    Button(action: nextMonth) {
                        Image(systemName: "chevron.right")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }
                    .disabled(!canGoToNextMonth())
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color(.systemGray6))
                
                // Full-Screen Calendar
                ScrollView([.horizontal, .vertical]) {
                    VStack(spacing: 0) {
                        // Monthly Notes (3 lines at top)
                        MonthlyNotesView(month: currentMonth)
                            .padding(.bottom, 10)
                        
                        // Calendar Grid
                        CalendarGridView(month: currentMonth)
                    }
                    .scaleEffect(scaleFactor)
                    .frame(minWidth: geometry.size.width * scaleFactor, 
                           minHeight: geometry.size.height * scaleFactor)
                }
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            scaleFactor = max(0.5, min(3.0, value))
                        }
                )
            }
        }
    }
    
    private func canGoToPreviousMonth() -> Bool {
        let calendar = Calendar.current
        let currentMonthStart = calendar.dateInterval(of: .month, for: Date())?.start ?? Date()
        let proposedMonth = calendar.date(byAdding: .month, value: -1, to: currentMonth) ?? currentMonth
        return proposedMonth >= currentMonthStart
    }
    
    private func canGoToNextMonth() -> Bool {
        let calendar = Calendar.current
        let oneYearFromNow = calendar.date(byAdding: .month, value: 12, to: Date()) ?? Date()
        let proposedMonth = calendar.date(byAdding: .month, value: 1, to: currentMonth) ?? currentMonth
        return proposedMonth < oneYearFromNow
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
    
    private func monthYearString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }
    
    private func printCalendar() {
        let printInfo = UIPrintInfo(dictionary: nil)
        printInfo.outputType = UIPrintInfo.OutputType.general
        printInfo.jobName = "Provider Schedule Calendar"
        
        let printController = UIPrintInteractionController.shared
        printController.printInfo = printInfo
        printController.printingItem = generatePrintableCalendar()
        
        printController.present(animated: true) { (controller, completed, error) in
            if let error = error {
                print("Print error: \(error.localizedDescription)")
            }
        }
    }
    
    private func generatePrintableCalendar() -> Data {
        var htmlContent = """
        <html>
        <head>
            <style>
                body { font-family: Arial, sans-serif; margin: 20px; }
                .header { text-align: center; font-size: 24px; font-weight: bold; margin-bottom: 30px; }
                .month-section { page-break-before: always; margin-bottom: 40px; }
                .month-section:first-child { page-break-before: auto; }
                .month-title { font-size: 20px; font-weight: bold; margin-bottom: 15px; border-bottom: 2px solid #333; }
                .monthly-notes { background-color: #f5f5f5; padding: 10px; margin-bottom: 20px; border-radius: 5px; }
                .notes-title { font-weight: bold; margin-bottom: 8px; }
                .calendar-table { width: 100%; border-collapse: collapse; }
                .calendar-table th, .calendar-table td { border: 1px solid #ccc; padding: 8px; vertical-align: top; }
                .calendar-table th { background-color: #e9e9e9; text-align: center; font-weight: bold; }
                .calendar-table td { height: 80px; width: 14.28%; }
                .day-number { font-weight: bold; margin-bottom: 5px; }
                .day-content { font-size: 11px; line-height: 1.2; }
                .empty-cell { background-color: #f9f9f9; }
            </style>
        </head>
        <body>
            <div class="header">Provider Schedule Calendar</div>
        """
        
        // Generate 3 months: current + 2 future
        for monthOffset in 0..<3 {
            guard let targetMonth = Calendar.current.date(byAdding: .month, value: monthOffset, to: currentMonth) else { continue }
            
            htmlContent += generateMonthHTML(for: targetMonth)
        }
        
        htmlContent += """
        </body>
        </html>
        """
        
        return htmlContent.data(using: .utf8) ?? Data()
    }
    
    private func generateMonthHTML(for month: Date) -> String {
        let calendar = Calendar.current
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMMM yyyy"
        
        var html = """
        <div class="month-section">
            <div class="month-title">\(monthFormatter.string(from: month))</div>
        """
        
        // Add monthly notes
        html += generateMonthlyNotesHTML(for: month)
        
        // Add calendar grid
        html += generateCalendarGridHTML(for: month)
        
        html += "</div>"
        
        return html
    }
    
    private func generateMonthlyNotesHTML(for month: Date) -> String {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: month)
        let monthNum = calendar.component(.month, from: month)
        
        let request: NSFetchRequest<MonthlyNotes> = MonthlyNotes.fetchRequest()
        request.predicate = NSPredicate(format: "year == %d AND month == %d", year, monthNum)
        
        var notesHTML = """
        <div class="monthly-notes">
            <div class="notes-title">Monthly Notes:</div>
        """
        
        do {
            let notes = try viewContext.fetch(request)
            if let monthlyNotes = notes.first {
                let line1 = monthlyNotes.line1?.isEmpty == false ? monthlyNotes.line1! : "—"
                let line2 = monthlyNotes.line2?.isEmpty == false ? monthlyNotes.line2! : "—"
                let line3 = monthlyNotes.line3?.isEmpty == false ? monthlyNotes.line3! : "—"
                
                notesHTML += """
                <div>1. \(line1)</div>
                <div>2. \(line2)</div>
                <div>3. \(line3)</div>
                """
            } else {
                notesHTML += """
                <div>1. —</div>
                <div>2. —</div>
                <div>3. —</div>
                """
            }
        } catch {
            notesHTML += "<div>Error loading monthly notes</div>"
        }
        
        notesHTML += "</div>"
        
        return notesHTML
    }
    
    private func generateCalendarGridHTML(for month: Date) -> String {
        let calendar = Calendar.current
        let weekdaySymbols = calendar.shortWeekdaySymbols
        
        var html = """
        <table class="calendar-table">
            <tr>
        """
        
        // Add weekday headers
        for weekday in weekdaySymbols {
            html += "<th>\(weekday)</th>"
        }
        html += "</tr>"
        
        // Get month info
        guard let monthInterval = calendar.dateInterval(of: .month, for: month),
              let firstWeekday = calendar.dateInterval(of: .weekOfYear, for: monthInterval.start)?.start else {
            return html + "</table>"
        }
        
        let daysInMonth = calendar.range(of: .day, in: .month, for: month)?.count ?? 30
        let firstWeekdayOfMonth = calendar.component(.weekday, from: monthInterval.start)
        
        var dayOfMonth = 1 - (firstWeekdayOfMonth - 1)
        
        // Generate calendar rows
        for _ in 0..<6 {
            html += "<tr>"
            
            for _ in 1...7 {
                if dayOfMonth < 1 || dayOfMonth > daysInMonth {
                    html += "<td class='empty-cell'></td>"
                } else {
                    let cellDate = calendar.date(byAdding: .day, value: dayOfMonth - 1, to: monthInterval.start)!
                    html += generateDayCellHTML(for: cellDate, dayNumber: dayOfMonth)
                }
                dayOfMonth += 1
            }
            
            html += "</tr>"
            
            if dayOfMonth > daysInMonth {
                break
            }
        }
        
        html += "</table>"
        
        return html
    }
    
    private func generateDayCellHTML(for date: Date, dayNumber: Int) -> String {
        let request: NSFetchRequest<DailySchedule> = DailySchedule.fetchRequest()
        let startOfDay = Calendar.current.startOfDay(for: date)
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!
        request.predicate = NSPredicate(format: "date >= %@ AND date < %@", startOfDay as NSDate, endOfDay as NSDate)
        
        var cellContent = "<div class='day-number'>\(dayNumber)</div><div class='day-content'>"
        
        do {
            let schedules = try viewContext.fetch(request)
            if let schedule = schedules.first {
                let line1 = schedule.line1?.isEmpty == false ? schedule.line1! : ""
                let line2 = schedule.line2?.isEmpty == false ? schedule.line2! : ""
                let line3 = schedule.line3?.isEmpty == false ? schedule.line3! : ""
                
                if !line1.isEmpty { cellContent += "\(line1)<br>" }
                if !line2.isEmpty { cellContent += "\(line2)<br>" }
                if !line3.isEmpty { cellContent += "\(line3)<br>" }
            }
        } catch {
            cellContent += "Error loading schedule"
        }
        
        cellContent += "</div>"
        
        return "<td>\(cellContent)</td>"
    }
}

struct MonthlyNotesView: View {
    let month: Date
    @Environment(\.managedObjectContext) private var viewContext
    
    @State private var line1 = ""
    @State private var line2 = ""
    @State private var line3 = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Monthly Notes")
                .font(.headline)
                .fontWeight(.bold)
            
            VStack(spacing: 4) {
                TextField("Line 1", text: $line1)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onChange(of: line1) { _, newValue in
                        saveMonthlyNotes()
                    }
                
                TextField("Line 2", text: $line2)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onChange(of: line2) { _, newValue in
                        saveMonthlyNotes()
                    }
                
                TextField("Line 3", text: $line3)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onChange(of: line3) { _, newValue in
                        saveMonthlyNotes()
                    }
            }
        }
        .padding(.horizontal, 20)
        .onAppear {
            loadMonthlyNotes()
        }
        .onChange(of: month) { _, _ in
            loadMonthlyNotes()
        }
    }
    
    private func loadMonthlyNotes() {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: month)
        let monthNum = calendar.component(.month, from: month)
        
        let request: NSFetchRequest<MonthlyNotes> = MonthlyNotes.fetchRequest()
        request.predicate = NSPredicate(format: "year == %d AND month == %d", year, monthNum)
        
        do {
            let notes = try viewContext.fetch(request)
            if let monthlyNotes = notes.first {
                line1 = monthlyNotes.line1 ?? ""
                line2 = monthlyNotes.line2 ?? ""
                line3 = monthlyNotes.line3 ?? ""
            } else {
                line1 = ""
                line2 = ""
                line3 = ""
            }
        } catch {
            print("Error loading monthly notes: \(error)")
        }
    }
    
    private func saveMonthlyNotes() {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: month)
        let monthNum = calendar.component(.month, from: month)
        
        let request: NSFetchRequest<MonthlyNotes> = MonthlyNotes.fetchRequest()
        request.predicate = NSPredicate(format: "year == %d AND month == %d", year, monthNum)
        
        do {
            let notes = try viewContext.fetch(request)
            let monthlyNotes: MonthlyNotes
            
            if let existingNotes = notes.first {
                monthlyNotes = existingNotes
            } else {
                monthlyNotes = MonthlyNotes(context: viewContext)
                monthlyNotes.id = UUID()
                monthlyNotes.year = Int32(year)
                monthlyNotes.month = Int32(monthNum)
            }
            
            monthlyNotes.line1 = line1
            monthlyNotes.line2 = line2
            monthlyNotes.line3 = line3
            
            try viewContext.save()
        } catch {
            print("Error saving monthly notes: \(error)")
        }
    }
}

struct CalendarGridView: View {
    let month: Date
    
    private let calendar = Calendar.current
    private let weekdaySymbols = Calendar.current.shortWeekdaySymbols
    
    var body: some View {
        VStack(spacing: 0) {
            // Weekday Headers
            HStack(spacing: 0) {
                ForEach(weekdaySymbols, id: \.self) { weekday in
                    Text(weekday)
                        .font(.headline)
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color(.systemGray5))
                }
            }
            
            // Calendar Days Grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 7), spacing: 1) {
                ForEach(daysInMonth(), id: \.self) { date in
                    if let date = date {
                        DayCell(date: date)
                            .aspectRatio(1.2, contentMode: .fit)
                    } else {
                        Color.clear
                            .aspectRatio(1.2, contentMode: .fit)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
    }
    
    private func daysInMonth() -> [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: month) else { return [] }
        
        let firstOfMonth = monthInterval.start
        let firstWeekday = calendar.component(.weekday, from: firstOfMonth)
        let leadingEmptyDays = (firstWeekday - calendar.firstWeekday + 7) % 7
        
        var days: [Date?] = Array(repeating: nil, count: leadingEmptyDays)
        
        let numberOfDays = calendar.range(of: .day, in: .month, for: month)?.count ?? 0
        
        for day in 1...numberOfDays {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: firstOfMonth) {
                days.append(date)
            }
        }
        
        // Fill remaining cells to complete the grid
        while days.count % 7 != 0 {
            days.append(nil)
        }
        
        return days
    }
}

struct DayCell: View {
    let date: Date
    @Environment(\.managedObjectContext) private var viewContext
    
    @State private var line1 = ""
    @State private var line2 = ""
    @State private var line3 = ""
    
    private var dayNumber: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Day Number
            Text(dayNumber)
                .font(.caption)
                .fontWeight(.bold)
                .padding(.leading, 6)
                .padding(.top, 4)
            
            // 3 editable lines with visible borders
            VStack(spacing: 2) {
                TextField("Schedule line 1", text: $line1)
                    .font(.caption2)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onChange(of: line1) { _, newValue in
                        saveDailySchedule()
                    }
                
                TextField("Schedule line 2", text: $line2)
                    .font(.caption2)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onChange(of: line2) { _, newValue in
                        saveDailySchedule()
                    }
                
                TextField("Schedule line 3", text: $line3)
                    .font(.caption2)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onChange(of: line3) { _, newValue in
                        saveDailySchedule()
                    }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.systemGray6))
        .overlay(
            Rectangle()
                .stroke(Color(.systemGray3), lineWidth: 1)
        )
        .onAppear {
            loadDailySchedule()
        }
    }
    
    private func loadDailySchedule() {
        let request: NSFetchRequest<DailySchedule> = DailySchedule.fetchRequest()
        request.predicate = NSPredicate(format: "date == %@", date as NSDate)
        
        do {
            let schedules = try viewContext.fetch(request)
            if let schedule = schedules.first {
                line1 = schedule.line1 ?? ""
                line2 = schedule.line2 ?? ""
                line3 = schedule.line3 ?? ""
            } else {
                line1 = ""
                line2 = ""
                line3 = ""
            }
        } catch {
            print("Error loading daily schedule: \(error)")
        }
    }
    
    private func saveDailySchedule() {
        let request: NSFetchRequest<DailySchedule> = DailySchedule.fetchRequest()
        request.predicate = NSPredicate(format: "date == %@", date as NSDate)
        
        do {
            let schedules = try viewContext.fetch(request)
            let schedule: DailySchedule
            
            if let existingSchedule = schedules.first {
                schedule = existingSchedule
            } else {
                schedule = DailySchedule(context: viewContext)
                schedule.id = UUID()
                schedule.date = date
            }
            
            schedule.line1 = line1
            schedule.line2 = line2
            schedule.line3 = line3
            
            try viewContext.save()
        } catch {
            print("Error saving daily schedule: \(error)")
        }
    }
}

#Preview {
    ContentView().environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
