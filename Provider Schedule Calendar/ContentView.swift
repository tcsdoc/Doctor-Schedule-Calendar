//
//  ContentView.swift
//  Provider Schedule Calendar
//
//  Clean CloudKit Implementation with Custom Zones for Privacy
//

import SwiftUI
import CloudKit
import LinkPresentation

// MARK: - Custom Activity Item Source for Email Formatting
class ShareActivityItemSource: NSObject, UIActivityItemSource {
    private let text: String
    private let url: URL
    private let subject: String
    
    init(text: String, url: URL, subject: String) {
        self.text = text
        self.url = url
        self.subject = subject
        super.init()
    }
    
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return text
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        if activityType == .mail {
            return "\(text)\n\n\(url.absoluteString)"
        }
        return url
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        return subject
    }
}



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
            .onReceive(NotificationCenter.default.publisher(for: .saveAllActiveDays)) { _ in
                debugLog("🔗 NOTIFICATION RECEIVED: saveAllActiveDays - triggering save for sharing")
                saveForSharing()
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
    
    // Save function specifically for sharing - doesn't show "No Changes" alert
    private func saveForSharing() {
        debugLog("🔗 SAVE FOR SHARING: Checking for data to save before sharing")
        
        guard cloudKitManager.cloudKitAvailable else {
            debugLog("❌ CloudKit not available for sharing save")
            return
        }
        
        let modifiedRecords = cloudKitManager.dailySchedules.filter { $0.isModified }
        let modifiedMonthlyNotes = cloudKitManager.monthlyNotes.filter { $0.isModified }
        
        if modifiedRecords.isEmpty && modifiedMonthlyNotes.isEmpty {
            debugLog("🔗 SAVE FOR SHARING: No changes to save - data already current")
            return // Silently return without blocking sharing
        }
        
        guard cloudKitManager.userCustomZone != nil else {
            debugLog("❌ Zone not ready for sharing save")
            return
        }
        
        debugLog("🔗 SAVE FOR SHARING: Saving \(modifiedRecords.count) daily + \(modifiedMonthlyNotes.count) monthly records")
        
        // Use the same save pattern as performActualSave but without UI alerts
        let dispatchGroup = DispatchGroup()
        var saveErrors: [String] = []
        
        // Save each modified daily schedule record
        for record in modifiedRecords {
            dispatchGroup.enter()
            
            cloudKitManager.saveOrDeleteDailySchedule(
                existingRecordName: record.id,
                existingZoneID: record.zoneID,
                date: record.date ?? Date(),
                line1: record.line1,
                line2: record.line2,
                line3: record.line3
            ) { success, error in
                if !success {
                    if let error = error {
                        saveErrors.append("Daily record save failed: \(error)")
                    }
                }
                dispatchGroup.leave()
            }
        }
        
        // Save each modified monthly note record
        for note in modifiedMonthlyNotes {
            dispatchGroup.enter()
            
            cloudKitManager.saveOrDeleteMonthlyNotes(
                existingRecordName: note.id,
                month: note.month,
                year: note.year,
                line1: note.line1,
                line2: note.line2,
                line3: note.line3
            ) { success, error in
                if !success {
                    if let error = error {
                        saveErrors.append("Monthly note save failed: \(error)")
                    }
                }
                dispatchGroup.leave()
            }
        }
        
        // Wait for all saves to complete
        dispatchGroup.notify(queue: .main) {
            if saveErrors.isEmpty {
                debugLog("✅ SAVE FOR SHARING: All data saved successfully")
            } else {
                debugLog("❌ SAVE FOR SHARING: Some errors occurred: \(saveErrors.joined(separator: ", "))")
            }
        }
    }
    
    // MARK: - CloudKit Custom Zone Sharing (Privacy-Focused)
    private func shareSchedule() {
        debugLog("🔗 SHARE BUTTON: Preparing to share schedule data")
        
        // Check if there are unsaved changes that need to be saved first
        let hasUnsavedChanges = cloudKitManager.hasUnsavedChanges
        
        if hasUnsavedChanges {
            debugLog("🔗 SHARE: Unsaved changes detected - saving before sharing")
            // Save first, then share
            NotificationCenter.default.post(name: .saveAllActiveDays, object: nil)
            
            // Wait for save completion before sharing
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.performShare()
            }
        } else {
            debugLog("🔗 SHARE: All data already saved - proceeding with sharing")
            // Data is already saved, proceed immediately with sharing
            performShare()
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
                    
                    // MINIMAL DEBUG: Check share configuration 
                    debugLog("🔗 SHARE CONFIG: Participants: \(share.participants.count)")
                    debugLog("🔗 SHARE CONFIG: Public permission: \(share.publicPermission.rawValue)")
                    debugLog("🔗 SHARE CONFIG: Owner exists: true")
                    if share.participants.count > 0 {
                        debugLog("🔗 SHARE CONFIG: Has \(share.participants.count) participant(s)")
                    } else {
                        debugLog("🔗 SHARE CONFIG: No participants (owner-only share)")
                    }
                    
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
        let shareText = "You're invited to view my Provider Schedule Calendar. Open the link below on your iOS device to access the shared calendar."
        
        // Create a custom activity item source for better email formatting
        let customItem = ShareActivityItemSource(
            text: shareText,
            url: shareURL,
            subject: "Provider Schedule Calendar - Shared Access"
        )
        
        let activityViewController = UIActivityViewController(
            activityItems: [customItem],
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
        
        // Directly proceed to save without debug confirmation
        performActualSave()
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
        let modifiedMonthlyNotes = cloudKitManager.monthlyNotes.filter { $0.isModified }
        
        if modifiedRecords.isEmpty && modifiedMonthlyNotes.isEmpty {
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
        
        // Save each modified daily schedule record
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
        
        // Also save modified monthly notes (already declared above)
        for monthlyNote in modifiedMonthlyNotes {
            dispatchGroup.enter()
            
            cloudKitManager.saveOrDeleteMonthlyNotes(
                existingRecordName: monthlyNote.id,
                month: monthlyNote.month,
                year: monthlyNote.year,
                line1: monthlyNote.line1,
                line2: monthlyNote.line2,
                line3: monthlyNote.line3
            ) { success, error in
                if !success {
                    let errorMsg = "Failed to save monthly notes for \(monthlyNote.month)/\(monthlyNote.year): \(error?.localizedDescription ?? "Unknown error")"
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
                for index in 0..<self.cloudKitManager.monthlyNotes.count {
                    self.cloudKitManager.monthlyNotes[index].isModified = false
                }
                
                // Show success alert
                let totalSaved = modifiedRecords.count + modifiedMonthlyNotes.count
                let message = totalSaved == 1 ? "Changes saved successfully." : "\(totalSaved) changes saved successfully."
                let alert = UIAlertController(title: "Saved", message: message, preferredStyle: .alert)
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
                    color: #666;
                    background-color: #fff;
                }
                .monthly-notes {
                    margin-top: 20px;
                    padding: 12px;
                    border: 1px solid #000;
                    border-radius: 8px;
                    background-color: #fff;
                }
                .monthly-notes-title {
                    font-size: 16px;
                    font-weight: bold;
                    margin-bottom: 8px;
                    color: #000;
                }
                .monthly-note-field {
                    display: flex;
                    align-items: center;
                    margin-bottom: 6px;
                    font-size: 10px;
                }
                .monthly-note-label {
                    width: 48px;
                    font-weight: medium;
                    color: #000;
                    margin-right: 6px;
                }
                .monthly-note-value {
                    flex: 1;
                    padding: 2px 4px;
                    border-radius: 4px;
                    font-weight: medium;
                }
                .monthly-note-line1 {
                    background-color: #fff;
                    border: 1px solid #000;
                    color: #000;
                }
                .monthly-note-line2 {
                    background-color: #fff;
                    border: 1px solid #000;
                    color: #000;
                }
                .monthly-note-line3 {
                    background-color: #fff;
                    border: 1px solid #000;
                    color: #000;
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
            """
            
            // Add monthly notes for this month
            let monthComponent = calendar.component(.month, from: monthDate)
            let yearComponent = calendar.component(.year, from: monthDate)
            let monthlyNote = getMonthlyNotesForMonth(month: monthComponent, year: yearComponent)
            
            html += """
                <div class="monthly-notes">
                    <div class="monthly-notes-title">Notes:</div>
            """
            
            // Add each note field with same styling as app
            if let line1 = monthlyNote?.line1, !line1.isEmpty {
                html += """
                    <div class="monthly-note-field">
                        <span class="monthly-note-label">Note1:</span>
                        <span class="monthly-note-value monthly-note-line1">\(line1)</span>
                    </div>
                """
            } else {
                html += """
                    <div class="monthly-note-field">
                        <span class="monthly-note-label">Note1:</span>
                        <span class="monthly-note-value monthly-note-line1"></span>
                    </div>
                """
            }
            
            if let line2 = monthlyNote?.line2, !line2.isEmpty {
                html += """
                    <div class="monthly-note-field">
                        <span class="monthly-note-label">Note2:</span>
                        <span class="monthly-note-value monthly-note-line2">\(line2)</span>
                    </div>
                """
            } else {
                html += """
                    <div class="monthly-note-field">
                        <span class="monthly-note-label">Note2:</span>
                        <span class="monthly-note-value monthly-note-line2"></span>
                    </div>
                """
            }
            
            if let line3 = monthlyNote?.line3, !line3.isEmpty {
                html += """
                    <div class="monthly-note-field">
                        <span class="monthly-note-label">Note3:</span>
                        <span class="monthly-note-value monthly-note-line3">\(line3)</span>
                    </div>
                """
            } else {
                html += """
                    <div class="monthly-note-field">
                        <span class="monthly-note-label">Note3:</span>
                        <span class="monthly-note-value monthly-note-line3"></span>
                    </div>
                """
            }
            
            html += """
                </div>
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
    
    private func getMonthlyNotesForMonth(month: Int, year: Int) -> MonthlyNotesRecord? {
        return cloudKitManager.monthlyNotes.first { note in
            note.month == month && note.year == year
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

// MARK: - Monthly Notes Field Types
enum MonthlyNotesField: CaseIterable {
    case line1, line2, line3
}

// MARK: - MonthlyNotesView
struct MonthlyNotesView: View {
    let month: Date
    let onDataChanged: () -> Void
    @EnvironmentObject private var cloudKitManager: CloudKitManager
    @FocusState private var focusedField: MonthlyNotesField?
    
    private var monthComponent: Int {
        Calendar.current.component(.month, from: month)
    }
    
    private var yearComponent: Int {
        Calendar.current.component(.year, from: month)
    }
    
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes:")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)
            
            VStack(spacing: 6) {
                MonthlyNoteField(label: "Note 1", fieldType: .line1)
                MonthlyNoteField(label: "Note 2", fieldType: .line2)
                MonthlyNoteField(label: "Note 3", fieldType: .line3)
            }
        }
        .padding(12)
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(8)
    }
    
    private func MonthlyNoteField(label: String, fieldType: MonthlyNotesField) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 48, alignment: .leading)
            
            TextField("", text: Binding(
                get: { getFieldValue(fieldType) },
                set: { updateField(fieldType, value: $0.uppercased()) } // Force uppercase
            ))
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(fieldTextColor(for: fieldType))
            .focused($focusedField, equals: fieldType)
            .disabled(!cloudKitManager.isZoneReady)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(fieldBackgroundColor(for: fieldType))
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(fieldBorderColor(for: fieldType), lineWidth: 1)
            )
            .onSubmit {
                moveToNextField()
            }
        }
    }
    
    // MARK: - Field Color Coding (Matching Daily Schedule Colors)
    private func fieldTextColor(for fieldType: MonthlyNotesField) -> Color {
        switch fieldType {
        case .line1: return .blue      // Note 1 - Blue (matching OS field)
        case .line2: return .green     // Note 2 - Green (matching CL field)
        case .line3: return .red       // Note 3 - Red (matching OFF field)
        }
    }
    
    private func fieldBackgroundColor(for fieldType: MonthlyNotesField) -> Color {
        switch fieldType {
        case .line1: return .blue.opacity(0.1)      // Light blue background
        case .line2: return .green.opacity(0.1)     // Light green background
        case .line3: return .red.opacity(0.1)       // Light red background
        }
    }
    
    private func fieldBorderColor(for fieldType: MonthlyNotesField) -> Color {
        switch fieldType {
        case .line1: return .blue.opacity(0.3)      // Blue border
        case .line2: return .green.opacity(0.3)     // Green border
        case .line3: return .red.opacity(0.3)       // Red border
        }
    }
    
    private func getFieldValue(_ fieldType: MonthlyNotesField) -> String {
        // CRITICAL: Get data from global memory, not just CloudKit records
        // This ensures typed data persists during screen refresh/scroll
        let record = cloudKitManager.monthlyNotes.first { $0.month == monthComponent && $0.year == yearComponent }
        
        switch fieldType {
        case .line1: return (record?.line1 ?? "").uppercased()
        case .line2: return (record?.line2 ?? "").uppercased()
        case .line3: return (record?.line3 ?? "").uppercased()
        }
    }
    
    private func updateField(_ fieldType: MonthlyNotesField, value: String) {
        // Update local memory only - CloudKit save happens when Save button is pressed
        // Find or create monthly record in local memory
        if let index = cloudKitManager.monthlyNotes.firstIndex(where: { $0.month == monthComponent && $0.year == yearComponent }) {
            // Update existing record by modifying its properties directly
            switch fieldType {
            case .line1:
                cloudKitManager.monthlyNotes[index].line1 = value
            case .line2:
                cloudKitManager.monthlyNotes[index].line2 = value
            case .line3:
                cloudKitManager.monthlyNotes[index].line3 = value
            }
            cloudKitManager.monthlyNotes[index].isModified = true
        } else {
            // Create new record in local memory using the correct initializer
            var newRecord = MonthlyNotesRecord(
                month: monthComponent,
                year: yearComponent,
                zoneID: cloudKitManager.userZoneID
            )
            
            // Set the specific field value
            switch fieldType {
            case .line1:
                newRecord.line1 = value
            case .line2:
                newRecord.line2 = value
            case .line3:
                newRecord.line3 = value
            }
            newRecord.isModified = true
            
            cloudKitManager.monthlyNotes.append(newRecord)
        }
        
        onDataChanged()
    }
    
    private func moveToNextField() {
        switch focusedField {
        case .line1:
            focusedField = .line2
        case .line2:
            focusedField = .line3
        case .line3:
            focusedField = nil
        case nil:
            break
        }
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
            VStack(spacing: 8) {
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
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 24, alignment: .leading)
            
            TextField("", text: Binding(
                get: { getFieldValue(fieldType) },
                set: { updateField(fieldType, value: $0.uppercased()) } // Force uppercase
            ))
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(fieldTextColor(for: fieldType))
            .focused($focusedField, equals: fieldType)
            .disabled(!cloudKitManager.isZoneReady)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(fieldBackgroundColor(for: fieldType))
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(fieldBorderColor(for: fieldType), lineWidth: 1)
            )
            .onSubmit {
                moveToNextField()
            }
        }
        .padding(.vertical, 2) // Add spacing between fields
    }
    
    // MARK: - Field Color Coding
    private func fieldTextColor(for fieldType: FieldType) -> Color {
        switch fieldType {
        case .line1: return .blue      // OS field - Blue
        case .line2: return .green     // CL field - Green  
        case .line3: return .red       // OFF field - Red
        }
    }
    
    private func fieldBackgroundColor(for fieldType: FieldType) -> Color {
        switch fieldType {
        case .line1: return .blue.opacity(0.1)      // Light blue background
        case .line2: return .green.opacity(0.1)     // Light green background
        case .line3: return .red.opacity(0.1)       // Light red background
        }
    }
    
    private func fieldBorderColor(for fieldType: FieldType) -> Color {
        switch fieldType {
        case .line1: return .blue.opacity(0.3)      // Blue border
        case .line2: return .green.opacity(0.3)     // Green border
        case .line3: return .red.opacity(0.3)       // Red border
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
        case .line1: return (record.line1 ?? "").uppercased()
        case .line2: return (record.line2 ?? "").uppercased()
        case .line3: return (record.line3 ?? "").uppercased()
        }
    }
    
    private func updateField(_ fieldType: FieldType, value: String) {
        // Safety check: don't try to update records if zone isn't ready
        guard cloudKitManager.isZoneReady else {
            return
        }
        
        // CRITICAL FIX: Don't create records or trigger modifications for meaningless empty changes
        // Check if this is actually a meaningful change
        let currentValue = getFieldValue(fieldType)
        let newValue = value.uppercased()
        
        // If values are the same (including both being empty), don't do anything
        if currentValue == newValue {
            return
        }
        
        // Use Task to avoid "Publishing changes from within view updates" errors
        Task { @MainActor in
            // Only create record if we have actual content OR if we're clearing an existing record
            let hasContent = !newValue.isEmpty
            let isClearing = currentValue != newValue && newValue.isEmpty && !currentValue.isEmpty
            
            if hasContent || isClearing {
                // Create record if it doesn't exist (separate from view rendering)
                self.cloudKitManager.createRecordForEditing(date: self.date)
                
                // Now get the index
                guard let index = self.cloudKitManager.getRecordIndex(for: self.date),
                      index < self.cloudKitManager.dailySchedules.count else {
                    return
                }
                
                switch fieldType {
                case .line1:
                    self.cloudKitManager.updateField(at: index, field: "line1", value: newValue)
                case .line2:
                    self.cloudKitManager.updateField(at: index, field: "line2", value: newValue)
                case .line3:
                    self.cloudKitManager.updateField(at: index, field: "line3", value: newValue)
                }
                
                self.onDataChanged()
            }
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

