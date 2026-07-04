// DuplicateViews.swift
// Duplicate detection review sheet and row views.

import SwiftUI

// MARK: - Duplicate Details Review View
struct DuplicateDetailsView: View {
    let result: ScheduleViewModel.DuplicateDetectionResult
    let onCleanup: () -> Void
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Header summary
                VStack(spacing: 8) {
                    Text("📋 Duplicate Cleanup Report")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("This is a preview. Nothing will be deleted until you confirm.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    HStack(spacing: 20) {
                        VStack {
                            Text("\(result.totalAffectedDates)")
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundColor(.orange)
                            Text("Affected Dates")
                                .font(.caption)
                        }
                        
                        VStack {
                            Text("\(result.totalDuplicateCount)")
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundColor(.red)
                            Text("Records to Delete")
                                .font(.caption)
                        }
                    }
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(12)
                }
                .padding()
                
                // Scrollable list of duplicates
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if !result.scheduleDuplicates.isEmpty {
                            Text("Schedule Duplicates")
                                .font(.headline)
                                .padding(.horizontal)
                            
                            ForEach(result.scheduleDuplicates, id: \.dateKey) { group in
                                DuplicateGroupRow(group: group, type: "Schedule")
                            }
                        }
                        
                        if !result.monthlyNoteDuplicates.isEmpty {
                            Text("Monthly Note Duplicates")
                                .font(.headline)
                                .padding(.horizontal)
                                .padding(.top, 8)
                            
                            ForEach(result.monthlyNoteDuplicates, id: \.dateKey) { group in
                                DuplicateGroupRow(group: group, type: "Monthly Note")
                            }
                        }
                    }
                }
                
                // Action buttons
                HStack(spacing: 16) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
                    
                    Button("Proceed with Cleanup") {
                        onCleanup()
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct DuplicateGroupRow: View {
    let group: ScheduleViewModel.DuplicateGroup
    let type: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(group.dateKey)
                .font(.subheadline)
                .fontWeight(.semibold)
            
            if let keepRecord = group.recordToKeep {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    VStack(alignment: .leading) {
                        Text("KEEP: \(keepRecord.recordID.recordName)")
                            .font(.caption)
                        Text("Modified: \(formatDate(keepRecord.modificationDate ?? keepRecord.creationDate))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            ForEach(group.recordsToDelete, id: \.recordID) { record in
                HStack {
                    Image(systemName: "trash.circle.fill")
                        .foregroundColor(.red)
                    VStack(alignment: .leading) {
                        Text("DELETE: \(record.recordID.recordName)")
                            .font(.caption)
                        Text("Modified: \(formatDate(record.modificationDate ?? record.creationDate))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
        .padding(.horizontal)
    }
    
    private func formatDate(_ date: Date?) -> String {
        guard let date = date else { return "Unknown" }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
