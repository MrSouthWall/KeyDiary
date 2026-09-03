//
//  MouseClickRecord.swift
//  KeyDiary
//

import Foundation

nonisolated enum MouseButton: Int, Codable, CaseIterable, Hashable, Sendable {
    case left = 0
    case right = 1

    var title: String {
        switch self {
        case .left: L10n.text("左键")
        case .right: L10n.text("右键")
        }
    }
}

nonisolated struct MouseClickRecord: Identifiable, Hashable, Sendable {
    let id: UUID
    let timestamp: Date
    let button: MouseButton
    let applicationName: String
    let bundleIdentifier: String?

    init(
        id: UUID = UUID(),
        timestamp: Date = .now,
        button: MouseButton,
        applicationName: String,
        bundleIdentifier: String?
    ) {
        self.id = id
        self.timestamp = timestamp
        self.button = button
        self.applicationName = applicationName
        self.bundleIdentifier = bundleIdentifier
    }
}

nonisolated struct MouseClickCounts: Equatable, Sendable {
    var left = 0
    var right = 0

    var total: Int { left + right }

    subscript(button: MouseButton) -> Int {
        get {
            switch button {
            case .left: left
            case .right: right
            }
        }
        set {
            switch button {
            case .left: left = newValue
            case .right: right = newValue
            }
        }
    }
}
