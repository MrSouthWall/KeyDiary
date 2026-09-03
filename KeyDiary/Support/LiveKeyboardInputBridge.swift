//
//  LiveKeyboardInputBridge.swift
//  KeyDiary
//

import AppKit
import SwiftUI

/// Prevents ordinary key presses from reaching AppKit's unhandled-key path while
/// a live keyboard surface is active. The Quartz recorder still observes the
/// physical event independently, so consuming the local event does not affect
/// recording or the keycap animation.
struct LiveKeyboardInputBridge: NSViewRepresentable {
    let isEnabled: Bool

    func makeNSView(context: Context) -> LiveKeyboardInputView {
        let view = LiveKeyboardInputView()
        view.isEnabled = isEnabled
        return view
    }

    func updateNSView(_ nsView: LiveKeyboardInputView, context: Context) {
        nsView.isEnabled = isEnabled
    }

    static func dismantleNSView(_ nsView: LiveKeyboardInputView, coordinator: ()) {
        nsView.stopMonitoring()
    }
}

final class LiveKeyboardInputView: NSView {
    var isEnabled = false

    private var eventMonitor: Any?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        startMonitoring()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        stopMonitoring()
    }

    private func startMonitoring() {
        guard eventMonitor == nil else { return }

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard
                let self,
                self.isEnabled,
                let window = self.window,
                event.window === window
            else {
                return event
            }

            // Keep menu commands and app keyboard shortcuts on the normal
            // responder path. Live input only needs to absorb typing keys.
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if modifiers.contains(.command) {
                return event
            }

            // Do not interfere if a text editor is temporarily presented in
            // the same window hierarchy.
            if let textView = window.firstResponder as? NSTextView, textView.isEditable {
                return event
            }

            return nil
        }
    }

    fileprivate func stopMonitoring() {
        guard let eventMonitor else { return }
        NSEvent.removeMonitor(eventMonitor)
        self.eventMonitor = nil
    }
}
