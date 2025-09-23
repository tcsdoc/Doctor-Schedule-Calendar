import Foundation

// MARK: - Shared Debug Logging for PSC Redesign
func redesignLog(_ message: String) {
    #if DEBUG
    print("PSC REDESIGN: \(message)")
    #endif
}
