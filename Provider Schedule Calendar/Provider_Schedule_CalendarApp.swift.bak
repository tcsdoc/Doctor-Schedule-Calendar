//
//  Provider_Schedule_CalendarApp.swift
//  Provider Schedule Calendar
//
//  Created by mark on 7/5/25.
//

import SwiftUI

@main
struct Provider_Schedule_CalendarApp: App {
    let cloudKitManager = CloudKitManager.shared

    init() {
        debugLog("🚀 Provider Schedule Calendar initialized - Custom Zones: ProviderScheduleZone")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(cloudKitManager) // CloudKitManager with custom zones for privacy
        }
    }
}
