//
//  PlaybackRangeTimeline.swift
//  KeyDiary
//

import SwiftUI

struct PlaybackRangeTimeline: View {
    @Bindable var store: KeyDiaryStore

    @Environment(\.keyDiaryAccentColor) private var themeColor

    @State private var transientStartFraction: Double?
    @State private var transientEndFraction: Double?
    @State private var activeDragTarget: PlaybackRangeDragTarget?
    @State private var hoveredDragTarget: PlaybackRangeDragTarget?
    @State private var rangeDragOrigin: PlaybackRangeDragOrigin?

    private let trackInset: CGFloat = 19
    private let minimumRangeFraction = 0.002

    var body: some View {
        VStack(spacing: 10) {
            header
            rangeLabels
            rangeTrack
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.separator.opacity(0.72), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 9, y: 4)
        .disabled(store.filteredRecordCount == 0 || store.isPlaybackVideoExportInProgress)
        .opacity(store.filteredRecordCount == 0 ? 0.62 : 1)
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Label("回放片段", systemImage: "timeline.selection")
                .font(.caption.weight(.semibold))
                .foregroundStyle(themeColor)

            Text(
                L10n.format(
                    "%@ 次按键 · 回放约 %@",
                    store.playbackRecordCount.formatted(),
                    store.estimatedPlaybackDurationTitle
                )
            )
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())

            Spacer(minLength: 8)

            Button {
                transientStartFraction = nil
                transientEndFraction = nil
                store.resetPlaybackRange()
            } label: {
                Label("恢复全部", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.plain)
            .font(.caption.weight(.medium))
            .foregroundStyle(store.isFullPlaybackRangeSelected ? Color.secondary : themeColor)
            .disabled(store.isFullPlaybackRangeSelected)
            .help("恢复完整回放区间")
        }
    }

    private var rangeLabels: some View {
        HStack(spacing: 12) {
            rangeLabel(
                title: "开始",
                date: store.playbackDate(at: displayedStartFraction),
                alignment: .leading
            )

            Spacer(minLength: 8)

            VStack(spacing: 2) {
                Text("已选区间")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)
                Text(selectedRangeDurationTitle)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(themeColor)
                    .contentTransition(.numericText())
            }

            Spacer(minLength: 8)

            rangeLabel(
                title: "结束",
                date: store.playbackDate(at: displayedEndFraction),
                alignment: .trailing
            )
        }
    }

    private func rangeLabel(title: String, date: Date?, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 1) {
            Text(L10n.text(title))
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
            Text(date.map(playbackDateTitle) ?? "--")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private var rangeTrack: some View {
        GeometryReader { proxy in
            let trackWidth = max(proxy.size.width - trackInset * 2, 1)
            let startX = trackInset + trackWidth * displayedStartFraction
            let endX = trackInset + trackWidth * displayedEndFraction
            let selectionWidth = max(endX - startX, 2)
            let tickLabelWidth = min(max(trackWidth / 5, 64), 112)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: trackWidth, height: 10)
                    .overlay {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(Color.primary.opacity(0.14), lineWidth: 1)
                    }
                    .offset(x: trackInset, y: 13)
                    .allowsHitTesting(false)

                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(themeColor.gradient)
                    .frame(width: selectionWidth, height: 10)
                    .offset(x: startX, y: 13)
                    .allowsHitTesting(false)

                if !store.isFullPlaybackRangeSelected {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(themeColor.opacity(
                            activeDragTarget == .selection ? 0.13 : 0.001
                        ))
                        .frame(width: selectionWidth, height: 30)
                        .offset(x: startX, y: 3)
                        .allowsHitTesting(false)

                    if selectionWidth > 82 {
                        Image(systemName: "arrow.left.and.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white.opacity(
                                activeDragTarget == .selection ? 0.95 : 0.72
                            ))
                            .position(x: (startX + endX) / 2, y: 18)
                            .allowsHitTesting(false)
                    }
                }

                ForEach(Array(timelineTickFractions.enumerated()), id: \.offset) { index, fraction in
                    let tickX = trackInset + trackWidth * fraction
                    let isEndpoint = index == 0 || index == timelineTickFractions.count - 1
                    let labelX = tickLabelCenterX(
                        index: index,
                        tickX: tickX,
                        trackWidth: trackWidth,
                        labelWidth: tickLabelWidth
                    )

                    Rectangle()
                        .fill(Color.secondary.opacity(isEndpoint ? 0.62 : 0.42))
                        .frame(width: 1, height: isEndpoint ? 8 : 6)
                        .position(x: tickX, y: isEndpoint ? 28 : 27)
                        .allowsHitTesting(false)

                    Text(timelineTickTitle(at: fraction))
                        .frame(width: tickLabelWidth, alignment: tickLabelAlignment(at: index))
                        .position(x: labelX, y: 45)
                        .foregroundStyle(isEndpoint ? .secondary : .tertiary)
                        .allowsHitTesting(false)
                }

                Color.clear
                    .frame(width: trackWidth, height: 30)
                    .offset(x: trackInset, y: 3)
                    .contentShape(Rectangle())
                    .gesture(trackInteractionGesture(trackWidth: trackWidth))
                    .help("拖动橙色选区可整体平移；点击其他位置可移动最近的时间端点")

                rangeHandle(title: "起始时间", isStart: true, trackWidth: trackWidth)
                    .position(x: startX, y: 18)
                    .zIndex(2)

                rangeHandle(title: "结束时间", isStart: false, trackWidth: trackWidth)
                    .position(x: endX, y: 18)
                    .zIndex(2)

            }
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(.tertiary)
            .coordinateSpace(name: "playback-range-track")
        }
        .frame(height: 60)
    }

    private func rangeHandle(title: String, isStart: Bool, trackWidth: CGFloat) -> some View {
        let target: PlaybackRangeDragTarget = isStart ? .start : .end

        return PlaybackRangeHandle(
            isActive: activeDragTarget == target,
            isHovered: hoveredDragTarget == target
        )
            .accessibilityLabel(L10n.text(title))
            .accessibilityValue(playbackDateTitle(store.playbackDate(
                at: isStart ? displayedStartFraction : displayedEndFraction
            )))
            .accessibilityAdjustableAction { direction in
                let step = direction == .increment ? 0.01 : -0.01
                if isStart {
                    commit(start: min(displayedStartFraction + step, displayedEndFraction - minimumRangeFraction),
                           end: displayedEndFraction)
                } else {
                    commit(start: displayedStartFraction,
                           end: max(displayedEndFraction + step, displayedStartFraction + minimumRangeFraction))
                }
            }
            .onHover { isHovered in
                hoveredDragTarget = isHovered ? target : nil
            }
            .help(
                L10n.format(
                    "拖动调整%@时间",
                    isStart ? L10n.text("开始") : L10n.text("结束")
                )
            )
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("playback-range-track"))
                    .onChanged { value in
                        activeDragTarget = target
                        let fraction = min(max((value.location.x - trackInset) / trackWidth, 0), 1)
                        if isStart {
                            transientStartFraction = min(fraction, displayedEndFraction - minimumRangeFraction)
                        } else {
                            transientEndFraction = max(fraction, displayedStartFraction + minimumRangeFraction)
                        }
                    }
                    .onEnded { _ in
                        commit(start: displayedStartFraction, end: displayedEndFraction)
                        activeDragTarget = nil
                    }
            )
    }

    private func trackInteractionGesture(trackWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("playback-range-track"))
            .onChanged { value in
                let fraction = fraction(at: value.location.x, trackWidth: trackWidth)
                let target = activeDragTarget ?? interactionTarget(at: fraction)
                activeDragTarget = target

                switch target {
                case .start:
                    transientStartFraction = min(fraction, displayedEndFraction - minimumRangeFraction)
                case .end:
                    transientEndFraction = max(fraction, displayedStartFraction + minimumRangeFraction)
                case .selection:
                    let origin = rangeDragOrigin ?? PlaybackRangeDragOrigin(
                        start: displayedStartFraction,
                        end: displayedEndFraction
                    )
                    if rangeDragOrigin == nil {
                        rangeDragOrigin = origin
                    }

                    let proposedDelta = value.translation.width / trackWidth
                    let delta = min(max(proposedDelta, -origin.start), 1 - origin.end)
                    transientStartFraction = origin.start + delta
                    transientEndFraction = origin.end + delta
                }
            }
            .onEnded { _ in
                commit(start: displayedStartFraction, end: displayedEndFraction)
                rangeDragOrigin = nil
                activeDragTarget = nil
            }
    }

    private func interactionTarget(at fraction: Double) -> PlaybackRangeDragTarget {
        if !store.isFullPlaybackRangeSelected,
           fraction > displayedStartFraction,
           fraction < displayedEndFraction {
            return .selection
        }
        return nearestHandle(to: fraction)
    }

    private func nearestHandle(to fraction: Double) -> PlaybackRangeDragTarget {
        abs(fraction - displayedStartFraction) <= abs(fraction - displayedEndFraction)
            ? .start
            : .end
    }

    private func fraction(at x: CGFloat, trackWidth: CGFloat) -> Double {
        min(max((x - trackInset) / trackWidth, 0), 1)
    }

    private var displayedStartFraction: Double {
        min(max(transientStartFraction ?? store.playbackSelectionStartFraction, 0), 1)
    }

    private var displayedEndFraction: Double {
        min(max(transientEndFraction ?? store.playbackSelectionEndFraction, 0), 1)
    }

    private func commit(start: Double, end: Double) {
        let lower = min(max(start, 0), 1)
        let upper = min(max(end, lower + minimumRangeFraction), 1)
        transientStartFraction = nil
        transientEndFraction = nil
        store.setPlaybackRange(startFraction: lower, endFraction: upper)
    }

    private var selectedRangeDurationTitle: String {
        guard let start = store.playbackDate(at: displayedStartFraction),
              let end = store.playbackDate(at: displayedEndFraction) else {
            return "--"
        }
        return durationTitle(end.timeIntervalSince(start))
    }

    private func durationTitle(_ duration: TimeInterval) -> String {
        let seconds = max(Int(duration.rounded()), 0)
        if seconds < 60 { return L10n.format("%lld 秒", Int64(seconds)) }

        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        if minutes < 60 {
            return remainingSeconds == 0
                ? L10n.format("%lld 分钟", Int64(minutes))
                : L10n.format("%lld 分 %lld 秒", Int64(minutes), Int64(remainingSeconds))
        }

        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if hours < 24 {
            return remainingMinutes == 0
                ? L10n.format("%lld 小时", Int64(hours))
                : L10n.format("%lld 小时 %lld 分", Int64(hours), Int64(remainingMinutes))
        }

        let days = hours / 24
        let remainingHours = hours % 24
        return remainingHours == 0
            ? L10n.format("%lld 天", Int64(days))
            : L10n.format("%lld 天 %lld 小时", Int64(days), Int64(remainingHours))
    }

    private var timelineTickFractions: [Double] {
        guard let start = store.playbackTimelineStart,
              let end = store.playbackTimelineEnd else {
            return []
        }
        guard end > start else { return [0.5] }
        return [0, 0.25, 0.5, 0.75, 1]
    }

    private func tickLabelCenterX(
        index: Int,
        tickX: CGFloat,
        trackWidth: CGFloat,
        labelWidth: CGFloat
    ) -> CGFloat {
        guard timelineTickFractions.count > 1 else {
            return trackInset + trackWidth / 2
        }
        if index == 0 { return trackInset + labelWidth / 2 }
        if index == timelineTickFractions.count - 1 {
            return trackInset + trackWidth - labelWidth / 2
        }
        return tickX
    }

    private func tickLabelAlignment(at index: Int) -> Alignment {
        guard timelineTickFractions.count > 1 else { return .center }
        if index == 0 { return .leading }
        if index == timelineTickFractions.count - 1 { return .trailing }
        return .center
    }

    private func timelineTickTitle(at fraction: Double) -> String {
        guard let date = store.playbackDate(at: fraction),
              let start = store.playbackTimelineStart,
              let end = store.playbackTimelineEnd else {
            return "--"
        }

        let duration = end.timeIntervalSince(start)
        if duration <= 10 * 60 {
            return date.formatted(.dateTime.hour().minute().second())
        }
        if Calendar.current.isDate(start, inSameDayAs: end) {
            return date.formatted(.dateTime.hour().minute())
        }
        if duration <= 7 * 24 * 60 * 60 {
            return date.formatted(.dateTime.month().day().hour().minute())
        }
        return date.formatted(.dateTime.month().day())
    }

    private func playbackDateTitle(_ date: Date?) -> String {
        guard let date else { return "--" }
        guard let start = store.playbackTimelineStart, let end = store.playbackTimelineEnd else {
            return date.formatted(.dateTime.hour().minute().second())
        }
        if Calendar.current.isDate(start, inSameDayAs: end) {
            return date.formatted(.dateTime.hour().minute().second())
        }
        return date.formatted(.dateTime.month().day().hour().minute())
    }
}

private enum PlaybackRangeDragTarget: Equatable {
    case start
    case end
    case selection
}

private struct PlaybackRangeDragOrigin {
    let start: Double
    let end: Double
}

private struct PlaybackRangeHandle: View {
    let isActive: Bool
    let isHovered: Bool
    @Environment(\.keyDiaryAccentColor) private var themeColor

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(.regularMaterial)
                .frame(width: isActive ? 18 : 16, height: isActive ? 36 : 34)
                .overlay {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(
                            themeColor.opacity(isActive || isHovered ? 1 : 0.82),
                            lineWidth: isActive ? 2 : 1
                        )
                }
                .shadow(
                    color: .black.opacity(isActive ? 0.18 : 0.1),
                    radius: isActive ? 4 : 2,
                    y: 1
                )

            Capsule()
                .fill(themeColor)
                .frame(width: 3, height: 18)
        }
        .frame(width: 38, height: 46)
        .contentShape(Rectangle())
        .scaleEffect(isHovered && !isActive ? 1.04 : 1)
        .animation(.easeOut(duration: 0.12), value: isActive)
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}
