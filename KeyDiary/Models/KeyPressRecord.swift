//
//  KeyPressRecord.swift
//  KeyDiary
//

import Foundation

struct KeyPressRecord: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let timestamp: Date
    let keyCode: UInt16
    let key: String
    let applicationName: String
    let bundleIdentifier: String?

    init(
        id: UUID = UUID(),
        timestamp: Date = .now,
        keyCode: UInt16,
        key: String,
        applicationName: String,
        bundleIdentifier: String?
    ) {
        self.id = id
        self.timestamp = timestamp
        self.keyCode = keyCode
        self.key = key
        self.applicationName = applicationName
        self.bundleIdentifier = bundleIdentifier
    }
}
