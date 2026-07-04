import Foundation
import Testing
@testable import Provider_Schedule_Calendar

private func utcDate(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0, second: Int = 0) -> Date {
    var components = DateComponents()
    components.calendar = Calendar(identifier: .gregorian)
    components.timeZone = TimeZone(identifier: "UTC")
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    components.second = second
    return components.date!
}

struct ModelTests {

    // MARK: - ScheduleRecord

    @Test func scheduleRecordDeterministicID() {
        let date = utcDate(year: 2026, month: 7, day: 4)
        let record = ScheduleRecord(date: date)
        #expect(record.id == "schedule_2026-07-04")
    }

    @Test func scheduleRecordUTCBoundary() {
        // 2026-08-01T03:00:00Z is still July 31 in New York; ID must use UTC date.
        let date = utcDate(year: 2026, month: 8, day: 1, hour: 3)
        let record = ScheduleRecord(date: date)
        #expect(record.id == "schedule_2026-08-01")
    }

    @Test func scheduleRecordIDPreservation() {
        let date = utcDate(year: 2026, month: 1, day: 15)
        let record = ScheduleRecord(id: "LEGACY-UUID-123", date: date)
        #expect(record.id == "LEGACY-UUID-123")
    }

    @Test func scheduleRecordIsEmpty() {
        let empty = ScheduleRecord(date: utcDate(year: 2026, month: 1, day: 1))
        #expect(empty.isEmpty)

        let withOS = ScheduleRecord(date: utcDate(year: 2026, month: 1, day: 1), os: "Dr. Smith")
        #expect(!withOS.isEmpty)

        let withCL = ScheduleRecord(date: utcDate(year: 2026, month: 1, day: 1), cl: "X")
        #expect(!withCL.isEmpty)

        let withOff = ScheduleRecord(date: utcDate(year: 2026, month: 1, day: 1), off: "X")
        #expect(!withOff.isEmpty)

        let withCall = ScheduleRecord(date: utcDate(year: 2026, month: 1, day: 1), call: "X")
        #expect(!withCall.isEmpty)
    }

    @Test func scheduleRecordCodableRoundTrip() throws {
        let original = ScheduleRecord(
            id: "CUSTOM-SCHEDULE-ID",
            date: utcDate(year: 2026, month: 3, day: 10),
            os: "OS value",
            cl: "CL value",
            off: "Off value",
            call: "Call value"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ScheduleRecord.self, from: data)
        #expect(decoded.id == "CUSTOM-SCHEDULE-ID")
        #expect(decoded.os == "OS value")
        #expect(decoded.cl == "CL value")
        #expect(decoded.off == "Off value")
        #expect(decoded.call == "Call value")
    }

    // MARK: - MonthlyNote

    @Test func monthlyNoteDeterministicID() {
        let note = MonthlyNote(month: 7, year: 2026)
        #expect(note.id == "notes_2026-07")
    }

    @Test func monthlyNoteIDPreservation() {
        let note = MonthlyNote(id: "LEGACY-NOTE-456", month: 3, year: 2026)
        #expect(note.id == "LEGACY-NOTE-456")
    }

    @Test func monthlyNoteCodableRoundTrip() throws {
        let original = MonthlyNote(
            id: "CUSTOM-NOTE-ID",
            month: 11,
            year: 2025,
            line1: "Line one",
            line2: "Line two",
            line3: "Line three"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MonthlyNote.self, from: data)
        #expect(decoded.id == "CUSTOM-NOTE-ID")
        #expect(decoded.month == 11)
        #expect(decoded.year == 2025)
        #expect(decoded.line1 == "Line one")
        #expect(decoded.line2 == "Line two")
        #expect(decoded.line3 == "Line three")
    }
}
