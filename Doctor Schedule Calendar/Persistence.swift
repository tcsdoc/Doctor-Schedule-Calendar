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
        
        // Create 2 Locations
        let location1 = Location(context: viewContext)
        location1.id = UUID()
        location1.name = "Main Clinic"
        location1.address = "123 Medical Center Dr, Suite 100"
        location1.phone = "(555) 123-4567"
        
        let location2 = Location(context: viewContext)
        location2.id = UUID()
        location2.name = "Satellite Office"
        location2.address = "456 Health Plaza, Building B"
        location2.phone = "(555) 987-6543"
        
        // Create 9 Providers
        let providerNames = [
            ("Dr. Sarah Johnson", "Cardiology"),
            ("Dr. Michael Chen", "Pediatrics"),
            ("Dr. Emily Rodriguez", "Dermatology"),
            ("Dr. David Kim", "Internal Medicine"),
            ("Dr. Lisa Thompson", "Family Practice"),
            ("Dr. Robert Wilson", "Orthopedics"),
            ("Dr. Maria Garcia", "Neurology"),
            ("Dr. James Brown", "Radiology"),
            ("Dr. Jennifer Davis", "Emergency Medicine")
        ]
        
        var providers: [Provider] = []
        for (name, specialty) in providerNames {
            let provider = Provider(context: viewContext)
            provider.id = UUID()
            provider.name = name
            provider.specialty = specialty
            provider.email = "\(name.lowercased().replacingOccurrences(of: " ", with: ".").replacingOccurrences(of: "dr.", with: ""))@clinic.com"
            provider.phone = "(555) \(Int.random(in: 100...999))-\(Int.random(in: 1000...9999))"
            providers.append(provider)
        }
        
        // Create sample schedules for next 3 months
        let calendar = Calendar.current
        let today = Date()
        
        // Sample daily schedules for demonstration
        for monthOffset in 0..<3 {
            guard let monthStart = calendar.date(byAdding: .month, value: monthOffset, to: today),
                  let monthRange = calendar.range(of: .day, in: .month, for: monthStart) else { continue }
            
            // Create monthly notes
            let monthlyNotes = MonthlyNotes(context: viewContext)
            monthlyNotes.id = UUID()
            monthlyNotes.month = Int16(calendar.component(.month, from: monthStart))
            monthlyNotes.year = Int16(calendar.component(.year, from: monthStart))
            monthlyNotes.line1 = monthOffset == 0 ? "Current month scheduling notes" : "Future planning notes"
            monthlyNotes.line2 = "Holiday coverage: Check federal calendar"
            monthlyNotes.line3 = "Training sessions: First Friday of month"
            
            // Create daily schedules for each day of the month
            for day in 1...monthRange.count {
                guard let date = calendar.date(byAdding: .day, value: day - 1, 
                                             to: calendar.dateInterval(of: .month, for: monthStart)?.start ?? monthStart) else { continue }
                
                // Skip past dates
                if date < calendar.startOfDay(for: today) { continue }
                
                // Create schedule entry for this day
                let dailySchedule = DailySchedule(context: viewContext)
                dailySchedule.id = UUID()
                dailySchedule.date = date
                
                // Randomly assign providers and locations for demo data
                let weekday = calendar.component(.weekday, from: date)
                if weekday >= 2 && weekday <= 6 { // Monday to Friday
                    let randomProvider = providers.randomElement()
                    let randomLocation = [location1, location2].randomElement()
                    
                    dailySchedule.providerID = randomProvider?.id
                    dailySchedule.locationID = randomLocation?.id
                    dailySchedule.line1 = "\(randomProvider?.name ?? "TBD") at \(randomLocation?.name ?? "TBD")"
                    dailySchedule.line2 = "8:00 AM - 5:00 PM"
                    dailySchedule.line3 = "Regular clinic hours"
                } else {
                    // Weekend - limited coverage
                    if weekday == 1 { // Sunday
                        dailySchedule.line1 = "Emergency coverage only"
                        dailySchedule.line2 = "On-call: \(providers.randomElement()?.name ?? "TBD")"
                        dailySchedule.line3 = "Location: Main Clinic"
                        dailySchedule.locationID = location1.id
                    }
                    // Saturday - no scheduled coverage in this demo
                }
            }
        }
        
        do {
            try viewContext.save()
        } catch {
            // Replace this implementation with code to handle the error appropriately.
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
