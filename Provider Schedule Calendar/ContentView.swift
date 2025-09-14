//
//  ContentView.swift
//  Provider Schedule Calendar
//
//  Clean CloudKit Implementation with Custom Zones for Privacy
//

import SwiftUI
import CloudKit
import LinkPresentation



// MARK: - Next Day Navigation (Preserved from Original)
extension Notification.Name {
    static let moveToNextDay = Notification.Name("moveToNextDay")
    static let saveAllActiveDays = Notification.Name("saveAllActiveDays")
    static let saveError = Notification.Name("saveError")
}

// MARK: - Support Structures
struct NextDayFocusRequest {
    let fromDate: Date
    let targetDate: Date
}

struct SaveErrorInfo {
    let message: String
    let details: String
}





struct ContentView: View {
    @EnvironmentObject private var cloudKitManager: CloudKitManager
    @State private var currentDate = Date()
    @State private var saveError = false
    @State private var saveErrorMessage = ""
    private let calendar = Calendar.current
    private let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()
    
    var body: some View {
        NavigationView {
            VStack {
                headerSection
                
                // Show CloudKit status messages
                if !cloudKitManager.cloudKitAvailable {
                    Text(cloudKitManager.errorMessage ?? "CloudKit not available")
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding(.horizontal)
                        .multilineTextAlignment(.center)
                }
                
                if cloudKitManager.isLoading || !cloudKitManager.isZoneReady {
                    VStack(spacing: 12) {
                        ProgressView()
                        if !cloudKitManager.isZoneReady {
                            Text("Setting up secure calendar zone...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Loading calendar data...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 20) {
                            ForEach(monthsToShow, id: \.self) { month in
                                MonthView(month: month, onDataChanged: markAsChanged)
                            }
                        }
                        .padding(.vertical, 16)
                        .padding(.horizontal, 8)
                    }
                }
            }
            .onAppear {
                cloudKitManager.fetchAllData()
            }
            .refreshable {
                // CRITICAL: Never refresh if any field is being edited - protects precision codes
                let isAnyFieldActive = cloudKitManager.isAnyFieldBeingEdited
                if !isAnyFieldActive {
                    debugLog("🔄 Manual refresh - safe to proceed")
                    cloudKitManager.fetchAllData()
                } else {
                    debugLog("🛡️ BLOCKED manual refresh - field being edited")
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .saveError)) { notification in
                if let errorInfo = notification.object as? SaveErrorInfo {
                    handleSaveError(errorInfo)
                }
            }
        }
        .navigationViewStyle(.stack)
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 8) {
            // New Menu Bar
            HStack {
                Text("Provider Schedule Calendar")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                HStack(spacing: 12) {
                    // Save State Button (SSB) with Error Handling
                    Button(action: saveAllChanges) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(saveButtonColor)
                                .frame(width: 8, height: 8)
                            Text(saveButtonText)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(6)
                    }
                    
                    // Print button
                    Button(action: printSchedule) {
                        HStack(spacing: 4) {
                            Image(systemName: "printer")
                                .font(.caption)
                            Text("Print")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(6)
                    }
                    
                    // Share calendar button (CloudKit custom zones with privacy)
                    if cloudKitManager.cloudKitAvailable {
                        Button(action: shareSchedule) {
                            HStack(spacing: 4) {
                                Image(systemName: "person.2.badge.plus")
                                    .font(.caption)
                                Text("Share")
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(6)
                        }
                    }
                    
                    // Diagnostic button for production debugging
                    Button(action: showDiagnostics) {
                        HStack(spacing: 2) {
                            Image(systemName: "wrench.and.screwdriver")
                                .font(.caption2)
                            Text("Diag")
                                .font(.caption2)
                        }
                        .foregroundColor(.orange)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(4)
                    }
                    
                    // Version number
                    Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown").\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown")")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
            
            // Error message display
            if saveError && !saveErrorMessage.isEmpty {
                Text(saveErrorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding(.horizontal)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top)
    }
    
    // MARK: - Save Button State Computed Properties
    private var saveButtonColor: Color {
        if saveError {
            return .red
        } else if cloudKitManager.hasUnsavedChanges {
            return .yellow
        } else {
            return .green
        }
    }
    
    private var saveButtonText: String {
        if saveError {
            return "Error"
        } else {
            return "Save"
        }
    }
    
    private var monthsToShow: [Date] {
        var months: [Date] = []
        
        for i in 0..<12 {
            if let month = calendar.date(byAdding: .month, value: i, to: currentDate) {
                months.append(month)
            }
        }
        
        return months
    }
    
    // MARK: - CloudKit Custom Zone Sharing (Privacy-Focused)
    private func shareSchedule() {
        // TRIGGER 4: Share Button - Save all active daily fields before creating share
        debugLog("🔗 SHARE BUTTON: Triggering save of all active daily field data before sharing")
        NotificationCenter.default.post(name: .saveAllActiveDays, object: nil)
        
        // Small delay to ensure save completes before sharing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.performShare()
        }
    }
    
    private func performShare() {
        debugLog("🔗 SHARE DEBUG: Starting share creation process")
        debugLog("🔗 Zone: \(cloudKitManager.userCustomZone?.zoneID.zoneName ?? "nil")")
        debugLog("🔗 CloudKit Available: \(cloudKitManager.cloudKitAvailable)")
        debugLog("🔗 Zone Ready: \(cloudKitManager.isZoneReady)")
        debugLog("🔗 Records in zone: \(cloudKitManager.dailySchedules.count)")
        
        // Proceed with sharing attempt and detailed logging
        attemptDevelopmentShare()
    }
    
    private func attemptDevelopmentShare() {
        cloudKitManager.createCustomZoneShare(completion: { result in
            Task { @MainActor in
                switch result {
                case .success(let share):
                    debugLog("✅ SHARE SUCCESS: Share created successfully")
                    debugLog("🔗 SHARE URL: \(share.url?.absoluteString ?? "NO URL")")
                    self.presentCloudKitSharingController(for: share)
                    
                case .failure(let error):
                    debugLog("❌ SHARE FAILED: \(error.localizedDescription)")
                    
                    // Detailed error analysis for debugging Production issues
                    var errorDetails = "Error: \(error.localizedDescription)\n\n"
                    
                    if let ckError = error as? CKError {
                        errorDetails += "CloudKit Error Code: \(ckError.code.rawValue)\n"
                        errorDetails += "Error Type: \(ckError.code)\n"
                        
                        switch ckError.code {
                        case .networkUnavailable:
                            errorDetails += "Issue: Network connection problem"
                        case .notAuthenticated:
                            errorDetails += "Issue: Not signed into iCloud"
                        case .permissionFailure:
                            errorDetails += "Issue: CloudKit permissions problem"
                        case .quotaExceeded:
                            errorDetails += "Issue: iCloud storage quota exceeded"
                        case .zoneNotFound:
                            errorDetails += "Issue: Custom zone missing or corrupted"
                        case .serverRejectedRequest:
                            errorDetails += "Issue: CloudKit server rejected the request"
                        case .serviceUnavailable:
                            errorDetails += "Issue: CloudKit service temporarily unavailable"
                        default:
                            errorDetails += "Issue: Unknown CloudKit error"
                        }
                        
                        if let underlying = (ckError as NSError).userInfo[NSUnderlyingErrorKey] as? Error {
                            errorDetails += "\nUnderlying: \(underlying.localizedDescription)"
                        }
                    } else {
                        errorDetails += "Non-CloudKit Error: \((error as NSError).domain) (\((error as NSError).code))"
                    }
                    
                    let alert = UIAlertController(
                        title: "Sharing Failed",
                        message: errorDetails,
                        preferredStyle: .alert
                    )
                    
                    alert.addAction(UIAlertAction(title: "Copy Error Details", style: .default) { _ in
                        UIPasteboard.general.string = errorDetails
                        debugLog("📋 Error details copied to clipboard")
                    })
                    
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let rootViewController = windowScene.windows.first?.rootViewController {
                        rootViewController.present(alert, animated: true)
                    }
                }
            }
        })
    }
    
    private func showProductionSwitchInstructions() {
        let instructions = """
        To test sharing properly:
        
        1. Change entitlements to Production:
           com.apple.developer.icloud-container-environment = Production
        
        2. Use Release build configuration
        
        3. Install via TestFlight or Archive
        
        4. Your zone will be stable for sharing
        """
        
        let alert = UIAlertController(
            title: "Switch to Production",
            message: instructions,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(alert, animated: true)
        }
    }
    
    private func presentCloudKitSharingController(for share: CKShare) {
        guard let shareURL = share.url else {
            debugLog("❌ No share URL available")
            showAlert(title: "Sharing Error", message: "Unable to generate sharing link. Please try again.")
            return
        }
        
        // Present sharing options with the URL
        let shareText = """
        You're invited to view my Provider Schedule Calendar.
        
        Open this link on your iOS device:
        
        \(shareURL.absoluteString)
        """
        
        let activityViewController = UIActivityViewController(
            activityItems: [shareText, shareURL],
            applicationActivities: nil
        )
        
        // Configure for iPad
        if let popover = activityViewController.popoverPresentationController {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first {
                popover.sourceView = window
                popover.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
        }
        
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            debugLog("❌ Could not find root view controller")
            return
        }
        
        rootViewController.present(activityViewController, animated: true)
        
        debugLog("✅ Sharing link generated: \(shareURL.absoluteString)")
    }
    
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(alert, animated: true)
        }
    }
    
    
    
    
    private func getMonthKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: date)
    }
    
    // MARK: - Global Save Function
    private func saveAllChanges() {
        // Clear any previous error state
        saveError = false
        saveErrorMessage = ""
        
        // PRODUCTION DEBUG: Show status in alert
        let modifiedCount = cloudKitManager.dailySchedules.filter { $0.isModified }.count
        let totalCount = cloudKitManager.dailySchedules.count
        let zoneStatus = cloudKitManager.userCustomZone?.zoneID.zoneName ?? "nil"
        let cloudKitStatus = cloudKitManager.cloudKitAvailable ? "Available" : "Not Available"
        
        let debugInfo = """
        SAVE DEBUG INFO:
        
        CloudKit: \(cloudKitStatus)
        Zone: \(zoneStatus)
        Total Records: \(totalCount)
        Modified Records: \(modifiedCount)
        
        Will attempt to save \(modifiedCount) records.
        """
        
        // Show debug info in alert
        let alert = UIAlertController(title: "Save Status", message: debugInfo, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Continue Save", style: .default) { _ in
            self.performActualSave()
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(alert, animated: true)
        }
    }
    
    private func performActualSave() {
        guard cloudKitManager.cloudKitAvailable else {
            let errorInfo = SaveErrorInfo(
                message: "CloudKit not available",
                details: "Please check your iCloud connection and try again."
            )
            handleSaveError(errorInfo)
            return
        }
        
        // NEW GLOBAL MEMORY SAVE: Process all modified records
        let modifiedRecords = cloudKitManager.dailySchedules.filter { $0.isModified }
        
        if modifiedRecords.isEmpty {
            let alert = UIAlertController(title: "No Changes", message: "No changes to save.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootViewController = windowScene.windows.first?.rootViewController {
                rootViewController.present(alert, animated: true)
            }
            return
        }
        
        // CRITICAL: Check if zone is ready before saving
        guard cloudKitManager.userCustomZone != nil else {
            let errorInfo = SaveErrorInfo(
                message: "Zone not ready",
                details: "Custom zone setup is not complete. Please wait and try again."
            )
            handleSaveError(errorInfo)
            return
        }
        
        // Save each modified record
        let dispatchGroup = DispatchGroup()
        var saveErrors: [String] = []
        
        for record in modifiedRecords {
            dispatchGroup.enter()
            
            cloudKitManager.saveOrDeleteDailySchedule(
                existingRecordName: record.id, // Use existing record ID from global memory
                existingZoneID: record.zoneID, // Use existing zone ID from global memory
                date: record.date ?? Date(),
                line1: record.line1,
                line2: record.line2,
                line3: record.line3
            ) { success, error in
                if !success {
                    let dateStr = DateFormatter.localizedString(from: record.date ?? Date(), dateStyle: .short, timeStyle: .none)
                    let errorMsg = "Failed to save \(dateStr): \(error?.localizedDescription ?? "Unknown error")"
                    saveErrors.append(errorMsg)
                }
                dispatchGroup.leave()
            }
        }
        
        // Wait for all saves to complete and show result
        dispatchGroup.notify(queue: .main) {
            if saveErrors.isEmpty {
                // Success - clear all isModified flags
                for index in 0..<self.cloudKitManager.dailySchedules.count {
                    self.cloudKitManager.dailySchedules[index].isModified = false
                }
                
                // Show success alert
                let alert = UIAlertController(title: "Save Complete", message: "Successfully saved \(modifiedRecords.count) records to CloudKit", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let rootViewController = windowScene.windows.first?.rootViewController {
                    rootViewController.present(alert, animated: true)
                }
            } else {
                // Some saves failed
                let errorInfo = SaveErrorInfo(
                    message: "Save failed for \(saveErrors.count) records",
                    details: saveErrors.joined(separator: "\n")
                )
                self.handleSaveError(errorInfo)
            }
        }
    }
    
    // MARK: - Error Handling
    private func handleSaveError(_ errorInfo: SaveErrorInfo) {
        saveError = true
        saveErrorMessage = errorInfo.message
        debugLog("🚨 Save Error: \(errorInfo.message) - \(errorInfo.details)")
        
        // Clear error state after 10 seconds to allow retry
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
            if self.saveError {
                self.saveError = false
                self.saveErrorMessage = ""
                debugLog("🔄 Cleared save error state - ready for retry")
            }
        }
    }
    
    // MARK: - Data Sync Debug
    private func showDataSyncDebug() {
        // Get Sept 1 data from global memory
        let sept1Date = Calendar.current.date(from: DateComponents(year: 2025, month: 9, day: 1)) ?? Date()
        let scheduleForSept1 = cloudKitManager.dailySchedules.first { schedule in
            guard let scheduleDate = schedule.date else { return false }
            return Calendar.current.isDate(scheduleDate, inSameDayAs: sept1Date)
        }
        
        let globalMemoryData = """
        SEPT 1 - GLOBAL MEMORY:
        line1: '\(scheduleForSept1?.line1 ?? "nil")'
        line2: '\(scheduleForSept1?.line2 ?? "nil")'
        line3: '\(scheduleForSept1?.line3 ?? "nil")'
        isModified: \(scheduleForSept1?.isModified ?? false)
        
        TOTAL RECORDS IN MEMORY: \(cloudKitManager.dailySchedules.count)
        MODIFIED RECORDS: \(cloudKitManager.dailySchedules.filter { $0.isModified }.count)
        """
        
        let alert = UIAlertController(title: "Data Sync Debug", message: globalMemoryData, preferredStyle: .alert)
        
        alert.addAction(UIAlertAction(title: "Refresh from CloudKit", style: .default) { _ in
            self.cloudKitManager.fetchAllData()
            
            // Show updated data after fetch
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                let updatedSchedule = self.cloudKitManager.dailySchedules.first { schedule in
                    guard let scheduleDate = schedule.date else { return false }
                    return Calendar.current.isDate(scheduleDate, inSameDayAs: sept1Date)
                }
                let updatedData = """
                AFTER CLOUDKIT FETCH:
                line1: '\(updatedSchedule?.line1 ?? "nil")'
                line2: '\(updatedSchedule?.line2 ?? "nil")'
                line3: '\(updatedSchedule?.line3 ?? "nil")'
                
                TOTAL RECORDS: \(self.cloudKitManager.dailySchedules.count)
                """
                
                let resultAlert = UIAlertController(title: "After Fetch", message: updatedData, preferredStyle: .alert)
                resultAlert.addAction(UIAlertAction(title: "OK", style: .default))
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let rootViewController = windowScene.windows.first?.rootViewController {
                    rootViewController.present(resultAlert, animated: true)
                }
            }
        })
        
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(alert, animated: true)
        }
    }
    
    // MARK: - Print Function
    private func printSchedule() {
        let htmlContent = generatePrintHTML()
        
        let printController = UIPrintInteractionController.shared
        printController.printPageRenderer = createPageRenderer(with: htmlContent)
        
        // Configure print job
        let printInfo = UIPrintInfo(dictionary: nil)
        printInfo.jobName = "Provider Schedule Calendar"
        printInfo.outputType = .general
        printController.printInfo = printInfo
        
        // Present print interface
        if UIDevice.current.userInterfaceIdiom == .pad {
            // iPad - use popover from current window
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first {
                printController.present(from: CGRect(x: 100, y: 100, width: 0, height: 0), in: window, animated: true) { _, _, _ in }
            }
        } else {
            // iPhone - use modal
            printController.present(animated: true) { _, _, _ in }
        }
    }
    
    private func generatePrintHTML() -> String {
        var html = """
        <html>
        <head>
            <meta charset="UTF-8">
            <style>
                @page {
                    size: letter;
                    margin: 0.5in;
                }
                body {
                    font-family: Arial, sans-serif;
                    font-size: 12px;
                    margin: 0;
                    padding: 0;
                }
                .month-page {
                    page-break-after: always;
                    height: 100vh;
                }
                .month-page:last-child {
                    page-break-after: avoid;
                }
                .month-header {
                    text-align: center;
                    font-size: 24px;
                    font-weight: bold;
                    margin-bottom: 20px;
                    color: #333;
                }
                .calendar-grid {
                    width: 100%;
                    border-collapse: collapse;
                    table-layout: fixed;
                }
                .calendar-grid th, .calendar-grid td {
                    border: 1px solid #ccc;
                    padding: 4px;
                    vertical-align: top;
                    height: 80px;
                    width: 14.28%;
                }
                .calendar-grid th {
                    background-color: #f5f5f5;
                    font-weight: bold;
                    text-align: center;
                    height: 30px;
                }
                .day-number {
                    font-weight: bold;
                    margin-bottom: 4px;
                }
                .schedule-line {
                    font-size: 10px;
                    margin: 1px 0;
                    line-height: 1.2;
                }
                .other-month {
                    color: #ccc;
                    background-color: #fafafa;
                }
            </style>
        </head>
        <body>
        """
        
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        
        for monthOffset in 0..<12 {
            guard let monthDate = calendar.date(byAdding: .month, value: monthOffset, to: currentDate) else { continue }
            
            html += """
            <div class="month-page">
                <div class="month-header">\(formatter.string(from: monthDate))</div>
                <table class="calendar-grid">
                    <tr>
                        <th>Sun</th><th>Mon</th><th>Tue</th><th>Wed</th><th>Thu</th><th>Fri</th><th>Sat</th>
                    </tr>
            """
            
            // Get first day of month and calculate grid
            let firstOfMonth = calendar.dateInterval(of: .month, for: monthDate)!.start
            let firstWeekday = calendar.component(.weekday, from: firstOfMonth) - 1 // 0 = Sunday
            let daysInMonth = calendar.range(of: .day, in: .month, for: monthDate)!.count
            
            var dayCount = 1
            var cellCount = 0
            
            // Generate calendar grid (6 weeks max)
            for week in 0..<6 {
                html += "<tr>"
                
                for dayOfWeek in 0..<7 {
                    if week == 0 && dayOfWeek < firstWeekday {
                        // Empty cell before month starts
                        html += "<td class='other-month'></td>"
                    } else if dayCount <= daysInMonth {
                        // Day in current month
                        let dayDate = calendar.date(byAdding: .day, value: dayCount - 1, to: firstOfMonth)!
                        let scheduleData = getScheduleForDate(dayDate)
                        
                        html += "<td>"
                        html += "<div class='day-number'>\(dayCount)</div>"
                        
                        if let schedule = scheduleData {
                            if let line1 = schedule.line1, !line1.isEmpty {
                                html += "<div class='schedule-line'>OS: \(line1)</div>"
                            }
                            if let line2 = schedule.line2, !line2.isEmpty {
                                html += "<div class='schedule-line'>CL: \(line2)</div>"
                            }
                            if let line3 = schedule.line3, !line3.isEmpty {
                                html += "<div class='schedule-line'>OFF: \(line3)</div>"
                            }
                        }
                        
                        html += "</td>"
                        dayCount += 1
                    } else {
                        // Empty cell after month ends
                        html += "<td class='other-month'></td>"
                    }
                    cellCount += 1
                }
                
                html += "</tr>"
                
                // Stop if we've shown all days in the month
                if dayCount > daysInMonth {
                    break
                }
            }
            
            html += """
                </table>
            </div>
            """
        }
        
        html += """
        </body>
        </html>
        """
        
        return html
    }
    
    private func getScheduleForDate(_ date: Date) -> DailyScheduleRecord? {
        return cloudKitManager.dailySchedules.first { schedule in
            guard let scheduleDate = schedule.date else { return false }
            return Calendar.current.isDate(scheduleDate, inSameDayAs: date)
        }
    }
    
    private func createPageRenderer(with htmlContent: String) -> UIPrintPageRenderer {
        let renderer = UIPrintPageRenderer()
        
        let formatter = UIMarkupTextPrintFormatter(markupText: htmlContent)
        formatter.perPageContentInsets = UIEdgeInsets(top: 36, left: 36, bottom: 36, right: 36)
        
        renderer.addPrintFormatter(formatter, startingAtPageAt: 0)
        
        return renderer
    }
    
    // MARK: - Track Changes Function
    private func markAsChanged() {
        // Global memory system automatically tracks changes
        // No need to manually set hasUnsavedChanges
        debugLog("🔄 Data changed - global memory system tracking changes automatically")
    }
    
    // MARK: - Production Diagnostics
    private func showDiagnostics() {
        let customZone = cloudKitManager.userCustomZone?.zoneID.zoneName ?? "None"
        let scheduleCount = cloudKitManager.dailySchedules.count
        let notesCount = cloudKitManager.monthlyNotes.count
        let cloudKitStatus = cloudKitManager.cloudKitAvailable ? "Available" : "Unavailable"
        let activeEditSessions = cloudKitManager.isAnyFieldBeingEdited ? "Yes" : "No"
        
        // Sample a few recent schedules to show what's actually saved
        let recentSchedules = cloudKitManager.dailySchedules.suffix(3).map { schedule in
            let dateStr = DateFormatter.localizedString(from: schedule.date ?? Date(), dateStyle: .short, timeStyle: .none)
            return "\(dateStr): '\(schedule.line1 ?? "")'/'\(schedule.line2 ?? "")'/'\(schedule.line3 ?? "")'"
        }.joined(separator: "\n")
        
        let diagnosticInfo = """
        CloudKit Status: \(cloudKitStatus)
        Custom Zone: \(customZone)
        Daily Schedules: \(scheduleCount)
        Monthly Notes: \(notesCount)
        Active Editing: \(activeEditSessions)
        Error: \(cloudKitManager.errorMessage ?? "None")
        
        Recent Data in CloudKit:
        \(recentSchedules.isEmpty ? "No recent data" : recentSchedules)
        """
        
        let alert = UIAlertController(
            title: "Production Diagnostics",
            message: diagnosticInfo,
            preferredStyle: .alert
        )
        
        // Always add zone reset button for manual troubleshooting
        alert.addAction(UIAlertAction(title: "🚨 Reset Zone", style: .destructive) { _ in
            self.showResetZoneConfirmation()
        })
        
        // Add data recovery button
        alert.addAction(UIAlertAction(title: "🔍 Data Recovery", style: .default) { _ in
            self.cloudKitManager.emergencyDataRecovery()
        })
        
        // Add comprehensive debug button
        alert.addAction(UIAlertAction(title: "🔍 Debug All Zones", style: .default) { _ in
            self.cloudKitManager.debugAllZonesAndData()
        })
        
        // Add data sync debug button
        alert.addAction(UIAlertAction(title: "🔄 Debug Data Sync", style: .default) { _ in
            self.showDataSyncDebug()
        })
        
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(alert, animated: true)
        }
    }
    
    // MARK: - Reset Zone Confirmation
    private func showResetZoneConfirmation() {
        let confirmAlert = UIAlertController(
            title: "⚠️ DANGER: Reset Zone",
            message: "This will PERMANENTLY DELETE ALL your calendar data!\n\n• All daily schedules will be lost\n• All monthly notes will be lost\n• This action CANNOT be undone\n\nAre you absolutely sure you want to continue?",
            preferredStyle: .alert
        )
        
        // Destructive action to actually reset
        confirmAlert.addAction(UIAlertAction(title: "YES - Delete All Data", style: .destructive) { _ in
            debugLog("🚨 User confirmed zone reset - proceeding with data deletion")
            self.cloudKitManager.emergencyZoneReset()
        })
        
        // Safe cancel option (default)
        confirmAlert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            debugLog("✅ User cancelled zone reset - data preserved")
        })
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(confirmAlert, animated: true)
        }
    }
}

// MARK: - MonthView
struct MonthView: View {
    let month: Date
    let onDataChanged: () -> Void
    @EnvironmentObject private var cloudKitManager: CloudKitManager
    
    private let calendar = Calendar.current
    private let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            monthHeader
            notesSection
            daysOfWeekHeader
            calendarGrid
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .shadow(color: Color.gray.opacity(0.2), radius: 4, x: 0, y: 2)
    }
    
    private var monthHeader: some View {
        Text(monthFormatter.string(from: month))
            .font(.title2)
            .fontWeight(.bold)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.bottom, 5)
    }
    
    private var notesSection: some View {
        MonthlyNotesView(month: month, onDataChanged: onDataChanged)
    }
    
    private var daysOfWeekHeader: some View {
        HStack {
            ForEach(Calendar.current.shortWeekdaySymbols, id: \.self) { day in
                Text(day)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(8)
    }
    
    private var calendarGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
            ForEach(daysInMonth, id: \.self) { date in
                if calendar.isDate(date, equalTo: month, toGranularity: .month) {
                    DayCell(date: date, schedule: scheduleForDate(date), onDataChanged: onDataChanged)
                } else {
                    Rectangle()
                        .fill(Color.clear)
                        .frame(minHeight: 120)
                }
            }
        }
    }
    
    private var daysInMonth: [Date] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: month) else {
            return []
        }
        
        let startOfMonth = monthInterval.start
        let endOfMonth = monthInterval.end
        
        // Get start of calendar grid (may include days from previous month)
        let startOfCalendar = calendar.dateInterval(of: .weekOfYear, for: startOfMonth)?.start ?? startOfMonth
        
        // Get end of calendar grid (may include days from next month)
        let endOfCalendar = calendar.dateInterval(of: .weekOfYear, for: calendar.date(byAdding: .day, value: -1, to: endOfMonth) ?? endOfMonth)?.end ?? endOfMonth
        
        var dates: [Date] = []
        var currentDate = startOfCalendar
        
        while currentDate < endOfCalendar {
            dates.append(currentDate)
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
        }
        
        return dates
    }
    
    private func scheduleForDate(_ date: Date) -> DailyScheduleRecord? {
        return cloudKitManager.dailySchedules.first { record in
            guard let recordDate = record.date else { return false }
            return calendar.isDate(recordDate, inSameDayAs: date)
        }
    }
}

// MARK: - MonthlyNotesView
struct MonthlyNotesView: View {
    let month: Date
    let onDataChanged: () -> Void
    @EnvironmentObject private var cloudKitManager: CloudKitManager
    
    private var monthComponent: Int {
        Calendar.current.component(.month, from: month)
    }
    
    private var yearComponent: Int {
        Calendar.current.component(.year, from: month)
    }
    
    private var monthlyRecord: MonthlyNotesRecord? {
        cloudKitManager.monthlyNotes.first { $0.month == monthComponent && $0.year == yearComponent }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes:")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)
            
            VStack(spacing: 6) {
                ForEach(1...3, id: \.self) { lineNumber in
                    MonthlyNoteField(
                        lineNumber: lineNumber,
                        text: getFieldValue(lineNumber),
                        onTextChanged: { newValue in
                            updateField(lineNumber, value: newValue)
                        }
                    )
                }
            }
        }
        .padding(12)
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(8)
    }
    
    private func getFieldValue(_ lineNumber: Int) -> String {
        guard let record = monthlyRecord else { return "" }
        switch lineNumber {
        case 1: return record.line1 ?? ""
        case 2: return record.line2 ?? ""
        case 3: return record.line3 ?? ""
        default: return ""
        }
    }
    
    private func updateField(_ lineNumber: Int, value: String) {
        // TODO: Implement monthly notes editing when CloudKitManager functions are properly exposed
        // For now, monthly notes are read-only
        onDataChanged()
    }
}

struct MonthlyNoteField: View {
    let lineNumber: Int
    let text: String
    let onTextChanged: (String) -> Void
    
    var body: some View {
        TextField("Note \(lineNumber)", text: Binding(
            get: { text },
            set: { onTextChanged($0) }
        ))
        .font(.system(size: 14))
        .padding(8)
        .background(Color(.systemBackground))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(.systemGray4), lineWidth: 1)
        )
    }
}

// MARK: - DayCell
struct DayCell: View {
    let date: Date
    let schedule: DailyScheduleRecord?
    let onDataChanged: () -> Void
    @EnvironmentObject private var cloudKitManager: CloudKitManager
    
    @State private var isEditing = false
    @FocusState private var focusedField: FieldType?
    
    enum FieldType: CaseIterable {
        case line1, line2, line3
    }
    
    private let calendar = Calendar.current
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Day number
            HStack {
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(isCurrentMonth ? .primary : .secondary)
                Spacer()
            }
            
            // Schedule fields
            VStack(spacing: 3) {
                ScheduleField(label: "OS", fieldType: .line1)
                ScheduleField(label: "CL", fieldType: .line2)
                ScheduleField(label: "OFF", fieldType: .line3)
            }
        }
        .padding(4)
        .frame(minHeight: 120, alignment: .topLeading)
        .background(isCurrentMonth ? Color(.systemBackground) : Color(.secondarySystemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color(.systemGray5), lineWidth: 0.5)
        )
    }
    
    private var isCurrentMonth: Bool {
        let today = Date()
        return calendar.isDate(date, equalTo: today, toGranularity: .month)
    }
    
    private func ScheduleField(label: String, fieldType: FieldType) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 22, alignment: .leading)
            
            TextField("", text: Binding(
                get: { getFieldValue(fieldType) },
                set: { updateField(fieldType, value: $0) }
            ))
            .font(.system(size: 10))
            .focused($focusedField, equals: fieldType)
            .disabled(!cloudKitManager.isZoneReady)
            .onSubmit {
                moveToNextField()
            }
        }
    }
    
    private func getFieldValue(_ fieldType: FieldType) -> String {
        // Safety check: don't try to access records if zone isn't ready
        guard cloudKitManager.isZoneReady else {
            return ""
        }
        
        // Use read-only function to avoid creating records during view rendering
        guard let index = cloudKitManager.getRecordIndex(for: date),
              index < cloudKitManager.dailySchedules.count else {
            return ""
        }
        
        let record = cloudKitManager.dailySchedules[index]
        
        switch fieldType {
        case .line1: return record.line1 ?? ""
        case .line2: return record.line2 ?? ""
        case .line3: return record.line3 ?? ""
        }
    }
    
    private func updateField(_ fieldType: FieldType, value: String) {
        // Safety check: don't try to update records if zone isn't ready
        guard cloudKitManager.isZoneReady else {
            return
        }
        
        // Use Task to avoid "Publishing changes from within view updates" errors
        Task { @MainActor in
            // Create record if it doesn't exist (separate from view rendering)
            self.cloudKitManager.createRecordForEditing(date: self.date)
            
            // Now get the index
            guard let index = self.cloudKitManager.getRecordIndex(for: self.date),
                  index < self.cloudKitManager.dailySchedules.count else {
                return
            }
            
            switch fieldType {
            case .line1:
                self.cloudKitManager.updateField(at: index, field: "line1", value: value)
            case .line2:
                self.cloudKitManager.updateField(at: index, field: "line2", value: value)
            case .line3:
                self.cloudKitManager.updateField(at: index, field: "line3", value: value)
            }
            
            self.onDataChanged()
        }
    }
    
    private func moveToNextField() {
        switch focusedField {
        case .line1:
            focusedField = .line2
        case .line2:
            focusedField = .line3
        case .line3:
            focusedField = nil
        case .none:
            break
        }
    }
}

