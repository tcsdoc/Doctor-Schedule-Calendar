import Foundation

// MARK: - On-device schedule cache (offline read + unsynced edits)
struct ScheduleCacheSnapshot: Codable {
    let savedAt: Date
    let schedules: [String: ScheduleRecord]
    let monthlyNotes: [String: MonthlyNote]
    let pendingScheduleKeys: [String]
    let pendingNoteKeys: [String]

    init(
        savedAt: Date,
        schedules: [String: ScheduleRecord],
        monthlyNotes: [String: MonthlyNote],
        pendingScheduleKeys: [String] = [],
        pendingNoteKeys: [String] = []
    ) {
        self.savedAt = savedAt
        self.schedules = schedules
        self.monthlyNotes = monthlyNotes
        self.pendingScheduleKeys = pendingScheduleKeys
        self.pendingNoteKeys = pendingNoteKeys
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        savedAt = try container.decode(Date.self, forKey: .savedAt)
        schedules = try container.decode([String: ScheduleRecord].self, forKey: .schedules)
        monthlyNotes = try container.decode([String: MonthlyNote].self, forKey: .monthlyNotes)
        pendingScheduleKeys = try container.decodeIfPresent([String].self, forKey: .pendingScheduleKeys) ?? []
        pendingNoteKeys = try container.decodeIfPresent([String].self, forKey: .pendingNoteKeys) ?? []
    }
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

    static func save(
        schedules: [String: ScheduleRecord],
        monthlyNotes: [String: MonthlyNote],
        pendingScheduleKeys: Set<String>,
        pendingNoteKeys: Set<String>
    ) {
        let snapshot = ScheduleCacheSnapshot(
            savedAt: Date(),
            schedules: schedules,
            monthlyNotes: monthlyNotes,
            pendingScheduleKeys: Array(pendingScheduleKeys).sorted(),
            pendingNoteKeys: Array(pendingNoteKeys).sorted()
        )
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: cacheFileURL, options: .atomic)
        } catch {
            redesignLog("❌ Failed to save local schedule cache: \(error)")
        }
    }
}
