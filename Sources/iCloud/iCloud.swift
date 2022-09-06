//
//  CloudStorage.swift
//  Wallet
//
//  Created by Liu Pengpeng on 2022/6/15.
//

import Foundation
import CloudKit

public enum iCloudFileStatus: Equatable {
    case synced
    case notSync(error: iCloudFileSyncError?)
    
    public static func == (lhs: iCloudFileStatus, rhs: iCloudFileStatus) -> Bool {
        switch (lhs, rhs) {
        case (.synced, .synced), (.notSync, .notSync):
            return true
        default:
            return false
        }
    }
    
    public var isSynced: Bool {
        return self == .synced
    }
}


public enum iCloudFileSyncError: Error, LocalizedError {
    case overQuota
    case serverNotAvailable
    
    case fileNotFound
    case createFileFailure
    case saveFileFailure
    
    case timeOut
    case unknown
    
    public var errorDescription: String? {
        switch self {
        case .overQuota:
            return "Over quota"
        case .serverNotAvailable:
            return "Server not available"
        case .fileNotFound:
            return "File not found"
        case .createFileFailure:
            return "Create file failure"
        case .saveFileFailure:
            return "Save file failure"
        case .timeOut:
            return "Time out"
        case .unknown:
            return "Unknow error"
        }
    }
    
    
    // NSURLUbiquitousItemDownloadingErrorKey contains an error with this code when the item has not been uploaded to iCloud by the other devices yet
    // NSUbiquitousFileUnavailableError API_AVAILABLE(macos(10.9), ios(7.0), watchos(2.0), tvos(9.0)) = 4353,

    // NSURLUbiquitousItemUploadingErrorKey contains an error with this code when the item has not been uploaded to iCloud because it would make the account go over-quota
    // NSUbiquitousFileNotUploadedDueToQuotaError API_AVAILABLE(macos(10.9), ios(7.0), watchos(2.0), tvos(9.0)) = 4354,
    
    // NSURLUbiquitousItemDownloadingErrorKey and NSURLUbiquitousItemUploadingErrorKey contain an error with this code when connecting to the iCloud servers failed
    // NSUbiquitousFileUbiquityServerNotAvailable API_AVAILABLE(macos(10.9), ios(7.0), watchos(2.0), tvos(9.0)) = 4355,

}

public typealias iCloudStatus = CKAccountStatus
public extension iCloudStatus {
    var isEnable: Bool {
        switch self {
        case .available:
            return true
        default:
            return false
        }
    }
}

import Combine
import UIKit

final public class iCloud: ObservableObject {
    
    @Published public var status: iCloudStatus = .couldNotDetermine
    @Published public var docs: [Document] = []
    
    private(set) var metadataProvider: MetadataProvider?
    private let container = CKContainer.default()
    
    private var cancellableSet = Set<AnyCancellable>()
    
    public init() {
        subscribe()
        requestAccountStatus()
    }
    
    private func subscribe() {
        
        // Subscribe iCloud status change event
        let names: [NSNotification.Name] = [
            .CKAccountChanged,
            UIApplication.didBecomeActiveNotification
        ]
        let publishers = names.map { NotificationCenter.default.publisher(for: $0) }
        
        Publishers
            .MergeMany(publishers)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.requestAccountStatus()
            }
            .store(in: &cancellableSet)
        
        // Subscribe iCloud file change event
        NotificationCenter
            .default
            .publisher(for: .sicdMetadataDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self = self else { return }
                guard notification.object is MetadataProvider,
                      let userInfo = notification.userInfo as? MetadataProvider.MetadataDidChangeUserInfo,
                      let metadataItemList = userInfo[.queryResults] else {
                    return
                }
                self.docs = Array(Set(metadataItemList.map {
                    Document(fileURL: $0.url, fileItem: $0.nsMetadataItem)
                }))
                .sorted(by: {
                    $0.creationDate.timeIntervalSince1970 < $1.creationDate.timeIntervalSince1970
                })
            }
            .store(in: &cancellableSet)
    }
    
    private func requestAccountStatus() {
        container.accountStatus { [weak self] status, err in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard err == nil else {
                    self.status = status
                    return
                }
                
                if status.isEnable {
                    self.metadataProvider = MetadataProvider(containerIdentifier: nil)
                    self.status = status
                } else {
                    self.status = status
                }
            }
        }
    }
}

extension iCloud {

    public func createDocument(with fileName: String, completionHandler: ((iCloudFileStatus) -> Void)?) {
        guard let fileURL = url(for: fileName) else {
            completionHandler?(.notSync(error: .fileNotFound))
            return
        }
        
        /// In case that the folder not exists
        let fileManager = FileManager.default
        let folderPath = fileURL.deletingLastPathComponent().path
        do {
            try fileManager.createDirectory(atPath: folderPath, withIntermediateDirectories: true, attributes: nil)
        } catch _ {
            completionHandler?(.notSync(error: .createFileFailure))
            return
        }
        
        // save(to:for:completionHandler:) keeps the document open, so close the document after the saving finishes.
        // Keeping the document open prevents (blocks) others from coordinated writing it.
        //
        // Ignore the document saving error here because
        // Document's handleError method should have handled the document reading or saving error, if necessary.
        //
        let document = Document(fileURL: fileURL)
        
        document.save(to: fileURL, for: .forCreating) { _ in
            document.close { success in
                // File create success, but not sync to iCloud drive, should listen for change
                completionHandler?(success ? .notSync(error: nil) : .notSync(error: .createFileFailure))
            }
        }
    }

    public func removeDocument(at fileURL: URL) {
        DispatchQueue.main.async {
            NSFileCoordinator().coordinate(writingItemAt: fileURL, options: .forDeleting, error: nil) { newURL in
                do {
                    try FileManager.default.removeItem(atPath: newURL.path)
                } catch let error as NSError {
                    print(error.localizedDescription)
                }
            }
        }
    }
    
    public func removeAll() {
        docs.forEach {
            removeDocument(at: $0.fileURL)
        }
    }
    
    public func renameDocument(at url: URL, to newName: String) {
        
        let fileManager = FileManager.default
        do {
            let dirPath = url.deletingLastPathComponent().absoluteString
            let newPath = "\(dirPath)\(newName)"
            if fileManager.fileExists(atPath: newPath) {
                try fileManager.removeItem(at: URL(string: newPath)!)
            }
            try fileManager.moveItem(at: url, to: URL(string: newPath)!)
        } catch let error {
            print(error.localizedDescription)
        }
    }
    
    public func url(for fileName: String) -> URL? {
        guard let rootURL = metadataProvider?.containerRootURL else { return nil }
        
        var url = rootURL.appendingPathComponent("Data") // Scope: Documents, Data
        let name = fileName.isEmpty ? "Untitled" : fileName
        url = url.appendingPathComponent(name, isDirectory: false)
        return url
    }
    
    public func fileExisted(name: String) -> Bool {
        return docs.filter({ $0.phrase?.joined(separator: " ") == name}).count != 0
    }
}
