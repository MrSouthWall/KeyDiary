//
//  LaunchAtLoginController.swift
//  KeyDiary
//

import Observation
import ServiceManagement

@MainActor
@Observable
final class LaunchAtLoginController {
    private static let automaticRegistrationAttemptedKey =
        "launchAtLogin.automaticRegistrationAttempted"

    private let service = SMAppService.mainApp

    private(set) var status: SMAppService.Status
    private(set) var errorMessage: String?

    init() {
        status = service.status
    }

    var isEnabled: Bool {
        status == .enabled
    }

    var requiresApproval: Bool {
        status == .requiresApproval
    }

    func registerOnFirstLaunchIfNeeded(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: Self.automaticRegistrationAttemptedKey) else {
            refresh()
            return
        }

        defaults.set(true, forKey: Self.automaticRegistrationAttemptedKey)
        refresh()

        guard Self.canAttemptRegistration(from: status) else { return }
        updateRegistration(shouldEnable: true)
    }

    func setEnabled(_ shouldEnable: Bool) {
        refresh()

        if shouldEnable, status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
            return
        }

        updateRegistration(shouldEnable: shouldEnable)
    }

    func refresh() {
        status = service.status
        if status == .enabled {
            errorMessage = nil
        }
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private func updateRegistration(shouldEnable: Bool) {
        errorMessage = nil

        do {
            if shouldEnable {
                guard Self.canAttemptRegistration(from: status) else { return }
                try service.register()
            } else {
                guard status == .enabled || status == .requiresApproval else { return }
                try service.unregister()
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        refresh()
    }

    static func canAttemptRegistration(from status: SMAppService.Status) -> Bool {
        // macOS 26 can report `notFound` before the main app has its first
        // Background Task Management record. Registering creates that record.
        status == .notRegistered || status == .notFound
    }
}
