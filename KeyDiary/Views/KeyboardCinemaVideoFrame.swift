//
//  KeyboardCinemaVideoFrame.swift
//  KeyDiary
//

import SwiftUI

struct KeyboardCinemaVideoFrame: View {
    let pixelFrame: KeyboardPixelFrame
    let progress: Double
    let currentTime: TimeInterval
    let duration: TimeInterval
    let videoTitle: String
    let colorMode: KeyboardPixelColorMode
    let framingMode: KeyboardVideoFramingMode
    let isInverted: Bool
    let usesTransparentBackground: Bool

    @Environment(\.keyDiaryAccentColor) private var themeColor

    var body: some View {
        ZStack {
            if !usesTransparentBackground {
                background
            }

            KeyboardStage(
                activeKeyDescription: nil,
                activeKeyCodes: [],
                displayMode: .cinema,
                layoutMode: .qwerty,
                isPlaying: true,
                keyCounts: [:],
                alignsToTop: false,
                pixelFrame: pixelFrame,
                pixelColorMode: colorMode
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
                Image(systemName: "rectangle.grid.3x2.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(themeColor)

                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.text("KEY DIARY"))
                        .font(.system(size: 25, weight: .bold, design: .rounded))
                        .tracking(1.8)
                    Text("键盘像素影院")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(
                L10n.format(
                    "%@  ·  %@取景%@",
                    colorMode.title,
                    framingMode.title,
                    isInverted ? L10n.text("  ·  已反相") : ""
                )
            )
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var footer: some View {
        VStack(spacing: 18) {
            HStack(alignment: .lastTextBaseline) {
                Text(videoTitle)
                    .font(.system(size: 25, weight: .semibold, design: .rounded))
                    .lineLimit(1)

                Spacer()

                Text("\(timeTitle(currentTime)) / \(timeTitle(duration))")
                    .font(.system(size: 17, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
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

    private func timeTitle(_ time: TimeInterval) -> String {
        let totalSeconds = max(Int(time.rounded(.down)), 0)
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}
