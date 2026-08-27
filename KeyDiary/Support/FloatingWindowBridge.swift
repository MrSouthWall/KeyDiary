//
//  FloatingWindowBridge.swift
//  KeyDiary
//

import AppKit
import SwiftUI

enum FloatingKeyboardWindowMetrics {
    static let aspectRatio = CGSize(width: 900, height: 430)
    static let minimumWidth: CGFloat = 100
    static let minimumHeight = minimumWidth * aspectRatio.height / aspectRatio.width
    static let cornerRadius: CGFloat = 24
}

/// Applies the AppKit-only behavior required by the dedicated floating keyboard window.
struct FloatingWindowBridge: NSViewRepresentable {
    func makeNSView(context: Context) -> FloatingWindowConfigurationView {
        FloatingWindowConfigurationView()
    }

    func updateNSView(_ nsView: FloatingWindowConfigurationView, context: Context) {
        nsView.applyConfiguration()
    }
}

final class FloatingWindowConfigurationView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyConfiguration()

        DispatchQueue.main.async { [weak self] in
            self?.applyConfiguration()
        }
    }

    func applyConfiguration() {
        guard let window else { return }

        window.level = .floating
        window.hidesOnDeactivate = false
        window.styleMask.insert(.resizable)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.contentAspectRatio = FloatingKeyboardWindowMetrics.aspectRatio
        window.contentMinSize = CGSize(
            width: FloatingKeyboardWindowMetrics.minimumWidth,
            height: FloatingKeyboardWindowMetrics.minimumHeight
        )
        window.minSize = window.contentMinSize
        window.collectionBehavior.formUnion([.canJoinAllSpaces, .fullScreenAuxiliary])
        window.invalidateShadow()
    }
}

enum FloatingWindowResizeEdge {
    case top
    case bottom
    case left
    case right
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
}

struct WindowResizeHandle: NSViewRepresentable {
    let edge: FloatingWindowResizeEdge

    func makeNSView(context: Context) -> WindowResizeHandleView {
        WindowResizeHandleView(edge: edge)
    }

    func updateNSView(_ nsView: WindowResizeHandleView, context: Context) {
        nsView.edge = edge
    }
}

final class WindowResizeHandleView: NSView {
    var edge: FloatingWindowResizeEdge {
        didSet {
            window?.invalidateCursorRects(for: self)
        }
    }

    private var initialMouseLocation: NSPoint?
    private var initialWindowFrame: NSRect?

    init(edge: FloatingWindowResizeEdge) {
        self.edge = edge
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: resizeCursor)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        initialMouseLocation = NSEvent.mouseLocation
        initialWindowFrame = window.frame
    }

    override func mouseDragged(with event: NSEvent) {
        guard
            let window,
            let initialMouseLocation,
            let initialWindowFrame
        else { return }

        let mouseLocation = NSEvent.mouseLocation
        let delta = NSPoint(
            x: mouseLocation.x - initialMouseLocation.x,
            y: mouseLocation.y - initialMouseLocation.y
        )
        let frame = resizedFrame(from: initialWindowFrame, delta: delta)
        window.setFrame(frame, display: true)
        window.invalidateShadow()
    }

    override func mouseUp(with event: NSEvent) {
        initialMouseLocation = nil
        initialWindowFrame = nil
    }

    private func resizedFrame(from initialFrame: NSRect, delta: NSPoint) -> NSRect {
        let aspectRatio = FloatingKeyboardWindowMetrics.aspectRatio.width
            / FloatingKeyboardWindowMetrics.aspectRatio.height
        let minimumWidth = FloatingKeyboardWindowMetrics.minimumWidth

        switch edge {
        case .left, .right:
            let widthDelta = edge == .left ? -delta.x : delta.x
            let width = max(minimumWidth, initialFrame.width + widthDelta)
            let height = width / aspectRatio
            let originX = edge == .left ? initialFrame.maxX - width : initialFrame.minX
            return NSRect(
                x: originX,
                y: initialFrame.midY - height / 2,
                width: width,
                height: height
            )

        case .top, .bottom:
            let heightDelta = edge == .bottom ? -delta.y : delta.y
            let height = max(minimumWidth / aspectRatio, initialFrame.height + heightDelta)
            let width = height * aspectRatio
            let originY = edge == .bottom ? initialFrame.maxY - height : initialFrame.minY
            return NSRect(
                x: initialFrame.midX - width / 2,
                y: originY,
                width: width,
                height: height
            )

        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            let movesLeft = edge == .topLeft || edge == .bottomLeft
            let movesBottom = edge == .bottomLeft || edge == .bottomRight
            let horizontalDirection: CGFloat = movesLeft ? -1 : 1
            let verticalDirection: CGFloat = movesBottom ? -1 : 1
            let projectedWidthDelta = (
                horizontalDirection * delta.x
                    + verticalDirection * delta.y / aspectRatio
            ) / (1 + 1 / (aspectRatio * aspectRatio))
            let width = max(minimumWidth, initialFrame.width + projectedWidthDelta)
            let height = width / aspectRatio
            let originX = movesLeft ? initialFrame.maxX - width : initialFrame.minX
            let originY = movesBottom ? initialFrame.maxY - height : initialFrame.minY
            return NSRect(x: originX, y: originY, width: width, height: height)
        }
    }

    private var resizeCursor: NSCursor {
        switch edge {
        case .left, .right, .topLeft, .bottomRight:
            return .resizeLeftRight
        case .top, .bottom, .topRight, .bottomLeft:
            return .resizeUpDown
        }
    }
}
