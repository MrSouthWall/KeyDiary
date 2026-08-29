//
//  SettingsView.swift
//  KeyDiary
//

import SwiftUI

struct KeyDiarySettingsView: View {
    @Bindable var store: KeyDiaryStore
    @Bindable var launchAtLogin: LaunchAtLoginController

    @AppStorage(KeyDiaryTheme.appearanceStorageKey) private var appearanceRawValue = AppAppearance.system.rawValue
    @AppStorage(KeyDiaryTheme.accentColorStorageKey) private var accentColorHex = KeyDiaryTheme.defaultAccentHex
    @AppStorage(KeySoundPreferences.isEnabledStorageKey) private var isKeySoundEnabled = false
    @AppStorage(KeySoundPreferences.styleStorageKey) private var keySoundStyleRawValue = KeySoundPreferences.defaultStyle.rawValue
    @AppStorage(KeySoundPreferences.volumeStorageKey) private var keySoundVolume = KeySoundPreferences.defaultVolume

    @Environment(\.openWindow) private var openWindow

    @State private var isShowingClearConfirmation = false
    @State private var replacementImportURL: URL?
    @State private var isShowingReplaceConfirmation = false

    var body: some View {
        TabView {
            generalSettings
                .tabItem {
                    Label("通用", systemImage: "gearshape")
                }

            OpenSourceProjectsSettingsView()
                .tabItem {
                    Label("开源项目", systemImage: "shippingbox")
                }
        }
        .frame(width: 540, height: 720)
    }

    private var generalSettings: some View {
        Form {
            Section("外观") {
                LabeledContent("显示模式") {
                    Picker("显示模式", selection: $appearanceRawValue) {
                        ForEach(AppAppearance.allCases) { appearance in
                            Label(appearance.title, systemImage: appearance.systemImage)
                                .tag(appearance.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }

                LabeledContent("主题色") {
                    HStack(spacing: 10) {
                        ColorPicker(
                            "主题色",
                            selection: accentColorBinding,
                            supportsOpacity: false
                        )
                        .labelsHidden()

                        Button("恢复默认") {
                            accentColorHex = KeyDiaryTheme.defaultAccentHex
                        }
                        .disabled(accentColorHex == KeyDiaryTheme.defaultAccentHex)
                    }
                }
            }

            Section("启动") {
                Toggle("登录时自动启动", isOn: launchAtLoginBinding)

                if launchAtLogin.requiresApproval {
                    LabeledContent("系统权限") {
                        Button("打开系统设置…") {
                            launchAtLogin.openSystemSettings()
                        }
                    }

                    Text("请在“通用 > 登录项与扩展”中允许“键盘日记”在登录时运行。")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if let errorMessage = launchAtLogin.errorMessage {
                    Text(L10n.format("无法更新登录项：%@", errorMessage))
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }

                Text("应用启动后会驻留在菜单栏，不会自动显示主界面。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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

            Section("按键声音") {
                Toggle("按下按键时播放声音", isOn: $isKeySoundEnabled)

                LabeledContent("音色") {
                    Picker("音色", selection: $keySoundStyleRawValue) {
                        Section("机械键盘") {
                            ForEach(KeySoundStyle.mechanicalStyles) { style in
                                Label(style.title, systemImage: style.systemImage)
                                    .tag(style.rawValue)
                            }
                        }

                        Section("钢琴") {
                            ForEach(KeySoundStyle.pianoStyles) { style in
                                Label(style.title, systemImage: style.systemImage)
                                    .tag(style.rawValue)
                            }
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                .disabled(!isKeySoundEnabled)

                LabeledContent("音量") {
                    HStack(spacing: 10) {
                        Image(systemName: "speaker.fill")
                            .foregroundStyle(.secondary)

                        Slider(value: $keySoundVolume, in: 0.05...1)
                            .frame(width: 185)

                        Text(keySoundVolume, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 38, alignment: .trailing)
                    }
                }
                .disabled(!isKeySoundEnabled)

                HStack(alignment: .firstTextBaseline) {
                    Text(
                        L10n.format(
                            "%@ 自动记录和回放时会播放，导出视频也会包含声音。",
                            selectedKeySoundStyle.detail
                        )
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("试听") {
                        store.previewKeySound(
                            styleRawValue: keySoundStyleRawValue,
                            volume: keySoundVolume
                        )
                    }
                }

                if let usageHint = selectedKeySoundStyle.usageHint {
                    Text(usageHint)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Section("数据") {
                LabeledContent("本机记录") {
                    Text(L10n.format("%@ 条", store.recordCount.formatted()))
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
                    .tint(.red)
                    .disabled(
                        store.recordCount == 0 ||
                        store.isDataTransferInProgress ||
                        store.isPlaybackVideoExportInProgress
                    )
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            store.refreshInputMonitoringStatus()
            launchAtLogin.refresh()
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

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin.isEnabled },
            set: { launchAtLogin.setEnabled($0) }
        )
    }

    private var accentColorBinding: Binding<Color> {
        Binding(
            get: { KeyDiaryTheme.color(for: accentColorHex) },
            set: { accentColorHex = KeyDiaryTheme.hexString(from: $0) }
        )
    }

    private var selectedKeySoundStyle: KeySoundStyle {
        KeySoundStyle(rawValue: keySoundStyleRawValue) ?? KeySoundPreferences.defaultStyle
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
        if !store.hasInputMonitoringPermission { return L10n.text("需要输入监控权限") }
        return store.isRecording ? L10n.text("正在记录") : L10n.text("记录已暂停")
    }

    private var statusColor: Color {
        if !store.hasInputMonitoringPermission { return .orange }
        return store.isRecording ? .green : .secondary
    }
}

#Preview {
    KeyDiarySettingsView(
        store: KeyDiaryStore(),
        launchAtLogin: LaunchAtLoginController()
    )
}
