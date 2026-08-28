//
//  PlaybackVideoFrame.swift
//  KeyDiary
//

import SwiftUI

struct PlaybackVideoFrame: View {
    let activeRecord: KeyPressRecord?
    let progress: Double
    let dateRangeTitle: String
    let applicationTitle: String
    let speed: Double
    let usesTransparentBackground: Bool
    @Environment(\.keyDiaryAccentColor) private var themeColor

    var body: some View {
        ZStack {
            if !usesTransparentBackground {
                background
            }

            KeyboardStage(
                activeKeyDescription: activeRecord?.key,
                activeKeyCodes: activeRecord.map { Set([$0.keyCode]) } ?? [],
                displayMode: .playback,
                isPlaying: activeRecord != nil,
                keyCounts: [:],
                alignsToTop: false
            )
            .padding(.horizontal, 72)
            .padding(.top, 128)
            .padding(.bottom, 150)

            VStack(spacing: 0) {
                header
                Spacer()
                footer
            }
            .padding(.horizontal, 68)
            .padding(.vertical, 52)
        }
        .environment(\.colorScheme, .light)
    }

    private var background: some View {
        ZStack {
            Rectangle()
                .fill(.background)

            RadialGradient(
                colors: [themeColor.opacity(0.1), .clear],
                center: .center,
                startRadius: 40,
                endRadius: 850
            )

            LinearGradient(
                colors: [themeColor.opacity(0.05), .clear, themeColor.opacity(0.025)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            HStack(spacing: 14) {
                Image(systemName: "keyboard.badge.ellipsis")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(themeColor)

                VStack(alignment: .leading, spacing: 3) {
                    Text("KEY DIARY")
                        .font(.system(size: 25, weight: .bold, design: .rounded))
                        .tracking(1.8)
                    Text("键盘回放")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text("\(dateRangeTitle)  ·  \(displayApplicationTitle)  ·  \(speedTitle)")
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var footer: some View {
        VStack(spacing: 18) {
            HStack(alignment: .lastTextBaseline) {
                Text(activeRecord.map { "当前按键  \($0.key)" } ?? "回放完成")
                    .font(.system(size: 27, weight: .semibold, design: .rounded))
                    .foregroundStyle(activeRecord == nil ? Color.secondary : themeColor)

                Spacer()

                if let activeRecord {
                    Text(activeRecord.timestamp.formatted(
                        .dateTime.year().month().day().hour().minute().second()
                    ))
                    .font(.system(size: 17, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                }
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.13))
                    Capsule()
                        .fill(themeColor)
                        .frame(width: proxy.size.width * min(max(progress, 0), 1))
                }
            }
            .frame(height: 8)
        }
    }

    private var displayApplicationTitle: String {
        applicationTitle == "All apps" ? "全部 App" : applicationTitle
    }

    private var speedTitle: String {
        String(format: "%g×", speed)
    }
}
