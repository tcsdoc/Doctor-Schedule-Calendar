//
//  Doctor_Schedule_CalendarApp.swift
//  Doctor Schedule Calendar
//
//  Created by mark on 7/5/25.
//

import SwiftUI

@main
struct Doctor_Schedule_CalendarApp: App {
    let cloudKitManager = CloudKitManager.shared

    init() {
        NSLog("🔥 APP STARTING - THIS SHOULD APPEAR IN CONSOLE")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(cloudKitManager)
        }
    }
}
