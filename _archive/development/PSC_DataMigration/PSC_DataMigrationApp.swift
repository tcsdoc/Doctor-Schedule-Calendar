//
//  PSC_DataMigrationApp.swift
//  PSC Data Migration
//
//  Migration app to transfer Lisa's data from Version 2 to Version 3
//  Source Zone: com.apple.coredata.cloudkit.share.0E031FC4-3C64-4F34-AFEC-375AD170A0E9
//  Target Zone: user_com.gulfcoast.ProviderCalendar
//

import SwiftUI

@main
struct PSC_DataMigrationApp: App {
    @StateObject private var migrationManager = MigrationManager.shared
    
    var body: some Scene {
        WindowGroup {
            MigrationView()
                .environmentObject(migrationManager)
        }
    }
}
