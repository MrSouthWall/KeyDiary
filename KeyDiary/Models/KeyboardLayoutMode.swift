//
//  KeyboardLayoutMode.swift
//  KeyDiary
//

import Foundation

enum KeyboardLayoutMode: String, CaseIterable, Identifiable {
    case qwerty
    case alphabetical

    var id: Self { self }

    var title: String {
        switch self {
        case .qwerty: "QWERTY"
        case .alphabetical: "A–Z"
        }
    }

    var accessibilityTitle: String {
        switch self {
        case .qwerty: L10n.text("QWERTY 排列")
        case .alphabetical: L10n.text("字母顺序排列")
        }
    }

    var letterRows: [[Character]] {
        switch self {
        case .qwerty:
            [Array("QWERTYUIOP"), Array("ASDFGHJKL"), Array("ZXCVBNM")]
        case .alphabetical:
            [Array("ABCDEFGHIJ"), Array("KLMNOPQRS"), Array("TUVWXYZ")]
        }
    }
}
