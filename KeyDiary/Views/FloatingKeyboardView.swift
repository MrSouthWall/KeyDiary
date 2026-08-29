//
//  FloatingKeyboardView.swift
//  KeyDiary
//

import SwiftUI

/// A focused, always-on-top surface that mirrors live physical keyboard input.
struct FloatingKeyboardView: View {
    @Bindable var store: KeyDiaryStore

    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openWindow) private var openWindow
    @Environment(\.keyDiaryAccentColor) private var themeColor
    @State private var isPointerInside = false

    var body: some View {
        let windowShape = RoundedRectangle(
            cornerRadius: FloatingKeyboardWindowMetrics.cornerRadius,
            style: .continuous
        )

        ZStack {
            floatingBackground

            KeyboardStage(
                activeKeyDescription: store.activeLiveKeySummary,
                activeKeyCodes: store.activeLiveKeyCodes,
                displayMode: .live,
                layoutMode: .qwerty,
                isPlaying: false,
                keyCounts: [:],
                alignsToTop: false,
                pixelFrame: nil,
                pixelColorMode: nil
            )
            .offset(y: -8)
            .padding(12)

            windowDragArea

            FloatingWindowResizeOverlay()

            restoreMainWindowButton
                .opacity(isPointerInside ? 1 : 0)
                .scaleEffect(isPointerInside ? 1 : 0.88)
                .allowsHitTesting(isPointerInside)
                .accessibilityHidden(!isPointerInside)
                .frame(width: 42, height: 42)
                .padding(3)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .clipShape(windowShape)
        .frame(
            minWidth: FloatingKeyboardWindowMetrics.minimumWidth,
            minHeight: FloatingKeyboardWindowMetrics.minimumHeight
        )
        .background {
            FloatingWindowBridge()
        }
        .contentShape(windowShape)
        .onHover { isInside in
            withAnimation(.easeOut(duration: 0.15)) {
                isPointerInside = isInside
            }
        }
        .accessibilityLabel("实时悬浮键盘")
    }

    private var windowDragArea: some View {
        HStack(spacing: 0) {
            windowDragRegion

            Color.clear
                .frame(width: 48)
        }
        .frame(height: 28)
        .padding(.horizontal, 6)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var windowDragRegion: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(WindowDragGesture())
            .allowsWindowActivationEvents(true)
    }

    private var restoreMainWindowButton: some View {
        Button(action: restoreMainWindow) {
            Image(systemName: "rectangle.on.rectangle")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 30, height: 30)
                .background(.regularMaterial, in: Circle())
                .overlay {
                    Circle()
                        .stroke(.separator.opacity(0.75), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .help("返回主窗口")
        .accessibilityLabel("返回主窗口")
    }

    private func restoreMainWindow() {
        openWindow(id: "main")
        dismissWindow(id: "floating-keyboard")
    }

    private var floatingBackground: some View {
        ZStack {
            Rectangle()
                .fill(.background)

            RadialGradient(
                colors: [themeColor.opacity(0.1), .clear],
                center: .center,
                startRadius: 30,
                endRadius: 420
            )
        }
        .ignoresSafeArea()
    }
}

private struct FloatingWindowResizeOverlay: View {
    private let edgeThickness: CGFloat = 8
    private let cornerSize: CGFloat = 18

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                WindowResizeHandle(edge: .top)
                    .frame(height: edgeThickness)
                    .padding(.horizontal, cornerSize)

                Spacer(minLength: 0)

                WindowResizeHandle(edge: .bottom)
                    .frame(height: edgeThickness)
                    .padding(.horizontal, cornerSize)
            }

            HStack(spacing: 0) {
                WindowResizeHandle(edge: .left)
                    .frame(width: edgeThickness)
                    .padding(.vertical, cornerSize)

                Spacer(minLength: 0)

                WindowResizeHandle(edge: .right)
                    .frame(width: edgeThickness)
                    .padding(.vertical, cornerSize)
            }

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    WindowResizeHandle(edge: .topLeft)
                        .frame(width: cornerSize, height: cornerSize)

                    Spacer(minLength: 0)

                    WindowResizeHandle(edge: .topRight)
                        .frame(width: cornerSize, height: cornerSize)
                }

                Spacer(minLength: 0)

                HStack(spacing: 0) {
                    WindowResizeHandle(edge: .bottomLeft)
                        .frame(width: cornerSize, height: cornerSize)

                    Spacer(minLength: 0)

                    WindowResizeHandle(edge: .bottomRight)
                        .frame(width: cornerSize, height: cornerSize)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    FloatingKeyboardView(store: KeyDiaryStore())
        .frame(width: 900, height: 430)
}
