import Foundation

/// ScheduleLocalCache uses one fixed file; tests touching it must not overlap.
enum CacheFileGate {
    private static let lock = NSRecursiveLock()

    static func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}
