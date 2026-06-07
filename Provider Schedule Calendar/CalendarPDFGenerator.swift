import Foundation
import UIKit

// MARK: - Master calendar PDF (Print + Documents backup)
enum CalendarPDFGenerator {
    static let masterPDFFileName = "Provider Schedule Master.pdf"

    static var masterPDFURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(masterPDFFileName)
    }

    /// e.g. "Updated June 6th, 08:32AM"
    static func updatedLabel(for date: Date) -> String {
        let calendar = Calendar.current
        let day = calendar.component(.day, from: date)
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMMM"
        let monthName = monthFormatter.string(from: date)

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "hh:mma"
        timeFormatter.amSymbol = "AM"
        timeFormatter.pmSymbol = "PM"
        let time = timeFormatter.string(from: date)

        return "Updated \(monthName) \(day)\(ordinalSuffix(for: day)), \(time)"
    }

    static func generatePDFData(
        schedules: [String: ScheduleRecord],
        monthlyNotes: [String: MonthlyNote],
        months: [Date],
        updatedAt: Date
    ) -> Data? {
        let pageSize = CGSize(width: 612, height: 792)
        let pageMargin: CGFloat = 36
        let contentRect = CGRect(
            x: pageMargin,
            y: pageMargin,
            width: pageSize.width - (pageMargin * 2),
            height: pageSize.height - (pageMargin * 2)
        )

        let pdfData = NSMutableData()
        UIGraphicsBeginPDFContextToData(pdfData, CGRect(origin: .zero, size: pageSize), nil)

        for (index, month) in months.enumerated() {
            UIGraphicsBeginPDFPage()
            let context = UIGraphicsGetCurrentContext()!
            var pageRect = contentRect

            if index == 0 {
                drawUpdatedLabel(updatedLabel(for: updatedAt), in: &pageRect, context: context)
            }

            drawCalendarMonth(
                month: month,
                schedules: schedules,
                monthlyNotes: monthlyNotes,
                in: pageRect,
                context: context
            )
        }

        UIGraphicsEndPDFContext()
        return pdfData as Data
    }

    @discardableResult
    static func writeMasterPDFToDocuments(
        schedules: [String: ScheduleRecord],
        monthlyNotes: [String: MonthlyNote],
        months: [Date],
        updatedAt: Date
    ) -> Bool {
        guard let data = generatePDFData(
            schedules: schedules,
            monthlyNotes: monthlyNotes,
            months: months,
            updatedAt: updatedAt
        ) else {
            redesignLog("❌ Failed to generate master PDF")
            return false
        }

        do {
            try data.write(to: masterPDFURL, options: .atomic)
            return true
        } catch {
            redesignLog("❌ Failed to write master PDF: \(error)")
            return false
        }
    }

    // MARK: - Private drawing

    private static func ordinalSuffix(for day: Int) -> String {
        let teens = day % 100
        if teens >= 11 && teens <= 13 { return "th" }
        switch day % 10 {
        case 1: return "st"
        case 2: return "nd"
        case 3: return "rd"
        default: return "th"
        }
    }

    private static func drawUpdatedLabel(_ label: String, in rect: inout CGRect, context: CGContext) {
        let font = UIFont.boldSystemFont(ofSize: 11)
        let size = label.size(withAttributes: [.font: font])
        let drawRect = CGRect(
            x: rect.midX - size.width / 2,
            y: rect.minY,
            width: size.width,
            height: size.height
        )
        label.draw(in: drawRect, withAttributes: [
            .font: font,
            .foregroundColor: UIColor.darkGray
        ])
        rect.origin.y += size.height + 8
        rect.size.height -= size.height + 8
    }

    private static func drawCalendarMonth(
        month: Date,
        schedules: [String: ScheduleRecord],
        monthlyNotes: [String: MonthlyNote],
        in rect: CGRect,
        context: CGContext
    ) {
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMMM yyyy"
        let monthTitle = monthFormatter.string(from: month)

        var currentY = rect.minY

        let titleFont = UIFont.boldSystemFont(ofSize: 16)
        let titleSize = monthTitle.size(withAttributes: [.font: titleFont])
        let titleRect = CGRect(
            x: rect.midX - titleSize.width / 2,
            y: currentY,
            width: titleSize.width,
            height: titleSize.height
        )
        monthTitle.draw(in: titleRect, withAttributes: [
            .font: titleFont,
            .foregroundColor: UIColor.black
        ])
        currentY += titleSize.height + 10

        if let monthlyNote = monthlyNotes[monthKey(for: month)] {
            let line1 = monthlyNote.line1?.isEmpty == false ? monthlyNote.line1! : ""
            let line2 = monthlyNote.line2?.isEmpty == false ? monthlyNote.line2! : ""

            if !line1.isEmpty || !line2.isEmpty {
                let notesFont = UIFont.systemFont(ofSize: 9)
                let lineHeight: CGFloat = 12
                var totalHeight: CGFloat = 0
                if !line1.isEmpty { totalHeight += lineHeight }
                if !line2.isEmpty { totalHeight += lineHeight }

                let notesRect = CGRect(x: rect.minX, y: currentY, width: rect.width, height: totalHeight)
                context.setFillColor(UIColor.lightGray.cgColor)
                context.fill(notesRect.insetBy(dx: -3, dy: -2))

                var lineY = currentY
                if !line1.isEmpty {
                    line1.draw(at: CGPoint(x: rect.minX, y: lineY), withAttributes: [
                        .font: notesFont,
                        .foregroundColor: UIColor.black
                    ])
                    lineY += lineHeight
                }
                if !line2.isEmpty {
                    line2.draw(at: CGPoint(x: rect.minX, y: lineY), withAttributes: [
                        .font: notesFont,
                        .foregroundColor: UIColor.black
                    ])
                }

                currentY += totalHeight + 5
            }
        }

        let availableHeight = rect.maxY - currentY - 17
        let cellWidth = rect.width / 7
        let headerHeight: CGFloat = 30
        let calendarHeight = availableHeight - headerHeight
        let weeks = getWeeksForMonth(month)
        let cellHeight = calendarHeight / CGFloat(weeks)

        drawCalendarGrid(
            month: month,
            schedules: schedules,
            startY: currentY,
            rect: rect,
            cellWidth: cellWidth,
            cellHeight: cellHeight,
            headerHeight: headerHeight,
            context: context
        )
    }

    private static func getWeeksForMonth(_ month: Date) -> Int {
        let calendarDays = getCalendarDaysWithAlignment(for: month)
        let weeks = calendarDays.chunked(into: 7)

        var weeksWithContent = 0
        for week in weeks {
            let hasMonthContent = week.contains { date in
                Calendar.current.isDate(date, equalTo: month, toGranularity: .month)
            }
            if hasMonthContent {
                weeksWithContent += 1
            }
        }
        return weeksWithContent
    }

    private static func drawCalendarGrid(
        month: Date,
        schedules: [String: ScheduleRecord],
        startY: CGFloat,
        rect: CGRect,
        cellWidth: CGFloat,
        cellHeight: CGFloat,
        headerHeight: CGFloat,
        context: CGContext
    ) {
        var currentY = startY
        let headerFont = UIFont.boldSystemFont(ofSize: 12)
        let weekdays = Calendar.current.shortWeekdaySymbols

        for (index, weekday) in weekdays.enumerated() {
            let headerRect = CGRect(
                x: rect.minX + CGFloat(index) * cellWidth,
                y: currentY,
                width: cellWidth,
                height: headerHeight
            )

            context.setFillColor(UIColor.lightGray.cgColor)
            context.fill(headerRect)
            context.setStrokeColor(UIColor.black.cgColor)
            context.setLineWidth(1.0)
            context.stroke(headerRect)

            let textSize = weekday.size(withAttributes: [.font: headerFont])
            let textRect = CGRect(
                x: headerRect.midX - textSize.width / 2,
                y: headerRect.midY - textSize.height / 2,
                width: textSize.width,
                height: textSize.height
            )
            weekday.draw(in: textRect, withAttributes: [
                .font: headerFont,
                .foregroundColor: UIColor.black
            ])
        }
        currentY += headerHeight

        let calendarDays = getCalendarDaysWithAlignment(for: month)
        let weeksToShow = calendarDays.chunked(into: 7).filter { week in
            week.contains { date in
                Calendar.current.isDate(date, equalTo: month, toGranularity: .month)
            }
        }

        for week in weeksToShow {
            for (dayIndex, date) in week.enumerated() {
                let cellRect = CGRect(
                    x: rect.minX + CGFloat(dayIndex) * cellWidth,
                    y: currentY,
                    width: cellWidth,
                    height: cellHeight
                )

                context.setStrokeColor(UIColor.black.cgColor)
                context.setLineWidth(1.0)
                context.stroke(cellRect)

                if Calendar.current.isDate(date, equalTo: month, toGranularity: .month) {
                    drawDayCell(date: date, schedule: schedules[dateKey(for: date)], in: cellRect)
                }
            }
            currentY += cellHeight
        }
    }

    private static func drawDayCell(date: Date, schedule: ScheduleRecord?, in rect: CGRect) {
        let dayNumber = Calendar.current.component(.day, from: date)
        let padding: CGFloat = 2
        let contentRect = rect.insetBy(dx: padding, dy: padding)
        var textY = contentRect.minY

        let dayFont = UIFont.boldSystemFont(ofSize: 10)
        let dayText = "\(dayNumber)"
        let daySize = dayText.size(withAttributes: [.font: dayFont])

        dayText.draw(at: CGPoint(x: contentRect.minX, y: textY), withAttributes: [
            .font: dayFont,
            .foregroundColor: UIColor.black
        ])
        textY += daySize.height + 1

        let scheduleFont = UIFont.systemFont(ofSize: 7)
        let maxWidth = contentRect.width

        drawLabelAndValue("OS", value: schedule?.os, startY: &textY, at: contentRect.minX, maxWidth: maxWidth, font: scheduleFont)
        drawLabelAndValue("CL", value: schedule?.cl, startY: &textY, at: contentRect.minX, maxWidth: maxWidth, font: scheduleFont)
        drawLabelAndValue("OFF", value: schedule?.off, startY: &textY, at: contentRect.minX, maxWidth: maxWidth, font: scheduleFont)
        drawLabelAndValue("CALL", value: schedule?.call, startY: &textY, at: contentRect.minX, maxWidth: maxWidth, font: scheduleFont)
    }

    private static func drawLabelAndValue(
        _ label: String,
        value: String?,
        startY: inout CGFloat,
        at x: CGFloat,
        maxWidth: CGFloat,
        font: UIFont
    ) {
        let lineHeight: CGFloat = 8
        label.draw(at: CGPoint(x: x, y: startY), withAttributes: [
            .font: font,
            .foregroundColor: UIColor.black
        ])
        startY += lineHeight

        if let value = value, !value.isEmpty {
            let maxChars = Int(maxWidth / 4)
            let displayValue = value.count > maxChars ? String(value.prefix(maxChars - 1)) + "…" : value
            displayValue.draw(at: CGPoint(x: x, y: startY), withAttributes: [
                .font: font,
                .foregroundColor: UIColor.black
            ])
        }
        startY += lineHeight
    }

    private static func getCalendarDaysWithAlignment(for month: Date) -> [Date] {
        let calendar = Calendar.current
        guard let monthInterval = calendar.dateInterval(of: .month, for: month),
              let firstWeekday = calendar.dateInterval(of: .weekOfYear, for: monthInterval.start)?.start else {
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

    private static func monthKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    private static func dateKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }
}
