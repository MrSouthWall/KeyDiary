//
//  ContentView.swift
//  KeyDiary
//
//  Created by MrSouthWall on 2026/8/25.
//

import SwiftUI

struct ContentView: View {
    @Bindable var store: KeyDiaryStore

    @State private var isShowingCustomRange = false
    @State private var isShowingClearConfirmation = false

    var body: some View {
        ZStack {
            stageBackground

            KeyboardStage(
                activeKey: store.activePlaybackKey,
                activeKeyCode: store.activePlaybackKeyCode,
                isPlaying: store.isPlaying,
                keyCounts: store.filteredKeyCounts
            )
            .padding(.horizontal, 34)
            .padding(.top, 84)
            .padding(.bottom, 56)

            VStack(spacing: 0) {
                topBar
                Spacer()
                stageCaption
            }
            .padding(18)
        }
        .frame(minWidth: 920, minHeight: 600)
        .sheet(isPresented: $isShowingCustomRange) {
            DateRangeSheet(
                initialFrom: store.fromDate,
                initialTo: store.toDate
            ) { fromDate, toDate in
                store.selectCustomRange(from: fromDate, to: toDate)
            }
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
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "keyboard.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 30, height: 30)
                    .background(.tint.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 1) {
                    Text("Key Diary")
                        .font(.subheadline.weight(.semibold))
                    recordingStatus
                }
            }

            Spacer()

            if store.pressesToday > 0 {
                Text("今日 \(store.pressesToday.formatted()) 次")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }

            Button {
                store.isPlaying ? store.stopPlayback() : store.playFilteredRecords()
            } label: {
                Image(systemName: store.isPlaying ? "stop.fill" : "play.fill")
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
            .help(store.isPlaying ? "停止回放" : "回放当前范围")
            .disabled(store.filteredRecords.isEmpty && !store.isPlaying)

            SecondaryControlsMenu(
                store: store,
                showCustomRange: { isShowingCustomRange = true },
                requestClearRecords: { isShowingClearConfirmation = true }
            )
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(.separator.opacity(0.45), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.06), radius: 14, y: 6)
    }

    private var recordingStatus: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var stageCaption: some View {
        HStack(spacing: 8) {
            Image(systemName: store.isPlaying ? "waveform" : "move.3d")
            Text(stageCaptionText)
                .contentTransition(.numericText())
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.thinMaterial, in: Capsule())
    }

    private var stageBackground: some View {
        ZStack {
            Rectangle()
                .fill(.background)

            RadialGradient(
                colors: [.orange.opacity(0.1), .clear],
                center: .center,
                startRadius: 40,
                endRadius: 520
            )

            LinearGradient(
                colors: [.blue.opacity(0.035), .clear, .orange.opacity(0.025)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }

    private var statusText: String {
        if !store.hasInputMonitoringPermission { return "需要输入监控权限" }
        return store.isRecording ? "正在记录" : "记录已暂停"
    }

    private var statusColor: Color {
        if !store.hasInputMonitoringPermission { return .orange }
        return store.isRecording ? .green : .secondary
    }

    private var stageCaptionText: String {
        if store.isPlaying {
            return "正在回放 · \(store.activePlaybackKey ?? "准备中")"
        }
        if store.filteredRecords.isEmpty {
            return "当前范围暂无记录 · 拖动可查看角度"
        }
        return "\(store.filteredRecords.count.formatted()) 次按键 · 拖动可查看角度"
    }
}

#Preview {
    ContentView(store: KeyDiaryStore())
}
