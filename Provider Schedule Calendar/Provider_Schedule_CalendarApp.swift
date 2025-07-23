//
//  Provider_Schedule_CalendarApp.swift
//  Provider Schedule Calendar
//
//  Created by mark on 7/5/25.
//

import SwiftUI

@main
struct Provider_Schedule_CalendarApp: App {
    let coreDataManager = CoreDataCloudKitManager.shared

    init() {
        #if DEBUG
        NSLog("🔥 APP STARTING WITH CORE DATA + CLOUDKIT SHARING - THIS SHOULD APPEAR IN CONSOLE")
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, coreDataManager.viewContext)
                .environmentObject(coreDataManager)
                .onOpenURL { url in
                    // Handle CloudKit share URLs
                    handleIncomingURL(url)
                }
        }
    }
    
    // MARK: - CloudKit Share URL Handling
    private func handleIncomingURL(_ url: URL) {
        guard url.scheme == "https" && url.host == "www.icloud.com" else { return }
        
        // This is a CloudKit share URL
        #if DEBUG
        print("📨 Received CloudKit share URL: \(url)")
        #endif
        
        // Extract share metadata from URL
        // The actual implementation would parse the CloudKit share URL
        // and call coreDataManager.handleAcceptedShare()
    }
}
