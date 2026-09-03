//
//  AppleMouseStatisticsView.swift
//  KeyDiary
//

import SwiftUI

struct AppleMouseStatisticsView: View {
    let counts: MouseClickCounts
    let pressedButtons: Set<MouseButton>

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.keyDiaryAccentColor) private var themeColor

    init(counts: MouseClickCounts, pressedButtons: Set<MouseButton> = []) {
        self.counts = counts
        self.pressedButtons = pressedButtons
    }

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 2) {
                Text("鼠标点击")
                    .font(.headline)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(counts.total.formatted())
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                    Text("次点击")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                    .contentTransition(.numericText())
            }

            GeometryReader { proxy in
                let size = mouseSize(in: proxy.size)

                ZStack {
                    mouseUnderbody
                        .frame(width: size.width, height: size.height)

                    ZStack {
                        mouseShell

                        mouseGlassDepth
                            .clipShape(AppleMouseSilhouette())

                        mouseHeatOverlay
                            .clipShape(AppleMouseSilhouette())

                        AppleMouseGloss()
                            .fill(
                                LinearGradient(
                                    stops: [
                                        .init(color: .white.opacity(0.76), location: 0),
                                        .init(color: .white.opacity(0.28), location: 0.36),
                                        .init(color: .white.opacity(0.06), location: 0.72),
                                        .init(color: .clear, location: 1)
                                    ],
                                    startPoint: UnitPoint(x: 0.08, y: 0.02),
                                    endPoint: UnitPoint(x: 0.88, y: 0.84)
                                )
                            )
                            .clipShape(AppleMouseSilhouette())
                            .blur(radius: size.width * 0.012)
                            .blendMode(.screen)

                        AppleMouseCrownHighlight()
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.3),
                                        .white.opacity(0.94),
                                        .white.opacity(0.24)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                style: StrokeStyle(
                                    lineWidth: max(1.2, size.width * 0.012),
                                    lineCap: .round
                                )
                            )
                            .blur(radius: size.width * 0.003)
                            .blendMode(.screen)

                        mousePressOverlay
                            .clipShape(AppleMouseSilhouette())

                        AppleMouseSilhouette()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.98),
                                        Color(white: 0.84).opacity(0.62),
                                        Color(white: 0.62).opacity(0.46),
                                        .white.opacity(0.74)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.15
                            )

                        AppleMouseSilhouette()
                            .inset(by: 3)
                            .strokeBorder(
                                LinearGradient(
                                    stops: [
                                        .init(color: .white.opacity(0.72), location: 0),
                                        .init(color: .white.opacity(0.16), location: 0.34),
                                        .init(color: .clear, location: 0.62),
                                        .init(color: .white.opacity(0.3), location: 1)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.8
                            )

                        AppleMouseTailRim()
                            .stroke(
                                LinearGradient(
                                    stops: [
                                        .init(color: .clear, location: 0),
                                        .init(color: .white.opacity(0.46), location: 0.16),
                                        .init(color: .white.opacity(0.9), location: 0.5),
                                        .init(color: .white.opacity(0.46), location: 0.84),
                                        .init(color: .clear, location: 1)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                style: StrokeStyle(
                                    lineWidth: max(0.9, size.width * 0.007),
                                    lineCap: .round
                                )
                            )

                        Image(systemName: "apple.logo")
                            .font(.system(size: size.width * 0.15, weight: .regular))
                            .foregroundStyle(Color(white: 0.58).opacity(0.34))
                            .offset(y: size.height * 0.28)
                    }
                    .frame(width: size.width, height: size.height)
                    .scaleEffect(
                        x: isAnyButtonPressed ? 0.996 : 1,
                        y: isAnyButtonPressed ? 0.994 : 1,
                        anchor: .bottom
                    )
                    .offset(y: isAnyButtonPressed ? 2.2 : 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(
                    reduceMotion ? nil : .spring(response: 0.12, dampingFraction: 0.72),
                    value: pressedButtons
                )
            }
            .aspectRatio(0.52, contentMode: .fit)

            HStack(spacing: 8) {
                metricChip(button: .left, count: counts.left)
                metricChip(button: .right, count: counts.right)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Apple 鼠标点击统计")
        .accessibilityValue(accessibilityValue)
    }

    private var mouseUnderbody: some View {
        AppleMouseSilhouette()
            .fill(
                LinearGradient(
                    colors: [
                        Color(white: 0.985),
                        Color(white: 0.94),
                        Color(white: 0.86)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .offset(y: 2.2)
            .shadow(
                color: .black.opacity(colorScheme == .dark ? 0.32 : 0.12),
                radius: 9,
                x: 0,
                y: 7
            )
    }

    private var mouseShell: some View {
        AppleMouseSilhouette()
            .fill(
                LinearGradient(
                    colors: [
                        Color(white: 1),
                        Color(white: 0.985),
                        Color(white: 0.945),
                        Color(white: 0.875)
                    ],
                    startPoint: UnitPoint(x: 0.28, y: 0),
                    endPoint: UnitPoint(x: 0.78, y: 1)
                )
            )
            .overlay {
                AppleMouseSilhouette()
                    .inset(by: 2.4)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.92), .white.opacity(0.12)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
    }

    private var mouseGlassDepth: some View {
        GeometryReader { proxy in
            ZStack {
                RadialGradient(
                    colors: [.white.opacity(0.46), .white.opacity(0.08), .clear],
                    center: UnitPoint(x: 0.3, y: 0.08),
                    startRadius: 0,
                    endRadius: proxy.size.width * 1.15
                )

                RadialGradient(
                    colors: [
                        Color(red: 0.72, green: 0.78, blue: 0.84).opacity(0.18),
                        .clear
                    ],
                    center: UnitPoint(x: 0.82, y: 0.88),
                    startRadius: 0,
                    endRadius: proxy.size.width * 0.92
                )

                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0.2), location: 0),
                        .init(color: .clear, location: 0.52),
                        .init(color: Color(white: 0.56).opacity(0.06), location: 0.88),
                        .init(color: .white.opacity(0.12), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .allowsHitTesting(false)
    }

    private var mouseHeatOverlay: some View {
        GeometryReader { proxy in
            let maximum = max(counts.left, counts.right, 1)

            ZStack {
                RadialGradient(
                    colors: [
                        themeColor.opacity(heatOpacity(counts.left, maximum: maximum)),
                        themeColor.opacity(0.018),
                        .clear
                    ],
                    center: UnitPoint(x: 0.2, y: 0.12),
                    startRadius: 0,
                    endRadius: proxy.size.width * 0.95
                )
                RadialGradient(
                    colors: [
                        themeColor.opacity(heatOpacity(counts.right, maximum: maximum)),
                        themeColor.opacity(0.018),
                        .clear
                    ],
                    center: UnitPoint(x: 0.8, y: 0.12),
                    startRadius: 0,
                    endRadius: proxy.size.width * 0.95
                )
            }
        }
    }

    private var mousePressOverlay: some View {
        GeometryReader { proxy in
            ZStack {
                RadialGradient(
                    colors: [
                        themeColor.opacity(0.5),
                        themeColor.opacity(0.14),
                        .clear
                    ],
                    center: UnitPoint(x: 0.16, y: 0.08),
                    startRadius: 0,
                    endRadius: proxy.size.width * 1.15
                )
                .opacity(pressedButtons.contains(.left) ? 1 : 0)

                RadialGradient(
                    colors: [
                        themeColor.opacity(0.5),
                        themeColor.opacity(0.14),
                        .clear
                    ],
                    center: UnitPoint(x: 0.84, y: 0.08),
                    startRadius: 0,
                    endRadius: proxy.size.width * 1.15
                )
                .opacity(pressedButtons.contains(.right) ? 1 : 0)

                LinearGradient(
                    colors: [.black.opacity(isAnyButtonPressed ? 0.055 : 0), .clear],
                    startPoint: .top,
                    endPoint: UnitPoint(x: 0.5, y: 0.42)
                )
            }
        }
        .allowsHitTesting(false)
    }

    private func metricChip(button: MouseButton, count: Int) -> some View {
        let isPressed = pressedButtons.contains(button)

        return HStack(spacing: 6) {
            Circle()
                .fill(themeColor.opacity(count == 0 ? 0.22 : 0.82))
                .frame(width: 7, height: 7)
                .scaleEffect(isPressed ? 1.35 : 1)
            Text(button.title)
                .foregroundStyle(.secondary)
            Text(count.formatted())
                .fontWeight(.semibold)
                .contentTransition(.numericText())
        }
        .font(.caption)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: Capsule())
        .background(themeColor.opacity(isPressed ? 0.18 : 0), in: Capsule())
        .overlay {
            Capsule()
                .stroke(
                    isPressed ? themeColor.opacity(0.72) : Color.secondary.opacity(0.22),
                    lineWidth: isPressed ? 1.1 : 0.7
                )
        }
        .scaleEffect(isPressed ? 0.97 : 1)
        .animation(
            reduceMotion ? nil : .spring(response: 0.12, dampingFraction: 0.72),
            value: isPressed
        )
    }

    private var isAnyButtonPressed: Bool {
        !pressedButtons.isEmpty
    }

    private var accessibilityValue: String {
        let countsDescription = L10n.format(
            "左键 %@ 次，右键 %@ 次，总计 %@ 次",
            counts.left.formatted(),
            counts.right.formatted(),
            counts.total.formatted()
        )
        let pressedDescription: String?
        switch (pressedButtons.contains(.left), pressedButtons.contains(.right)) {
        case (true, true): pressedDescription = L10n.text("左右键均按下")
        case (true, false): pressedDescription = L10n.text("左键按下")
        case (false, true): pressedDescription = L10n.text("右键按下")
        case (false, false): pressedDescription = nil
        }
        return pressedDescription.map { "\(countsDescription)，\($0)" } ?? countsDescription
    }

    private func heatOpacity(_ count: Int, maximum: Int) -> Double {
        guard count > 0 else { return 0.012 }
        return 0.025 + 0.075 * Double(count) / Double(maximum)
    }

    private func mouseSize(in available: CGSize) -> CGSize {
        let height = min(available.height, available.width / 0.52)
        return CGSize(width: height * 0.52, height: height)
    }
}

private struct AppleMouseSilhouette: InsettableShape {
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let width = rect.width
        let height = rect.height
        var path = Path()

        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: rect.minX + width * 0.94, y: rect.minY + height * 0.115),
            control1: CGPoint(x: rect.minX + width * 0.75, y: rect.minY - height * 0.004),
            control2: CGPoint(x: rect.minX + width * 0.91, y: rect.minY + height * 0.042)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + width * 0.95, y: rect.minY + height * 0.76),
            control1: CGPoint(x: rect.maxX, y: rect.minY + height * 0.34),
            control2: CGPoint(x: rect.minX + width * 0.985, y: rect.minY + height * 0.64)
        )
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.minY + height * 0.985),
            control1: CGPoint(x: rect.minX + width * 0.906, y: rect.minY + height * 0.91),
            control2: CGPoint(x: rect.minX + width * 0.78, y: rect.minY + height * 0.985)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + width * 0.05, y: rect.minY + height * 0.76),
            control1: CGPoint(x: rect.minX + width * 0.22, y: rect.minY + height * 0.985),
            control2: CGPoint(x: rect.minX + width * 0.094, y: rect.minY + height * 0.91)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + width * 0.06, y: rect.minY + height * 0.115),
            control1: CGPoint(x: rect.minX + width * 0.015, y: rect.minY + height * 0.64),
            control2: CGPoint(x: rect.minX, y: rect.minY + height * 0.34)
        )
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.minY),
            control1: CGPoint(x: rect.minX + width * 0.09, y: rect.minY + height * 0.042),
            control2: CGPoint(x: rect.minX + width * 0.25, y: rect.minY - height * 0.004)
        )
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> AppleMouseSilhouette {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

private struct AppleMouseGloss: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.minY + rect.height * 0.055))
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.74, y: rect.minY + rect.height * 0.3),
            control1: CGPoint(x: rect.minX + rect.width * 0.34, y: rect.minY - rect.height * 0.012),
            control2: CGPoint(x: rect.minX + rect.width * 0.62, y: rect.minY + rect.height * 0.12)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.87, y: rect.minY + rect.height * 0.76),
            control1: CGPoint(x: rect.minX + rect.width * 0.84, y: rect.minY + rect.height * 0.42),
            control2: CGPoint(x: rect.minX + rect.width * 0.9, y: rect.minY + rect.height * 0.63)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.6, y: rect.minY + rect.height * 0.47),
            control1: CGPoint(x: rect.minX + rect.width * 0.78, y: rect.minY + rect.height * 0.63),
            control2: CGPoint(x: rect.minX + rect.width * 0.69, y: rect.minY + rect.height * 0.53)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.27, y: rect.minY + rect.height * 0.25),
            control1: CGPoint(x: rect.minX + rect.width * 0.49, y: rect.minY + rect.height * 0.4),
            control2: CGPoint(x: rect.minX + rect.width * 0.37, y: rect.minY + rect.height * 0.32)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.minY + rect.height * 0.055),
            control1: CGPoint(x: rect.minX + rect.width * 0.17, y: rect.minY + rect.height * 0.19),
            control2: CGPoint(x: rect.minX + rect.width * 0.1, y: rect.minY + rect.height * 0.11)
        )
        path.closeSubpath()
        return path
    }
}

private struct AppleMouseCrownHighlight: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.14, y: rect.minY + rect.height * 0.09))
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.86, y: rect.minY + rect.height * 0.09),
            control1: CGPoint(x: rect.minX + rect.width * 0.33, y: rect.minY + rect.height * 0.005),
            control2: CGPoint(x: rect.minX + rect.width * 0.67, y: rect.minY + rect.height * 0.005)
        )
        return path
    }
}

private struct AppleMouseTailRim: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.074, y: rect.minY + rect.height * 0.755))
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.973),
            control1: CGPoint(x: rect.minX + rect.width * 0.106, y: rect.minY + rect.height * 0.895),
            control2: CGPoint(x: rect.minX + rect.width * 0.22, y: rect.minY + rect.height * 0.973)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.926, y: rect.minY + rect.height * 0.755),
            control1: CGPoint(x: rect.minX + rect.width * 0.78, y: rect.minY + rect.height * 0.973),
            control2: CGPoint(x: rect.minX + rect.width * 0.894, y: rect.minY + rect.height * 0.895)
        )
        return path
    }
}

#Preview {
    AppleMouseStatisticsView(counts: MouseClickCounts(left: 12_847, right: 3_291))
        .frame(width: 250, height: 560)
        .padding(40)
}
