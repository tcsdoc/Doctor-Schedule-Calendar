import SwiftUI
import CloudKit
import UIKit


// MARK: - Modern PSC with SV-Inspired UI + Calendar Editing
struct ContentView: View {
    @StateObject private var viewModel = ScheduleViewModel()
    @State private var currentMonthIndex = 0
    @State private var showingSaveAlert = false
    @State private var saveMessage = ""
    @State private var showingManageSheet = false
    @State private var existingShare: CKShare?
    @State private var shareReadyForManagement = false
    @State private var showingShareActions = false
    @State private var isPreparingShare = false
    @State private var isFlashing = false
    
    // Duplicate detection states
    @State private var showingDuplicateAlert = false
    @State private var duplicateDetectionResult: ScheduleViewModel.DuplicateDetectionResult?
    @State private var showingDuplicateDetails = false
    @State private var isDuplicateCheckComplete = false
    
    /// Recreated when returning from background so TextFields regain focus after overnight resume.
    @State private var editorRefreshID = UUID()
    @Environment(\.scenePhase) private var scenePhase
    
    // Note: Share functionality now uses standard iOS share sheet directly
    
    private let calendar = Calendar.current
    private static let offlineCacheFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
    private var offlineCacheFormatter: DateFormatter { Self.offlineCacheFormatter }

    private var appVersionLabel: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "4.3"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "📅 PSC v\(version) (\(build))"
    }
    
    var body: some View {
        // FULL SCREEN iPad Layout - No NavigationView constraints
        VStack(spacing: 0) {
            // Fixed header - FULL WIDTH
            modernHeader
                .background(Color(UIColor.systemBackground))
                .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 2)
            
                // Monthly Notes Section
                if let currentMonth = viewModel.availableMonths.safeGet(index: currentMonthIndex) {
                    MonthlyNotesContainer(
                        currentMonth: currentMonth,
                        viewModel: viewModel,
                        monthKey: monthKey(for: currentMonth)
                    )
                    .id("\(monthKey(for: currentMonth))-\(viewModel.monthlyNotes.count)-\(editorRefreshID)")
                }
                
                // Calendar content - FULL WIDTH with keyboard awareness
                ScrollView {
                    VStack(spacing: 20) {
                        if let currentMonth = viewModel.availableMonths.safeGet(index: currentMonthIndex) {
                            MonthCalendarView(
                                month: currentMonth,
                                schedules: viewModel.schedules,
                                onScheduleChange: viewModel.updateSchedule,
                                onFocusChange: { viewModel.editorFocusChanged("calendar", isFocused: $0) }
                            )
                            .id(editorRefreshID)
                            .padding(.horizontal, 20) // Only horizontal padding for calendar
                        } else {
                            Text("No data available")
                                .foregroundColor(.gray)
                                .padding()
                        }
                        }
                    .padding(.vertical, 20)
                    }
                }
        .onAppear {
            initializeCurrentMonth()
        }
        .alert("Save Status", isPresented: $showingSaveAlert) {
            Button("OK") {}
        } message: {
            Text(saveMessage)
        }
        .alert("Data Integrity Check", isPresented: $showingDuplicateAlert) {
            if let result = duplicateDetectionResult {
                if result.totalAffectedDates <= 10 {
                    // Simple alert for small numbers
                    Button("Cancel", role: .cancel) {}
                    Button("Fix Now", role: .destructive) {
                        performDuplicateCleanup(result)
                    }
                } else {
                    // Require review for large numbers
                    Button("Cancel", role: .cancel) {}
                    Button("Review Report") {
                        showingDuplicateDetails = true
                    }
                }
            }
        } message: {
            if let result = duplicateDetectionResult {
                if result.totalAffectedDates <= 10 {
                    Text(formatSimpleDuplicateMessage(result))
                } else {
                    Text(formatLargeDuplicateMessage(result))
                }
            }
        }
        .sheet(isPresented: $showingManageSheet) {
            if let share = existingShare {
                CloudKitManagementView(share: share)
            }
        }
        .sheet(isPresented: $showingDuplicateDetails) {
            if let result = duplicateDetectionResult {
                DuplicateDetailsView(result: result, onCleanup: {
                    showingDuplicateDetails = false
                    performDuplicateCleanup(result)
                })
            }
        }
        .onChange(of: shareReadyForManagement) {
            if shareReadyForManagement && existingShare != nil {
                showingManageSheet = true
                shareReadyForManagement = false // Reset for next use
            }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            switch newPhase {
            case .background:
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil, from: nil, for: nil
                )
            case .active where oldPhase == .background:
                editorRefreshID = UUID()
            default:
                break
            }
        }
        .onChange(of: viewModel.latestDuplicateResult?.hasDuplicates) { _, hasDuplicates in
            guard hasDuplicates == true, !isDuplicateCheckComplete,
                  let result = viewModel.latestDuplicateResult else { return }
            isDuplicateCheckComplete = true
            duplicateDetectionResult = result
            showingDuplicateAlert = true
        }
    }
    
    // MARK: - Ultra-Compact iPad Header (minimal height for 6-week months)
    private var modernHeader: some View {
        VStack(spacing: 6) {
            // ULTRA-COMPACT: Single row with essentials only
            HStack(spacing: 16) {
                // Left: App name only
                Text(appVersionLabel)
                    .font(.headline)
                    .fontWeight(.bold)
                
                Spacer()
                
                // Center: Status (compact)
                if viewModel.isSaving {
                        HStack(spacing: 4) {
                        ProgressView().scaleEffect(0.7)
                        Text("Saving").font(.caption)
                    }
                    .foregroundColor(.orange)
                } else if viewModel.isLoading {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(1.0)
                        Text("Loading from Cloud...").font(.headline).fontWeight(.semibold)
                    }
                    .foregroundColor(.blue)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                    .opacity(isFlashing ? 0.3 : 1.0)
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isFlashing)
                    .onAppear {
                        isFlashing = true
                    }
                    .onDisappear {
                        isFlashing = false
                    }
                } else if viewModel.isSyncingFromCloud {
                    HStack(spacing: 4) {
                        ProgressView().scaleEffect(0.7)
                        Text("Syncing with Cloud...").font(.caption)
                    }
                    .foregroundColor(.blue)
                } else if viewModel.isOffline, let cacheDate = viewModel.offlineCacheDate {
                    Text("📴 Offline — schedule as of \(offlineCacheFormatter.string(from: cacheDate))")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.orange)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                } else if !viewModel.isCloudKitAvailable {
                    Text("⚠️ Cloud Issue").font(.caption)
                        .foregroundColor(.red)
                } else if viewModel.hasChanges {
                    Text("⚠️ Saved on iPad — not to Cloud")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.yellow.opacity(0.85))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.orange.opacity(0.5), lineWidth: 1)
                        )
                } else {
                    Text("✅ Ready").font(.caption)
                        .foregroundColor(.green)
                }
                
                Spacer()
                
                // Right: Compact action buttons (with edge spacing)
                HStack(spacing: 8) {
                    Button(action: saveData) {
                        HStack(spacing: 3) {
                            Image(systemName: "square.and.arrow.down")
                            Text(saveButtonText)
                        }
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue)
                        .cornerRadius(6)
                    }
                    
                    Button(action: shareCalendar) {
                        HStack(spacing: 3) {
                            if isPreparingShare {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: "person.badge.plus")
                            }
                            Text(isPreparingShare ? "Preparing…" : "Share")
                        }
                        .font(.caption)
                        .foregroundColor(.green)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(6)
                    }
                    .disabled(isPreparingShare)
                    
                    Button(action: { showingShareActions = true }) {
                        HStack(spacing: 3) {
                            Image(systemName: "person.2.circle")
                            Text("Manage")
                        }
                        .font(.caption)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(6)
                    }
                    .confirmationDialog("Share Options", isPresented: $showingShareActions, titleVisibility: .visible) {
                        Button("Manage Existing Share") {
                            manageShares()
                        }
                        Button("Reset Share Link") {
                            shareCalendar()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("Reset creates a new ScheduleViewer link and invalidates the previous one. Use this if viewers see “Share not found”.")
                    }
                    
                    Button(action: printCalendar) {
                        HStack(spacing: 3) {
                            Image(systemName: "printer")
                            Text("Print")
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(6)
                    }
                    
                }
                .padding(.trailing, 60) // EVEN MORE padding - move buttons further from navigation area
            }
            
            // ULTRA-COMPACT: Month navigation inline
            if !viewModel.availableMonths.isEmpty {
                HStack(spacing: 16) {
                    Button(action: previousMonth) {
                        Image(systemName: "chevron.left.circle.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }
                    .disabled(currentMonthIndex <= 0)
                    
                    Spacer()
                    
                    Text(currentMonthName)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Button(action: nextMonth) {
                        Image(systemName: "chevron.right.circle.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }
                    .disabled(currentMonthIndex >= viewModel.availableMonths.count - 1)
                }
            }
        }
        .padding(.horizontal, 50) // MUCH MORE padding to move buttons away from edges
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(0)
    }
    
    // MARK: - Navigation Logic
    private var currentMonthName: String {
        guard let currentMonth = viewModel.availableMonths.safeGet(index: currentMonthIndex) else {
            return "No Data"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: currentMonth)
    }
    
    private func previousMonth() {
        if currentMonthIndex > 0 {
            currentMonthIndex -= 1
        }
    }
    
    private func nextMonth() {
        if currentMonthIndex < viewModel.availableMonths.count - 1 {
            currentMonthIndex += 1
        }
    }
    
    private func initializeCurrentMonth() {
        guard !viewModel.availableMonths.isEmpty else { return }
        
        let now = Date()
        // Try to find current month in available months
        if let foundIndex = viewModel.availableMonths.firstIndex(where: { month in
            calendar.isDate(month, equalTo: now, toGranularity: .month)
        }) {
            currentMonthIndex = foundIndex
        } else {
            // Default to first available month
            currentMonthIndex = 0
        }
        
    }
    
    // MARK: - Actions
    private var saveButtonText: String {
        return viewModel.hasChanges ? "Save" : "Saved"
    }
    
    private func saveData() {
        Task {
            if viewModel.hasChanges {
                let (cloudSuccess, savedCount, totalCount, savedLocallyOnly) = await viewModel.saveChanges()
                await MainActor.run {
                    if cloudSuccess {
                        saveMessage = "✅ All \(totalCount) changes saved successfully!"
                    } else if savedLocallyOnly {
                        saveMessage = """
                        ✅ Saved locally on this iPad.
                        
                        Not saved to the Cloud (no internet). Your data is on this device; the PDF in Documents is updated for backup.
                        Tap Save when you're online to sync to the Cloud.
                        """
                    } else {
                        let failedCount = totalCount - savedCount
                        saveMessage = "⚠️ Partial save: \(savedCount)/\(totalCount) on the Cloud\n\(failedCount) still pending — tap Save to retry"
                    }
                    showingSaveAlert = true
                        }
                    } else {
                await MainActor.run {
                    saveMessage = "✅ No changes to save"
                    showingSaveAlert = true
                }
            }
        }
    }
    
    private func shareCalendar() {
        Task {
            await performShare()
        }
    }
    
    private func performShare() async {
        await MainActor.run { isPreparingShare = true }
        defer {
            Task { @MainActor in
                isPreparingShare = false
            }
        }
        
        do {
            // Always issue a fresh .readOnly link share so SV can accept it.
            // Reusing stale CloudKit short tokens causes "Share not found".
            let share = try await viewModel.createShare()
            
            guard let shareURL = share.url else {
                await MainActor.run {
                    saveMessage = "❌ No share URL available. Please try again."
                    showingSaveAlert = true
                }
                return
            }
            
            guard share.publicPermission == .readOnly else {
                await MainActor.run {
                    saveMessage = "❌ Share was created without link access. Please use Reset Share Link and try again."
                    showingSaveAlert = true
                }
                return
            }
            
            redesignLog("✅ Issuing workable share URL: \(shareURL.absoluteString)")
            
            let shareText = """
            You're invited to view the Provider Schedule Calendar.

            In the ScheduleViewer app, tap Add Share and paste this link:
            """
            
            let customItem = ShareActivityItemSource(
                text: shareText,
                url: shareURL,
                subject: "Provider Schedule Calendar - Shared Access"
            )
            
            await MainActor.run {
                let activityViewController = UIActivityViewController(
                    activityItems: [customItem],
                    applicationActivities: nil
                )
                
                if let popover = activityViewController.popoverPresentationController {
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let window = windowScene.windows.first {
                        popover.sourceView = window
                        popover.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
                        popover.permittedArrowDirections = []
                    }
                }
                
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let window = windowScene.windows.first,
                   let rootViewController = window.rootViewController {
                    rootViewController.present(activityViewController, animated: true)
                }
            }
            
        } catch {
            await MainActor.run {
                saveMessage = "❌ Share creation failed: \(error.localizedDescription)"
                showingSaveAlert = true
                redesignLog("❌ Share creation error: \(error)")
            }
        }
    }
    
    private func manageShares() {
        Task {
            do {
                
                // Try to fetch existing share first
                if let existingShare = try await viewModel.getExistingShare() {
                    await MainActor.run {
                        self.existingShare = existingShare
                        
                        // Trigger sheet presentation via onChange
                        if existingShare.url != nil {
                            self.shareReadyForManagement = true
                        } else {
                            redesignLog("❌ Share has no URL, cannot open management interface")
                            saveMessage = "❌ Share is invalid - cannot manage"
                            showingSaveAlert = true
                        }
                    }
                } else {
                    // No existing share found
                    await MainActor.run {
                        saveMessage = "ℹ️ No active shares found to manage. Create a share first using the Share button."
                        showingSaveAlert = true
                    }
                }
                
            } catch {
                await MainActor.run {
                    saveMessage = "❌ Failed to check for existing shares: \(error.localizedDescription)"
                    showingSaveAlert = true
                    redesignLog("❌ Error checking for existing shares: \(error)")
                }
            }
        }
    }
    
    private func monthKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }
    
    // MARK: - Print Functions (PDFKit Direct Generation)
    private func printCalendar() {
        let updatedAt = Date()
        guard let pdfData = CalendarPDFGenerator.generatePDFData(
            schedules: viewModel.schedules,
            monthlyNotes: viewModel.monthlyNotes,
            months: viewModel.availableMonths,
            updatedAt: updatedAt
        ) else {
            DispatchQueue.main.async {
                self.saveMessage = "❌ Failed to generate PDF"
                self.showingSaveAlert = true
            }
            return
        }

        let printController = UIPrintInteractionController.shared
        let printInfo = UIPrintInfo.printInfo()

        printInfo.outputType = .general
        printInfo.jobName = "Provider Schedule Calendar"
        printInfo.orientation = .portrait

        printController.printInfo = printInfo
        printController.showsNumberOfCopies = true
        printController.printingItem = pdfData

        printController.present(animated: true) { (_, completed, error) in
            if let error = error {
                DispatchQueue.main.async {
                    self.saveMessage = "❌ Print failed: \(error.localizedDescription)"
                    self.showingSaveAlert = true
                }
            } else if completed {
                DispatchQueue.main.async {
                    self.saveMessage = "🖨️ Calendar printed successfully!"
                    self.showingSaveAlert = true
                }
            }
        }
    }

    // MARK: - Duplicate Detection Functions
    
    private func formatSimpleDuplicateMessage(_ result: ScheduleViewModel.DuplicateDetectionResult) -> String {
        var message = "⚠️ Found \(result.totalDuplicateCount) duplicate records across \(result.totalAffectedDates) dates.\n\n"
        message += "This may cause incorrect data in ScheduleViewer.\n\n"
        message += "Affected dates:\n"
        
        for group in result.scheduleDuplicates.prefix(10) {
            message += "• \(group.dateKey) (Schedule)\n"
        }
        for group in result.monthlyNoteDuplicates.prefix(10) {
            message += "• \(group.dateKey) (Monthly Note)\n"
        }
        
        message += "\nThe most recent record will be kept for each date."
        return message
    }
    
    private func formatLargeDuplicateMessage(_ result: ScheduleViewModel.DuplicateDetectionResult) -> String {
        return """
        ⚠️ LARGE DATA ISSUE DETECTED
        
        Found \(result.totalDuplicateCount) duplicate records across \(result.totalAffectedDates) dates.
        
        Due to the large number of duplicates, you must review the cleanup report before proceeding.
        
        This will:
        • Keep the most recent record for each date
        • Delete all older duplicate records
        • Create an audit log file
        
        Tap "Review Report" to see what will be cleaned up.
        """
    }
    
    private func performDuplicateCleanup(_ result: ScheduleViewModel.DuplicateDetectionResult) {
        Task {
            do {
                _ = try await viewModel.cleanupDuplicates(result)
                
                await MainActor.run {
                    saveMessage = """
                    ✅ Cleanup Complete!
                    
                    Removed \(result.totalDuplicateCount) duplicate records.
                    
                    Audit log saved to Documents folder.
                    """
                    showingSaveAlert = true
                    
                    // Reset state
                    duplicateDetectionResult = nil
                }
                
                // Save any remaining local edits after cleanup
                let (cloudSuccess, savedCount, totalCount, _) = await viewModel.saveChanges()
                if !cloudSuccess && savedCount == 0 {
                    await MainActor.run {
                        saveMessage = """
                        ✅ Saved locally on this iPad.
                        
                        Not saved to the Cloud yet. Tap Save when online to sync.
                        """
                        showingSaveAlert = true
                    }
                } else if !cloudSuccess {
                    await MainActor.run {
                        let failedCount = totalCount - savedCount
                        saveMessage = "⚠️ Partial save: \(savedCount)/\(totalCount) saved\n\(failedCount) records still pending — tap Save to retry."
                        showingSaveAlert = true
                    }
                }

                await viewModel.refreshAfterCleanup()
            } catch {
                await MainActor.run {
                    saveMessage = "❌ Cleanup failed: \(error.localizedDescription)"
                    showingSaveAlert = true
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
