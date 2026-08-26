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
