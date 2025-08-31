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
        #if DEBUG
        NSLog("🔥 APP STARTING WITH PRIVACY-FOCUSED CLOUDKIT CUSTOM ZONES")
        print("🔥 APP STARTING WITH PRIVACY-FOCUSED CLOUDKIT CUSTOM ZONES")
        #endif
        
        // Force console output even in release
        NSLog("🚀 Provider Schedule Calendar initialized - Custom Zones: user_com.gulfcoast.ProviderCalendar")
        print("🚀 Provider Schedule Calendar initialized - Custom Zones: user_com.gulfcoast.ProviderCalendar")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(cloudKitManager) // CloudKitManager with custom zones for privacy
        }
    }
}
