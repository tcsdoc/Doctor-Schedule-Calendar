#!/usr/bin/env swift

import Foundation
import CloudKit

// Quick CloudKit to CSV exporter
class CloudKitExporter {
    private let container: CKContainer
    private let database: CKDatabase
    
    init() {
        container = CKContainer(identifier: "iCloud.com.gulfcoast.ProviderCalendar")
        database = container.privateCloudDatabase
    }
    
    func exportDailySchedules() {
        print("Exporting Daily Schedules...")
        
        let query = CKQuery(recordType: "CD_DailySchedule", predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "CD_date", ascending: true)]
        
        let operation = CKQueryOperation(query: query)
        operation.zoneID = CKRecordZone.ID(zoneName: "user_com.gulfcoast.ProviderCalendar")
        operation.resultsLimit = 1000
        
        var records: [CKRecord] = []
        operation.recordMatchedBlock = { recordID, result in
            switch result {
            case .success(let record):
                records.append(record)
            case .failure(let error):
                print("Error fetching record: \(error)")
            }
        }
        
        operation.queryResultBlock = { result in
            switch result {
            case .success(_):
                self.writeDailySchedulesToCSV(records)
            case .failure(let error):
                print("Query failed: \(error)")
            }
        }
        
        database.add(operation)
    }
    
    func exportMonthlyNotes() {
        print("Exporting Monthly Notes...")
        
        let query = CKQuery(recordType: "CD_MonthlyNotes", predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "CD_month", ascending: true)]
        
        let operation = CKQueryOperation(query: query)
        operation.zoneID = CKRecordZone.ID(zoneName: "user_com.gulfcoast.ProviderCalendar")
        operation.resultsLimit = 1000
        
        var records: [CKRecord] = []
        operation.recordMatchedBlock = { recordID, result in
            switch result {
            case .success(let record):
                records.append(record)
            case .failure(let error):
                print("Error fetching record: \(error)")
            }
        }
        
        operation.queryResultBlock = { result in
            switch result {
            case .success(_):
                self.writeMonthlyNotesToCSV(records)
            case .failure(let error):
                print("Query failed: \(error)")
            }
        }
        
        database.add(operation)
    }
    
    private func writeDailySchedulesToCSV(_ records: [CKRecord]) {
        var csv = "Date,Line1,Line2,Line3\n"
        
        for record in records {
            let date = record["CD_date"] as? Date ?? Date()
            let line1 = record["CD_line1"] as? String ?? ""
            let line2 = record["CD_line2"] as? String ?? ""
            let line3 = record["CD_line3"] as? String ?? ""
            
            let dateStr = ISO8601DateFormatter().string(from: date)
            csv += "\"\(dateStr)\",\"\(line1)\",\"\(line2)\",\"\(line3)\"\n"
        }
        
        try? csv.write(to: URL(fileURLWithPath: "daily_schedules.csv"), atomically: true, encoding: .utf8)
        print("Daily schedules exported to daily_schedules.csv")
    }
    
    private func writeMonthlyNotesToCSV(_ records: [CKRecord]) {
        var csv = "Month,Year,Line1,Line2,Line3\n"
        
        for record in records {
            let month = record["CD_month"] as? Int ?? 0
            let year = record["CD_year"] as? Int ?? 0
            let line1 = record["CD_line1"] as? String ?? ""
            let line2 = record["CD_line2"] as? String ?? ""
            let line3 = record["CD_line3"] as? String ?? ""
            
            csv += "\"\(month)\",\"\(year)\",\"\(line1)\",\"\(line2)\",\"\(line3)\"\n"
        }
        
        try? csv.write(to: URL(fileURLWithPath: "monthly_notes.csv"), atomically: true, encoding: .utf8)
        print("Monthly notes exported to monthly_notes.csv")
    }
}

// Run the exporter
let exporter = CloudKitExporter()
exporter.exportDailySchedules()
exporter.exportMonthlyNotes()

print("Export complete! Check for daily_schedules.csv and monthly_notes.csv files.")
