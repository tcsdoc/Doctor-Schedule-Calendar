//
//  Doctor_Schedule_CalendarApp.swift
//  Doctor Schedule Calendar
//
//  Created by mark on 7/5/25.
//

import SwiftUI

@main
struct Doctor_Schedule_CalendarApp: App {
    let coreDataManager = CoreDataCloudKitManager.shared

    init() {
        NSLog("🔥 APP STARTING WITH CORE DATA + CLOUDKIT SHARING - THIS SHOULD APPEAR IN CONSOLE")
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
        print("📨 Received CloudKit share URL: \(url)")
        
        // Extract share metadata from URL
        // The actual implementation would parse the CloudKit share URL
        // and call coreDataManager.handleAcceptedShare()
    }
}
