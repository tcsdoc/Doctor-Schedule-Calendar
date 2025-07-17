//
//  Persistence.swift
//  Doctor Schedule Calendar
//
//  Created by mark on 7/5/25.
//

import Foundation
import CoreData
import CloudKit

struct PersistenceController {
    static let shared = PersistenceController()

    static var preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext
        // ... preview data ...
        for i in 0..<3 {
            let newItem = DailySchedule(context: viewContext)
            newItem.date = Date().addingTimeInterval(TimeInterval(i * 86400))
            newItem.id = UUID()
            newItem.line1 = "Sample Line 1"
            newItem.line2 = "Sample Line 2"
            newItem.line3 = "Sample Line 3"
        }
        do {
            try viewContext.save()
        } catch {
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
        return result
    }()

    let container: NSPersistentCloudKitContainer

    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "Doctor_Schedule_Calendar")

        if inMemory {
            // For previews, use a memory-only store
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }

        // Enable history tracking and remote change notifications
        guard let description = container.persistentStoreDescriptions.first else {
            fatalError("###<FATAL>### Failed to retrieve a persistent store description.")
        }
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        
        // Configure CloudKit container options for public database
        if let description = container.persistentStoreDescriptions.first {
            description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: "iCloud.com.gulfcoast.ProviderCalendar")
            description.cloudKitContainerOptions?.databaseScope = .public
        }

        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        })
        
        container.viewContext.automaticallyMergesChangesFromParent = true
    }
}
