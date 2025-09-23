import SwiftUI

// @main  // Disabled for testing - will replace original when ready
struct Provider_Schedule_CalendarApp_New: App {
    
    init() {
        redesignLog("🚀 Provider Schedule Calendar REDESIGN initialized")
        redesignLog("🎯 Modern architecture: MVVM + Simple CloudKit + SV-inspired UI")
    }

    var body: some Scene {
        WindowGroup {
            ContentView_New()
        }
    }
}

