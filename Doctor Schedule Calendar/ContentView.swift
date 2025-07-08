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
                HStack {
                    Text("PROVIDER SCHEDULE")
                        .font(.title)
                        .fontWeight(.bold)
                    
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
                        
                        Text("Build 004")
                            .font(.caption)
                            .foregroundColor(.gray)
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
        
        return (0..<3).compactMap { offset in
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
        
        // Create a simple text formatter with all the calendar data
        let calendarText = generateCalendarText()
        let formatter = UISimpleTextPrintFormatter(text: calendarText)
        
        printController.printFormatter = formatter
        
        // Present the print dialog
        printController.present(animated: true) { controller, completed, error in
            if let error = error {
                print("Print error: \(error)")
            }
        }
    }
    
    private func generateCalendarText() -> String {
        var text = "PROVIDER SCHEDULE\n\n"
        
        // Get months to display
        let calendar = Calendar.current
        let currentMonth = calendar.dateInterval(of: .month, for: currentDate)!.start
        let months = (0..<3).compactMap { offset in
            calendar.date(byAdding: .month, value: offset, to: currentMonth)
        }
        
        for month in months {
            let monthFormatter = DateFormatter()
            monthFormatter.dateFormat = "MMMM yyyy"
            let monthString = monthFormatter.string(from: month)
            
            text += "\(monthString)\n"
            text += String(repeating: "=", count: monthString.count) + "\n\n"
            
            // Monthly notes
            let monthValue = Int32(calendar.component(.month, from: month))
            let yearValue = Int32(calendar.component(.year, from: month))
            if let notes = monthlyNotes.first(where: { $0.month == monthValue && $0.year == yearValue }) {
                if let line1 = notes.line1, !line1.isEmpty {
                    text += "Monthly Note 1: \(line1)\n"
                }
                if let line2 = notes.line2, !line2.isEmpty {
                    text += "Monthly Note 2: \(line2)\n"
                }
                if let line3 = notes.line3, !line3.isEmpty {
                    text += "Monthly Note 3: \(line3)\n"
                }
                text += "\n"
            }
            
            // Calendar grid
            let daysInMonth = getDaysInMonth(for: month)
            let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
            
            // Header
            text += weekdays.joined(separator: "\t") + "\n"
            text += String(repeating: "-", count: 50) + "\n"
            
            // Calendar days
            for (index, date) in daysInMonth.enumerated() {
                let column = index % 7
                let dayNumber = calendar.component(.day, from: date)
                
                if column == 0 && index > 0 {
                    text += "\n"
                }
                
                text += "\(dayNumber)"
                
                // Add schedule data if exists
                let dayStart = calendar.startOfDay(for: date)
                if let schedule = dailySchedules.first(where: { schedule in
                    guard let scheduleDate = schedule.date else { return false }
                    return calendar.isDate(scheduleDate, inSameDayAs: dayStart)
                }) {
                    if let line1 = schedule.line1, !line1.isEmpty {
                        text += " (\(line1))"
                    }
                }
                
                text += "\t"
            }
            
            text += "\n\n" + String(repeating: "=", count: 50) + "\n\n"
        }
        
        return text
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
            // Month header
            Text(monthFormatter.string(from: month))
                .font(.title2)
                .fontWeight(.bold)
                .padding(.bottom, 5)
            
            // Monthly notes section
            MonthlyNotesView(month: month, monthlyNotes: monthlyNotes, viewContext: viewContext)
            
            // Days of week header
            HStack {
                ForEach(Calendar.current.shortWeekdaySymbols, id: \.self) { day in
                    Text(day)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 10)
            
            // Calendar grid
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
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(10)
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
            // Day number
            Text("\(calendar.component(.day, from: date))")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(calendar.isDate(date, inSameDayAs: Date()) ? .red : .primary)
                .padding(.bottom, 2)
            
            // Three text fields for scheduling
            VStack(spacing: 8) {
                TextField("", text: Binding(
                    get: { schedule?.line1 ?? "" },
                    set: { newValue in
                        updateSchedule()
                        schedule?.line1 = newValue
                        saveContext()
                    }
                ))
                .font(.system(size: 14))
                .frame(height: 32)
                .padding(6)
                .background(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color.gray.opacity(0.4), lineWidth: 0.5)
                )
                .focused($focusedField, equals: .line1)
                .onSubmit {
                    focusedField = .line2
                }
                
                TextField("", text: Binding(
                    get: { schedule?.line2 ?? "" },
                    set: { newValue in
                        updateSchedule()
                        schedule?.line2 = newValue
                        saveContext()
                    }
                ))
                .font(.system(size: 14))
                .frame(height: 32)
                .padding(6)
                .background(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color.gray.opacity(0.4), lineWidth: 0.5)
                )
                .focused($focusedField, equals: .line2)
                .onSubmit {
                    focusedField = .line3
                }
                
                TextField("", text: Binding(
                    get: { schedule?.line3 ?? "" },
                    set: { newValue in
                        updateSchedule()
                        schedule?.line3 = newValue
                        saveContext()
                    }
                ))
                .font(.system(size: 14))
                .frame(height: 32)
                .padding(6)
                .background(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color.gray.opacity(0.4), lineWidth: 0.5)
                )
                .focused($focusedField, equals: .line3)
                .onSubmit {
                    // Clear focus after line3, staying within this day only
                    focusedField = nil
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 250)
        .background(
            RoundedRectangle(cornerRadius: 2)
                .fill(calendar.isDate(date, inSameDayAs: Date()) ? Color.red.opacity(0.1) : Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
                )
        )
        .onAppear {
            loadSchedule()
        }
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
        VStack(alignment: .leading, spacing: 2) {
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
                .font(.system(size: 12))
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(height: 25)
            }
        }
        .onAppear {
            loadNotes()
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
