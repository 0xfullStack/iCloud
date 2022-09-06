//
//  Document.swift
//  Wallet
//
//  Created by Liu Pengpeng on 2022/6/15.
//

import UIKit
import BIP39

public class Document: UIDocument, Identifiable {
    public var id = UUID()

    public let fileItem: NSMetadataItem?
    
    init(fileURL: URL, fileItem: NSMetadataItem? = nil) {
        self.fileItem = fileItem
        super.init(fileURL: fileURL)
    }
    
    public override func contents(forType typeName: String) throws -> Any {
        return Data()
    }
    
    public override func load(fromContents contents: Any, ofType typeName: String?) throws {
        
    }
    
    public var name: String {
        guard let base64Name = self.fileURL.lastPathComponent.components(separatedBy: "@").last else {
           return "Undefined"
        }
        return base64Name.base64ToUTF8() ?? "?"
    }

    public var creationDate: Date {
        guard let dateString = self.name.components(separatedBy: "-").last else {
            return .distantPast
        }

        let date = Date(timeIntervalSince1970: TimeInterval(dateString) ?? 0)
        return date
    }

    public var namedEntropy: String {
        return fileURL.lastPathComponent
    }

    public var entropy: String {
        guard let base64Name = self.fileURL.lastPathComponent.components(separatedBy: "@").first else {
           return "Undefined"
        }
        return base64Name.base64ToHex() ?? "?"
    }

    public var phrase: [String]? {
        try? Mnemonic(entropy: [UInt8](hex: entropy)).phrase
    }

    public var formatedDateString: String {
        return DateFormatter.short.string(from: self.creationDate)
    }
}

extension Document: Comparable {
    public static func < (lhs: Document, rhs: Document) -> Bool {
        lhs.creationDate.compare(rhs.creationDate) == ComparisonResult.orderedDescending
    }
}

extension DateFormatter {
    static var short: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}

extension String {
    var isValidRecoveryPhrase: Bool {
        Mnemonic.isValid(phrase: self.components(separatedBy: " "))
    }
    
    func base64ToUTF8() -> String? {
        guard let data = Data(base64Encoded: self.replacingOccurrences(of: "-", with: "/")) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
    
    func base64ToHex() -> String? {
        Data(base64Encoded: self.replacingOccurrences(of: "-", with: "/"))?.toHexString()
    }
}

import CryptoSwift
import CryptoTokenKit
extension Data {
    public init(hex: String) {
        self.init(Array<UInt8>(hex: hex))
    }

    public var bytes: Array<UInt8> {
        Array(self)
    }

    public func toHexString() -> String {
        self.bytes.toHexString()
    }
}
