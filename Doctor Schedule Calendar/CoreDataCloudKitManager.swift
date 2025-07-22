import Foundation
import CoreData
import CloudKit
import SwiftUI

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
            fatalError("Could not retrieve a persistent store description.")
        }
        
        // Set up CloudKit configuration
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        
        // Configure CloudKit container options
        let cloudKitOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: containerIdentifier)
        description.cloudKitContainerOptions = cloudKitOptions
        
        // Load the persistent stores
        container.loadPersistentStores { (storeDescription, error) in
            if let error = error as NSError? {
                print("❌ Core Data error: \(error), \(error.userInfo)")
                fatalError("Unresolved error \(error), \(error.userInfo)")
            } else {
                print("✅ Core Data store loaded successfully")
            }
        }
        
        // Configure automatic syncing
        container.viewContext.automaticallyMergesChangesFromParent = true
        
        do {
            try container.viewContext.setQueryGenerationFrom(.current)
        } catch {
            print("❌ Failed to pin viewContext to the current generation: \(error)")
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
                    self?.cloudKitStatus = "CloudKit Available"
                    print("✅ CloudKit available for sharing")
                case .noAccount:
                    self?.isCloudKitEnabled = false
                    self?.cloudKitStatus = "No iCloud Account"
                    print("❌ No iCloud account")
                case .restricted:
                    self?.isCloudKitEnabled = false
                    self?.cloudKitStatus = "iCloud Restricted"
                    print("❌ iCloud account restricted")
                case .couldNotDetermine:
                    self?.isCloudKitEnabled = false
                    self?.cloudKitStatus = "iCloud Status Unknown"
                    print("❌ Could not determine iCloud status")
                case .temporarilyUnavailable:
                    self?.isCloudKitEnabled = false
                    self?.cloudKitStatus = "iCloud Temporarily Unavailable"
                    print("⚠️ iCloud temporarily unavailable")
                @unknown default:
                    self?.isCloudKitEnabled = false
                    self?.cloudKitStatus = "Unknown iCloud Status"
                    print("❓ Unknown iCloud status")
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
            print("📊 Remote changes detected, refreshing UI")
            self?.objectWillChange.send()
        }
    }
    
    // MARK: - Core Data Operations
    func save() {
        let context = viewContext
        
        guard context.hasChanges else { return }
        
        do {
            try context.save()
            print("✅ Core Data saved successfully")
        } catch {
            print("❌ Core Data save error: \(error)")
        }
    }
    
    // MARK: - CloudKit Sharing Methods
    
    /// Create a share for the schedule data
    func createShare(for schedule: DailySchedule, completion: @escaping (Result<CKShare, Error>) -> Void) {
        persistentContainer.share([schedule], to: nil) { [weak self] objectIDs, share, container, error in
            if let error = error {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }
            
            guard let share = share else {
                DispatchQueue.main.async {
                    completion(.failure(CoreDataError.shareCreationFailed))
                }
                return
            }
            
            // Configure share properties
            share[CKShare.SystemFieldKey.title] = "Provider Schedule"
            share.publicPermission = .none
            
            DispatchQueue.main.async {
                self?.currentShare = share
                completion(.success(share))
            }
        }
    }
    
    /// Add participant to share by email (using UICloudSharingController)
    func addParticipant(email: String, permission: CKShare.ParticipantPermission, to share: CKShare, completion: @escaping (Result<Void, Error>) -> Void) {
        // For CloudKit sharing, we'll use UICloudSharingController which handles
        // participant management automatically
        DispatchQueue.main.async {
            completion(.success(()))
        }
    }
    
    /// Save share to CloudKit
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
    
    /// Present sharing controller
    func presentSharingController(for share: CKShare, from viewController: UIViewController) {
        let sharingController = UICloudSharingController(share: share, container: cloudKitContainer)
        sharingController.delegate = self
        sharingController.availablePermissions = [.allowReadOnly, .allowReadWrite]
        
        DispatchQueue.main.async {
            self.sharingController = sharingController
            viewController.present(sharingController, animated: true)
        }
    }
    
    /// Handle share acceptance
    func handleAcceptedShare(_ shareMetadata: CKShare.Metadata) {
        let acceptSharesOperation = CKAcceptSharesOperation(shareMetadatas: [shareMetadata])
        
        acceptSharesOperation.acceptSharesResultBlock = { result in
            switch result {
            case .success:
                print("✅ Successfully accepted share")
                DispatchQueue.main.async {
                    // Refresh data to show shared content
                    self.objectWillChange.send()
                }
            case .failure(let error):
                print("❌ Error accepting share: \(error)")
            }
        }
        
        cloudKitContainer.add(acceptSharesOperation)
    }
    
    /// Fetch shared schedules (simplified for Core Data + CloudKit)
    func fetchSharedSchedules() {
        // With NSPersistentCloudKitContainer, shared data is automatically
        // managed and will appear in Core Data fetch requests
        print("📊 Shared schedules are automatically managed by Core Data + CloudKit")
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }
}

// MARK: - UICloudSharingControllerDelegate
extension CoreDataCloudKitManager: UICloudSharingControllerDelegate {
    func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
        print("❌ Failed to save share: \(error)")
    }
    
    func itemTitle(for csc: UICloudSharingController) -> String? {
        return "Provider Schedule"
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