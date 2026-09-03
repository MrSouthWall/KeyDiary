//
//  QuartzKeyboardMonitor.swift
//  KeyDiary
//

import AppKit
import ApplicationServices

/// Passively observes keyboard and primary mouse-button events in the current login session.
@MainActor
final class QuartzKeyboardMonitor {
    private static let systemDefinedEventType = CGEventType(rawValue: 14)!
    private static let hidEventMask: CGEventMask = [
        CGEventType.keyDown,
        CGEventType.keyUp,
        CGEventType.flagsChanged,
        CGEventType.leftMouseDown,
        CGEventType.leftMouseUp,
        CGEventType.rightMouseDown,
        CGEventType.rightMouseUp
    ].reduce(into: CGEventMask(0)) { mask, type in
        mask |= CGEventMask(1) << type.rawValue
    }
    private static let systemEventMask = CGEventMask(1) << systemDefinedEventType.rawValue

    private struct TapState {
        let port: CFMachPort
        let runLoopSource: CFRunLoopSource
    }

    /// Event-tap callbacks run on the run loop that owns their source. Both
    /// sources are installed on the main run loop, so this reference never
    /// crosses threads even though Core Graphics doesn't declare it Sendable.
    private struct MainRunLoopEvent: @unchecked Sendable {
        nonisolated(unsafe) let value: CGEvent

        nonisolated init(value: CGEvent) {
            self.value = value
        }
    }

    private var keyboardTap: TapState?
    private var systemKeyTap: TapState?
    private let onEvent: (NSEvent) -> Void
    private let onReset: () -> Void

    init(
        onEvent: @escaping (NSEvent) -> Void,
        onReset: @escaping () -> Void = {}
    ) {
        self.onEvent = onEvent
        self.onReset = onReset
    }

    var isRunning: Bool {
        guard let keyboardTap else { return false }
        return CGEvent.tapIsEnabled(tap: keyboardTap.port)
    }

    @discardableResult
    func start() -> Bool {
        if isRunning { return true }
        guard CGPreflightListenEventAccess() else { return false }

        // Clean up a stale disabled tap before replacing it.
        stop()

        // cghidEventTap is restricted to root processes. Input Monitoring grants
        // sandboxed apps access to a passive tap at the user-session layer.
        guard let keyboardTap = makeTap(location: .cgSessionEventTap, mask: Self.hidEventMask) else {
            return false
        }
        self.keyboardTap = keyboardTap

        // Brightness and media events are synthesized as NX_SYSDEFINED events at
        // the user-session layer on some keyboards. This tap is supplemental: a
        // failure to create it must not disable ordinary HID keyboard recording.
        systemKeyTap = makeTap(
            location: .cgSessionEventTap,
            mask: Self.systemEventMask
        )
        return true
    }

    func stop() {
        removeTap(keyboardTap)
        removeTap(systemKeyTap)
        keyboardTap = nil
        systemKeyTap = nil
    }

    private func makeTap(location: CGEventTapLocation, mask: CGEventMask) -> TapState? {
        guard let port = CGEvent.tapCreate(
            tap: location,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: Self.eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return nil
        }

        guard let runLoopSource = CFMachPortCreateRunLoopSource(
            kCFAllocatorDefault,
            port,
            0
        ) else {
            CFMachPortInvalidate(port)
            return nil
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        return TapState(port: port, runLoopSource: runLoopSource)
    }

    private func removeTap(_ tap: TapState?) {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap.port, enable: false)
        CFMachPortInvalidate(tap.port)
        CFRunLoopRemoveSource(CFRunLoopGetMain(), tap.runLoopSource, .commonModes)
    }

    private func handle(_ event: CGEvent) {
        guard let appKitEvent = NSEvent(cgEvent: event) else { return }
        onEvent(appKitEvent)
    }

    private func reenableAfterSystemDisable() {
        // A disabled event tap may have missed key-up events. Resetting prevents
        // the real-time keyboard from leaving keys visually stuck down.
        onReset()
        if let keyboardTap {
            CGEvent.tapEnable(tap: keyboardTap.port, enable: true)
        }
        if let systemKeyTap {
            CGEvent.tapEnable(tap: systemKeyTap.port, enable: true)
        }
    }

    private nonisolated static let eventTapCallback: CGEventTapCallBack = {
        _, type, event, context in
        guard let context else { return Unmanaged.passUnretained(event) }
        let monitor = Unmanaged<QuartzKeyboardMonitor>.fromOpaque(context).takeUnretainedValue()
        let mainRunLoopEvent = MainRunLoopEvent(value: event)

        MainActor.assumeIsolated {
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                monitor.reenableAfterSystemDisable()
            } else {
                monitor.handle(mainRunLoopEvent.value)
            }
        }

        // listenOnly taps cannot alter or suppress the original event.
        return Unmanaged.passUnretained(event)
    }
}
