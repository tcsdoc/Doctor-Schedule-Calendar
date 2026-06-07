import Foundation

// MARK: - On-device schedule cache (offline read access)
struct ScheduleCacheSnapshot: Codable {
    let savedAt: Date
    let schedules: [String: ScheduleRecord]
    let monthlyNotes: [String: MonthlyNote]
}

enum ScheduleLocalCache {
    private static let fileName = "schedule_cache.json"

    private static var cacheFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("ProviderScheduleCalendar", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(fileName)
    }

    static func load() -> ScheduleCacheSnapshot? {
        let url = cacheFileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(ScheduleCacheSnapshot.self, from: data)
        } catch {
            redesignLog("❌ Failed to load local schedule cache: \(error)")
            return nil
        }
    }

    static func save(schedules: [String: ScheduleRecord], monthlyNotes: [String: MonthlyNote]) {
        let snapshot = ScheduleCacheSnapshot(
            savedAt: Date(),
            schedules: schedules,
            monthlyNotes: monthlyNotes
        )
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: cacheFileURL, options: .atomic)
        } catch {
            redesignLog("❌ Failed to save local schedule cache: \(error)")
        }
    }
}
