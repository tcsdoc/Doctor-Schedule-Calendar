import Foundation
import Testing
@testable import Provider_Schedule_Calendar

private func utcDate(year: Int, month: Int, day: Int) -> Date {
    var components = DateComponents()
    components.calendar = Calendar(identifier: .gregorian)
    components.timeZone = TimeZone(identifier: "UTC")
    components.year = year
    components.month = month
    components.day = day
    return components.date!
}

struct CacheTests {

    @Test func cacheRoundTrip() {
        CacheFileGate.withLock {
            let scheduleDate = utcDate(year: 2030, month: 6, day: 1)
            let scheduleKey = "2030-06-01"
            let schedules: [String: ScheduleRecord] = [
                scheduleKey: ScheduleRecord(date: scheduleDate, os: "Cached OS")
            ]
            let notes: [String: MonthlyNote] = [
                "2030-06": MonthlyNote(month: 6, year: 2030, line1: "Note line")
            ]
            let pendingScheduleKeys: Set<String> = ["2030-06-01", "2030-06-02"]
            let pendingNoteKeys: Set<String> = ["2030-06"]

            ScheduleLocalCache.save(
                schedules: schedules,
                monthlyNotes: notes,
                pendingScheduleKeys: pendingScheduleKeys,
                pendingNoteKeys: pendingNoteKeys
            )

            let loaded = ScheduleLocalCache.load()
            #expect(loaded != nil)
            #expect(loaded?.schedules[scheduleKey]?.os == "Cached OS")
            #expect(loaded?.monthlyNotes["2030-06"]?.line1 == "Note line")
            #expect(loaded?.pendingScheduleKeys == ["2030-06-01", "2030-06-02"])
            #expect(loaded?.pendingNoteKeys == ["2030-06"])
        }
    }

    @Test func cacheOverwrite() {
        CacheFileGate.withLock {
            let snapshotA: [String: ScheduleRecord] = [
                "2030-07-01": ScheduleRecord(date: utcDate(year: 2030, month: 7, day: 1), os: "A")
            ]
            ScheduleLocalCache.save(
                schedules: snapshotA,
                monthlyNotes: [:],
                pendingScheduleKeys: [],
                pendingNoteKeys: []
            )

            let snapshotB: [String: ScheduleRecord] = [
                "2030-08-01": ScheduleRecord(date: utcDate(year: 2030, month: 8, day: 1), cl: "B")
            ]
            ScheduleLocalCache.save(
                schedules: snapshotB,
                monthlyNotes: [:],
                pendingScheduleKeys: ["2030-08-01"],
                pendingNoteKeys: []
            )

            let loaded = ScheduleLocalCache.load()
            #expect(loaded?.schedules.count == 1)
            #expect(loaded?.schedules["2030-07-01"] == nil)
            #expect(loaded?.schedules["2030-08-01"]?.cl == "B")
            #expect(loaded?.pendingScheduleKeys == ["2030-08-01"])
        }
    }

    @Test func cacheLegacyIDSurvivesRoundTrip() {
        CacheFileGate.withLock {
            let legacyID = "LEGACY-UUID-CACHE-789"
            let date = utcDate(year: 2030, month: 9, day: 15)
            let key = "2030-09-15"
            let schedules: [String: ScheduleRecord] = [
                key: ScheduleRecord(id: legacyID, date: date, call: "On call")
            ]

            ScheduleLocalCache.save(
                schedules: schedules,
                monthlyNotes: [:],
                pendingScheduleKeys: [],
                pendingNoteKeys: []
            )

            let loaded = ScheduleLocalCache.load()
            #expect(loaded?.schedules[key]?.id == legacyID)
            #expect(loaded?.schedules[key]?.call == "On call")
        }
    }
}
