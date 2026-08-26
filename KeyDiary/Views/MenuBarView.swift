//
//  MenuBarView.swift
//  KeyDiary
//

import AppKit
import SwiftUI

struct MenuBarView: View {
    @Bindable var store: KeyDiaryStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(statusText)

        if store.hasInputMonitoringPermission {
            Button(store.isRecording ? "暂停记录" : "继续记录") {
                store.isRecording ? store.stopRecording() : store.startRecording()
            }
        } else {
            Button("授权输入监控…") {
                store.requestAccessAndStart()
            }
        }

        Divider()

        Text("今日已记录 \(store.pressesToday) 次按键")
            .foregroundStyle(.secondary)

        Text("数据仅保存在本机")
            .foregroundStyle(.secondary)

        Button("打开 Key Diary") {
            openWindow(id: "main")
        }
        .keyboardShortcut("o")

        Divider()

        Button("退出 Key Diary") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private var statusText: String {
        if !store.hasInputMonitoringPermission { return "需要输入监控权限" }
        return store.isRecording ? "正在自动记录" : "记录已暂停"
    }
}
