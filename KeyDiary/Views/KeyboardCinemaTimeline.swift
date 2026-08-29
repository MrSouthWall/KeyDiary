//
//  KeyboardCinemaTimeline.swift
//  KeyDiary
//

import SwiftUI

struct KeyboardCinemaTimeline: View {
    @Bindable var player: KeyboardVideoPlayer
    @Environment(\.keyDiaryAccentColor) private var themeColor

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "rectangle.grid.3x2.fill")
                    .foregroundStyle(themeColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(player.videoTitle ?? L10n.text("键盘像素影院"))
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text(
                        L10n.format(
                            "84 个%@采样像素 · %@取景 · 保留键帽字符与立体材质",
                            player.colorMode.title,
                            player.framingMode.title
                        )
                    )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if player.isLoading {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在载入")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(player.currentTimeTitle) / \(player.durationTitle)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Slider(
                value: Binding(
                    get: { player.progress },
                    set: { player.seek(to: $0) }
                ),
                in: 0...1
            )
            .tint(themeColor)
            .disabled(!player.hasVideo || player.isLoading)

            if let errorMessage = player.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.separator.opacity(0.72), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.1), radius: 11, y: 5)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("键盘像素影院时间轴")
    }
}
