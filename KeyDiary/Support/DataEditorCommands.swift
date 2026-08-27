//
//  DataEditorCommands.swift
//  KeyDiary
//

import AppKit
import SwiftUI

struct DataEditorCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .pasteboard) {
            Divider()

            Button("筛选与编辑数据…") {
                openWindow(id: "data-editor")
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
        }
    }
}
