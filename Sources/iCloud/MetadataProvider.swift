//
//  MetadataProvider.swift
//  Wallet
//
//  Created by Liu Pengpeng on 2022/6/15.
//

import Foundation
import Combine

extension Notification.Name {
    static let sicdMetadataDidChange = Notification.Name("WalletMetadataDidChange")
}

class MetadataProvider {
    // Give userInfo a stronger type.
    //
    typealias MetadataDidChangeUserInfo = [MetadataDidChangeUserInfoKey: [MetadataItem]]
    enum MetadataDidChangeUserInfoKey: String {
        case queryResults
    }
    
    private(set) var containerRootURL: URL?
    private let metadataQuery = NSMetadataQuery()
    private var querySubscriber: AnyCancellable?
    
    // Failable init: fails if there isn’t a logged-in iCloud account.
    //
    init?(containerIdentifier: String?) {

        guard FileManager.default.ubiquityIdentityToken != nil else {
            print("⛔️ iCloud isn't enabled yet. Please enable iCloud and run again.")
            return nil
        }
        
        // Dispatch to a global queue because url(forUbiquityContainerIdentifier:) might take a nontrivial
        // amount of time to set up iCloud and return the requested URL
        //
        DispatchQueue.global().async {
            if let url = FileManager.default.url(forUbiquityContainerIdentifier: containerIdentifier) {
                DispatchQueue.main.async {
                    self.containerRootURL = url
                }
                return
            }
            print("⛔️ Failed to retrieve iCloud container URL for:\(containerIdentifier ?? "nil")\n"
                    + "Make sure your iCloud is available and run again.")
        }
        
        // Observe and handle NSMetadataQuery's notifications.
        // Posts .metadataDidChange from the main queue and returns after clients finish handling it.
        //
        let names: [NSNotification.Name] = [.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate]
        let publishers = names.map { NotificationCenter.default.publisher(for: $0) }
        querySubscriber = Publishers.MergeMany(publishers).receive(on: DispatchQueue.main).sink { notification in
            guard notification.object as? NSMetadataQuery === self.metadataQuery else { return }
            var userInfo = MetadataDidChangeUserInfo()
            userInfo[.queryResults] = self.metadataItemList()
            NotificationCenter.default.post(name: .sicdMetadataDidChange, object: self, userInfo: userInfo)
        }
        
        // [Entropy](URLEncoded-Base64)-[Label](URLEncoded-Bae64)
        // Yzk5OTJhN2JhN2I4MzRjMTQ0MGFmY2M3MzAxNmNmMDAyZmE3ZDQ0Zg==@U2F0b3NoaQ==
        // Files named with a suffix of `.delete` have been deleted by owners.
        metadataQuery.notificationBatchingInterval = 1
        metadataQuery.searchScopes = [NSMetadataQueryUbiquitousDataScope, NSMetadataQueryUbiquitousDocumentsScope]
        metadataQuery.predicate = NSPredicate(format: "%K MATCHES %@", NSMetadataItemFSNameKey, "^[A-Za-z0-9+-=]*@[A-Za-z0-9+-=]*(?<!(.delete))$")
        metadataQuery.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSContentChangeDateKey, ascending: true)]

        metadataQuery.start()
    }
    
    // Stop metadataQuery if it is still running.
    //
    deinit {
        guard metadataQuery.isStarted else { return }
        metadataQuery.stop()
    }
}

// MARK: - Providing metadata items
//
extension MetadataProvider {
    // Convert nsMetataItems to a MetadataItem array.
    // Filter out directory items and items that don't have a valid item URL.
    // Note that querying the .isDirectoryKey key from a file results in failure.
    //
    private func metadataItemList(from nsMetataItems: [NSMetadataItem]) -> [MetadataItem] {
        let validItems = nsMetataItems.filter { item in
            guard let fileURL = item.value(forAttribute: NSMetadataItemURLKey) as? URL,
                  item.value(forAttribute: NSMetadataItemFSNameKey) != nil else { return false }
            
            let resourceKeys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey]
            if let resourceValues = try? (fileURL as NSURL).resourceValues(forKeys: resourceKeys),
                let isDirectory = resourceValues[URLResourceKey.isDirectoryKey] as? Bool, isDirectory,
                let isPackage = resourceValues[URLResourceKey.isPackageKey] as? Bool, !isPackage {
                return false
            }
            return true
        }
        
        // Valid items have a valid item URL and file system name,
        // so unwrap the optionals directly.
        //
        return validItems.sorted {
            let name0 = $0.value(forAttribute: NSMetadataItemFSNameKey) as? String
            let name1 = $1.value(forAttribute: NSMetadataItemFSNameKey) as? String
            return name0! < name1!
        } .map {
            let itemURL = $0.value(forAttribute: NSMetadataItemURLKey) as? URL
            return MetadataItem(nsMetadataItem: $0, url: itemURL!)
        }
    }
    
    // Provide metadataItems directly from the query.
    // To avoid potential conflicts, disable the query update when accessing the results,
    // and enable it after finishing the access.
    //
    func metadataItemList() -> [MetadataItem] {
        var result = [MetadataItem]()
        metadataQuery.disableUpdates()
        if let metadatItems = metadataQuery.results as? [NSMetadataItem] {
            result = metadataItemList(from: metadatItems)
        }
        metadataQuery.enableUpdates()
        return result
    }
}


// MetadataItem is a wrapper of NSMetadataItem.
// When users rename an item, nsMetadataItem is the same, but the URL is different.
// Use url.path to implement Hashable and Equatable because only url.path is visible.
//
struct MetadataItem: Hashable {
    let nsMetadataItem: NSMetadataItem?
    let url: URL
    
    static func == (lhs: MetadataItem, rhs: MetadataItem) -> Bool {
        return lhs.url.path == rhs.url.path
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(url.path)
    }
}
