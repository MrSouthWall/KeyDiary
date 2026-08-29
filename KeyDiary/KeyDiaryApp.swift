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
    @AppStorage(KeyDiaryTheme.appearanceStorageKey) private var appearanceRawValue = AppAppearance.system.rawValue
    @AppStorage(KeyDiaryTheme.accentColorStorageKey) private var accentColorHex = KeyDiaryTheme.defaultAccentHex

    var body: some Scene {
        WindowGroup("键盘日记", id: "main") {
            ContentView(store: appDelegate.store, videoPlayer: appDelegate.videoPlayer)
                .background {
                    DockVisibilityBridge(controller: appDelegate.dockVisibility)
                }
                .keyDiaryTheme(appearanceRawValue: appearanceRawValue, accentHex: accentColorHex)
        }
        .defaultSize(width: 1_180, height: 760)
        .defaultLaunchBehavior(.suppressed)
        .commands {
            DataEditorCommands()
        }

        Window("原片对照", id: "video-preview") {
            OriginalVideoPreviewView(player: appDelegate.videoPlayer)
                .keyDiaryTheme(appearanceRawValue: appearanceRawValue, accentHex: accentColorHex)
        }
        .defaultSize(width: 360, height: 320)
        .windowResizability(.contentMinSize)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)

        Window("实时悬浮键盘", id: "floating-keyboard") {
            FloatingKeyboardView(store: appDelegate.store)
                .background {
                    DockVisibilityBridge(controller: appDelegate.dockVisibility)
                }
                .keyDiaryTheme(appearanceRawValue: appearanceRawValue, accentHex: accentColorHex)
        }
        .defaultSize(width: 900, height: 430)
        .windowStyle(.plain)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)

        Window("数据编辑", id: "data-editor") {
            DataEditorView(store: appDelegate.store)
                .background {
                    DockVisibilityBridge(controller: appDelegate.dockVisibility)
                }
                .keyDiaryTheme(appearanceRawValue: appearanceRawValue, accentHex: accentColorHex)
        }
        .defaultSize(width: 1_180, height: 720)
        .defaultLaunchBehavior(.suppressed)

        Settings {
            KeyDiarySettingsView(
                store: appDelegate.store,
                launchAtLogin: appDelegate.launchAtLogin
            )
                .background {
                    DockVisibilityBridge(controller: appDelegate.dockVisibility)
                }
                .keyDiaryTheme(appearanceRawValue: appearanceRawValue, accentHex: accentColorHex)
        }

        MenuBarExtra {
            MenuBarView(
                store: appDelegate.store,
                dockVisibility: appDelegate.dockVisibility
            )
                .keyDiaryTheme(appearanceRawValue: appearanceRawValue, accentHex: accentColorHex)
        } label: {
            Image(systemName: appDelegate.store.isRecording ? "keyboard" : "keyboard")
        }
        .menuBarExtraStyle(.menu)
    }
}

@MainActor
final class KeyDiaryAppDelegate: NSObject, NSApplicationDelegate {
    let store = KeyDiaryStore()
    let videoPlayer = KeyboardVideoPlayer()
    let launchAtLogin = LaunchAtLoginController()
    let dockVisibility = DockVisibilityController()

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        launchAtLogin.registerOnFirstLaunchIfNeeded()
        store.resumeAutomaticRecordingIfPossible()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        launchAtLogin.refresh()
        store.resumeAutomaticRecordingIfPossible()
    }

    func applicationWillTerminate(_ notification: Notification) {
        videoPlayer.cancelVideoExport()
        store.prepareForTermination()
    }

    func applicationShouldRestoreApplicationState(_ app: NSApplication) -> Bool {
        false
    }

    func applicationShouldSaveApplicationState(_ app: NSApplication) -> Bool {
        false
    }
}
