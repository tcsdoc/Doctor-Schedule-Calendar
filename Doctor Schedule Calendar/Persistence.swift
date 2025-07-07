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
        
        // Create sample doctors
        let doctor1 = Doctor(context: viewContext)
        doctor1.id = UUID()
        doctor1.name = "Dr. Sarah Johnson"
        doctor1.specialization = "Cardiology"
        doctor1.email = "sarah.johnson@hospital.com"
        doctor1.phone = "(555) 123-4567"
        
        let doctor2 = Doctor(context: viewContext)
        doctor2.id = UUID()
        doctor2.name = "Dr. Michael Chen"
        doctor2.specialization = "Pediatrics"
        doctor2.email = "michael.chen@hospital.com"
        doctor2.phone = "(555) 987-6543"
        
        let doctor3 = Doctor(context: viewContext)
        doctor3.id = UUID()
        doctor3.name = "Dr. Emily Rodriguez"
        doctor3.specialization = "Dermatology"
        doctor3.email = "emily.rodriguez@hospital.com"
        doctor3.phone = "(555) 456-7890"
        
        // Create sample appointments
        let calendar = Calendar.current
        let today = Date()
        
        // Appointment 1 - Today at 9:00 AM
        let appointment1 = Appointment(context: viewContext)
        appointment1.id = UUID()
        appointment1.title = "Routine Checkup"
        appointment1.patientName = "John Smith"
        appointment1.startDate = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: today) ?? today
        appointment1.endDate = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: today) ?? today
        appointment1.notes = "Annual physical examination"
        appointment1.doctor = doctor1
        
        // Appointment 2 - Today at 2:00 PM
        let appointment2 = Appointment(context: viewContext)
        appointment2.id = UUID()
        appointment2.title = "Follow-up Visit"
        appointment2.patientName = "Lisa Wilson"
        appointment2.startDate = calendar.date(bySettingHour: 14, minute: 0, second: 0, of: today) ?? today
        appointment2.endDate = calendar.date(bySettingHour: 14, minute: 30, second: 0, of: today) ?? today
        appointment2.notes = "Check blood pressure medication effectiveness"
        appointment2.doctor = doctor1
        
        // Appointment 3 - Tomorrow at 10:30 AM
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let appointment3 = Appointment(context: viewContext)
        appointment3.id = UUID()
        appointment3.title = "Child Wellness Visit"
        appointment3.patientName = "Emma Thompson"
        appointment3.startDate = calendar.date(bySettingHour: 10, minute: 30, second: 0, of: tomorrow) ?? tomorrow
        appointment3.endDate = calendar.date(bySettingHour: 11, minute: 15, second: 0, of: tomorrow) ?? tomorrow
        appointment3.notes = "6-month checkup for 2-year-old"
        appointment3.doctor = doctor2
        
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
