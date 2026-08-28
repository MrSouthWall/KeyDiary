//
//  KeySoundStyle.swift
//  KeyDiary
//

import Foundation

enum KeySoundStyle: String, CaseIterable, Identifiable {
    case mechanicalRed
    case mechanicalBrown = "physicalKeyboard"
    case mechanicalBlue
    case pianoImprovisation = "piano"
    case pianoKeyboard
    case pianoMelody

    var id: Self { self }

    var title: String {
        switch self {
        case .mechanicalRed: "机械键盘 · 红轴"
        case .mechanicalBrown: "机械键盘 · 茶轴"
        case .mechanicalBlue: "机械键盘 · 青轴"
        case .pianoImprovisation: "钢琴 · 即兴演奏"
        case .pianoKeyboard: "钢琴 · 键盘演奏"
        case .pianoMelody: "钢琴 · 自动旋律"
        }
    }

    var systemImage: String {
        switch self {
        case .mechanicalRed, .mechanicalBrown, .mechanicalBlue: "keyboard"
        case .pianoImprovisation, .pianoKeyboard, .pianoMelody: "pianokeys"
        }
    }

    var detail: String {
        switch self {
        case .mechanicalRed: "线性、轻快而克制，适合长时间输入。"
        case .mechanicalBrown: "带适度段落感，兼顾清晰反馈与安静。"
        case .mechanicalBlue: "清脆的触发声与回弹声，机械感最鲜明。"
        case .pianoImprovisation: "按使用频率编排五声音阶，正常打字也能形成旋律。"
        case .pianoKeyboard: "使用常见虚拟钢琴布局，可按键位主动演奏半音阶。"
        case .pianoMelody: "每次按键推进一段预设旋律，无需记住任何琴键。"
        }
    }

    var isMechanical: Bool {
        switch self {
        case .mechanicalRed, .mechanicalBrown, .mechanicalBlue: true
        case .pianoImprovisation, .pianoKeyboard, .pianoMelody: false
        }
    }

    var usageHint: String? {
        switch self {
        case .pianoKeyboard:
            "低音区：Z S X D C V G B H N J M　高音区：Q 2 W 3 E R 5 T 6 Y 7 U I"
        case .pianoMelody:
            "任意按键都会推进旋律；输入速度决定节奏。"
        case .mechanicalRed, .mechanicalBrown, .mechanicalBlue, .pianoImprovisation:
            nil
        }
    }

    static let mechanicalStyles: [KeySoundStyle] = [
        .mechanicalRed,
        .mechanicalBrown,
        .mechanicalBlue
    ]

    static let pianoStyles: [KeySoundStyle] = [
        .pianoImprovisation,
        .pianoKeyboard,
        .pianoMelody
    ]
}

enum KeySoundPreferences {
    static let isEnabledStorageKey = "keySound.isEnabled"
    static let styleStorageKey = "keySound.style"
    static let volumeStorageKey = "keySound.volume"

    static let defaultStyle = KeySoundStyle.mechanicalBrown
    static let defaultVolume = 0.55
}
