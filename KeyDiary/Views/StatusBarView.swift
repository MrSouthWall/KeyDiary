//
//  StatusBarView.swift
//  KeyDiary
//

import SwiftUI

struct KeyDiaryStatusBar: View {
    @Bindable var store: KeyDiaryStore
    @Bindable var videoPlayer: KeyboardVideoPlayer
    @Binding var selection: KeyboardDisplayMode
    @Binding var keyboardLayout: KeyboardLayoutMode
    @AppStorage(KeySoundPreferences.isEnabledStorageKey) private var isKeySoundEnabled = false
    @State private var isVideoFormatPresented = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.keyDiaryAccentColor) private var themeColor

    let showCustomRange: () -> Void
    let openFloatingKeyboard: () -> Void
    let openVideoPreview: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            DisplayModeTabs(selection: $selection)

            Spacer(minLength: 8)

            if selection == .live {
                floatingKeyboardButton
            } else if selection == .cinema {
                cinemaVideoButton

                barDivider
                cinemaPlaybackButton
                barDivider
                cinemaPreviewButton
                barDivider
                cinemaColorModeButton
                barDivider
                cinemaFramingMenu
                barDivider
                cinemaInvertButton
                barDivider
                cinemaLoopButton
                barDivider
                cinemaExportButton
            } else {
                DateRangeMenu(
                    store: store,
                    tint: optionTint,
                    showCustomRange: showCustomRange
                )
                .disabled(store.isPlaybackVideoExportInProgress)
                barDivider
                ApplicationMenu(store: store, tint: optionTint)
                    .disabled(store.isPlaybackVideoExportInProgress)

                if selection == .statistics {
                    barDivider
                    KeyboardLayoutPicker(selection: $keyboardLayout, tint: optionTint)
                }

                if selection == .playback {
                    barDivider
                    PlaybackDurationMenu(store: store, tint: optionTint)
                        .disabled(store.isPlaybackVideoExportInProgress)
                    barDivider
                    playbackSoundButton
                    barDivider
                    playbackButton
                    barDivider
                    playbackVideoButton
                }
            }

        }
        .padding(.horizontal, 10)
        .frame(height: 52)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.separator.opacity(0.72), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.1), radius: 11, y: 5)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: selection)
    }

    private var optionTint: Color {
        themeColor
    }

    private var floatingKeyboardButton: some View {
        Button(action: openFloatingKeyboard) {
            Label("悬浮键盘", systemImage: "rectangle.on.rectangle.angled")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.green)
                .lineLimit(1)
                .padding(.horizontal, 9)
                .frame(height: 52)
        }
        .buttonStyle(.plain)
        .help("打开实时悬浮键盘并关闭主窗口")
        .accessibilityLabel("打开实时悬浮键盘并关闭主窗口")
    }

    private var playbackButton: some View {
        Button {
            store.isPlaying ? store.stopPlayback() : store.playFilteredRecords()
        } label: {
            Label(
                store.isPlaying ? L10n.text("停止") : L10n.text("播放"),
                systemImage: store.isPlaying ? "stop.fill" : "play.fill"
            )
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(themeColor)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .frame(height: 52)
            .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .disabled(
            (store.playbackRecordCount == 0 && !store.isPlaying) ||
            store.isPlaybackVideoExportInProgress
        )
        .help(store.isPlaying ? L10n.text("停止回放") : L10n.text("回放时间轴选中区间"))
    }

    private var playbackSoundButton: some View {
        Button {
            isKeySoundEnabled.toggle()
            if !isKeySoundEnabled {
                store.stopPlaybackSounds()
            }
        } label: {
            Label(
                "声音",
                systemImage: isKeySoundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill"
            )
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(isKeySoundEnabled ? themeColor : Color.secondary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(height: 52)
            .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .disabled(store.isPlaybackVideoExportInProgress)
        .help(
            isKeySoundEnabled
                ? L10n.text("关闭回放和视频按键声音")
                : L10n.text("启用回放和视频按键声音")
        )
        .accessibilityLabel("回放声音")
        .accessibilityValue(isKeySoundEnabled ? L10n.text("已启用") : L10n.text("已关闭"))
        .accessibilityAddTraits(isKeySoundEnabled ? .isSelected : [])
    }

    private var cinemaVideoButton: some View {
        Button {
            guard let url = DataFilePanels.chooseKeyboardCinemaVideo() else { return }
            videoPlayer.loadVideo(from: url)
        } label: {
            Label("选择视频", systemImage: "folder.badge.plus")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(themeColor)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .frame(height: 52)
        }
        .buttonStyle(.plain)
        .disabled(videoPlayer.isLoading || videoPlayer.isVideoExportInProgress)
        .help("选择其他视频并用键帽播放")
    }

    private var cinemaPlaybackButton: some View {
        Button {
            videoPlayer.togglePlayback()
        } label: {
            Label(
                videoPlayer.isPlaying ? L10n.text("暂停") : L10n.text("播放"),
                systemImage: videoPlayer.isPlaying ? "pause.fill" : "play.fill"
            )
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(themeColor)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(height: 52)
            .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .disabled(
            !videoPlayer.hasVideo ||
            videoPlayer.isLoading ||
            videoPlayer.isVideoExportInProgress
        )
        .keyboardShortcut(.space, modifiers: [])
        .help(
            videoPlayer.isPlaying ? L10n.text("暂停像素视频") : L10n.text("继续播放像素视频")
        )
    }

    private var cinemaPreviewButton: some View {
        Button(action: openVideoPreview) {
            Label("原片窗", systemImage: "pip")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(themeColor)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(height: 52)
        }
        .buttonStyle(.plain)
        .disabled(!videoPlayer.hasVideo)
        .help("打开与键盘同步的原片对照小窗")
    }

    private var cinemaInvertButton: some View {
        Button {
            videoPlayer.isInverted.toggle()
        } label: {
            Label("反相", systemImage: "circle.righthalf.filled")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(videoPlayer.isInverted ? themeColor : Color.secondary)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .frame(height: 52)
        }
        .buttonStyle(.plain)
        .disabled(videoPlayer.isVideoExportInProgress)
        .help(
            videoPlayer.isInverted ? L10n.text("恢复视频颜色") : L10n.text("反转视频颜色")
        )
        .accessibilityValue(videoPlayer.isInverted ? L10n.text("已开启") : L10n.text("已关闭"))
    }

    private var cinemaColorModeButton: some View {
        Button {
            videoPlayer.colorMode = videoPlayer.colorMode == .color ? .binary : .color
        } label: {
            Label(
                videoPlayer.colorMode.title,
                systemImage: videoPlayer.colorMode == .binary
                    ? "circle.lefthalf.filled"
                    : "paintpalette.fill"
            )
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(themeColor)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(height: 52)
            .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .disabled(!videoPlayer.hasVideo || videoPlayer.isVideoExportInProgress)
        .help(
            videoPlayer.colorMode == .binary
                ? L10n.text("切换到彩色采样")
                : L10n.text("切换到无灰阶的黑白二值采样")
        )
        .accessibilityLabel("键帽颜色模式")
        .accessibilityValue(videoPlayer.colorMode.title)
    }

    private var cinemaFramingMenu: some View {
        Menu {
            ForEach(KeyboardVideoFramingMode.allCases) { mode in
                Button {
                    videoPlayer.framingMode = mode
                } label: {
                    if videoPlayer.framingMode == mode {
                        Label(mode.title, systemImage: "checkmark")
                    } else {
                        Text(mode.title)
                    }
                }
                .help(mode.helpText)
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "aspectratio")
                Text(videoPlayer.framingMode.title)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(themeColor)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(height: 52)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(!videoPlayer.hasVideo || videoPlayer.isVideoExportInProgress)
        .help(L10n.format("取景范围：%@", videoPlayer.framingMode.helpText))
        .accessibilityLabel("取景范围")
        .accessibilityValue(videoPlayer.framingMode.title)
    }

    private var cinemaLoopButton: some View {
        Button {
            videoPlayer.loops.toggle()
        } label: {
            Label("循环", systemImage: "repeat")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(videoPlayer.loops ? themeColor : Color.secondary)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .frame(height: 52)
        }
        .buttonStyle(.plain)
        .disabled(videoPlayer.isVideoExportInProgress)
        .help(videoPlayer.loops ? L10n.text("关闭循环播放") : L10n.text("开启循环播放"))
        .accessibilityValue(videoPlayer.loops ? L10n.text("已开启") : L10n.text("已关闭"))
    }

    @ViewBuilder
    private var cinemaExportButton: some View {
        if videoPlayer.isVideoExportInProgress {
            Button {
                videoPlayer.cancelVideoExport()
            } label: {
                HStack(spacing: 7) {
                    ProgressView(value: videoPlayer.videoExportProgress)
                        .progressViewStyle(.circular)
                        .controlSize(.small)

                    Text(videoPlayer.videoExportProgress, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()

                    Image(systemName: "xmark.circle.fill")
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(themeColor)
                .padding(.horizontal, 8)
                .frame(height: 52)
            }
            .buttonStyle(.plain)
            .help("取消像素视频导出")
        } else {
            Button {
                isVideoFormatPresented.toggle()
            } label: {
                HStack(spacing: 5) {
                    Label("导出", systemImage: "video.fill")
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(themeColor)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .frame(height: 52)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isVideoFormatPresented, arrowEdge: .bottom) {
                PlaybackVideoExportPanel { settings in
                    exportCinemaVideo(settings: settings)
                }
                .frame(width: 360)
            }
            .disabled(!videoPlayer.hasVideo || videoPlayer.isLoading)
            .help("以当前黑白/彩色与取景设置导出键盘像素视频")
        }
    }

    @ViewBuilder
    private var playbackVideoButton: some View {
        if store.isPlaybackVideoExportInProgress {
            Button {
                store.cancelPlaybackVideoExport()
            } label: {
                HStack(spacing: 8) {
                    ProgressView(value: store.playbackVideoExportProgress)
                        .progressViewStyle(.circular)
                        .controlSize(.small)

                    Text(store.playbackVideoExportProgress, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()

                    Image(systemName: "xmark.circle.fill")
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(themeColor)
                .padding(.horizontal, 10)
                .frame(height: 52)
            }
            .buttonStyle(.plain)
            .help("取消视频录制")
        } else {
            Button {
                isVideoFormatPresented.toggle()
            } label: {
                HStack(spacing: 6) {
                    Label("视频", systemImage: "video.fill")
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(themeColor)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .frame(height: 52)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isVideoFormatPresented, arrowEdge: .bottom) {
                PlaybackVideoExportPanel { settings in
                    exportVideo(settings: settings)
                }
                .frame(width: 360)
            }
            .disabled(store.playbackRecordCount == 0 || store.isPlaying)
            .help("将时间轴选中区间录制为回放视频")
        }
    }

    private func exportVideo(settings: PlaybackVideoSettings) {
        isVideoFormatPresented = false
        guard let url = DataFilePanels.choosePlaybackVideoFile(settings: settings) else { return }
        store.exportPlaybackVideo(settings: settings, to: url)
    }

    private func exportCinemaVideo(settings: PlaybackVideoSettings) {
        isVideoFormatPresented = false
        guard let url = DataFilePanels.chooseKeyboardCinemaExportFile(settings: settings) else { return }
        videoPlayer.exportVideo(settings: settings, to: url)
    }

    private var barDivider: some View {
        Rectangle()
            .fill(.separator.opacity(0.65))
            .frame(width: 1, height: 22)
            .padding(.horizontal, 2)
    }
}

private struct KeyboardLayoutPicker: View {
    @Binding var selection: KeyboardLayoutMode
    let tint: Color

    var body: some View {
        HStack(spacing: 2) {
            ForEach(KeyboardLayoutMode.allCases) { layout in
                layoutButton(layout)
            }
        }
        .padding(3)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("统计键盘排列")
        .help("切换键帽排列，对比高频字母是否集中")
    }

    private func layoutButton(_ layout: KeyboardLayoutMode) -> some View {
        let isSelected = selection == layout

        return Button {
            selection = layout
        } label: {
            Text(layout.title)
                .font(.system(size: 12, weight: isSelected ? .semibold : .medium, design: .rounded))
                .foregroundStyle(isSelected ? tint : Color.secondary)
                .frame(minWidth: 48, minHeight: 28)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? tint.opacity(0.12) : .clear)
                        .shadow(color: .black.opacity(isSelected ? 0.08 : 0), radius: 2, y: 1)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(layout.accessibilityTitle)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct DisplayModeTabs: View {
    @Binding var selection: KeyboardDisplayMode
    @Environment(\.keyDiaryAccentColor) private var themeColor

    var body: some View {
        HStack(spacing: 2) {
            ForEach(KeyboardDisplayMode.allCases) { mode in
                tab(mode)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("键盘显示模式")
    }

    private func tab(_ mode: KeyboardDisplayMode) -> some View {
        let isSelected = selection == mode
        let tint = accentColor(for: mode)

        return Button {
            guard selection != mode else { return }
            selection = mode
        } label: {
            HStack(spacing: 6) {
                Image(systemName: mode.systemImage)
                    .font(.system(size: 14, weight: .semibold))

                Text(mode.title)
                    .font(.system(size: 15, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? tint : Color.secondary)
            .padding(.horizontal, 10)
            .frame(height: 52)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(tint)
                    .frame(height: 2)
                    .padding(.horizontal, 10)
                    .opacity(isSelected ? 1 : 0)
            }
        }
        .buttonStyle(.plain)
        .keyboardShortcut(keyEquivalent(for: mode), modifiers: .command)
        .help(
            L10n.format("切换到%@模式（⌘%@）", mode.title, shortcutNumber(for: mode))
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func accentColor(for mode: KeyboardDisplayMode) -> Color {
        themeColor
    }

    private func keyEquivalent(for mode: KeyboardDisplayMode) -> KeyEquivalent {
        KeyEquivalent(Character(shortcutNumber(for: mode)))
    }

    private func shortcutNumber(for mode: KeyboardDisplayMode) -> String {
        switch mode {
        case .live: "1"
        case .statistics: "2"
        case .playback: "3"
        case .cinema: "4"
        }
    }
}

private struct DateRangeMenu: View {
    @Bindable var store: KeyDiaryStore
    let tint: Color
    let showCustomRange: () -> Void
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            StatusBarOptionLabel(
                caption: "时间",
                value: store.selectedDateRangeTitle,
                systemImage: "calendar",
                tint: tint,
                width: 118
            )
        }
        .buttonStyle(StatusBarOptionButtonStyle())
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            selectionPanel
        }
        .fixedSize()
        .help("筛选时间范围")
        .accessibilityLabel(L10n.format("时间筛选，%@", store.selectedDateRangeTitle))
    }

    private var selectionPanel: some View {
        StatusSelectionPanel(title: "选择时间范围", systemImage: "calendar") {
            rangeRow("今天", dayCount: 1)
            rangeRow("最近 7 天", dayCount: 7)
            rangeRow("最近 30 天", dayCount: 30)

            Divider()
                .padding(.vertical, 3)

            StatusSelectionRow(
                title: "全部记录",
                isSelected: store.selectedDateRangeSelection == .all
            ) {
                store.selectAllRecords()
                isPresented = false
            }

            StatusSelectionRow(
                title: "自定义…",
                detail: store.selectedDateRangeSelection == .custom ? store.selectedDateRangeTitle : nil,
                isSelected: store.selectedDateRangeSelection == .custom
            ) {
                isPresented = false
                showCustomRange()
            }
        }
        .frame(width: 218)
    }

    private func rangeRow(_ title: String, dayCount: Int) -> some View {
        StatusSelectionRow(
            title: title,
            isSelected: store.selectedDateRangeSelection == .recentDays(dayCount)
        ) {
            store.selectRecentDays(dayCount)
            isPresented = false
        }
    }
}

private struct ApplicationMenu: View {
    @Bindable var store: KeyDiaryStore
    let tint: Color
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            StatusBarOptionLabel(
                caption: "App",
                value: applicationTitle(store.selectedApplication),
                systemImage: "app.dashed",
                tint: tint,
                width: 132
            )
        }
        .buttonStyle(StatusBarOptionButtonStyle())
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            StatusSelectionPanel(title: "选择 App", systemImage: "app.dashed") {
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(store.applications, id: \.self) { application in
                            StatusSelectionRow(
                                title: applicationTitle(application),
                                isSelected: store.selectedApplication == application
                            ) {
                                store.selectedApplication = application
                                isPresented = false
                            }
                        }
                    }
                }
                .frame(maxHeight: 280)
            }
            .frame(width: 238)
        }
        .fixedSize()
        .help("筛选 App")
        .accessibilityLabel(
            L10n.format("App 筛选，%@", applicationTitle(store.selectedApplication))
        )
    }

    private func applicationTitle(_ application: String) -> String {
        switch application {
        case "All apps": L10n.text("全部 App")
        case "Unknown app": L10n.text("Unknown app")
        default: application
        }
    }
}

private struct PlaybackDurationMenu: View {
    @Bindable var store: KeyDiaryStore
    let tint: Color
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            StatusBarOptionLabel(
                caption: "播放时长",
                value: "\(store.estimatedPlaybackDurationTitle) · \(compactSpeedTitle(store.playbackSpeed))",
                systemImage: "timer",
                tint: tint,
                width: 148
            )
        }
        .buttonStyle(StatusBarOptionButtonStyle())
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            StatusSelectionPanel(title: "回放速度", systemImage: "timer") {
                HStack {
                    Text("预计播放时长")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(store.estimatedPlaybackDurationTitle)
                        .fontWeight(.semibold)
                }
                .font(.system(size: 12))
                .padding(.horizontal, 8)
                .padding(.bottom, 5)

                Divider()
                    .padding(.bottom, 3)

                VStack(spacing: 7) {
                    HStack {
                        Text("自定义速度")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(compactSpeedTitle(store.playbackSpeed))
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    }

                    Slider(
                        value: $store.playbackSpeed,
                        in: PlaybackTiming.speedRange
                    ) {
                        Text("回放速度")
                    } minimumValueLabel: {
                        Text("1×")
                    } maximumValueLabel: {
                        Text("16×")
                    }
                    .controlSize(.small)
                }
                .font(.system(size: 11))
                .padding(.horizontal, 8)
                .padding(.bottom, 5)

                Divider()
                    .padding(.bottom, 3)

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5),
                    spacing: 6
                ) {
                    ForEach(PlaybackTiming.speedPresets, id: \.self) { speed in
                        speedButton(speed)
                    }
                }
                .padding(.horizontal, 2)
            }
            .frame(width: 330)
        }
        .fixedSize()
        .help("预计播放时长；菜单中可调整回放速度")
        .accessibilityLabel(
            L10n.format("播放时长，%@", store.estimatedPlaybackDurationTitle)
        )
    }

    private func speedButton(_ speed: Double) -> some View {
        let isSelected = store.playbackSpeed == speed

        return Button {
            store.playbackSpeed = speed
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .opacity(isSelected ? 1 : 0)

                Text(compactSpeedTitle(speed))
                    .monospacedDigit()
            }
            .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .frame(maxWidth: .infinity, minHeight: 32)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.accentColor.opacity(isSelected ? 0.13 : 0.045))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(
            speed == 1
                ? L10n.text("正常速度")
                : L10n.format("%@ 速度", compactSpeedTitle(speed))
        )
        .accessibilityLabel(
            speed == 1
                ? L10n.text("正常速度")
                : L10n.format("%@ 速度", compactSpeedTitle(speed))
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func compactSpeedTitle(_ speed: Double) -> String {
        String(format: "%g×", speed)
    }
}

private struct StatusBarOptionLabel: View {
    let caption: String
    let value: String
    let systemImage: String
    let tint: Color
    let width: CGFloat

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 1) {
                Text(L10n.text(caption))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }

            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .frame(width: width, height: 52)
        .contentShape(Rectangle())
        .accessibilityLabel(L10n.format("%@，%@", L10n.text(caption), value))
    }
}

private struct StatusBarOptionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.62 : 1)
            .contentShape(Rectangle())
    }
}

struct StatusSelectionPanel<Content: View>: View {
    let title: String
    let systemImage: String
    let content: Content

    init(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(L10n.text(title), systemImage: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.bottom, 6)

            content
        }
        .padding(10)
        .background(.regularMaterial)
    }
}

private struct StatusSelectionRow: View {
    let title: String
    var detail: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .opacity(isSelected ? 1 : 0)
                    .frame(width: 12)

                Text(L10n.text(title))
                    .lineLimit(1)

                Spacer(minLength: 8)

                if let detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.accentColor.opacity(isSelected ? 0.12 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
