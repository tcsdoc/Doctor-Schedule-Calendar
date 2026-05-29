//
//  MigrationManager.swift
//  PSC Data Migration
//
//  Handles the migration of Lisa's schedule data from Version 2 to Version 3
//

import Foundation
import CloudKit
import SwiftUI

// MARK: - Debug Logging Helper
func migrationLog(_ message: String) {
    print("🔄 MIGRATION: \(message)")
}

@MainActor
class MigrationManager: ObservableObject {
    static let shared = MigrationManager()
    
    private let container: CKContainer
    private let privateDatabase: CKDatabase
    
    // Lisa's specific legacy zone from CloudKit Dashboard
    private let legacyZoneID = CKRecordZone.ID(
        zoneName: "com.apple.coredata.cloudkit.share.0E031FC4-3C64-4F34-AFEC-375AD170A0E9"
    )
    
    // Version 3 target zone
    private let targetZoneID = CKRecordZone.ID(zoneName: "user_com.gulfcoast.ProviderCalendar")
    
    @Published var migrationStatus: MigrationStatus = .notStarted
    @Published var progress: MigrationProgress = MigrationProgress()
    @Published var cloudKitAvailable = false
    @Published var errorMessage: String?
    
    private var discoveredRecords: [CKRecord] = []
    private var migratedRecords: [CKRecord] = []
    
    init() {
        container = CKContainer(identifier: "iCloud.com.gulfcoast.ProviderCalendar")
        privateDatabase = container.privateCloudDatabase
        
        checkCloudKitStatus()
        migrationLog("Migration Manager initialized")
        migrationLog("Legacy Zone: \(legacyZoneID.zoneName)")
        migrationLog("Target Zone: \(targetZoneID.zoneName)")
    }
    
    // MARK: - CloudKit Status
    private func checkCloudKitStatus() {
        container.accountStatus { [weak self] status, error in
            DispatchQueue.main.async {
                switch status {
                case .available:
                    self?.cloudKitAvailable = true
                    self?.errorMessage = nil
                    migrationLog("✅ CloudKit available for migration")
                case .noAccount:
                    self?.cloudKitAvailable = false
                    self?.errorMessage = "Please sign in to iCloud to perform migration"
                    migrationLog("❌ No iCloud account")
                case .restricted:
                    self?.cloudKitAvailable = false
                    self?.errorMessage = "iCloud access is restricted"
                    migrationLog("❌ CloudKit restricted")
                default:
                    self?.cloudKitAvailable = false
                    self?.errorMessage = "CloudKit unavailable"
                    migrationLog("❌ CloudKit unavailable")
                }
            }
        }
    }
    
    // MARK: - Migration Process
    func startMigration() {
        guard cloudKitAvailable else {
            errorMessage = "CloudKit not available for migration"
            return
        }
        
        migrationStatus = .discovering
        progress = MigrationProgress()
        errorMessage = nil
        
        migrationLog("🚀 Starting migration process")
        
        Task {
            do {
                // Step 1: Discover existing data
                try await discoverLegacyData()
                
                // Step 2: Create target zone
                try await createTargetZone()
                
                // Step 3: Migrate data
                try await migrateData()
                
                // Step 4: Verify migration
                try await verifyMigration()
                
                await MainActor.run {
                    migrationStatus = .completed
                    migrationLog("✅ Migration completed successfully!")
                }
                
            } catch {
                await MainActor.run {
                    migrationStatus = .failed
                    errorMessage = error.localizedDescription
                    migrationLog("❌ Migration failed: \(error)")
                }
            }
        }
    }
    
    // MARK: - Step 1: Discover Legacy Data
    private func discoverLegacyData() async throws {
        migrationLog("🔍 Step 1: Discovering legacy data in zone: \(legacyZoneID.zoneName)")
        
        await MainActor.run {
            migrationStatus = .discovering
            progress.currentStep = "Discovering existing data..."
        }
        
        // Query for all CD_DailySchedule records in legacy zone
        let dailyQuery = CKQuery(recordType: "CD_DailySchedule", predicate: NSPredicate(value: true))
        dailyQuery.sortDescriptors = [NSSortDescriptor(key: "CD_date", ascending: true)]
        
        let (dailyResults, _) = try await privateDatabase.records(matching: dailyQuery, inZoneWith: legacyZoneID)
        let dailyRecords = dailyResults.compactMap { try? $0.1.get() }
        
        // Query for all CD_MonthlyNotes records in legacy zone
        let monthlyQuery = CKQuery(recordType: "CD_MonthlyNotes", predicate: NSPredicate(value: true))
        monthlyQuery.sortDescriptors = [NSSortDescriptor(key: "CD_year", ascending: true)]
        
        let (monthlyResults, _) = try await privateDatabase.records(matching: monthlyQuery, inZoneWith: legacyZoneID)
        let monthlyRecords = monthlyResults.compactMap { try? $0.1.get() }
        
        discoveredRecords = dailyRecords + monthlyRecords
        
        await MainActor.run {
            progress.totalRecords = discoveredRecords.count
            progress.dailySchedules = dailyRecords.count
            progress.monthlyNotes = monthlyRecords.count
        }
        
        migrationLog("📊 Discovered \(dailyRecords.count) daily schedules")
        migrationLog("📊 Discovered \(monthlyRecords.count) monthly notes")
        migrationLog("📊 Total records to migrate: \(discoveredRecords.count)")
        
        guard !discoveredRecords.isEmpty else {
            throw MigrationError.noDataFound
        }
    }
    
    // MARK: - Step 2: Create Target Zone
    private func createTargetZone() async throws {
        migrationLog("🏗️ Step 2: Creating target zone: \(targetZoneID.zoneName)")
        
        await MainActor.run {
            migrationStatus = .preparingTarget
            progress.currentStep = "Creating target zone..."
        }
        
        // Check if target zone already exists
        let existingZones = try await privateDatabase.allRecordZones()
        
        if existingZones.contains(where: { $0.zoneID == targetZoneID }) {
            migrationLog("✅ Target zone already exists")
            return
        }
        
        // Create new target zone
        let newZone = CKRecordZone(zoneID: targetZoneID)
        let result = try await privateDatabase.modifyRecordZones(saving: [newZone], deleting: [])
        
        guard let _ = try result.saveResults[targetZoneID]?.get() else {
            throw MigrationError.zoneCreationFailed
        }
        
        migrationLog("✅ Target zone created successfully")
    }
    
    // MARK: - Step 3: Migrate Data
    private func migrateData() async throws {
        migrationLog("📦 Step 3: Migrating \(discoveredRecords.count) records")
        
        await MainActor.run {
            migrationStatus = .migrating
            progress.currentStep = "Migrating records..."
            progress.migratedRecords = 0
        }
        
        // Migrate records in batches to avoid CloudKit limits
        let batchSize = 50
        let batches = discoveredRecords.chunked(into: batchSize)
        
        for (batchIndex, batch) in batches.enumerated() {
            migrationLog("📦 Processing batch \(batchIndex + 1) of \(batches.count) (\(batch.count) records)")
            
            var recordsToSave: [CKRecord] = []
            
            for legacyRecord in batch {
                // Create new record in target zone with same data
                let newRecordID = CKRecord.ID(recordName: UUID().uuidString, zoneID: targetZoneID)
                let newRecord = CKRecord(recordType: legacyRecord.recordType, recordID: newRecordID)
                
                // Copy all fields from legacy record
                for key in legacyRecord.allKeys() {
                    if !key.hasPrefix("CD_") { continue } // Only copy our data fields
                    newRecord[key] = legacyRecord[key]
                }
                
                // Add entity name for Version 3 compatibility
                if legacyRecord.recordType == "CD_DailySchedule" {
                    newRecord["CD_entityName"] = "DailySchedule" as CKRecordValue
                } else if legacyRecord.recordType == "CD_MonthlyNotes" {
                    newRecord["CD_entityName"] = "MonthlyNotes" as CKRecordValue
                }
                
                recordsToSave.append(newRecord)
            }
            
            // Save batch to target zone
            let result = try await privateDatabase.modifyRecords(saving: recordsToSave, deleting: [])
            
            // Track successful saves
            for (recordID, saveResult) in result.saveResults {
                switch saveResult {
                case .success(let savedRecord):
                    migratedRecords.append(savedRecord)
                    await MainActor.run {
                        progress.migratedRecords += 1
                    }
                    migrationLog("✅ Migrated: \(recordID.recordName)")
                case .failure(let error):
                    migrationLog("❌ Failed to migrate \(recordID.recordName): \(error)")
                    throw error
                }
            }
            
            await MainActor.run {
                progress.currentStep = "Migrated \(progress.migratedRecords) of \(progress.totalRecords) records..."
            }
            
            // Small delay between batches to be nice to CloudKit
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 second
        }
        
        migrationLog("✅ All records migrated successfully")
    }
    
    // MARK: - Step 4: Verify Migration
    private func verifyMigration() async throws {
        migrationLog("🔍 Step 4: Verifying migration")
        
        await MainActor.run {
            migrationStatus = .verifying
            progress.currentStep = "Verifying migration..."
        }
        
        // Query target zone to verify all records are there
        let dailyQuery = CKQuery(recordType: "CD_DailySchedule", predicate: NSPredicate(value: true))
        let (dailyResults, _) = try await privateDatabase.records(matching: dailyQuery, inZoneWith: targetZoneID)
        let verifiedDaily = dailyResults.compactMap { try? $0.1.get() }
        
        let monthlyQuery = CKQuery(recordType: "CD_MonthlyNotes", predicate: NSPredicate(value: true))
        let (monthlyResults, _) = try await privateDatabase.records(matching: monthlyQuery, inZoneWith: targetZoneID)
        let verifiedMonthly = monthlyResults.compactMap { try? $0.1.get() }
        
        let totalVerified = verifiedDaily.count + verifiedMonthly.count
        
        await MainActor.run {
            progress.verifiedRecords = totalVerified
        }
        
        migrationLog("📊 Verification: \(verifiedDaily.count) daily schedules")
        migrationLog("📊 Verification: \(verifiedMonthly.count) monthly notes")
        migrationLog("📊 Total verified: \(totalVerified)")
        
        guard totalVerified == progress.totalRecords else {
            throw MigrationError.verificationFailed(expected: progress.totalRecords, found: totalVerified)
        }
        
        migrationLog("✅ Migration verification successful!")
    }
    
    // MARK: - Reset for Testing
    func resetMigration() {
        migrationStatus = .notStarted
        progress = MigrationProgress()
        errorMessage = nil
        discoveredRecords = []
        migratedRecords = []
        migrationLog("🔄 Migration reset")
    }
}

// MARK: - Data Models
enum MigrationStatus {
    case notStarted
    case discovering
    case preparingTarget
    case migrating
    case verifying
    case completed
    case failed
    
    var description: String {
        switch self {
        case .notStarted: return "Ready to migrate"
        case .discovering: return "Discovering data..."
        case .preparingTarget: return "Preparing target zone..."
        case .migrating: return "Migrating records..."
        case .verifying: return "Verifying migration..."
        case .completed: return "Migration completed!"
        case .failed: return "Migration failed"
        }
    }
}

struct MigrationProgress {
    var currentStep: String = ""
    var totalRecords: Int = 0
    var migratedRecords: Int = 0
    var verifiedRecords: Int = 0
    var dailySchedules: Int = 0
    var monthlyNotes: Int = 0
    
    var progressPercentage: Double {
        guard totalRecords > 0 else { return 0 }
        return Double(migratedRecords) / Double(totalRecords)
    }
}

enum MigrationError: LocalizedError {
    case noDataFound
    case zoneCreationFailed
    case verificationFailed(expected: Int, found: Int)
    
    var errorDescription: String? {
        switch self {
        case .noDataFound:
            return "No data found in legacy zone"
        case .zoneCreationFailed:
            return "Failed to create target zone"
        case .verificationFailed(let expected, let found):
            return "Verification failed: expected \(expected) records, found \(found)"
        }
    }
}

// MARK: - Array Extension
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
