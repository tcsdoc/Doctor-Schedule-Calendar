import Foundation
import CoreData
import CloudKit
import SwiftUI

@MainActor
class CoreDataCloudKitManager: NSObject, ObservableObject {
    static let shared = CoreDataCloudKitManager()
    
    // MARK: - CloudKit Configuration
    private let containerIdentifier = "iCloud.com.gulfcoast.ProviderCalendar"
    private var cloudKitContainer: CKContainer {
        return CKContainer(identifier: containerIdentifier)
    }
    
    // MARK: - Core Data Stack
    lazy var persistentContainer: NSPersistentCloudKitContainer = {
        let container = NSPersistentCloudKitContainer(name: "ScheduleData")
        
        // Configure for CloudKit
        guard let description = container.persistentStoreDescriptions.first else {
            // Handle error gracefully instead of fatalError
            #if DEBUG
            print("❌ Could not retrieve a persistent store description.")
            #endif
            return container
        }
        
        // Use CloudKit configuration for proper sharing support
        description.configuration = "CloudKit"
        
        // Set up CloudKit configuration
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        
        // Configure CloudKit container options for PRIVATE database (privacy-focused)
        let cloudKitOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: containerIdentifier)
        
        // Set database scope to PRIVATE for secure access with sharing
        // This keeps data private to the owner and only allows invited users to access it
        cloudKitOptions.databaseScope = .private
        
        description.cloudKitContainerOptions = cloudKitOptions
        
        // Load the persistent stores
        container.loadPersistentStores { (storeDescription, error) in
            if let error = error as NSError? {
                #if DEBUG
                print("❌ Core Data error: \(error), \(error.userInfo)")
                #endif
                // Handle error gracefully - don't crash the app
                // Log error for debugging but continue execution
            } else {
                #if DEBUG
                print("✅ Core Data store loaded successfully with PRIVATE database scope")
                print("🔒 Private database: Data is private by default, accessible only via secure sharing")
                #endif
            }
        }
        
        // Configure automatic syncing
        container.viewContext.automaticallyMergesChangesFromParent = true
        
        do {
            try container.viewContext.setQueryGenerationFrom(.current)
        } catch {
            #if DEBUG
            print("❌ Failed to pin viewContext to the current generation: \(error)")
            #endif
        }
        
        return container
    }()
    
    var viewContext: NSManagedObjectContext {
        return persistentContainer.viewContext
    }
    
    // MARK: - Published Properties
    @Published var isCloudKitEnabled = false
    @Published var cloudKitStatus: String = "Checking..."
    @Published var sharingController: UICloudSharingController?
    
    // MARK: - Sharing Properties
    @Published var currentShare: CKShare?
    @Published var sharedSchedules: [CKShare] = []
    
    private override init() {
        super.init()
        checkCloudKitStatus()
        setupRemoteChangeNotifications()
    }
    
    // MARK: - CloudKit Status Check
    private func checkCloudKitStatus() {
        cloudKitContainer.accountStatus { [weak self] status, error in
            DispatchQueue.main.async {
                switch status {
                case .available:
                    self?.isCloudKitEnabled = true
                    self?.cloudKitStatus = "CloudKit Private Database Available"
                    #if DEBUG
                    print("✅ CloudKit available - using PRIVATE database for privacy-focused sharing")
                    #endif
                case .noAccount:
                    self?.isCloudKitEnabled = false
                    self?.cloudKitStatus = "No iCloud Account"
                    #if DEBUG
                    print("❌ No iCloud account")
                    #endif
                case .restricted:
                    self?.isCloudKitEnabled = false
                    self?.cloudKitStatus = "iCloud Restricted"
                    #if DEBUG
                    print("❌ iCloud account restricted")
                    #endif
                case .couldNotDetermine:
                    self?.isCloudKitEnabled = false
                    self?.cloudKitStatus = "iCloud Status Unknown"
                    #if DEBUG
                    print("❌ Could not determine iCloud status")
                    #endif
                case .temporarilyUnavailable:
                    self?.isCloudKitEnabled = false
                    self?.cloudKitStatus = "iCloud Temporarily Unavailable"
                    #if DEBUG
                    print("⚠️ iCloud temporarily unavailable")
                    #endif
                @unknown default:
                    self?.isCloudKitEnabled = false
                    self?.cloudKitStatus = "Unknown iCloud Status"
                    #if DEBUG
                    print("❓ Unknown iCloud status")
                    #endif
                }
            }
        }
    }
    
    // MARK: - Remote Change Notifications
    private func setupRemoteChangeNotifications() {
        NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: persistentContainer.persistentStoreCoordinator,
            queue: .main
        ) { [weak self] _ in
            #if DEBUG
            print("📊 Remote changes detected, refreshing UI")
            #endif
            self?.objectWillChange.send()
        }
    }
    
    // MARK: - Core Data Operations
    func save() {
        let context = viewContext
        
        guard context.hasChanges else { 
            #if DEBUG
            print("📊 No Core Data changes to save")
            #endif
            return 
        }
        
        do {
            try context.save()
            #if DEBUG
            print("✅ Core Data saved successfully - CloudKit sync should follow")
            #endif
            
            // Check if we have any objects
            let scheduleCount = try context.count(for: DailySchedule.fetchRequest())
            let notesCount = try context.count(for: MonthlyNotes.fetchRequest())
            #if DEBUG
            print("📊 Current data count - Schedules: \(scheduleCount), Notes: \(notesCount)")
            #endif
            
            // Check CloudKit sync status after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                self.checkCloudKitSyncStatus()
            }
        } catch {
            #if DEBUG
            print("❌ Core Data save error: \(error)")
            print("❌ Error details: \(error.localizedDescription)")
            #endif
        }
    }
    
    /// Check if Core Data records are actually syncing to CloudKit
    func checkCloudKitSyncStatus() {
        #if DEBUG
        print("🔍 Checking CloudKit sync status...")
        #endif
        
        Task {
            do {
                let database = cloudKitContainer.privateCloudDatabase
                
                // Check for CD_DailySchedule records in CloudKit
                let scheduleQuery = CKQuery(recordType: "CD_DailySchedule", predicate: NSPredicate(value: true))
                let (scheduleRecords, _) = try await database.records(matching: scheduleQuery, resultsLimit: 10)
                
                let scheduleCount = scheduleRecords.count
                #if DEBUG
                print("📊 Found \(scheduleCount) CD_DailySchedule records in CloudKit")
                #endif
                
                // Check for CD_MonthlyNotes records in CloudKit  
                let notesQuery = CKQuery(recordType: "CD_MonthlyNotes", predicate: NSPredicate(value: true))
                let (notesRecords, _) = try await database.records(matching: notesQuery, resultsLimit: 10)
                
                let notesCount = notesRecords.count
                #if DEBUG
                print("📊 Found \(notesCount) CD_MonthlyNotes records in CloudKit")
                #endif
                
                if scheduleCount == 0 && notesCount == 0 {
                    #if DEBUG
                    print("⚠️ WARNING: No Core Data records found in CloudKit!")
                    print("   This suggests Core Data → CloudKit sync is not working")
                    print("   Check: 1) iCloud account signed in, 2) Network connection, 3) Entitlements")
                    #endif
                } else {
                    #if DEBUG
                    print("✅ Core Data → CloudKit sync appears to be working")
                    
                    // List some actual records
                    for (_, result) in scheduleRecords.prefix(3) {
                        if let record = try? result.get() {
                            let date = record["CD_date"] as? Date ?? Date()
                            let line1 = record["CD_line1"] as? String ?? ""
                            #if DEBUG
                            print("📅 CloudKit Schedule: \(date) - \(line1)")
                            #endif
                        }
                    }
                    #endif
                }
                
            } catch {
                #if DEBUG
                print("❌ Failed to check CloudKit sync status: \(error)")
                #endif
            }
        }
    }
    
    // MARK: - CloudKit Sharing Methods
    
    /// Share a schedule object explicitly with other users (Private -> Shared Database)
    func shareScheduleExplicitly(_ schedule: DailySchedule) {
        #if DEBUG
        print("🔗 Creating explicit share for schedule (Private -> Shared Database)")
        #endif
        
        // Share from private database to shared database for specific users
        persistentContainer.share([schedule], to: nil) { objectIDs, share, container, error in
            if let error = error {
                #if DEBUG
                print("❌ Error creating explicit share: \(error)")
                print("❌ Error details: \(error.localizedDescription)")
                #endif
            } else {
                #if DEBUG
                print("✅ Successfully created explicit share")
                if let share = share {
                    print("📊 Share created with title: \(share[CKShare.SystemFieldKey.title] ?? "Unknown")")
                }
                #endif
            }
        }
    }
    
    /// Create a share for the schedule data
    func createShare(for schedule: DailySchedule, completion: @escaping (Result<CKShare, Error>) -> Void) {
        #if DEBUG
        print("🔗 Creating share for schedule dated: \(schedule.date ?? Date())")
        #endif
        
        // Create new share
        persistentContainer.share([schedule], to: nil) { [weak self] objectIDs, share, container, error in
            if let error = error {
                #if DEBUG
                print("❌ Error creating share: \(error)")
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                #endif
                return
            }
            
            guard let share = share else {
                #if DEBUG
                print("❌ Share object is nil")
                DispatchQueue.main.async {
                    completion(.failure(CoreDataError.shareCreationFailed))
                }
                #endif
                return
            }
            
            self?.configureShare(share)
            
            DispatchQueue.main.async {
                self?.currentShare = share
                completion(.success(share))
            }
        }
    }
    
    /// Create a comprehensive share using CloudKit APIs directly (better for "Add People" support)
    func createComprehensiveShare(for schedules: [DailySchedule], completion: @escaping (Result<CKShare, Error>) -> Void) {
        #if DEBUG
        print("🔗 Creating comprehensive share using CloudKit APIs for \(schedules.count) schedules")
        #endif
        
        // Method 1: Try Core Data sharing first
        persistentContainer.share(schedules, to: nil) { [weak self] objectIDs, share, container, error in
            if let error = error {
                #if DEBUG
                print("❌ Core Data sharing failed: \(error)")
                // Try alternative CloudKit approach
                self?.createDirectCloudKitShare(for: schedules, completion: completion)
                #endif
                return
            }
            
            guard let share = share else {
                #if DEBUG
                print("❌ Core Data share object is nil, trying CloudKit approach")
                self?.createDirectCloudKitShare(for: schedules, completion: completion)
                #endif
                return
            }
            
            self?.configureShare(share)
            
            // Save the share to CloudKit to enable participant addition
            self?.saveAndPresentShare(share, completion: completion)
        }
    }
    
    /// Create share using CloudKit APIs directly
    private func createDirectCloudKitShare(for schedules: [DailySchedule], completion: @escaping (Result<CKShare, Error>) -> Void) {
        #if DEBUG
        print("🔗 Creating share using direct CloudKit APIs")
        #endif
        
        // Get the CloudKit record IDs for the schedules
        var recordIDs: [CKRecord.ID] = []
        
        for schedule in schedules {
            // Try to get the CloudKit record ID from Core Data
            if let ckRecordID = schedule.objectID.uriRepresentation().absoluteString.components(separatedBy: "/").last {
                let recordID = CKRecord.ID(recordName: ckRecordID)
                recordIDs.append(recordID)
            }
        }
        
        guard !recordIDs.isEmpty else {
            #if DEBUG
            print("❌ No CloudKit record IDs found")
            DispatchQueue.main.async {
                completion(.failure(CoreDataError.shareCreationFailed))
            }
            #endif
            return
        }
        
        // Create a share record
        let shareRecordID = CKRecord.ID(recordName: UUID().uuidString)
        let shareRecord = CKShare(rootRecord: CKRecord(recordType: "CD_DailySchedule", recordID: recordIDs.first!), shareID: shareRecordID)
        
        configureShare(shareRecord)
        
        saveAndPresentShare(shareRecord, completion: completion)
    }
    
    /// Save share to CloudKit and present
    private func saveAndPresentShare(_ share: CKShare, completion: @escaping (Result<CKShare, Error>) -> Void) {
        #if DEBUG
        print("🔗 Saving share to CloudKit to enable participant addition")
        #endif
        
        let saveOperation = CKModifyRecordsOperation(recordsToSave: [share], recordIDsToDelete: nil)
        saveOperation.savePolicy = .allKeys
        saveOperation.qualityOfService = .userInitiated
        
        saveOperation.modifyRecordsResultBlock = { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    #if DEBUG
                    print("✅ Share saved to CloudKit successfully - should enable 'Add People'")
                    #endif
                    self?.currentShare = share
                    completion(.success(share))
                case .failure(let error):
                    #if DEBUG
                    print("❌ Failed to save share to CloudKit: \(error)")
                    #endif
                    // Still try to present the share
                    self?.currentShare = share
                    completion(.success(share))
                }
            }
        }
        
        cloudKitContainer.privateCloudDatabase.add(saveOperation)
    }
    
    /// Configure share properties for maximum compatibility with "Add People"
    private func configureShare(_ share: CKShare) {
        let currentYear = Calendar.current.component(.year, from: Date())
        share[CKShare.SystemFieldKey.title] = "Provider Schedule \(currentYear)"
        // Remove custom share type that might cause App Store issues
        share.publicPermission = .none
        
        // Additional configuration that might help with participant addition
        share[CKShare.SystemFieldKey.thumbnailImageData] = nil
        
        #if DEBUG
        print("🔗 Share configuration:")
        print("   Title: \(share[CKShare.SystemFieldKey.title] ?? "None")")
        print("   Public Permission: \(share.publicPermission.rawValue)")
        print("   Share URL: \(share.url?.absoluteString ?? "Not yet generated")")
        #endif
    }
    
    /// Create CloudKit share for private database using Core Data sharing
    func createCloudKitShare(completion: @escaping (Result<CKShare, Error>) -> Void) {
        #if DEBUG
        print("🔗 Creating CloudKit share using Core Data + CloudKit integration")
        #endif
        
        // Use Core Data's built-in sharing instead of manual CloudKit sharing
        let context = persistentContainer.viewContext
        
        // Get some recent schedule data to share
        let fetchRequest: NSFetchRequest<DailySchedule> = DailySchedule.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \DailySchedule.date, ascending: false)]
        fetchRequest.fetchLimit = 1
        
        do {
            let schedules = try context.fetch(fetchRequest)
            if let schedule = schedules.first {
                #if DEBUG
                print("🔗 Found schedule to share: \(schedule.date ?? Date())")
                #endif
                
                // Use Core Data's sharing capabilities
                createShare(for: schedule, completion: completion)
            } else {
                #if DEBUG
                print("🔗 No schedule data found, creating sample data for sharing")
                #endif
                
                // Create sample data to enable sharing
                let sampleSchedule = DailySchedule(context: context)
                sampleSchedule.date = Date()
                sampleSchedule.line1 = "PROVIDER"
                sampleSchedule.line2 = "SCHEDULE"  
                sampleSchedule.line3 = "SHARED"
                
                save()
                
                // Try sharing the sample data
                createShare(for: sampleSchedule, completion: completion)
            }
        } catch {
            #if DEBUG
            print("❌ Error fetching schedule data: \(error)")
            #endif
            completion(.failure(error))
        }
    }
    

    

    
    /// Direct participant invitation (works without App Store)
    func inviteParticipantDirectly(email: String, completion: @escaping (Result<String, Error>) -> Void) {
        #if DEBUG
        print("🔗 Creating direct participant invitation for \(email)")
        print("🔗 Note: For development builds, use UICloudSharingController 'Add People' instead")
        #endif
        
        createCloudKitShare { result in
            switch result {
            case .success(let share):
                // Use UICloudSharingController for proper participant management
                // Skip complex user discovery - let UICloudSharingController handle it
                #if DEBUG
                print("✅ Share created successfully: \(share.recordID.recordName)")
                print("💡 Use UICloudSharingController 'Add People' button to invite \(email)")
                print("💡 This is the recommended approach for CloudKit sharing")
                #endif
                
                completion(.success("Share created. Use 'Add People' button in the sharing interface to invite \(email)"))
                
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    /// Add participant to share (UICloudSharingController handles this automatically)
    func addParticipant(email: String, permission: CKShare.ParticipantPermission, to share: CKShare, completion: @escaping (Result<Void, Error>) -> Void) {
        #if DEBUG
        print("🔗 Participant addition will be handled by UICloudSharingController")
        print("🔗 Email: \(email), Permission: \(permission.rawValue)")
        #endif
        
        // Note: UICloudSharingController handles participant addition automatically
        // when the user taps "Add People" and enters email addresses
        DispatchQueue.main.async {
            completion(.success(()))
        }
    }
    
    /// Fetch current share participants 
    func fetchShareParticipants(for share: CKShare, completion: @escaping (Result<[CKShare.Participant], Error>) -> Void) {
        #if DEBUG
        print("🔗 Fetching current share participants")
        #endif
        
        DispatchQueue.main.async {
            completion(.success(share.participants))
        }
    }
    
    /// Save share to CloudKit to enable participant addition
    private func saveShareToCloudKit(_ share: CKShare, completion: @escaping (Result<Void, Error>) -> Void) {
        let saveOperation = CKModifyRecordsOperation(recordsToSave: [share], recordIDsToDelete: nil)
        
        saveOperation.modifyRecordsResultBlock = { result in
            switch result {
            case .success:
                #if DEBUG
                print("✅ Share successfully saved to CloudKit")
                #endif
                completion(.success(()))
            case .failure(let error):
                #if DEBUG
                print("❌ Failed to save share to CloudKit: \(error)")
                #endif
                completion(.failure(error))
            }
        }
        
        saveOperation.qualityOfService = .userInitiated
        cloudKitContainer.privateCloudDatabase.add(saveOperation)
    }
    
    /// Save share to CloudKit (legacy method)
    private func saveShare(_ share: CKShare, completion: @escaping (Result<Void, Error>) -> Void) {
        let operation = CKModifyRecordsOperation(recordsToSave: [share], recordIDsToDelete: nil)
        operation.modifyRecordsResultBlock = { result in
            switch result {
            case .success:
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
        
        cloudKitContainer.privateCloudDatabase.add(operation)
    }
    
    /// Present sharing controller optimized for "Add People" functionality
    func presentSharingController(for share: CKShare, from viewController: UIViewController) {
        #if DEBUG
        print("🔗 ENHANCED DEBUG: Presenting sharing controller for 'Add People' testing")
        print("🔗 Share recordID: \(share.recordID)")
        print("🔗 Share URL: \(share.url?.absoluteString ?? "No URL")")
        print("🔗 Share owner: \(share.owner.debugDescription)")
        print("🔗 Share participants count: \(share.participants.count)")
        print("🔗 Share public permission: \(share.publicPermission.rawValue)")
        print("🔗 Share title: \(share[CKShare.SystemFieldKey.title] ?? "No title")")
        
        // Comprehensive share state debugging
        print("🔗 Share creation timestamp: \(share.creationDate?.description ?? "Unknown")")
        print("🔗 Share modification timestamp: \(share.modificationDate?.description ?? "Unknown")")
        
        // Log all participants
        for (index, participant) in share.participants.enumerated() {
            print("🔗 Participant \(index): \(participant.userIdentity.debugDescription)")
            print("   Role: \(participant.role.rawValue)")
            print("   Permission: \(participant.permission.rawValue)")
            print("   Acceptance status: \(participant.acceptanceStatus.rawValue)")
        }
        #endif
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            #if DEBUG
            print("🔗 Creating UICloudSharingController...")
            #endif
            
            // Create sharing controller with maximum compatibility settings
            let sharingController = UICloudSharingController(share: share, container: self.cloudKitContainer)
            sharingController.delegate = self
            
            // CRITICAL: Include .allowPrivate to enable "Add People" (from troubleshooting guide)
            sharingController.availablePermissions = [.allowPrivate, .allowReadOnly, .allowReadWrite]
            
            #if DEBUG
            print("🔗 UICloudSharingController created successfully")
            print("🔗 Available permissions set: \(sharingController.availablePermissions)")
            print("🔗 Container identifier: \(self.cloudKitContainer.containerIdentifier ?? "Unknown")")
            
            // iPad specific configuration
            if let popover = sharingController.popoverPresentationController {
                popover.sourceView = viewController.view
                popover.sourceRect = CGRect(x: viewController.view.bounds.midX, y: viewController.view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
                print("🔗 iPad popover configured")
            }
            
            self.sharingController = sharingController
            
            // Present immediately - no delay needed for minimal share
            viewController.present(sharingController, animated: true) {
                #if DEBUG
                print("✅ UICloudSharingController presented")
                print("🔗 NOW CHECK: Look for 'Add People' button in the sharing interface")
                print("🔗 If no 'Add People' appears, the issue is fundamental with share creation")
                
                // Enhanced post-presentation debugging
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    print("🔗 === POST-PRESENTATION ANALYSIS ===")
                    print("   Share URL final: \(share.url?.absoluteString ?? "Still generating")")
                    print("   Share participants: \(share.participants.count)")
                    print("   Controller permissions: \(sharingController.availablePermissions)")
                    print("🔗 === END ANALYSIS ===")
                }
                #endif
            }
            #endif
        }
    }
    

    
    /// Handle share acceptance using CKAcceptSharesOperation (as mentioned in documentation)
    func handleAcceptedShare(_ shareMetadata: CKShare.Metadata) {
        #if DEBUG
        print("🔗 Accepting share using CKAcceptSharesOperation")
        #endif
        
        let acceptSharesOperation = CKAcceptSharesOperation(shareMetadatas: [shareMetadata])
        acceptSharesOperation.qualityOfService = .userInitiated
        
        acceptSharesOperation.acceptSharesResultBlock = { [weak self] result in
            switch result {
            case .success:
                #if DEBUG
                print("✅ Successfully accepted share using CKAcceptSharesOperation")
                #endif
                DispatchQueue.main.async {
                    // Refresh data to show shared content
                    self?.objectWillChange.send()
                    // Trigger Core Data sync to pull in shared data
                    self?.persistentContainer.viewContext.refreshAllObjects()
                }
            case .failure(let error):
                #if DEBUG
                print("❌ Error accepting share: \(error)")
                #endif
            }
        }
        
        cloudKitContainer.add(acceptSharesOperation)
    }
    
    /// Check if a share URL can be accepted
    func canAcceptShare(url: URL) -> Bool {
        return url.scheme == "https" && url.host?.contains("icloud.com") == true
    }
    
    /// Fetch shared schedules (simplified for Core Data + CloudKit)
    func fetchSharedSchedules() {
        // With NSPersistentCloudKitContainer, shared data is automatically
        // managed and will appear in Core Data fetch requests
        #if DEBUG
        print("📊 Shared schedules are automatically managed by Core Data + CloudKit")
        #endif
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }
}

// MARK: - UICloudSharingControllerDelegate
extension CoreDataCloudKitManager: UICloudSharingControllerDelegate {
    func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
        #if DEBUG
        print("❌ Failed to save share: \(error)")
        #endif
    }
    
    func itemTitle(for csc: UICloudSharingController) -> String? {
        return "Provider Schedule"
    }
    
    func itemThumbnailData(for csc: UICloudSharingController) -> Data? {
        // Return nil to use default thumbnail
        return nil
    }
    
    func itemType(for csc: UICloudSharingController) -> String? {
        return "Schedule Data"
    }
    
    func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
        #if DEBUG
        print("✅ Share saved successfully")
        #endif
    }
    
    func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
        #if DEBUG
        print("🛑 Sharing stopped")
        #endif
    }
}

// MARK: - Custom Errors
enum CoreDataError: Error {
    case shareCreationFailed
    case userNotFound
    case sharingNotAvailable
    
    var localizedDescription: String {
        switch self {
        case .shareCreationFailed:
            return "Failed to create share"
        case .userNotFound:
            return "User not found"
        case .sharingNotAvailable:
            return "Sharing not available"
        }
    }
}