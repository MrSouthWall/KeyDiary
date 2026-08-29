//
//  AppTheme.swift
//  KeyDiary
//

import AppKit
import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: Self { self }

    var title: String {
        switch self {
        case .system: L10n.text("自动")
        case .light: L10n.text("浅色")
        case .dark: L10n.text("深色")
        }
    }

    var systemImage: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum KeyDiaryTheme {
    static let appearanceStorageKey = "appearance"
    static let accentColorStorageKey = "themeAccentColor"
    static let defaultAccentHex = "#FF9500"

    static func color(for storedHex: String) -> Color {
        let components = rgbComponents(for: storedHex) ?? rgbComponents(for: defaultAccentHex)!
        return Color(
            .sRGB,
            red: components.red,
            green: components.green,
            blue: components.blue,
            opacity: 1
        )
    }

    static func contrastingColor(for storedHex: String) -> Color {
        let components = rgbComponents(for: storedHex) ?? rgbComponents(for: defaultAccentHex)!
        let luminance = 0.2126 * linearized(components.red)
            + 0.7152 * linearized(components.green)
            + 0.0722 * linearized(components.blue)
        return luminance > 0.42 ? .black.opacity(0.78) : .white
    }

    static func hexString(from color: Color) -> String {
        guard let color = NSColor(color).usingColorSpace(.sRGB) else {
            return defaultAccentHex
        }

        let red = Int((color.redComponent * 255).rounded())
        let green = Int((color.greenComponent * 255).rounded())
        let blue = Int((color.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", red, green, blue)
    }

    private static func rgbComponents(for hex: String) -> (red: Double, green: Double, blue: Double)? {
        let normalized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard normalized.count == 6, let value = UInt64(normalized, radix: 16) else { return nil }

        return (
            Double((value >> 16) & 0xFF) / 255,
            Double((value >> 8) & 0xFF) / 255,
            Double(value & 0xFF) / 255
        )
    }

    private static func linearized(_ component: Double) -> Double {
        component <= 0.04045
            ? component / 12.92
            : pow((component + 0.055) / 1.055, 2.4)
    }
}

private struct KeyDiaryAccentColorKey: EnvironmentKey {
    static let defaultValue = KeyDiaryTheme.color(for: KeyDiaryTheme.defaultAccentHex)
}

private struct KeyDiaryAccentContrastColorKey: EnvironmentKey {
    static let defaultValue = KeyDiaryTheme.contrastingColor(for: KeyDiaryTheme.defaultAccentHex)
}

extension EnvironmentValues {
    var keyDiaryAccentColor: Color {
        get { self[KeyDiaryAccentColorKey.self] }
        set { self[KeyDiaryAccentColorKey.self] = newValue }
    }

    var keyDiaryAccentContrastColor: Color {
        get { self[KeyDiaryAccentContrastColorKey.self] }
        set { self[KeyDiaryAccentContrastColorKey.self] = newValue }
    }
}

private struct KeyDiaryThemeModifier: ViewModifier {
    let appearanceRawValue: String
    let accentHex: String

    func body(content: Content) -> some View {
        let appearance = AppAppearance(rawValue: appearanceRawValue) ?? .system
        content
            .keyDiaryAccent(hex: accentHex)
            .preferredColorScheme(appearance.colorScheme)
    }
}

private struct KeyDiaryAccentModifier: ViewModifier {
    let accentHex: String

    func body(content: Content) -> some View {
        let accent = KeyDiaryTheme.color(for: accentHex)
        content
            .tint(accent)
            .environment(\.keyDiaryAccentColor, accent)
            .environment(\.keyDiaryAccentContrastColor, KeyDiaryTheme.contrastingColor(for: accentHex))
    }
}

extension View {
    func keyDiaryTheme(appearanceRawValue: String, accentHex: String) -> some View {
        modifier(KeyDiaryThemeModifier(appearanceRawValue: appearanceRawValue, accentHex: accentHex))
    }

    func keyDiaryAccent(hex: String) -> some View {
        modifier(KeyDiaryAccentModifier(accentHex: hex))
    }
}
