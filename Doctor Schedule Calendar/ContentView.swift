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
        print("Print button tapped - generating provider schedule calendar")
        
        // Generate the actual calendar with provider schedules
        guard let printImage = generateProviderCalendarImage() else {
            print("Failed to create printable calendar image")
            return
        }
        
        let printInfo = UIPrintInfo(dictionary: nil)
        printInfo.outputType = UIPrintInfo.OutputType.general
        printInfo.jobName = "Provider Schedule Calendar"
        
        let printController = UIPrintInteractionController.shared
        printController.printInfo = printInfo
        printController.printingItem = printImage
        
        printController.present(animated: true) { (controller, completed, error) in
            DispatchQueue.main.async {
                if let error = error {
                    print("Print error: \(error)")
                } else {
                    print("Print completed successfully: \(completed)")
                }
            }
        }
    }
    
    private func generateProviderCalendarImage() -> UIImage? {
        let calendar = Calendar.current
        let currentDate = Date()
        
        // Get the current month and next 2 months
        guard let month1 = calendar.dateInterval(of: .month, for: currentDate),
              let month2Start = calendar.date(byAdding: .month, value: 1, to: currentDate),
              let month2 = calendar.dateInterval(of: .month, for: month2Start),
              let month3Start = calendar.date(byAdding: .month, value: 2, to: currentDate),
              let month3 = calendar.dateInterval(of: .month, for: month3Start) else {
            return nil
        }
        
        let months = [month1, month2, month3]
        
        // Create the printable content
        var calendarText = "PROVIDER SCHEDULE CALENDAR\n"
        calendarText += "Generated: \(currentDate.formatted(date: .abbreviated, time: .shortened))\n\n"
        
        for monthInterval in months {
            let monthName = monthInterval.start.formatted(.dateTime.month(.wide).year())
            calendarText += "\(monthName.uppercased())\n"
            calendarText += String(repeating: "=", count: monthName.count) + "\n\n"
            
            // Get monthly notes for this month
            let year = calendar.component(.year, from: monthInterval.start)
            let monthNum = calendar.component(.month, from: monthInterval.start)
            
            let monthlyNotesRequest: NSFetchRequest<MonthlyNotes> = MonthlyNotes.fetchRequest()
            monthlyNotesRequest.predicate = NSPredicate(format: "year == %d AND month == %d", year, monthNum)
            
            if let monthlyNotes = try? viewContext.fetch(monthlyNotesRequest).first {
                calendarText += "Monthly Notes:\n"
                if let line1 = monthlyNotes.line1, !line1.isEmpty { calendarText += "• \(line1)\n" }
                if let line2 = monthlyNotes.line2, !line2.isEmpty { calendarText += "• \(line2)\n" }
                if let line3 = monthlyNotes.line3, !line3.isEmpty { calendarText += "• \(line3)\n" }
                calendarText += "\n"
            }
            
            // Generate calendar grid
            let firstDayOfMonth = monthInterval.start
            let lastDayOfMonth = calendar.date(byAdding: .day, value: -1, to: monthInterval.end) ?? monthInterval.start
            let daysInMonth = calendar.component(.day, from: lastDayOfMonth)
            let firstWeekday = calendar.component(.weekday, from: firstDayOfMonth) - 1 // 0 = Sunday
            
            calendarText += "Sun  Mon  Tue  Wed  Thu  Fri  Sat\n"
            
            // Add leading spaces for first week
            for _ in 0..<firstWeekday {
                calendarText += "     "
            }
            
            // Add days with schedule info
            for day in 1...daysInMonth {
                let dayString = String(format: "%2d", day)
                
                if let dayDate = calendar.date(byAdding: .day, value: day - 1, to: firstDayOfMonth) {
                    // Check if there are schedules for this day
                    let dailyScheduleRequest: NSFetchRequest<DailySchedule> = DailySchedule.fetchRequest()
                    let startOfDay = calendar.startOfDay(for: dayDate)
                    let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
                    dailyScheduleRequest.predicate = NSPredicate(format: "date >= %@ AND date < %@", startOfDay as NSDate, endOfDay as NSDate)
                    
                    let schedules = (try? viewContext.fetch(dailyScheduleRequest)) ?? []
                    
                    if !schedules.isEmpty {
                        calendarText += "\(dayString)*"  // Mark days with schedules
                    } else {
                        calendarText += "\(dayString) "
                    }
                } else {
                    calendarText += "\(dayString) "
                }
                
                // New line after Saturday or at end of month
                let currentWeekday = (firstWeekday + day - 1) % 7
                if currentWeekday == 6 || day == daysInMonth {
                    calendarText += "\n"
                }
            }
            
            calendarText += "\n"
            
            // Add detailed schedule information for days with schedules
            let startOfMonth = monthInterval.start
            let endOfMonth = monthInterval.end
            
            let dailyScheduleRequest: NSFetchRequest<DailySchedule> = DailySchedule.fetchRequest()
            dailyScheduleRequest.predicate = NSPredicate(format: "date >= %@ AND date < %@", 
                                                       startOfMonth as NSDate, endOfMonth as NSDate)
            dailyScheduleRequest.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]
            
            let monthlySchedules = (try? viewContext.fetch(dailyScheduleRequest)) ?? []
            
            if !monthlySchedules.isEmpty {
                calendarText += "Schedule Details:\n"
                for schedule in monthlySchedules {
                    let dayFormatter = DateFormatter()
                    dayFormatter.dateFormat = "MMM d"
                    let dayString = dayFormatter.string(from: schedule.date ?? Date())
                    
                    calendarText += "\(dayString):\n"
                    if let line1 = schedule.line1, !line1.isEmpty { calendarText += "  • \(line1)\n" }
                    if let line2 = schedule.line2, !line2.isEmpty { calendarText += "  • \(line2)\n" }
                    if let line3 = schedule.line3, !line3.isEmpty { calendarText += "  • \(line3)\n" }
                }
                calendarText += "\n"
            }
            
            calendarText += "\n"
        }
        
        calendarText += "Legend: * = Scheduled day\n\n"
        calendarText += "Report generated on \(currentDate.formatted(date: .complete, time: .complete))\n"
        
        // Render to image
        return renderTextToImage(calendarText)
    }
    
    private func renderTextToImage(_ text: String) -> UIImage? {
        // Create a UILabel with the content
        let label = UILabel()
        label.text = text
        label.font = UIFont.monospacedSystemFont(ofSize: 9, weight: .regular)
        label.textColor = .black
        label.backgroundColor = .white
        label.numberOfLines = 0
        label.textAlignment = .left
        
        // Size the label for US Letter paper (8.5" x 11" at 72 DPI)
        let pageSize = CGSize(width: 612, height: 792)  // US Letter in points
        let margins = UIEdgeInsets(top: 50, left: 50, bottom: 50, right: 50)
        let contentSize = CGSize(
            width: pageSize.width - margins.left - margins.right,
            height: pageSize.height - margins.top - margins.bottom
        )
        
        label.frame = CGRect(origin: .zero, size: contentSize)
        
        // Render the label to an image
        let renderer = UIGraphicsImageRenderer(size: pageSize)
        let image = renderer.image { context in
            // Fill with white background
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: pageSize))
            
            // Translate to account for margins
            context.cgContext.translateBy(x: margins.left, y: margins.top)
            
            // Render the label
            label.layer.render(in: context.cgContext)
        }
        
        return image
    }
    
    private func generatePrintableCalendar() -> Data {
        // Fetch all data on main thread first
        var monthlyNotesData: [String: (String, String, String)] = [:]
        var dailyScheduleData: [String: (String, String, String)] = [:]
        
        let calendar = Calendar.current
        
        // Fetch monthly notes and daily schedules for 3 months
        for monthOffset in 0..<3 {
            guard let targetMonth = calendar.date(byAdding: .month, value: monthOffset, to: currentMonth) else { continue }
            
            // Fetch monthly notes
            let year = calendar.component(.year, from: targetMonth)
            let monthNum = calendar.component(.month, from: targetMonth)
            let monthKey = "\(year)-\(monthNum)"
            
            let monthlyRequest: NSFetchRequest<MonthlyNotes> = MonthlyNotes.fetchRequest()
            monthlyRequest.predicate = NSPredicate(format: "year == %d AND month == %d", year, monthNum)
            
            do {
                let monthlyNotes = try viewContext.fetch(monthlyRequest)
                if let notes = monthlyNotes.first {
                    monthlyNotesData[monthKey] = (notes.line1 ?? "", notes.line2 ?? "", notes.line3 ?? "")
                } else {
                    monthlyNotesData[monthKey] = ("", "", "")
                }
            } catch {
                monthlyNotesData[monthKey] = ("", "", "")
            }
            
            // Fetch daily schedules for the entire month
            guard let monthInterval = calendar.dateInterval(of: .month, for: targetMonth) else { continue }
            let startDate = monthInterval.start
            let endDate = monthInterval.end
            
            let dailyRequest: NSFetchRequest<DailySchedule> = DailySchedule.fetchRequest()
            dailyRequest.predicate = NSPredicate(format: "date >= %@ AND date < %@", startDate as NSDate, endDate as NSDate)
            
            do {
                let dailySchedules = try viewContext.fetch(dailyRequest)
                for schedule in dailySchedules {
                    let dayKey = calendar.startOfDay(for: schedule.date!).timeIntervalSince1970
                    dailyScheduleData[String(dayKey)] = (schedule.line1 ?? "", schedule.line2 ?? "", schedule.line3 ?? "")
                }
            } catch {
                print("Error fetching daily schedules: \(error)")
            }
        }
        
        // Generate HTML with fetched data
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
            guard let targetMonth = calendar.date(byAdding: .month, value: monthOffset, to: currentMonth) else { continue }
            
            htmlContent += generateMonthHTML(for: targetMonth, monthlyNotes: monthlyNotesData, dailySchedules: dailyScheduleData)
        }
        
        htmlContent += """
        </body>
        </html>
        """
        
        return htmlContent.data(using: .utf8) ?? Data()
    }
    
    private func generateMonthHTML(for month: Date, monthlyNotes: [String: (String, String, String)], dailySchedules: [String: (String, String, String)]) -> String {
        let calendar = Calendar.current
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMMM yyyy"
        
        var html = """
        <div class="month-section">
            <div class="month-title">\(monthFormatter.string(from: month))</div>
        """
        
        // Add monthly notes
        html += generateMonthlyNotesHTML(for: month, monthlyNotes: monthlyNotes)
        
        // Add calendar grid
        html += generateCalendarGridHTML(for: month, dailySchedules: dailySchedules)
        
        html += "</div>"
        
        return html
    }
    
    private func generateMonthlyNotesHTML(for month: Date, monthlyNotes: [String: (String, String, String)]) -> String {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: month)
        let monthNum = calendar.component(.month, from: month)
        let monthKey = "\(year)-\(monthNum)"
        
        var notesHTML = """
        <div class="monthly-notes">
            <div class="notes-title">Monthly Notes:</div>
        """
        
        if let notes = monthlyNotes[monthKey] {
            let line1 = notes.0.isEmpty ? "—" : notes.0
            let line2 = notes.1.isEmpty ? "—" : notes.1
            let line3 = notes.2.isEmpty ? "—" : notes.2
            
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
        
        notesHTML += "</div>"
        
        return notesHTML
    }
    
    private func generateCalendarGridHTML(for month: Date, dailySchedules: [String: (String, String, String)]) -> String {
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
        guard let monthInterval = calendar.dateInterval(of: .month, for: month) else {
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
                    html += generateDayCellHTML(for: cellDate, dayNumber: dayOfMonth, dailySchedules: dailySchedules)
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
    
    private func generateDayCellHTML(for date: Date, dayNumber: Int, dailySchedules: [String: (String, String, String)]) -> String {
        let startOfDay = Calendar.current.startOfDay(for: date)
        let dayKey = String(startOfDay.timeIntervalSince1970)
        
        var cellContent = "<div class='day-number'>\(dayNumber)</div><div class='day-content'>"
        
        if let schedule = dailySchedules[dayKey] {
            let line1 = schedule.0
            let line2 = schedule.1
            let line3 = schedule.2
            
            if !line1.isEmpty { cellContent += "\(line1)<br>" }
            if !line2.isEmpty { cellContent += "\(line2)<br>" }
            if !line3.isEmpty { cellContent += "\(line3)<br>" }
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
