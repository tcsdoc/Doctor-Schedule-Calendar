// SupportTypes.swift
// Shared enums and Array extensions used across PSC views.

// MARK: - Supporting Types
enum ScheduleField {
    case os, cl, off, call
}

// MARK: - Array Extension for Calendar Grid
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

// MARK: - Array Extension
extension Array {
    func safeGet(index: Int) -> Element? {
        return index >= 0 && index < count ? self[index] : nil
    }
}
