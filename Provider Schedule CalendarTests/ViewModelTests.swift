import Foundation
import Testing
@testable import Provider_Schedule_Calendar

private func utcDate(year: Int, month: Int, day: Int, hour: Int = 0) -> Date {
    var components = DateComponents()
    components.calendar = Calendar(identifier: .gregorian)
    components.timeZone = TimeZone(identifier: "UTC")
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    return components.date!
}

@MainActor
private func makeViewModel() -> ScheduleViewModel {
    // Ensures isInitializing is false immediately (cache hit path).
    ScheduleLocalCache.save(
        schedules: [:],
        monthlyNotes: [:],
        pendingScheduleKeys: [],
        pendingNoteKeys: []
    )
    let vm = ScheduleViewModel()
    vm.schedules = [:]
    vm.monthlyNotes = [:]
    return vm
}

struct ViewModelTests {

    @Test @MainActor func updateScheduleCreatesRecord() {
        CacheFileGate.withLock {
            let vm = makeViewModel()
            let date = utcDate(year: 2030, month: 2, day: 10)
            let key = "2030-02-10"

            vm.updateSchedule(date: date, field: .os, value: "Dr. Test")

            #expect(vm.schedules[key] != nil)
            #expect(vm.schedules[key]?.id == "schedule_2030-02-10")
            #expect(vm.schedules[key]?.os == "Dr. Test")
        }
    }

    @Test @MainActor func clearingAllFieldsRemovesSchedule() {
        CacheFileGate.withLock {
            let vm = makeViewModel()
            let date = utcDate(year: 2030, month: 2, day: 11)
            let key = "2030-02-11"

            vm.updateSchedule(date: date, field: .os, value: "Temp")
            #expect(vm.schedules[key] != nil)

            vm.updateSchedule(date: date, field: .os, value: "")
            #expect(vm.schedules[key] == nil)
        }
    }

    @Test @MainActor func refillPreservesLegacyIdentity() {
        CacheFileGate.withLock {
            let vm = makeViewModel()
            let date = utcDate(year: 2030, month: 1, day: 15)
            let key = "2030-01-15"

            vm.schedules[key] = ScheduleRecord(id: "LEGACY-REFILL-TEST", date: date, os: "X")
            vm.updateSchedule(date: date, field: .os, value: "")
            #expect(vm.schedules[key] == nil)

            vm.updateSchedule(date: date, field: .cl, value: "New CL")
            #expect(vm.schedules[key]?.id == "LEGACY-REFILL-TEST")
            #expect(vm.schedules[key]?.id != "schedule_2030-01-15")
            #expect(vm.schedules[key]?.cl == "New CL")
        }
    }

    @Test @MainActor func dateKeyAndMonthKeyUseUTC() {
        CacheFileGate.withLock {
            let vm = makeViewModel()
            // 2026-08-01T03:00:00Z — UTC August 1, local July 31 in New York.
            let boundaryDate = utcDate(year: 2026, month: 8, day: 1, hour: 3)

            #expect(vm.dateKey(for: boundaryDate) == "2026-08-01")
            #expect(vm.monthKey(for: boundaryDate) == "2026-08")
        }
    }

    @Test @MainActor func mergeCloudReplacesLocalState() {
        CacheFileGate.withLock {
            let vm = makeViewModel()
            let date = utcDate(year: 2030, month: 3, day: 1)
            let key = "2030-03-01"

            vm.schedules[key] = ScheduleRecord(date: date, os: "Local")
            let cloudSchedules: [String: ScheduleRecord] = [
                key: ScheduleRecord(date: date, os: "Cloud")
            ]

            vm.mergeCloudKitData(loadedSchedules: cloudSchedules, loadedNotes: [:])

            #expect(vm.schedules[key]?.os == "Cloud")
        }
    }

    @Test @MainActor func mergePendingLocalEditSurvives() {
        CacheFileGate.withLock {
            let vm = makeViewModel()
            let date = utcDate(year: 2030, month: 3, day: 2)
            let key = "2030-03-02"

            vm.updateSchedule(date: date, field: .os, value: "Pending Local")
            #expect(vm.schedules[key]?.os == "Pending Local")

            let cloudSchedules: [String: ScheduleRecord] = [
                key: ScheduleRecord(date: date, os: "Cloud Conflict")
            ]
            vm.mergeCloudKitData(loadedSchedules: cloudSchedules, loadedNotes: [:])

            #expect(vm.schedules[key]?.os == "Pending Local")
        }
    }

    @Test @MainActor func mergePendingDeletionStaysAbsent() {
        CacheFileGate.withLock {
            let vm = makeViewModel()
            let date = utcDate(year: 2030, month: 3, day: 3)
            let key = "2030-03-03"

            vm.updateSchedule(date: date, field: .os, value: "To Delete")
            #expect(vm.schedules[key] != nil)

            vm.updateSchedule(date: date, field: .os, value: "")
            #expect(vm.schedules[key] == nil)

            let cloudSchedules: [String: ScheduleRecord] = [
                key: ScheduleRecord(date: date, os: "Cloud Resurrection")
            ]
            vm.mergeCloudKitData(loadedSchedules: cloudSchedules, loadedNotes: [:])

            #expect(vm.schedules[key] == nil)
        }
    }

    @Test @MainActor func monthlyNotesCreateAndRemove() {
        CacheFileGate.withLock {
            let vm = makeViewModel()
            let date = utcDate(year: 2030, month: 4, day: 1)
            let key = "2030-04"

            vm.updateMonthlyNotesLine1(for: date, line1: "First line")
            #expect(vm.monthlyNotes[key]?.line1 == "First line")

            vm.updateMonthlyNotesLine2(for: date, line2: "Second line")
            #expect(vm.monthlyNotes[key]?.line2 == "Second line")

            vm.updateMonthlyNotesLine1(for: date, line1: "")
            #expect(vm.monthlyNotes[key]?.line2 == "Second line")

            vm.updateMonthlyNotesLine2(for: date, line2: "")
            #expect(vm.monthlyNotes[key] == nil)
        }
    }
}
