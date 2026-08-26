//
//  KeyboardRecorder.swift
//  KeyDiary
//

import AppKit
import ApplicationServices

@MainActor
final class KeyboardRecorder {
    private var pressedModifierKeyCodes: Set<UInt16> = []
    private lazy var quartzKeyboardMonitor = QuartzKeyboardMonitor { [weak self] event in
        self?.handle(event)
    }
    var onKeyPress: ((KeyPressRecord) -> Void)?

    var isRunning: Bool { quartzKeyboardMonitor.isRunning }

    @discardableResult
    func requestInputMonitoringPermission() -> Bool {
        CGRequestListenEventAccess()
    }

    @discardableResult
    func openInputMonitoringSettings() -> Bool {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") else {
            return false
        }
        return NSWorkspace.shared.open(url)
    }

    func hasInputMonitoringPermission() -> Bool {
        CGPreflightListenEventAccess()
    }

    func start() {
        guard hasInputMonitoringPermission() else { return }
        quartzKeyboardMonitor.start()
    }

    func stop() {
        quartzKeyboardMonitor.stop()
        pressedModifierKeyCodes.removeAll()
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .keyDown:
            // Caps Lock is normalized through flagsChanged below. Ignoring a possible
            // keyDown here prevents a keyboard driver from reporting the same press twice.
            guard event.keyCode != 57 else { return }
            record(keyCode: event.keyCode, key: KeyCodeResolver.label(for: event))

        case .flagsChanged:
            handleModifierFlagsChanged(event)

        case .systemDefined:
            guard let key = KeyCodeResolver.systemDefinedKey(for: event) else { return }
            record(keyCode: key.keyCode, key: key.label)

        default:
            break
        }
    }

    private func handleModifierFlagsChanged(_ event: NSEvent) {
        let keyCode = event.keyCode

        // Caps Lock sends flagsChanged for both the physical down and up transitions.
        // Toggle its tracked state and record only the down transition.
        if keyCode == 57 {
            if pressedModifierKeyCodes.remove(keyCode) != nil {
                return
            }
            pressedModifierKeyCodes.insert(keyCode)
            record(keyCode: keyCode, key: KeyCodeResolver.label(for: event))
            return
        }

        guard let flag = KeyCodeResolver.modifierFlag(for: keyCode) else { return }

        if pressedModifierKeyCodes.remove(keyCode) != nil {
            return
        }

        // Ignore a release for a modifier that was already held when recording started.
        guard event.modifierFlags.contains(flag) else { return }
        pressedModifierKeyCodes.insert(keyCode)
        record(keyCode: keyCode, key: KeyCodeResolver.label(for: event))
    }

    private func record(keyCode: UInt16, key: String) {
        let application = NSWorkspace.shared.frontmostApplication
        let record = KeyPressRecord(
            timestamp: .now,
            keyCode: keyCode,
            key: key,
            applicationName: application?.localizedName ?? "Unknown app",
            bundleIdentifier: application?.bundleIdentifier
        )
        onKeyPress?(record)
    }

}
