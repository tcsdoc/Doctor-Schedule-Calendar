//
//  Persistence.swift
//  Doctor Schedule Calendar
//
//  Created by mark on 7/5/25.
//

import CoreData

struct PersistenceController {
    static let shared = PersistenceController()

    @MainActor
    static let preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext
        
        // Create sample monthly notes for current month
        let currentDate = Date()
        let calendar = Calendar.current
        let currentMonth = calendar.component(.month, from: currentDate)
        let currentYear = calendar.component(.year, from: currentDate)
        
        let monthlyNotes = MonthlyNotes(context: viewContext)
        monthlyNotes.id = UUID()
        monthlyNotes.month = Int32(currentMonth)
        monthlyNotes.year = Int32(currentYear)
        monthlyNotes.line1 = "Holiday schedules updated"
        monthlyNotes.line2 = "Staff meeting planned for 15th"
        monthlyNotes.line3 = "New coverage protocols"
        
        // Create sample daily schedules for a few days
        let today = calendar.startOfDay(for: currentDate)
        
        for dayOffset in 0..<7 {
            if let date = calendar.date(byAdding: .day, value: dayOffset, to: today) {
                let dailySchedule = DailySchedule(context: viewContext)
                dailySchedule.id = UUID()
                dailySchedule.date = date
                
                switch dayOffset {
                case 0:
                    dailySchedule.line1 = "Dr. Smith - Main Clinic"
                    dailySchedule.line2 = "Dr. Johnson - Satellite"
                    dailySchedule.line3 = "Coverage until 6pm"
                case 1:
                    dailySchedule.line1 = "Dr. Wilson - Main Clinic"
                    dailySchedule.line2 = "Dr. Brown - Both locations"
                    dailySchedule.line3 = "Emergency on-call setup"
                case 2:
                    dailySchedule.line1 = "Dr. Davis - Satellite"
                    dailySchedule.line2 = "Dr. Miller - Main Clinic"
                    dailySchedule.line3 = "Extended hours"
                default:
                    dailySchedule.line1 = "Regular coverage"
                    dailySchedule.line2 = "Standard hours"
                    dailySchedule.line3 = "Check schedule"
                }
            }
        }
        
        do {
            try viewContext.save()
        } catch {
            // Replace this implementation with code to handle the error appropriately.
            // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
        return result
    }()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "Doctor_Schedule_Calendar")
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                // Replace this implementation with code to handle the error appropriately.
                // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.

                /*
                 Typical reasons for an error here include:
                 * The parent directory does not exist, cannot be created, or disallows writing.
                 * The persistent store is not accessible, due to permissions or data protection when the device is locked.
                 * The device is out of space.
                 * The store could not be migrated to the current model version.
                 Check the error message to determine what the actual problem was.
                 */
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        })
        container.viewContext.automaticallyMergesChangesFromParent = true
    }
}
