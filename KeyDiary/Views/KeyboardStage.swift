//
//  KeyboardStage.swift
//  KeyDiary
//

import SwiftUI

private struct KeyboardRenderScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

private extension EnvironmentValues {
    var keyboardRenderScale: CGFloat {
        get { self[KeyboardRenderScaleKey.self] }
        set { self[KeyboardRenderScaleKey.self] = newValue }
    }
}

private enum KeyboardMetrics {
    static let deckHeight: CGFloat = 420
    static let deckCornerRadius: CGFloat = 30
    static let deckInset: CGFloat = 12
    static let keyCornerRadius: CGFloat = 7
    static let exteriorKeyCornerRadius = deckCornerRadius - deckInset
    static let keySpacing: CGFloat = 8
    static let rowSpacing: CGFloat = 8
    static let rowCount: CGFloat = 6
    static let keyHeight = (deckHeight - deckInset * 2 - rowSpacing * (rowCount - 1)) / rowCount
    static let keyDepth: CGFloat = 5
    static let pressedKeyDepth: CGFloat = 2
    static let keyShadowRadius: CGFloat = 2
    static let pressedKeyShadowRadius: CGFloat = 7
    static let keyShadowOffset: CGFloat = 3
    static let pressedKeyShadowOffset: CGFloat = 1
    static let pressedKeyOffset: CGFloat = 3
    static let arrowKeySpacing: CGFloat = 3
}

struct KeyboardStage: View {
    let activeKeyDescription: String?
    let activeKeyCodes: Set<UInt16>
    let displayMode: KeyboardDisplayMode
    let isPlaying: Bool
    let keyCounts: [UInt16: Int]
    let alignsToTop: Bool

    @State private var rotation = CGSize(width: -1.5, height: 7)

    private var maximumCount: Int { keyCounts.values.max() ?? 0 }

    var body: some View {
        GeometryReader { proxy in
            let scale = max(0.01, min(proxy.size.width / 1_072, proxy.size.height / 470))
            let modelWidth = 1_048 * scale
            let modelHeight = 438 * scale
            let modelCenterY = alignsToTop ? modelHeight / 2 + 8 : proxy.size.height / 2 + 8

            KeyboardModel(
                activeKeyCodes: activeKeyCodes,
                keyCounts: keyCounts,
                maximumCount: maximumCount
            )
            .environment(\.keyboardRenderScale, scale)
            .frame(width: modelWidth, height: modelHeight)
            .rotation3DEffect(.degrees(rotation.height), axis: (x: 1, y: 0, z: 0), perspective: 0.42)
            .rotation3DEffect(.degrees(rotation.width), axis: (x: 0, y: 1, z: 0), perspective: 0.32)
            .position(x: proxy.size.width / 2, y: modelCenterY)
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 5)
                    .onChanged { value in
                        rotation.width = min(max(-1.5 + value.translation.width / 34, -9), 9)
                        rotation.height = min(max(7 + value.translation.height / 38, 2), 14)
                    }
                    .onEnded { _ in
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) {
                            rotation = CGSize(width: -1.5, height: 7)
                        }
                    }
            )
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityLabel: String {
        switch displayMode {
        case .live: "实时 3D 键盘"
        case .statistics: "3D 键盘统计热力图"
        case .playback: "3D 键盘回放"
        }
    }

    private var accessibilityValue: String {
        switch displayMode {
        case .live:
            activeKeyDescription.map { "当前按键 \($0)" } ?? "等待按键"
        case .statistics:
            "峰值 \(maximumCount) 次"
        case .playback:
            isPlaying ? "正在回放 \(activeKeyDescription ?? "")" : "回放已停止"
        }
    }
}

private struct KeyboardModel: View {
    let activeKeyCodes: Set<UInt16>
    let keyCounts: [UInt16: Int]
    let maximumCount: Int
    @Environment(\.keyboardRenderScale) private var renderScale

    var body: some View {
        VStack(spacing: 0) {
            KeyboardDeck(
                activeKeyCodes: activeKeyCodes,
                keyCounts: keyCounts,
                maximumCount: maximumCount
            )
            .frame(height: KeyboardMetrics.deckHeight * renderScale)

            Capsule()
                .fill(.black.opacity(0.25))
                .frame(width: 948 * renderScale, height: 13 * renderScale)
                .blur(radius: 7 * renderScale)
                .offset(y: -7 * renderScale)
        }
    }
}

private struct KeyboardDeck: View {
    let activeKeyCodes: Set<UInt16>
    let keyCounts: [UInt16: Int]
    let maximumCount: Int
    @Environment(\.keyboardRenderScale) private var renderScale
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: KeyboardMetrics.deckCornerRadius * renderScale, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            colorScheme == .dark ? Color(red: 0.72, green: 0.73, blue: 0.74) : Color(white: 0.91),
                            colorScheme == .dark ? Color(red: 0.46, green: 0.47, blue: 0.48) : Color(red: 0.63, green: 0.65, blue: 0.66),
                            colorScheme == .dark ? Color(red: 0.64, green: 0.65, blue: 0.66) : Color(red: 0.84, green: 0.85, blue: 0.85)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: KeyboardMetrics.deckCornerRadius * renderScale, style: .continuous)
                        .stroke(.white.opacity(colorScheme == .dark ? 0.42 : 0.72), lineWidth: 1.2 * renderScale)
                        .padding(renderScale)
                }
                .shadow(
                    color: .black.opacity(colorScheme == .dark ? 0.46 : 0.28),
                    radius: 2 * renderScale,
                    y: 5 * renderScale
                )

            VStack(spacing: KeyboardMetrics.rowSpacing * renderScale) {
                ForEach(Array(KeyboardLayout.rows.enumerated()), id: \.offset) { _, row in
                    KeyboardRowView(
                        keys: row,
                        height: KeyboardMetrics.keyHeight * renderScale,
                        activeKeyCodes: activeKeyCodes,
                        keyCounts: keyCounts,
                        maximumCount: maximumCount
                    )
                }
            }
            .padding(KeyboardMetrics.deckInset * renderScale)
        }
    }
}

private struct KeyboardRowView: View {
    let keys: [KeyboardKey]
    let height: CGFloat
    let activeKeyCodes: Set<UInt16>
    let keyCounts: [UInt16: Int]
    let maximumCount: Int
    @Environment(\.keyboardRenderScale) private var renderScale

    var body: some View {
        GeometryReader { proxy in
            let gap = KeyboardMetrics.keySpacing * renderScale
            let totalUnits = keys.reduce(0) { $0 + $1.width }
            let unit = (proxy.size.width - gap * CGFloat(keys.count - 1)) / totalUnits

            HStack(spacing: gap) {
                ForEach(keys) { key in
                    Group {
                        if let pairedKeyCode = key.pairedKeyCode {
                            ArrowKeyPair(
                                key: key,
                                pairedKeyCode: pairedKeyCode,
                                keyCounts: keyCounts,
                                maximumCount: maximumCount,
                                activeKeyCodes: activeKeyCodes
                            )
                        } else {
                            KeyboardKeyButton(
                                key: key,
                                count: key.keyCode.map { keyCounts[$0, default: 0] } ?? 0,
                                maximumCount: maximumCount,
                                isActive: key.keyCode.map(activeKeyCodes.contains) ?? false
                            )
                        }
                    }
                    .frame(width: unit * key.width, height: height)
                }
            }
        }
        .frame(height: height)
    }
}

private struct ArrowKeyPair: View {
    let key: KeyboardKey
    let pairedKeyCode: UInt16
    let keyCounts: [UInt16: Int]
    let maximumCount: Int
    let activeKeyCodes: Set<UInt16>
    @Environment(\.keyboardRenderScale) private var renderScale

    private var downKey: KeyboardKey {
        KeyboardKey(
            "\(key.id)-down",
            code: pairedKeyCode,
            symbol: "arrowtriangle.down.fill",
            face: .symbol(.center)
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let spacing = KeyboardMetrics.arrowKeySpacing * renderScale
            let arrowKeyHeight = (proxy.size.height - spacing) / 2

            VStack(spacing: spacing) {
                ArrowKeyHalfButton(
                    key: key,
                    count: key.keyCode.map { keyCounts[$0, default: 0] } ?? 0,
                    maximumCount: maximumCount,
                    isActive: key.keyCode.map(activeKeyCodes.contains) ?? false
                )
                .frame(maxWidth: .infinity)
                .frame(height: arrowKeyHeight)

                ArrowKeyHalfButton(
                    key: downKey,
                    count: keyCounts[pairedKeyCode, default: 0],
                    maximumCount: maximumCount,
                    isActive: activeKeyCodes.contains(pairedKeyCode)
                )
                .frame(maxWidth: .infinity)
                .frame(height: arrowKeyHeight)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

private struct ArrowKeyHalfButton: View {
    let key: KeyboardKey
    let count: Int
    let maximumCount: Int
    let isActive: Bool

    var body: some View {
        Button(action: {}) {
            KeyFace(key: key, count: count, isCompact: true)
        }
        .buttonStyle(ArrowKeyHalfStyle(isActive: isActive, heat: heat))
        .help(count == 0 ? key.accessibilityName : "\(key.accessibilityName)：\(count) 次")
        .accessibilityLabel(key.accessibilityName)
        .accessibilityValue("\(count) 次")
    }

    private var heat: Double {
        guard count > 0, maximumCount > 0 else { return 0 }
        return log(Double(count) + 1) / log(Double(maximumCount) + 1)
    }
}

private struct ArrowKeyHalfStyle: ButtonStyle {
    let isActive: Bool
    let heat: Double
    @Environment(\.keyboardRenderScale) private var renderScale
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.keyDiaryAccentColor) private var themeColor
    @Environment(\.keyDiaryAccentContrastColor) private var themeContrastColor

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed || isActive
        let cornerRadius = KeyboardMetrics.keyCornerRadius * renderScale

        configuration.label
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(pressed ? themeColor.opacity(0.62) : Color.black.opacity(colorScheme == .dark ? 0.72 : 0.38))
                        .offset(
                            y: (pressed ? KeyboardMetrics.pressedKeyDepth : KeyboardMetrics.keyDepth) * renderScale
                        )

                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: pressed
                                    ? [themeColor.opacity(0.78), themeColor]
                                    : colorScheme == .dark
                                        ? [Color(white: 0.16), Color(white: 0.09)]
                                        : [Color(white: 1.0), Color(white: 0.9)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay {
                            if !pressed, heat > 0 {
                                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                    .fill(themeColor.opacity(0.1 + heat * 0.34))
                            }
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .stroke(
                                    pressed ? themeColor.opacity(0.9) : .black.opacity(colorScheme == .dark ? 0.68 : 0.3),
                                    lineWidth: renderScale
                                )
                        }
                        .shadow(
                            color: pressed ? themeColor.opacity(0.34) : .black.opacity(colorScheme == .dark ? 0.34 : 0.18),
                            radius: (pressed
                                ? KeyboardMetrics.pressedKeyShadowRadius
                                : KeyboardMetrics.keyShadowRadius) * renderScale,
                            y: (pressed
                                ? KeyboardMetrics.pressedKeyShadowOffset
                                : KeyboardMetrics.keyShadowOffset) * renderScale
                        )
                }
            }
            .foregroundStyle(
                pressed
                    ? themeContrastColor
                    : colorScheme == .dark ? Color.white.opacity(0.84) : Color.black.opacity(0.68)
            )
            .contentShape(Rectangle())
            .offset(y: pressed ? KeyboardMetrics.pressedKeyOffset * renderScale : 0)
            .animation(.spring(response: 0.14, dampingFraction: 0.6), value: pressed)
    }
}

private struct KeyboardKeyButton: View {
    let key: KeyboardKey
    let count: Int
    let maximumCount: Int
    let isActive: Bool

    var body: some View {
        Button(action: {}) {
            KeyFace(key: key, count: count)
        }
        .buttonStyle(
            ThreeDimensionalKeyStyle(
                isActive: isActive,
                heat: heat,
                exteriorCorner: key.exteriorCorner
            )
        )
        .help(count == 0 ? key.accessibilityName : "\(key.accessibilityName)：\(count) 次")
        .accessibilityLabel(key.accessibilityName)
        .accessibilityValue("\(count) 次")
    }

    private var heat: Double {
        guard count > 0, maximumCount > 0 else { return 0 }
        return log(Double(count) + 1) / log(Double(maximumCount) + 1)
    }
}

private struct KeyFace: View {
    let key: KeyboardKey
    let count: Int
    let isCompact: Bool
    @Environment(\.keyboardRenderScale) private var renderScale
    @Environment(\.keyDiaryAccentColor) private var themeColor

    init(key: KeyboardKey, count: Int, isCompact: Bool = false) {
        self.key = key
        self.count = count
        self.isCompact = isCompact
    }

    var body: some View {
        ZStack {
            faceContent
                .foregroundStyle(.primary.opacity(0.64))

            if count > 0 {
                Text(compactCount)
                    .font(.system(size: (isCompact ? 6.5 : 8) * renderScale, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(themeColor)
                    .padding(.horizontal, (isCompact ? 2.5 : 4) * renderScale)
                    .frame(
                        minWidth: (isCompact ? 11 : 15) * renderScale,
                        minHeight: (isCompact ? 11 : 15) * renderScale
                    )
                    .background(.background.opacity(0.82), in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: key.countCorner.alignment)
                    .padding((isCompact ? 1 : 3) * renderScale)
            }
        }
    }

    @ViewBuilder
    private var faceContent: some View {
        switch key.face {
        case .centered:
            VStack(spacing: key.secondary == nil ? 0 : renderScale) {
                Text(key.primary)
                    .font(.system(size: 16 * renderScale, weight: .regular, design: .rounded))
                    .minimumScaleFactor(0.52)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                    .frame(height: 19 * renderScale)
                if let secondary = key.secondary {
                    Text(secondary)
                        .font(.system(size: 8.5 * renderScale, weight: .medium, design: .rounded))
                        .lineLimit(1)
                        .multilineTextAlignment(.center)
                        .frame(height: 11 * renderScale)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .function:
            VStack(spacing: 3 * renderScale) {
                symbol(size: 11.5 * renderScale)
                    .frame(width: 22 * renderScale, height: 16 * renderScale)
                if let secondary = key.secondary {
                    Text(secondary)
                        .font(.system(size: 8 * renderScale, weight: .medium, design: .rounded))
                        .lineLimit(1)
                        .frame(height: 10 * renderScale)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .symbol(let corner):
            symbol(size: (isCompact ? 9.5 : (key.isFunction ? 11.5 : 14)) * renderScale)
                .frame(
                    width: (isCompact ? 12 : 20) * renderScale,
                    height: (isCompact ? 12 : 20) * renderScale
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: corner.alignment)
                .padding(keyContentInsets)

        case .modifier(let iconCorner, let labelCorner):
            symbol(size: 14 * renderScale)
                .frame(width: 18 * renderScale, height: 18 * renderScale)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: iconCorner.alignment)
                .padding(keyContentInsets)
            if let secondary = key.secondary {
                Text(secondary)
                    .font(.system(size: 8.5 * renderScale, weight: .medium, design: .rounded))
                    .lineLimit(1)
                    .frame(height: 11 * renderScale)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: labelCorner.alignment)
                    .padding(keyContentInsets)
            }

        case .cornerText(let primaryCorner, let secondaryCorner):
            Text(key.primary)
                .font(.system(size: (key.isFunction ? 9.5 : 12) * renderScale, weight: .regular, design: .rounded))
                .lineLimit(1)
                .frame(height: (key.isFunction ? 12 : 16) * renderScale)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: primaryCorner.alignment)
                .padding(keyContentInsets)
            if let secondary = key.secondary {
                Text(secondary)
                    .font(.system(size: 8.5 * renderScale, weight: .medium, design: .rounded))
                    .lineLimit(1)
                    .frame(height: 11 * renderScale)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: secondaryCorner.alignment)
                    .padding(keyContentInsets)
            }
        }
    }

    @ViewBuilder
    private func symbol(size: CGFloat) -> some View {
        if let symbolName = key.symbolName {
            Image(systemName: symbolName)
                .font(.system(size: size, weight: .regular))
                .symbolRenderingMode(.monochrome)
        }
    }

    private var keyContentInsets: EdgeInsets {
        EdgeInsets(
            top: (isCompact ? 1 : 7) * renderScale,
            leading: (isCompact ? 3 : 9) * renderScale,
            bottom: (isCompact ? 1 : 7) * renderScale,
            trailing: (isCompact ? 3 : 9) * renderScale
        )
    }

    private var compactCount: String {
        if count >= 10_000 { return "\(count / 1_000)k" }
        if count >= 1_000 { return String(format: "%.1fk", Double(count) / 1_000) }
        return "\(count)"
    }
}

private struct ThreeDimensionalKeyStyle: ButtonStyle {
    let isActive: Bool
    let heat: Double
    let exteriorCorner: KeyCorner?
    @Environment(\.keyboardRenderScale) private var renderScale
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.keyDiaryAccentColor) private var themeColor
    @Environment(\.keyDiaryAccentContrastColor) private var themeContrastColor

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed || isActive
        let cornerRadii = keyCornerRadii

        configuration.label
            .background {
                ZStack {
                    UnevenRoundedRectangle(cornerRadii: cornerRadii, style: .continuous)
                        .fill(pressed ? themeColor.opacity(0.62) : Color.black.opacity(colorScheme == .dark ? 0.72 : 0.38))
                        .offset(
                            y: (pressed ? KeyboardMetrics.pressedKeyDepth : KeyboardMetrics.keyDepth) * renderScale
                        )

                    UnevenRoundedRectangle(cornerRadii: cornerRadii, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: pressed
                                    ? [themeColor.opacity(0.78), themeColor]
                                    : colorScheme == .dark
                                        ? [Color(white: 0.16), Color(white: 0.09)]
                                        : [Color(white: 1.0), Color(white: 0.9)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay {
                            if !pressed, heat > 0 {
                                UnevenRoundedRectangle(cornerRadii: cornerRadii, style: .continuous)
                                    .fill(themeColor.opacity(0.1 + heat * 0.34))
                            }
                        }
                        .overlay {
                            UnevenRoundedRectangle(cornerRadii: cornerRadii, style: .continuous)
                                .stroke(
                                    pressed ? themeColor.opacity(0.9) : .black.opacity(colorScheme == .dark ? 0.68 : 0.3),
                                    lineWidth: renderScale
                                )
                        }
                        .shadow(
                            color: pressed ? themeColor.opacity(0.34) : .black.opacity(colorScheme == .dark ? 0.34 : 0.18),
                            radius: (pressed
                                ? KeyboardMetrics.pressedKeyShadowRadius
                                : KeyboardMetrics.keyShadowRadius) * renderScale,
                            y: (pressed
                                ? KeyboardMetrics.pressedKeyShadowOffset
                                : KeyboardMetrics.keyShadowOffset) * renderScale
                        )
                }
            }
            .foregroundStyle(
                pressed
                    ? themeContrastColor
                    : colorScheme == .dark ? Color.white.opacity(0.84) : Color.black.opacity(0.68)
            )
            .offset(y: pressed ? KeyboardMetrics.pressedKeyOffset * renderScale : 0)
            .animation(.spring(response: 0.14, dampingFraction: 0.6), value: pressed)
    }

    private var keyCornerRadii: RectangleCornerRadii {
        let regular = KeyboardMetrics.keyCornerRadius * renderScale
        let exterior = KeyboardMetrics.exteriorKeyCornerRadius * renderScale

        return RectangleCornerRadii(
            topLeading: exteriorCorner == .topLeading ? exterior : regular,
            bottomLeading: exteriorCorner == .bottomLeading ? exterior : regular,
            bottomTrailing: exteriorCorner == .bottomTrailing ? exterior : regular,
            topTrailing: exteriorCorner == .topTrailing ? exterior : regular
        )
    }
}

private struct KeyboardKey: Identifiable {
    let id: String
    let keyCode: UInt16?
    let primary: String
    let secondary: String?
    let symbolName: String?
    let face: KeyFaceStyle
    let countCorner: KeyCorner
    let width: CGFloat
    let isFunction: Bool
    let pairedKeyCode: UInt16?
    let exteriorCorner: KeyCorner?

    init(
        _ id: String,
        code: UInt16? = nil,
        _ primary: String = "",
        secondary: String? = nil,
        symbol: String? = nil,
        face: KeyFaceStyle = .centered,
        countCorner: KeyCorner = .topTrailing,
        width: CGFloat = 1,
        function: Bool = false,
        pairedCode: UInt16? = nil,
        exteriorCorner: KeyCorner? = nil
    ) {
        self.id = id
        self.keyCode = code
        self.primary = primary
        self.secondary = secondary
        self.symbolName = symbol
        self.face = face
        self.countCorner = countCorner
        self.width = width
        self.isFunction = function
        self.pairedKeyCode = pairedCode
        self.exteriorCorner = exteriorCorner
    }

    var accessibilityName: String {
        if let secondary, !primary.isEmpty { return "\(primary) \(secondary)" }
        if let secondary { return secondary }
        return primary.isEmpty ? id : primary
    }
}

private enum KeyFaceStyle {
    case centered
    case function
    case symbol(KeyCorner)
    case modifier(icon: KeyCorner, label: KeyCorner)
    case cornerText(primary: KeyCorner, secondary: KeyCorner)
}

private enum KeyCorner: Equatable {
    case topLeading
    case top
    case topTrailing
    case leading
    case center
    case trailing
    case bottomLeading
    case bottom
    case bottomTrailing

    var alignment: Alignment {
        switch self {
        case .topLeading: .topLeading
        case .top: .top
        case .topTrailing: .topTrailing
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        case .bottomLeading: .bottomLeading
        case .bottom: .bottom
        case .bottomTrailing: .bottomTrailing
        }
    }
}

private enum KeyboardLayout {
    // Visual-only sentinel. No recorder maps an event to this key code.
    private static let displayOnlyLockKeyCode = UInt16.max

    static let rows: [[KeyboardKey]] = [
        [
            .init("esc", code: 53, "esc", face: .cornerText(primary: .bottomLeading, secondary: .bottomLeading), width: 1.55, function: true, exteriorCorner: .topLeading),
            .init("f1", code: 122, secondary: "F1", symbol: "sun.min", face: .function, function: true),
            .init("f2", code: 120, secondary: "F2", symbol: "sun.max", face: .function, function: true),
            .init("f3", code: 99, secondary: "F3", symbol: "rectangle.grid.2x2", face: .function, function: true),
            .init("f4", code: 118, secondary: "F4", symbol: "magnifyingglass", face: .function, function: true),
            .init("f5", code: 96, secondary: "F5", symbol: "mic.fill", face: .function, function: true),
            .init("f6", code: 97, secondary: "F6", symbol: "moon", face: .function, function: true),
            .init("f7", code: 98, secondary: "F7", symbol: "backward.fill", face: .function, function: true),
            .init("f8", code: 100, secondary: "F8", symbol: "playpause.fill", face: .function, function: true),
            .init("f9", code: 101, secondary: "F9", symbol: "forward.fill", face: .function, function: true),
            .init("f10", code: 109, secondary: "F10", symbol: "speaker.slash.fill", face: .function, function: true),
            .init("f11", code: 103, secondary: "F11", symbol: "speaker.wave.1.fill", face: .function, function: true),
            .init("f12", code: 111, secondary: "F12", symbol: "speaker.wave.3.fill", face: .function, function: true),
            .init("lock", code: displayOnlyLockKeyCode, symbol: "lock.fill", face: .symbol(.center), width: 1.02, function: true, exteriorCorner: .topTrailing)
        ],
        [
            .init("grave", code: 50, "~", secondary: "`"),
            .init("1", code: 18, "!", secondary: "1"), .init("2", code: 19, "@", secondary: "2"),
            .init("3", code: 20, "#", secondary: "3"), .init("4", code: 21, "¥", secondary: "4"),
            .init("5", code: 23, "%", secondary: "5"), .init("6", code: 22, "^", secondary: "6"),
            .init("7", code: 26, "&", secondary: "7"), .init("8", code: 28, "*", secondary: "8"),
            .init("9", code: 25, "(", secondary: "9"), .init("0", code: 29, ")", secondary: "0"),
            .init("minus", code: 27, "−", secondary: "_"), .init("equal", code: 24, "+", secondary: "="),
            .init("delete", code: 51, symbol: "delete.left", face: .symbol(.trailing), width: 1.55)
        ],
        [
            .init("tab", code: 48, symbol: "arrow.right.to.line.compact", face: .symbol(.leading), width: 1.55),
            .init("q", code: 12, "Q"), .init("w", code: 13, "W"), .init("e", code: 14, "E"),
            .init("r", code: 15, "R"), .init("t", code: 17, "T"), .init("y", code: 16, "Y"),
            .init("u", code: 32, "U"), .init("i", code: 34, "I"), .init("o", code: 31, "O"),
            .init("p", code: 35, "P"), .init("leftBracket", code: 33, "{", secondary: "["),
            .init("rightBracket", code: 30, "}", secondary: "]"), .init("backslash", code: 42, "|", secondary: "\\", width: 1.05)
        ],
        [
            .init("caps", code: 57, "•", secondary: "中/英", face: .cornerText(primary: .topLeading, secondary: .bottomLeading), width: 1.8),
            .init("a", code: 0, "A"), .init("s", code: 1, "S"), .init("d", code: 2, "D"),
            .init("f", code: 3, "F"), .init("g", code: 5, "G"), .init("h", code: 4, "H"),
            .init("j", code: 38, "J"), .init("k", code: 40, "K"), .init("l", code: 37, "L"),
            .init("semicolon", code: 41, ":", secondary: ";"), .init("quote", code: 39, "\"", secondary: "'"),
            .init("return", code: 36, symbol: "return", face: .symbol(.bottomTrailing), width: 2.04)
        ],
        [
            .init("leftShift", code: 56, symbol: "shift", face: .symbol(.bottomLeading), width: 2.35),
            .init("z", code: 6, "Z"), .init("x", code: 7, "X"), .init("c", code: 8, "C"),
            .init("v", code: 9, "V"), .init("b", code: 11, "B"), .init("n", code: 45, "N"),
            .init("m", code: 46, "M"), .init("comma", code: 43, "<", secondary: ","),
            .init("period", code: 47, ">", secondary: "."), .init("slash", code: 44, "?", secondary: "/"),
            .init("rightShift", code: 60, symbol: "shift", face: .symbol(.bottomTrailing), width: 2.25)
        ],
        [
            .init("globe", code: 63, symbol: "globe", face: .symbol(.bottomLeading), exteriorCorner: .bottomLeading),
            .init("leftControl", code: 59, secondary: "control", symbol: "control", face: .modifier(icon: .topLeading, label: .bottomLeading), width: 1.18),
            .init("leftOption", code: 58, secondary: "option", symbol: "option", face: .modifier(icon: .topLeading, label: .bottomLeading), width: 1.18),
            .init("leftCommand", code: 55, secondary: "command", symbol: "command", face: .modifier(icon: .topTrailing, label: .bottomLeading), countCorner: .topLeading, width: 1.35),
            .init("space", code: 49, "", width: 5.45),
            .init("rightCommand", code: 54, secondary: "command", symbol: "command", face: .modifier(icon: .topLeading, label: .bottomLeading), width: 1.35),
            .init("rightOption", code: 61, secondary: "option", symbol: "option", face: .modifier(icon: .topTrailing, label: .bottomLeading), width: 1.18),
            .init("left", code: 123, symbol: "arrowtriangle.left.fill", face: .symbol(.center)),
            .init("upDown", code: 126, symbol: "arrowtriangle.up.fill", face: .symbol(.center), pairedCode: 125),
            .init("right", code: 124, symbol: "arrowtriangle.right.fill", face: .symbol(.center), exteriorCorner: .bottomTrailing)
        ]
    ]
}
