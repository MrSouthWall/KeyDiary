//
//  MenuBarView.swift
//  KeyDiary
//

import AppKit
import SwiftUI

struct MenuBarView: View {
    @Bindable var store: KeyDiaryStore
    let dockVisibility: DockVisibilityController
    @AppStorage(KeySoundPreferences.isEnabledStorageKey) private var isKeySoundEnabled = false
    @AppStorage(KeySoundPreferences.styleStorageKey) private var keySoundStyleRawValue = KeySoundPreferences.defaultStyle.rawValue
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Toggle(isOn: recordingBinding) {
            Label {
                Text(statusText)
            } icon: {
                Image(systemName: "circle.fill")
            }
            .tint(statusColor)
        }
        .disabled(!store.hasInputMonitoringPermission)

        Label {
            Text(L10n.format("今日已按键 %@ 次", store.pressesToday.formatted()))
        } icon: { }
        Label {
            Text(L10n.format("今日已点击 %@ 次", store.clicksToday.formatted()))
        } icon: { }
        Divider()

        Button("打开主界面") {
            showWindow(id: "main")
        }
        .keyboardShortcut("o")

        Button("启用悬浮键盘") {
            showWindow(id: "floating-keyboard")
        }

        Toggle(isOn: $isKeySoundEnabled) {
            Text("按键声音")
        }

        Picker("声色选择", selection: $keySoundStyleRawValue) {
            Section("机械键盘") {
                ForEach(KeySoundStyle.mechanicalStyles) { style in
                    Text(style.title)
                        .tag(style.rawValue)
                }
            }

            Section("钢琴") {
                ForEach(KeySoundStyle.pianoStyles) { style in
                    Text(style.title)
                        .tag(style.rawValue)
                }
            }
        }
        .disabled(!isKeySoundEnabled)

        Button("编辑数据") {
            showWindow(id: "data-editor")
        }

        SettingsLink {
            Text("设置")
        }

        Divider()

        Button("退出") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func showWindow(id: String) {
        dockVisibility.prepareToShowInterface()
        openWindow(id: id)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private var recordingBinding: Binding<Bool> {
        Binding(
            get: { store.isRecording },
            set: { shouldRecord in
                shouldRecord ? store.startRecording() : store.stopRecording()
            }
        )
    }

    private var statusText: String {
        if !store.hasInputMonitoringPermission { return L10n.text("需要输入监控权限") }
        return store.isRecording ? L10n.text("记录中") : L10n.text("记录已暂停")
    }

    private var statusColor: Color {
        store.isRecording ? .green : .red
    }
}
