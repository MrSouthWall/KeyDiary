//
//  DockVisibilityController.swift
//  KeyDiary
//

import AppKit
import SwiftUI

@MainActor
final class DockVisibilityController {
    private var trackedWindows: Set<ObjectIdentifier> = []
    private var transitionGeneration = 0

    func prepareToShowInterface() {
        transitionGeneration += 1
        setActivationPolicy(.regular)
    }

    fileprivate func track(_ window: NSWindow) {
        transitionGeneration += 1
        trackedWindows.insert(ObjectIdentifier(window))
        setActivationPolicy(.regular)
    }

    fileprivate func stopTracking(_ window: NSWindow) {
        transitionGeneration += 1
        trackedWindows.remove(ObjectIdentifier(window))
        let generation = transitionGeneration

        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.transitionGeneration == generation,
                  self.trackedWindows.isEmpty else { return }
            self.setActivationPolicy(.accessory)
        }
    }

    private func setActivationPolicy(_ policy: NSApplication.ActivationPolicy) {
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
    }
}

struct DockVisibilityBridge: NSViewRepresentable {
    let controller: DockVisibilityController

    func makeNSView(context: Context) -> DockVisibilityTrackingView {
        DockVisibilityTrackingView(controller: controller)
    }

    func updateNSView(_ nsView: DockVisibilityTrackingView, context: Context) {
        nsView.controller = controller
    }

    static func dismantleNSView(_ nsView: DockVisibilityTrackingView, coordinator: ()) {
        nsView.disconnect()
    }
}

@MainActor
final class DockVisibilityTrackingView: NSView {
    var controller: DockVisibilityController

    private weak var trackedWindow: NSWindow?

    init(controller: DockVisibilityController) {
        self.controller = controller
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        guard trackedWindow !== window else { return }
        disconnect()

        guard let window else { return }
        trackedWindow = window
        controller.track(window)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: window
        )
    }

    func disconnect() {
        NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: trackedWindow)

        if let trackedWindow {
            controller.stopTracking(trackedWindow)
            self.trackedWindow = nil
        }
    }

    @objc
    private func windowWillClose(_ notification: Notification) {
        disconnect()
    }
}
