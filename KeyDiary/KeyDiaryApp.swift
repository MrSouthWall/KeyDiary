//
//  KeyDiaryApp.swift
//  KeyDiary
//
//  Created by MrSouthWall on 2026/8/25.
//

import AppKit
import SwiftUI

@main
struct KeyDiaryApp: App {
    @NSApplicationDelegateAdaptor(KeyDiaryAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Key Diary", id: "main") {
            ContentView(store: appDelegate.store)
        }
        .defaultSize(width: 1_180, height: 760)
        .defaultLaunchBehavior(.presented)
        .commands {
            DataEditorCommands()
        }

        Window("实时悬浮键盘", id: "floating-keyboard") {
            FloatingKeyboardView(store: appDelegate.store)
        }
        .defaultSize(width: 900, height: 430)
        .windowStyle(.plain)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)

        Window("数据编辑", id: "data-editor") {
            DataEditorView(store: appDelegate.store)
        }
        .defaultSize(width: 1_180, height: 720)
        .defaultLaunchBehavior(.suppressed)

        Settings {
            KeyDiarySettingsView(store: appDelegate.store)
        }

        MenuBarExtra {
            MenuBarView(store: appDelegate.store)
        } label: {
            Image(systemName: appDelegate.store.isRecording ? "keyboard.badge.ellipsis" : "keyboard")
        }
        .menuBarExtraStyle(.menu)
    }
}

@MainActor
final class KeyDiaryAppDelegate: NSObject, NSApplicationDelegate {
    let store = KeyDiaryStore()

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        store.resumeAutomaticRecordingIfPossible()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        store.resumeAutomaticRecordingIfPossible()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.prepareForTermination()
    }

    func applicationShouldRestoreApplicationState(_ app: NSApplication) -> Bool {
        false
    }

    func applicationShouldSaveApplicationState(_ app: NSApplication) -> Bool {
        false
    }
}
