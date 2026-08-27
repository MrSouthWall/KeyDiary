//
//  SettingsView.swift
//  KeyDiary
//

import SwiftUI

struct KeyDiarySettingsView: View {
    @Bindable var store: KeyDiaryStore

    @Environment(\.openWindow) private var openWindow

    @State private var isShowingClearConfirmation = false
    @State private var replacementImportURL: URL?
    @State private var isShowingReplaceConfirmation = false

    var body: some View {
        Form {
            Section("记录") {
                LabeledContent("状态") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 7, height: 7)

                        Text(statusTitle)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle("自动记录按键", isOn: recordingBinding)
                    .disabled(!store.hasInputMonitoringPermission)

                if !store.hasInputMonitoringPermission {
                    LabeledContent("输入监控权限") {
                        HStack(spacing: 8) {
                            Button("重新检测") {
                                store.refreshInputMonitoringStatus()
                            }

                            Button("前往授权…") {
                                store.requestAccessAndStart()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }

            Section("数据") {
                LabeledContent("本机记录") {
                    Text("\(store.recordCount.formatted()) 条")
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }

                LabeledContent("存储方式") {
                    Text("本机 SQLite 数据库")
                        .foregroundStyle(.secondary)
                }

                LabeledContent("管理记录") {
                    Button("打开数据编辑…") {
                        openWindow(id: "data-editor")
                    }
                }

                LabeledContent("导入与导出") {
                    HStack(spacing: 8) {
                        importMenu
                        exportMenu

                        if store.isDataTransferInProgress {
                            ProgressView()
                                .controlSize(.small)
                                .padding(.leading, 2)
                        }
                    }
                }

                Text("导出的文件包含按键与应用信息，请妥善保管。JSON、CSV 和 Excel 均可再次导入。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Text("清空后无法恢复。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("清除全部记录…", role: .destructive) {
                        isShowingClearConfirmation = true
                    }
                    .disabled(
                        store.recordCount == 0 ||
                        store.isDataTransferInProgress ||
                        store.isPlaybackVideoExportInProgress
                    )
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 420)
        .onAppear {
            store.refreshInputMonitoringStatus()
        }
        .confirmationDialog(
            "清除全部记录？",
            isPresented: $isShowingClearConfirmation
        ) {
            Button("清除全部记录", role: .destructive) {
                store.clearAllRecords()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作无法撤销，保存在这台 Mac 上的按键记录将被永久删除。")
        }
        .confirmationDialog(
            "替换全部本机记录？",
            isPresented: $isShowingReplaceConfirmation
        ) {
            Button("替换并导入", role: .destructive) {
                guard let replacementImportURL else { return }
                store.importData(from: replacementImportURL, mode: .replace)
                self.replacementImportURL = nil
            }
            Button("取消", role: .cancel) {
                replacementImportURL = nil
            }
        } message: {
            Text("现有记录将被所选文件中的记录替换。应用会先创建 JSON 备份；如果导入失败，数据库不会发生变化。")
        }
        .alert(item: $store.dataTransferNotice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("好"))
            )
        }
    }

    private var recordingBinding: Binding<Bool> {
        Binding(
            get: { store.isRecording },
            set: { shouldRecord in
                shouldRecord ? store.startRecording() : store.stopRecording()
            }
        )
    }

    private var importMenu: some View {
        Menu("导入…") {
            Button("合并导入…") {
                guard let url = DataFilePanels.chooseImportFile() else { return }
                store.importData(from: url, mode: .merge)
            }

            Divider()

            Button("替换全部记录…", role: .destructive) {
                guard let url = DataFilePanels.chooseImportFile() else { return }
                replacementImportURL = url
                isShowingReplaceConfirmation = true
            }
        }
        .disabled(store.isDataTransferInProgress || store.isPlaybackVideoExportInProgress)
    }

    private var exportMenu: some View {
        Menu("导出…") {
            ForEach(DataTransferFormat.allCases) { format in
                Button(format.title) {
                    guard let url = DataFilePanels.chooseExportFile(format: format) else { return }
                    store.exportData(format: format, to: url)
                }
            }
        }
        .disabled(
            store.recordCount == 0 ||
            store.isDataTransferInProgress ||
            store.isPlaybackVideoExportInProgress
        )
    }

    private var statusTitle: String {
        if !store.hasInputMonitoringPermission { return "需要输入监控权限" }
        return store.isRecording ? "正在记录" : "记录已暂停"
    }

    private var statusColor: Color {
        if !store.hasInputMonitoringPermission { return .orange }
        return store.isRecording ? .green : .secondary
    }
}

#Preview {
    KeyDiarySettingsView(store: KeyDiaryStore())
}
