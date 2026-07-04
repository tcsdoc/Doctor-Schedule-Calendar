// SharingSupport.swift
// CloudKit sharing UI and standard iOS share sheet item source.

import SwiftUI
import CloudKit
import UIKit

// MARK: - CloudKit Management View (for existing shares)
struct CloudKitManagementView: UIViewControllerRepresentable {
    let share: CKShare
    
    func makeUIViewController(context: Context) -> UICloudSharingController {
        let sharingController = UICloudSharingController(share: share, container: CKContainer(identifier: "iCloud.com.gulfcoast.ProviderCalendar"))
        sharingController.delegate = CloudKitSharingDelegate.shared
        return sharingController
    }
    
    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {
        // No updates needed
    }
}

// MARK: - CloudKit Sharing Delegate (for management interface)
class CloudKitSharingDelegate: NSObject, UICloudSharingControllerDelegate {
    static let shared = CloudKitSharingDelegate()
    
    func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
        redesignLog("❌ Failed to save share: \(error.localizedDescription)")
    }
    
    func itemTitle(for csc: UICloudSharingController) -> String? {
        return "Provider Schedule Calendar"
    }
    
    func itemType(for csc: UICloudSharingController) -> String? {
        return "Calendar Schedule"
    }
    
    func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
    }
    
    func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
    }
}

// MARK: - Standard iOS Share Activity Item Source (from original working implementation)
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
