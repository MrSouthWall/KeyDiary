//
//  L10n.swift
//  KeyDiary
//

import Foundation

enum L10n {
    nonisolated static var usesEnglishInterface: Bool {
        Bundle.main.preferredLocalizations.first?.hasPrefix("en") == true
    }

    nonisolated static func text(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: key, table: nil)
    }

    nonisolated static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(
            format: text(key),
            locale: Locale.current,
            arguments: arguments
        )
    }
}
