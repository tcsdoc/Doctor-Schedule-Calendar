//
//  MigrationView.swift
//  PSC Data Migration
//
//  User interface for Lisa's data migration from Version 2 to Version 3
//

import SwiftUI

struct MigrationView: View {
    @EnvironmentObject var migrationManager: MigrationManager
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                headerSection
                statusSection
                progressSection
                actionSection
                Spacer()
            }
            .padding()
            .navigationTitle("PSC Data Migration")
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 15) {
            Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            Text("Provider Schedule Calendar")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Data Migration Tool")
                .font(.headline)
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text("This tool will migrate your schedule data from")
                    .font(.body)
                    .multilineTextAlignment(.center)
                Text("Version 2 → Version 3")
                    .font(.headline)
                    .foregroundColor(.blue)
                    .fontWeight(.semibold)
            }
        }
    }
    
    // MARK: - Status Section
    private var statusSection: some View {
        VStack(spacing: 15) {
            // CloudKit Status
            HStack {
                Image(systemName: migrationManager.cloudKitAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(migrationManager.cloudKitAvailable ? .green : .red)
                Text("iCloud Connection")
                Spacer()
                Text(migrationManager.cloudKitAvailable ? "Ready" : "Not Available")
                    .foregroundColor(migrationManager.cloudKitAvailable ? .green : .red)
                    .fontWeight(.medium)
            }
            
            // Migration Status
            HStack {
                Image(systemName: statusIcon)
                    .foregroundColor(statusColor)
                Text("Migration Status")
                Spacer()
                Text(migrationManager.migrationStatus.description)
                    .foregroundColor(statusColor)
                    .fontWeight(.medium)
            }
            
            // Error Message
            if let errorMessage = migrationManager.errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .padding(.top, 5)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Progress Section
    private var progressSection: some View {
        VStack(spacing: 15) {
            if migrationManager.progress.totalRecords > 0 {
                // Progress Bar
                VStack(spacing: 8) {
                    HStack {
                        Text("Migration Progress")
                            .font(.headline)
                        Spacer()
                        Text("\(migrationManager.progress.migratedRecords)/\(migrationManager.progress.totalRecords)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    ProgressView(value: migrationManager.progress.progressPercentage)
                        .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                }
                
                // Current Step
                if !migrationManager.progress.currentStep.isEmpty {
                    Text(migrationManager.progress.currentStep)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                // Data Summary
                VStack(spacing: 8) {
                    Text("Data Summary")
                        .font(.headline)
                    
                    HStack {
                        VStack {
                            Text("\(migrationManager.progress.dailySchedules)")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.blue)
                            Text("Daily Schedules")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        VStack {
                            Text("\(migrationManager.progress.monthlyNotes)")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.green)
                            Text("Monthly Notes")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        VStack {
                            Text("\(migrationManager.progress.verifiedRecords)")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.purple)
                            Text("Verified")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Action Section
    private var actionSection: some View {
        VStack(spacing: 15) {
            switch migrationManager.migrationStatus {
            case .notStarted:
                Button("Start Migration") {
                    migrationManager.startMigration()
                }
                .disabled(!migrationManager.cloudKitAvailable)
                .foregroundColor(.white)
                .padding()
                .frame(maxWidth: .infinity)
                .background(migrationManager.cloudKitAvailable ? Color.blue : Color.gray)
                .cornerRadius(12)
                
                Text("⚠️ Make sure you're signed in with Lisa's Apple ID")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .multilineTextAlignment(.center)
                
            case .discovering, .preparingTarget, .migrating, .verifying:
                Button("Migration In Progress...") { }
                    .disabled(true)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.gray)
                    .cornerRadius(12)
                
            case .completed:
                VStack(spacing: 15) {
                    Text("✅ Migration Completed Successfully!")
                        .font(.headline)
                        .foregroundColor(.green)
                        .multilineTextAlignment(.center)
                    
                    Text("Lisa's data has been migrated to Version 3 format. You can now:")
                        .font(.body)
                        .multilineTextAlignment(.center)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("• Install Provider Schedule Calendar Version 3")
                        Text("• All schedule data will be visible")
                        Text("• Share schedules with ScheduleViewer")
                        Text("• Enjoy stable, bulletproof operation")
                    }
                    .font(.body)
                    .foregroundColor(.secondary)
                    
                    Button("Run Migration Again") {
                        migrationManager.resetMigration()
                    }
                    .foregroundColor(.blue)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)
                }
                
            case .failed:
                VStack(spacing: 15) {
                    Text("❌ Migration Failed")
                        .font(.headline)
                        .foregroundColor(.red)
                    
                    Button("Try Again") {
                        migrationManager.resetMigration()
                    }
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.red)
                    .cornerRadius(12)
                }
            }
        }
    }
    
    // MARK: - Computed Properties
    private var statusIcon: String {
        switch migrationManager.migrationStatus {
        case .notStarted:
            return "play.circle"
        case .discovering, .preparingTarget, .migrating, .verifying:
            return "arrow.trianglehead.2.clockwise.rotate.90"
        case .completed:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.circle.fill"
        }
    }
    
    private var statusColor: Color {
        switch migrationManager.migrationStatus {
        case .notStarted:
            return .blue
        case .discovering, .preparingTarget, .migrating, .verifying:
            return .orange
        case .completed:
            return .green
        case .failed:
            return .red
        }
    }
}

#Preview {
    MigrationView()
        .environmentObject(MigrationManager.shared)
}
