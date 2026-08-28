//
//  KeyboardRecorder.swift
//  KeyDiary
//

import AppKit
import ApplicationServices

@MainActor
final class KeyboardRecorder {
    private let keySoundPlayer = KeySoundPlayer()
    private var pressedKeys: [UInt16: String] = [:]
    private var pressedModifierKeyCodes: Set<UInt16> = []
    private lazy var quartzKeyboardMonitor = QuartzKeyboardMonitor(
        onEvent: { [weak self] event in
            self?.handle(event)
        },
        onReset: { [weak self] in
            self?.clearPressedKeys()
        }
    )
    var onKeyPress: ((KeyPressRecord) -> Void)?
    var onPressedKeysChanged: (([UInt16: String]) -> Void)?

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
        clearPressedKeys()
    }

    private func clearPressedKeys() {
        pressedModifierKeyCodes.removeAll()
        if !pressedKeys.isEmpty {
            pressedKeys.removeAll()
            onPressedKeysChanged?([:])
        }
    }

    func handle(_ event: NSEvent) {
        switch event.type {
        case .keyDown:
            // Caps Lock is normalized through flagsChanged below. Ignoring a possible
            // keyDown here prevents a keyboard driver from reporting the same press twice.
            guard event.keyCode != 57 else { return }
            let key = KeyCodeResolver.label(for: event)
            setPressed(true, keyCode: event.keyCode, key: key)
            record(keyCode: event.keyCode, key: key, playsSound: !event.isARepeat)

        case .keyUp:
            guard event.keyCode != 57 else { return }
            if pressedKeys[event.keyCode] != nil {
                keySoundPlayer.playReleaseUsingPreferences(keyCode: event.keyCode)
            }
            setPressed(false, keyCode: event.keyCode)

        case .flagsChanged:
            handleModifierFlagsChanged(event)

        case .systemDefined:
            guard let resolvedEvent = KeyCodeResolver.systemDefinedKeyEvent(for: event) else { return }
            let key = resolvedEvent.key
            if resolvedEvent.phase == .up, pressedKeys[key.keyCode] != nil {
                keySoundPlayer.playReleaseUsingPreferences(keyCode: key.keyCode)
            }
            setPressed(resolvedEvent.phase.isPressed, keyCode: key.keyCode, key: key.label)
            if resolvedEvent.phase.shouldRecord {
                record(
                    keyCode: key.keyCode,
                    key: key.label,
                    playsSound: resolvedEvent.phase == .down
                )
            }

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
                keySoundPlayer.playReleaseUsingPreferences(keyCode: keyCode)
                setPressed(false, keyCode: keyCode)
                return
            }
            pressedModifierKeyCodes.insert(keyCode)
            let key = KeyCodeResolver.label(for: event)
            setPressed(true, keyCode: keyCode, key: key)
            record(keyCode: keyCode, key: key)
            return
        }

        guard let flag = KeyCodeResolver.modifierFlag(for: keyCode) else { return }

        if pressedModifierKeyCodes.remove(keyCode) != nil {
            keySoundPlayer.playReleaseUsingPreferences(keyCode: keyCode)
            setPressed(false, keyCode: keyCode)
            return
        }

        // Ignore a release for a modifier that was already held when recording started.
        guard event.modifierFlags.contains(flag) else { return }
        pressedModifierKeyCodes.insert(keyCode)
        let key = KeyCodeResolver.label(for: event)
        setPressed(true, keyCode: keyCode, key: key)
        record(keyCode: keyCode, key: key)
    }

    private func setPressed(_ isPressed: Bool, keyCode: UInt16, key: String? = nil) {
        if isPressed {
            guard let key, pressedKeys[keyCode] != key else { return }
            pressedKeys[keyCode] = key
        } else {
            guard pressedKeys.removeValue(forKey: keyCode) != nil else { return }
        }
        onPressedKeysChanged?(pressedKeys)
    }

    func previewKeySound(style: KeySoundStyle, volume: Double) {
        keySoundPlayer.preview(keyCode: 0, style: style, volume: volume)
    }

    private func record(keyCode: UInt16, key: String, playsSound: Bool = true) {
        if playsSound {
            keySoundPlayer.playUsingPreferences(keyCode: keyCode)
        }
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
