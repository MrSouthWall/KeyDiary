//
//  KeyboardRecorder.swift
//  KeyDiary
//

import AppKit
import ApplicationServices

@MainActor
final class KeyboardRecorder {
    private static let capsLockKeyCode: UInt16 = 57
    private static let capsLockFeedbackDuration = Duration.milliseconds(120)

    private let keySoundPlayer = KeySoundPlayer()
    private var pressedKeys: [UInt16: String] = [:]
    private var pressedMouseButtons: Set<MouseButton> = []
    private var pressedModifierKeyCodes: Set<UInt16> = []
    private var capsLockFeedbackTask: Task<Void, Never>?
    private var recordsKeyPresses = false
    private(set) var isCapsLockEnabled = CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift)
    private lazy var quartzKeyboardMonitor = QuartzKeyboardMonitor(
        onEvent: { [weak self] event in
            self?.handleMonitoredEvent(event)
        },
        onReset: { [weak self] in
            self?.resetTransientState()
        }
    )
    var onKeyPress: ((KeyPressRecord) -> Void)?
    var onMouseClick: ((MouseClickRecord) -> Void)?
    var onPressedKeysChanged: (([UInt16: String]) -> Void)?
    var onPressedMouseButtonsChanged: ((Set<MouseButton>) -> Void)?
    var onCapsLockStateChanged: ((Bool) -> Void)?

    var isRunning: Bool { recordsKeyPresses && quartzKeyboardMonitor.isRunning }

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
        refreshCapsLockState()
        guard hasInputMonitoringPermission() else {
            recordsKeyPresses = false
            return
        }
        recordsKeyPresses = true
        if !quartzKeyboardMonitor.start() {
            recordsKeyPresses = false
        }
    }

    /// Pauses diary recording while keeping the passive modifier-state monitor alive.
    func pause() {
        recordsKeyPresses = false
        clearPressedInputs()
        refreshCapsLockState()
    }

    func stop() {
        recordsKeyPresses = false
        quartzKeyboardMonitor.stop()
        clearPressedInputs()
        refreshCapsLockState()
    }

    func refreshCapsLockState() {
        updateCapsLockState(
            CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift)
        )
    }

    private func resetTransientState() {
        clearPressedInputs()
        refreshCapsLockState()
    }

    private func clearPressedInputs() {
        capsLockFeedbackTask?.cancel()
        capsLockFeedbackTask = nil
        pressedModifierKeyCodes.removeAll()
        if !pressedKeys.isEmpty {
            pressedKeys.removeAll()
            onPressedKeysChanged?([:])
        }
        if !pressedMouseButtons.isEmpty {
            pressedMouseButtons.removeAll()
            onPressedMouseButtonsChanged?([])
        }
    }

    private func handleMonitoredEvent(_ event: NSEvent) {
        guard recordsKeyPresses else {
            if event.type == .flagsChanged {
                updateCapsLockState(event.modifierFlags.contains(.capsLock))
            }
            return
        }
        handle(event)
    }

    func handle(_ event: NSEvent) {
        switch event.type {
        case .keyDown:
            guard event.keyCode != Self.capsLockKeyCode else { return }
            let key = KeyCodeResolver.label(for: event)
            setPressed(true, keyCode: event.keyCode, key: key)
            record(keyCode: event.keyCode, key: key, playsSound: !event.isARepeat)

        case .keyUp:
            guard event.keyCode != Self.capsLockKeyCode else { return }
            if pressedKeys[event.keyCode] != nil {
                keySoundPlayer.playReleaseUsingPreferences(keyCode: event.keyCode)
            }
            setPressed(false, keyCode: event.keyCode)

        case .flagsChanged:
            let capsLockIsEnabled = event.modifierFlags.contains(.capsLock)
            if event.keyCode == Self.capsLockKeyCode {
                // Some keyboards emit flagsChanged for both physical transitions.
                // The lock state changes only once, so ignore the same-state partner.
                guard isCapsLockEnabled != capsLockIsEnabled else { return }
                updateCapsLockState(capsLockIsEnabled)
                handleCapsLockPress()
                return
            }
            updateCapsLockState(capsLockIsEnabled)
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

        case .leftMouseDown:
            setMouseButton(.left, pressed: true)
            recordMouseClick(button: .left)

        case .leftMouseUp:
            setMouseButton(.left, pressed: false)

        case .rightMouseDown:
            setMouseButton(.right, pressed: true)
            recordMouseClick(button: .right)

        case .rightMouseUp:
            setMouseButton(.right, pressed: false)

        default:
            break
        }
    }

    private func handleCapsLockPress() {
        capsLockFeedbackTask?.cancel()

        let key = "Caps"
        setPressed(true, keyCode: Self.capsLockKeyCode, key: key)
        record(keyCode: Self.capsLockKeyCode, key: key)

        capsLockFeedbackTask = Task { [weak self] in
            try? await Task.sleep(for: Self.capsLockFeedbackDuration)
            guard !Task.isCancelled, let self else { return }

            self.capsLockFeedbackTask = nil
            guard self.pressedKeys[Self.capsLockKeyCode] != nil else { return }
            self.keySoundPlayer.playReleaseUsingPreferences(keyCode: Self.capsLockKeyCode)
            self.setPressed(false, keyCode: Self.capsLockKeyCode)
        }
    }

    private func handleModifierFlagsChanged(_ event: NSEvent) {
        let keyCode = event.keyCode

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

    private func setMouseButton(_ button: MouseButton, pressed: Bool) {
        let didChange = pressed
            ? pressedMouseButtons.insert(button).inserted
            : pressedMouseButtons.remove(button) != nil
        guard didChange else { return }
        onPressedMouseButtonsChanged?(pressedMouseButtons)
    }

    private func updateCapsLockState(_ isEnabled: Bool) {
        guard isCapsLockEnabled != isEnabled else { return }
        isCapsLockEnabled = isEnabled
        onCapsLockStateChanged?(isEnabled)
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

    private func recordMouseClick(button: MouseButton) {
        let application = NSWorkspace.shared.frontmostApplication
        onMouseClick?(MouseClickRecord(
            timestamp: .now,
            button: button,
            applicationName: application?.localizedName ?? "Unknown app",
            bundleIdentifier: application?.bundleIdentifier
        ))
    }

}
