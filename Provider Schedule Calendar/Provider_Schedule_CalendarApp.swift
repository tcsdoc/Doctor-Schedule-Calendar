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
    let coreDataManager = CoreDataCloudKitManager.shared // Keep for Core Data if needed

    init() {
        #if DEBUG
        NSLog("🔥 APP STARTING WITH PRIVACY-FOCUSED CLOUDKIT CUSTOM ZONES")
        print("🔥 APP STARTING WITH PRIVACY-FOCUSED CLOUDKIT CUSTOM ZONES")
        #endif
        
        // Force console output even in release
        NSLog("🚀 Provider Schedule Calendar initialized - Version with Custom Zones")
        print("🚀 Provider Schedule Calendar initialized - Version with Custom Zones")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, coreDataManager.viewContext)
                .environmentObject(cloudKitManager) // Use new CloudKitManager for privacy
                .environmentObject(coreDataManager) // Keep for Core Data compatibility
        }
    }
}
