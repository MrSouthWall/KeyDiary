//
//  ContentView.swift
//  KeyDiary
//
//  Created by MrSouthWall on 2026/8/25.
//

import SwiftUI

struct ContentView: View {
    @Bindable var store: KeyDiaryStore
    @Bindable var videoPlayer: KeyboardVideoPlayer

    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.keyDiaryAccentColor) private var themeColor

    @State private var displayMode: KeyboardDisplayMode = .live
    @State private var isShowingCustomRange = false
    @State private var lastLiveKeySummary: String?

    var body: some View {
        ZStack {
            stageBackground

            KeyboardStage(
                activeKeyDescription: activeKeyDescription,
                activeKeyCodes: activeKeyCodes,
                displayMode: displayMode,
                isPlaying: stageIsPlaying,
                keyCounts: displayMode == .statistics ? store.filteredKeyCounts : [:],
                alignsToTop: false,
                pixelFrame: displayMode == .cinema ? videoPlayer.pixelFrame : nil
            )
            .transaction(value: displayMode) { transaction in
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
            .padding(.horizontal, 34)
            .padding(.top, 72)
            .padding(.bottom, stageBottomPadding)
            .animation(modeTransitionAnimation, value: stageBottomPadding)

            VStack(spacing: 0) {
                KeyDiaryStatusBar(
                    store: store,
                    videoPlayer: videoPlayer,
                    selection: $displayMode,
                    showCustomRange: { isShowingCustomRange = true },
                    openFloatingKeyboard: openFloatingKeyboard,
                    openVideoPreview: openVideoPreview
                )

                Spacer()

                if displayMode == .playback {
                    PlaybackRangeTimeline(store: store)
                        .frame(maxWidth: .infinity)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if displayMode == .cinema {
                    KeyboardCinemaTimeline(player: videoPlayer)
                        .frame(maxWidth: .infinity)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if displayMode != .playback, displayMode != .cinema {
                    HStack {
                        ModeStatusView(
                            title: modeStatusTitle,
                            detail: modeStatusDetail,
                            systemImage: modeStatusIcon,
                            tint: modeAccentColor
                        )
                        Spacer()
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(18)
            .animation(modeTransitionAnimation, value: displayMode)
        }
        .frame(minWidth: 920, minHeight: 600)
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .onChange(of: displayMode) { _, newMode in
            if newMode != .playback {
                store.stopPlayback()
            }
            if newMode == .cinema {
                videoPlayer.loadBundledBadAppleIfNeeded()
                openVideoPreview()
            } else {
                videoPlayer.pause()
                dismissWindow(id: "video-preview")
            }
        }
        .onChange(of: store.activeLiveKeySummary) { _, keySummary in
            if let keySummary {
                lastLiveKeySummary = keySummary
            }
        }
        .sheet(isPresented: $isShowingCustomRange) {
            DateRangeSheet(
                initialFrom: store.fromDate,
                initialTo: store.toDate
            ) { fromDate, toDate in
                store.selectCustomRange(from: fromDate, to: toDate)
            }
        }
        .alert(item: $store.dataTransferNotice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("好"))
            )
        }
        .alert(item: $videoPlayer.exportNotice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("好"))
            )
        }
    }

    private func openFloatingKeyboard() {
        dismissWindow(id: "video-preview")
        openWindow(id: "floating-keyboard")
        dismissWindow(id: "main")
    }

    private func openVideoPreview() {
        openWindow(id: "video-preview")
    }

    private var stageBackground: some View {
        ZStack {
            Rectangle()
                .fill(.background)

            RadialGradient(
                colors: [themeColor.opacity(0.1), .clear],
                center: .center,
                startRadius: 40,
                endRadius: 520
            )

            LinearGradient(
                colors: [themeColor.opacity(0.05), .clear, themeColor.opacity(0.025)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }

    private var modeStatusTitle: String {
        switch displayMode {
        case .live:
            if !store.hasInputMonitoringPermission { return "等待输入监控授权" }
            return store.isRecording ? "正在实时记录" : "实时记录已暂停"
        case .statistics:
            return store.filteredRecordCount == 0 ? "暂无统计数据" : "统计已更新"
        case .playback:
            if store.isPlaying { return "正在回放" }
            return store.playbackRecordCount == 0 ? "所选区间没有可回放记录" : "回放已就绪"
        case .cinema:
            return videoPlayer.isPlaying ? "键帽像素正在播放" : "键帽像素已暂停"
        }
    }

    private var modeStatusDetail: String {
        switch displayMode {
        case .live:
            if !store.hasInputMonitoringPermission { return "请在设置中完成授权" }
            if !store.isRecording { return "可在设置中继续记录" }
            return "最近按键 · \(lastLiveKeySummary ?? "等待输入")"
        case .statistics:
            if store.filteredRecordCount == 0 { return "请调整时间或 App 筛选" }
            return "当前筛选 · \(store.filteredRecordCount.formatted()) 次按键"
        case .playback:
            if store.isPlaying { return "当前按键 · \(store.activePlaybackKey ?? "准备中")" }
            if store.playbackRecordCount == 0 { return "请调整时间轴的起止位置" }
            return "所选 \(store.playbackRecordCount.formatted()) 条记录 · 预计 \(store.estimatedPlaybackDurationTitle)"
        case .cinema:
            return videoPlayer.videoTitle ?? "选择一个视频"
        }
    }

    private var modeStatusIcon: String {
        switch displayMode {
        case .live: "bolt.fill"
        case .statistics: "chart.bar.fill"
        case .playback: store.isPlaying ? "waveform" : "play.fill"
        case .cinema: videoPlayer.isPlaying ? "film.fill" : "film"
        }
    }

    private var modeAccentColor: Color {
        themeColor
    }

    private var activeKeyDescription: String? {
        switch displayMode {
        case .live: store.activeLiveKeySummary
        case .statistics: nil
        case .playback: store.activePlaybackKey
        case .cinema: nil
        }
    }

    private var activeKeyCodes: Set<UInt16> {
        switch displayMode {
        case .live: store.activeLiveKeyCodes
        case .statistics: []
        case .playback:
            store.activePlaybackKeyCode.map { Set([$0]) } ?? []
        case .cinema: []
        }
    }

    private var stageBottomPadding: CGFloat {
        switch displayMode {
        case .playback: 200
        case .cinema: 150
        case .live, .statistics: 60
        }
    }

    private var stageIsPlaying: Bool {
        displayMode == .cinema ? videoPlayer.isPlaying : store.isPlaying
    }

    private var modeTransitionAnimation: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.16)
    }
}

private struct ModeStatusView: View {
    let title: String
    let detail: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .contentTransition(.numericText())
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    ContentView(store: KeyDiaryStore(), videoPlayer: KeyboardVideoPlayer())
}
