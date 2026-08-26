//
//  SecondaryControlsMenu.swift
//  KeyDiary
//

import SwiftUI

struct SecondaryControlsMenu: View {
    @Bindable var store: KeyDiaryStore

    let showCustomRange: () -> Void
    let requestClearRecords: () -> Void

    var body: some View {
        Menu {
            recordingSection

            Divider()

            rangeMenu
            applicationMenu
            speedMenu

            Divider()

            Text("按键记录仅保存在本机，不会上传")

            Button("清除全部记录…", systemImage: "trash", role: .destructive) {
                requestClearRecords()
            }
            .disabled(store.records.isEmpty)
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: 18, height: 18)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("更多选项")
        .accessibilityLabel("更多选项")
    }

    @ViewBuilder
    private var recordingSection: some View {
        if store.hasInputMonitoringPermission {
            Button(
                store.isRecording ? "暂停记录" : "继续记录",
                systemImage: store.isRecording ? "pause.circle" : "record.circle"
            ) {
                store.isRecording ? store.stopRecording() : store.startRecording()
            }
        } else {
            Button("授权输入监控…", systemImage: "lock.open") {
                store.requestAccessAndStart()
            }

            Button("重新检测授权", systemImage: "arrow.clockwise") {
                store.refreshInputMonitoringStatus()
            }
        }
    }

    private var rangeMenu: some View {
        Menu("时间范围", systemImage: "calendar") {
            rangeButton("今天", daysBack: 0)
            rangeButton("最近 7 天", daysBack: 6)
            rangeButton("最近 30 天", daysBack: 29)

            Divider()

            Button("全部记录") {
                store.selectAllRecords()
            }

            Button("自定义…") {
                showCustomRange()
            }
        }
    }

    private var applicationMenu: some View {
        Menu("应用", systemImage: "app.dashed") {
            ForEach(store.applications, id: \.self) { application in
                Button {
                    store.selectedApplication = application
                } label: {
                    if store.selectedApplication == application {
                        Label(applicationTitle(application), systemImage: "checkmark")
                    } else {
                        Text(applicationTitle(application))
                    }
                }
            }
        }
    }

    private var speedMenu: some View {
        Menu("回放速度", systemImage: "gauge.with.dots.needle.50percent") {
            ForEach([0.5, 1.0, 2.0, 4.0], id: \.self) { speed in
                Button {
                    store.playbackSpeed = speed
                } label: {
                    if store.playbackSpeed == speed {
                        Label(speedTitle(speed), systemImage: "checkmark")
                    } else {
                        Text(speedTitle(speed))
                    }
                }
            }
        }
    }

    private func rangeButton(_ title: String, daysBack: Int) -> some View {
        Button(title) {
            store.selectRecentDays(daysBack + 1)
        }
    }

    private func applicationTitle(_ application: String) -> String {
        application == "All apps" ? "所有应用" : application
    }

    private func speedTitle(_ speed: Double) -> String {
        speed == 1 ? "1×" : String(format: "%g×", speed)
    }
}
