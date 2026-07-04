// CalendarGridViews.swift
// Month calendar grid, day cells, and schedule text fields.

import SwiftUI

// MARK: - Calendar Focus (Tab → next in-month OS)
enum CalendarFocusField: Hashable {
    case schedule(dateKey: String, field: ScheduleField)
}

func normalizeProviderText(_ text: String) -> String {
    text.uppercased().replacingOccurrences(of: "1/2", with: "½")
}

// MARK: - Month Calendar View (Editable Grid)
struct MonthCalendarView: View {
    let month: Date
    let schedules: [String: ScheduleRecord]
    let onScheduleChange: (Date, ScheduleField, String) -> Void
    let onFocusChange: (Bool) -> Void
    
    @FocusState private var focusedField: CalendarFocusField?
    
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
                            dateKey: dateKey(for: date),
                            schedule: schedules[dateKey(for: date)],
                            focusedField: $focusedField,
                            onTabToNextDay: { currentDate in
                                if let nextKey = nextInMonthOSDateKey(after: currentDate) {
                                    focusedField = .schedule(dateKey: nextKey, field: .os)
                                }
                            },
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
        .onChange(of: focusedField) { onFocusChange(focusedField != nil) }
    }
    
    private var inMonthDates: [Date] {
        calendarDays.filter { calendar.isDate($0, equalTo: month, toGranularity: .month) }
    }
    
    private func nextInMonthOSDateKey(after date: Date) -> String? {
        let dates = inMonthDates
        guard let index = dates.firstIndex(where: { calendar.isDate($0, inSameDayAs: date) }),
              index + 1 < dates.count else {
            return nil
        }
        return dateKey(for: dates[index + 1])
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
    let dateKey: String
    let schedule: ScheduleRecord?
    @FocusState.Binding var focusedField: CalendarFocusField?
    let onTabToNextDay: (Date) -> Void
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
                ScheduleTextField(
                    label: "OS",
                    fieldType: .os,
                    text: $osText,
                    focusValue: .schedule(dateKey: dateKey, field: .os),
                    focusedField: $focusedField,
                    onTab: { onTabToNextDay(date) }
                ) { newValue in
                    onFieldChange(.os, newValue)
                }
                
                ScheduleTextField(
                    label: "CL",
                    fieldType: .cl,
                    text: $clText,
                    focusValue: .schedule(dateKey: dateKey, field: .cl),
                    focusedField: $focusedField,
                    onTab: { onTabToNextDay(date) }
                ) { newValue in
                    onFieldChange(.cl, newValue)
                }
                
                ScheduleTextField(
                    label: "OFF",
                    fieldType: .off,
                    text: $offText,
                    focusValue: .schedule(dateKey: dateKey, field: .off),
                    focusedField: $focusedField,
                    onTab: { onTabToNextDay(date) }
                ) { newValue in
                    onFieldChange(.off, newValue)
                }
                
                ScheduleTextField(
                    label: "CALL",
                    fieldType: .call,
                    text: $callText,
                    focusValue: .schedule(dateKey: dateKey, field: .call),
                    focusedField: $focusedField,
                    onTab: { onTabToNextDay(date) }
                ) { newValue in
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
    let focusValue: CalendarFocusField
    @FocusState.Binding var focusedField: CalendarFocusField?
    let onTab: () -> Void
    let onCommit: (String) -> Void
    
    @State private var lastKnownText = ""
    
    // PSC Field Colors: OS=blue, CL=red, OFF=green, CALL=yellow
    private var fieldColor: Color {
        switch fieldType {
        case .os: return .blue
        case .cl: return .red
        case .off: return .green
        case .call: return .orange // Using orange instead of yellow for better readability
        }
    }
    
    private var isFocused: Bool {
        focusedField == focusValue
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
                .focused($focusedField, equals: focusValue)
                .onKeyPress(.tab) {
                    onTab()
                    return .handled
                }
                .onSubmit {
                    onCommit(normalizeProviderText(text))
                }
                .onChange(of: text) { _, newValue in
                    let normalized = normalizeProviderText(newValue)
                    if text != normalized {
                        text = normalized
                        return
                    }
                    // Call onCommit when text actually changes from user input
                    // Skip if this is just the initial load (lastKnownText will be empty)
                    if !lastKnownText.isEmpty || isFocused {
                        onCommit(normalized)
                    }
                    lastKnownText = normalized
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
