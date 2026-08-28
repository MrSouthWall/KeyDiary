//
//  KeySoundStyle.swift
//  KeyDiary
//

import Foundation

enum KeySoundStyle: String, CaseIterable, Identifiable, Sendable {
    case novelKeysCream
    case holyPanda
    case alpaca
    case turquoiseTealios
    case gateronBlackInk
    case gateronRedInk = "mechanicalRed"
    case cherryMXBlack
    case cherryMXBrown = "physicalKeyboard"
    case cherryMXBlue = "mechanicalBlue"
    case kailhBoxNavy
    case bucklingSpring
    case skcmBlueAlps
    case topre
    case pianoImprovisation = "piano"
    case pianoKeyboard
    case pianoMelody

    var id: Self { self }

    var title: String {
        switch self {
        case .novelKeysCream: "奶油轴"
        case .holyPanda: "圣熊猫轴"
        case .alpaca: "羊驼轴"
        case .turquoiseTealios: "绿松石轴"
        case .gateronBlackInk: "佳达隆黑墨水轴"
        case .gateronRedInk: "佳达隆红墨水轴"
        case .cherryMXBlack: "樱桃黑轴"
        case .cherryMXBrown: "樱桃茶轴"
        case .cherryMXBlue: "樱桃青轴"
        case .kailhBoxNavy: "凯华海军蓝轴"
        case .bucklingSpring: "屈曲弹簧"
        case .skcmBlueAlps: "阿尔卑斯蓝轴"
        case .topre: "东普雷静电容"
        case .pianoImprovisation: "钢琴 · 即兴演奏"
        case .pianoKeyboard: "钢琴 · 键盘演奏"
        case .pianoMelody: "钢琴 · 自动旋律"
        }
    }

    var systemImage: String {
        isMechanical ? "keyboard" : "pianokeys"
    }

    var detail: String {
        switch self {
        case .novelKeysCream: "线性轴体的顺滑、饱满录音采样。"
        case .holyPanda: "突出段落反馈的厚实录音采样。"
        case .alpaca: "轻柔、干净的线性轴录音采样。"
        case .turquoiseTealios: "清亮顺滑的线性轴录音采样。"
        case .gateronBlackInk: "低沉、扎实的线性轴录音采样。"
        case .gateronRedInk: "轻快、清晰的线性轴录音采样。"
        case .cherryMXBlack: "沉稳的 Cherry 线性轴录音采样。"
        case .cherryMXBrown: "带适度段落感的 Cherry 轴录音采样。"
        case .cherryMXBlue: "清脆鲜明的 Cherry 点击轴录音采样。"
        case .kailhBoxNavy: "反馈强烈的 BOX 点击轴录音采样。"
        case .bucklingSpring: "经典屈曲弹簧键盘的响亮录音采样。"
        case .skcmBlueAlps: "复古 Alps 点击轴的清脆录音采样。"
        case .topre: "柔和而深沉的静电容键盘录音采样。"
        case .pianoImprovisation: "按使用频率编排五声音阶，正常打字也能形成旋律。"
        case .pianoKeyboard: "使用常见虚拟钢琴布局，可按键位主动演奏半音阶。"
        case .pianoMelody: "每次按键推进一段预设旋律，无需记住任何琴键。"
        }
    }

    var isMechanical: Bool { kbsimIdentifier != nil }

    var kbsimIdentifier: String? {
        switch self {
        case .novelKeysCream: "cream"
        case .holyPanda: "holypanda"
        case .alpaca: "alpaca"
        case .turquoiseTealios: "turquoise"
        case .gateronBlackInk: "blackink"
        case .gateronRedInk: "redink"
        case .cherryMXBlack: "mxblack"
        case .cherryMXBrown: "mxbrown"
        case .cherryMXBlue: "mxblue"
        case .kailhBoxNavy: "boxnavy"
        case .bucklingSpring: "buckling"
        case .skcmBlueAlps: "bluealps"
        case .topre: "topre"
        case .pianoImprovisation, .pianoKeyboard, .pianoMelody: nil
        }
    }

    var usageHint: String? {
        switch self {
        case .pianoKeyboard:
            "低音区：Z S X D C V G B H N J M　高音区：Q 2 W 3 E R 5 T 6 Y 7 U I"
        case .pianoMelody:
            "任意按键都会推进旋律；输入速度决定节奏。"
        default:
            nil
        }
    }

    static let mechanicalStyles: [KeySoundStyle] = [
        .novelKeysCream,
        .holyPanda,
        .alpaca,
        .turquoiseTealios,
        .gateronBlackInk,
        .gateronRedInk,
        .cherryMXBlack,
        .cherryMXBrown,
        .cherryMXBlue,
        .kailhBoxNavy,
        .bucklingSpring,
        .skcmBlueAlps,
        .topre
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

    static let defaultStyle = KeySoundStyle.cherryMXBrown
    static let defaultVolume = 0.55
}

nonisolated struct KeySoundConfiguration: Equatable, Sendable {
    let isEnabled: Bool
    let style: KeySoundStyle
    let volume: Double

    @MainActor
    static var current: Self {
        let defaults = UserDefaults.standard
        let style = defaults.string(forKey: KeySoundPreferences.styleStorageKey)
            .flatMap(KeySoundStyle.init(rawValue:))
            ?? KeySoundPreferences.defaultStyle
        let volume = defaults.object(forKey: KeySoundPreferences.volumeStorageKey) == nil
            ? KeySoundPreferences.defaultVolume
            : defaults.double(forKey: KeySoundPreferences.volumeStorageKey)
        return Self(
            isEnabled: defaults.bool(forKey: KeySoundPreferences.isEnabledStorageKey),
            style: style,
            volume: min(max(volume, 0), 1)
        )
    }
}
