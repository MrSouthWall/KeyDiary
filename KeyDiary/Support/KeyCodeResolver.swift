//
//  KeyCodeResolver.swift
//  KeyDiary
//

import AppKit

enum KeyCodeResolver {
    struct ResolvedKey {
        let keyCode: UInt16
        let label: String
    }

    static func label(for event: NSEvent) -> String {
        if let specialKey = specialKeys[event.keyCode] {
            return specialKey
        }

        let text = event.charactersIgnoringModifiers ?? event.characters ?? ""
        return text.isEmpty ? "Key \(event.keyCode)" : text.uppercased()
    }

    static func modifierFlag(for keyCode: UInt16) -> NSEvent.ModifierFlags? {
        switch keyCode {
        case 54, 55: .command
        case 56, 60: .shift
        case 58, 61: .option
        case 59, 62: .control
        case 63: .function
        default: nil
        }
    }

    static func systemDefinedKey(for event: NSEvent) -> ResolvedKey? {
        guard event.type == .systemDefined else { return nil }

        // NX_SUBTYPE_AUX_CONTROL_BUTTONS. data1 packs the special-key identifier in
        // the high word and the transition state in bits 8...15.
        guard event.subtype.rawValue == 8 else { return nil }
        let data = UInt32(truncatingIfNeeded: event.data1)
        let systemKeyCode = Int((data >> 16) & 0xFFFF)
        let state = Int((data >> 8) & 0xFF)

        // 0xA is key down and 0xC is key repeat. 0xB is key up.
        guard state == 0xA || state == 0xC else { return nil }

        return systemKeyMap[systemKeyCode]
    }

    private static let specialKeys: [UInt16: String] = [
        36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 53: "Esc",
        54: "⌘", 55: "⌘", 56: "⇧", 57: "Caps", 58: "⌥", 59: "⌃",
        60: "⇧", 61: "⌥", 62: "⌃", 63: "fn",
        71: "Clear", 76: "Enter", 79: "End", 80: "F17", 90: "F20",
        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9",
        103: "F11", 105: "F13", 107: "F14", 109: "F10", 111: "F12",
        113: "F15", 114: "Help", 115: "Home", 116: "PgUp", 117: "Delete",
        118: "F4", 119: "End", 120: "F2", 121: "PgDn", 122: "F1",
        123: "←", 124: "→", 125: "↓", 126: "↑"
    ]

    // NX_KEYTYPE_* identifiers are translated to the virtual key codes already used
    // by the keyboard heat-map model.
    private static let systemKeyMap: [Int: ResolvedKey] = [
        0: ResolvedKey(keyCode: 111, label: "F12"), // Volume up
        1: ResolvedKey(keyCode: 103, label: "F11"), // Volume down
        2: ResolvedKey(keyCode: 120, label: "F2"),  // Brightness up
        3: ResolvedKey(keyCode: 122, label: "F1"),  // Brightness down
        7: ResolvedKey(keyCode: 109, label: "F10"), // Mute
        13: ResolvedKey(keyCode: 118, label: "F4"), // Launch panel / Spotlight position
        16: ResolvedKey(keyCode: 100, label: "F8"), // Play / pause
        17: ResolvedKey(keyCode: 101, label: "F9"), // Next
        18: ResolvedKey(keyCode: 98, label: "F7"),  // Previous
        32: ResolvedKey(keyCode: 99, label: "F3"),  // Mission Control
        0x9B: ResolvedKey(keyCode: 97, label: "F6"), // Do Not Disturb
        0xCF: ResolvedKey(keyCode: 96, label: "F5"), // Dictation / voice command
        0x221: ResolvedKey(keyCode: 118, label: "F4") // Spotlight / search
    ]
}
