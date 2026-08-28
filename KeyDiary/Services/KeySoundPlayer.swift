//
//  KeySoundPlayer.swift
//  KeyDiary
//

import AVFoundation
import Foundation
import OSLog

/// A polyphonic player for live key feedback.
///
/// Mechanical styles use the recorded kbsim samples bundled with the app, while
/// piano styles remain locally synthesized so rapid combinations can overlap.
@MainActor
final class KeySoundPlayer {
    enum PianoKeyRole: Hashable {
        case frequent
        case supporting
        case accent
        case structural
        case auxiliary
        case performance
        case melody
    }

    struct PianoKeyVoice: Hashable {
        let midiNote: Int
        let role: PianoKeyRole
        let brightness: Double
        let decayRate: Double
        let gain: Double
    }

    private struct PianoBufferKey: Hashable {
        let voice: PianoKeyVoice
        let colorSeed: UInt16
    }

    private struct MechanicalBufferKey: Hashable {
        let style: KeySoundStyle
        let sampleName: String
    }

    private static let sampleRate = 44_100.0
    private static let voiceCount = 12

    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(
        standardFormatWithSampleRate: KeySoundPlayer.sampleRate,
        channels: 1
    )!
    private let logger = Logger(subsystem: "com.MrSouthWall.KeyDiary", category: "KeySound")
    private var voices: [AVAudioPlayerNode] = []
    private var nextVoiceIndex = 0
    private var mechanicalBuffers: [MechanicalBufferKey: AVAudioPCMBuffer] = [:]
    private var unavailableMechanicalBuffers: Set<MechanicalBufferKey> = []
    private var pianoBuffers: [PianoBufferKey: AVAudioPCMBuffer] = [:]
    private var melodyStep = 0
    private var lastPlayedStyle: KeySoundStyle?

    init() {
        for _ in 0..<Self.voiceCount {
            let voice = AVAudioPlayerNode()
            engine.attach(voice)
            engine.connect(voice, to: engine.mainMixerNode, format: format)
            voices.append(voice)
        }

        engine.prepare()
    }

    func playUsingPreferences(keyCode: UInt16) {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: KeySoundPreferences.isEnabledStorageKey) else { return }

        let style = defaults.string(forKey: KeySoundPreferences.styleStorageKey)
            .flatMap(KeySoundStyle.init(rawValue:))
            ?? KeySoundPreferences.defaultStyle
        let volume = defaults.object(forKey: KeySoundPreferences.volumeStorageKey) == nil
            ? KeySoundPreferences.defaultVolume
            : defaults.double(forKey: KeySoundPreferences.volumeStorageKey)

        play(keyCode: keyCode, style: style, volume: volume)
    }

    func play(keyCode: UInt16, style: KeySoundStyle, volume: Double) {
        play(
            keyCode: keyCode,
            style: style,
            volume: volume,
            advancesMelody: true,
            mechanicalPhase: .press
        )
    }

    func preview(keyCode: UInt16, style: KeySoundStyle, volume: Double) {
        play(
            keyCode: keyCode,
            style: style,
            volume: volume,
            advancesMelody: false,
            mechanicalPhase: .press
        )
    }

    func playReleaseUsingPreferences(keyCode: UInt16) {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: KeySoundPreferences.isEnabledStorageKey) else { return }

        let style = defaults.string(forKey: KeySoundPreferences.styleStorageKey)
            .flatMap(KeySoundStyle.init(rawValue:))
            ?? KeySoundPreferences.defaultStyle
        guard style.isMechanical else { return }

        let volume = defaults.object(forKey: KeySoundPreferences.volumeStorageKey) == nil
            ? KeySoundPreferences.defaultVolume
            : defaults.double(forKey: KeySoundPreferences.volumeStorageKey)
        play(
            keyCode: keyCode,
            style: style,
            volume: volume,
            advancesMelody: false,
            mechanicalPhase: .release
        )
    }

    private enum MechanicalPhase: String {
        case press
        case release
    }

    private func play(
        keyCode: UInt16,
        style: KeySoundStyle,
        volume: Double,
        advancesMelody: Bool,
        mechanicalPhase: MechanicalPhase
    ) {
        guard !voices.isEmpty, startEngineIfNeeded() else { return }

        if style != lastPlayedStyle {
            if style == .pianoMelody { melodyStep = 0 }
            lastPlayedStyle = style
        }

        let buffer: AVAudioPCMBuffer?
        let styleGain: Double
        if style.isMechanical {
            buffer = mechanicalBuffer(
                keyCode: keyCode,
                style: style,
                phase: mechanicalPhase
            )
            styleGain = 1
        } else {
            let resolved = resolvePianoVoice(
                keyCode: keyCode,
                style: style,
                advancesMelody: advancesMelody
            )
            let bufferKey = PianoBufferKey(voice: resolved.voice, colorSeed: resolved.colorSeed)
            if let cached = pianoBuffers[bufferKey] {
                buffer = cached
            } else {
                let generated = Self.makePianoBuffer(
                    voice: resolved.voice,
                    colorSeed: resolved.colorSeed,
                    format: format
                )
                pianoBuffers[bufferKey] = generated
                buffer = generated
            }
            styleGain = resolved.voice.gain
        }

        guard let buffer else { return }
        let voice = voices[nextVoiceIndex]
        nextVoiceIndex = (nextVoiceIndex + 1) % voices.count
        voice.stop()
        voice.volume = Float(min(max(volume * styleGain, 0), 1))
        voice.scheduleBuffer(buffer, at: nil, options: .interrupts)
        voice.play()
    }

    static func pianoMIDINote(for keyCode: UInt16) -> Int {
        improvisationPianoVoice(for: keyCode).midiNote
    }

    static func pianoVoice(for keyCode: UInt16) -> PianoKeyVoice {
        improvisationPianoVoice(for: keyCode)
    }

    static func improvisationPianoVoice(for keyCode: UInt16) -> PianoKeyVoice {
        if let voice = pianoVoiceMap[keyCode] { return voice }

        // Unknown and extended keyboards still stay inside C-major pentatonic,
        // so every possible virtual key code remains harmonically compatible.
        let scaleIndex = Int(keyCode) % pentatonicIntervals.count
        let octave = 48 + (Int(keyCode) / pentatonicIntervals.count % 3) * 12
        return PianoKeyVoice(
            midiNote: octave + pentatonicIntervals[scaleIndex],
            role: .auxiliary,
            brightness: 0.96,
            decayRate: 2.55,
            gain: 0.84
        )
    }

    static func keyboardPianoVoice(for keyCode: UInt16) -> PianoKeyVoice {
        if let midiNote = keyboardPianoMap[keyCode] {
            return voice(midiNote, role: .performance)
        }

        // Non-note utility keys resolve to a quiet middle C instead of adding an
        // unexpected chromatic pitch while the user is performing.
        return voice(60, role: .structural)
    }

    static func melodyPianoVoice(at step: Int) -> PianoKeyVoice {
        let normalizedStep = ((step % melodyNotes.count) + melodyNotes.count) % melodyNotes.count
        let base = voice(melodyNotes[normalizedStep], role: .melody)
        let dynamic = melodyDynamics[normalizedStep % melodyDynamics.count]
        return PianoKeyVoice(
            midiNote: base.midiNote,
            role: base.role,
            brightness: base.brightness,
            decayRate: base.decayRate,
            gain: base.gain * dynamic
        )
    }

    private func resolvePianoVoice(
        keyCode: UInt16,
        style: KeySoundStyle,
        advancesMelody: Bool
    ) -> (voice: PianoKeyVoice, colorSeed: UInt16) {
        switch style {
        case .pianoImprovisation:
            return (Self.improvisationPianoVoice(for: keyCode), keyCode)
        case .pianoKeyboard:
            return (Self.keyboardPianoVoice(for: keyCode), keyCode)
        case .pianoMelody:
            let currentStep = melodyStep
            if advancesMelody {
                melodyStep = (melodyStep + 1) % Self.melodyNotes.count
            }
            return (Self.melodyPianoVoice(at: currentStep), UInt16(currentStep))
        case .novelKeysCream, .holyPanda, .alpaca, .turquoiseTealios,
                .gateronBlackInk, .gateronRedInk, .cherryMXBlack,
                .cherryMXBrown, .cherryMXBlue, .kailhBoxNavy,
                .bucklingSpring, .skcmBlueAlps, .topre:
            return (Self.improvisationPianoVoice(for: keyCode), keyCode)
        }
    }

    private func startEngineIfNeeded() -> Bool {
        if engine.isRunning { return true }
        do {
            try engine.start()
            return true
        } catch {
            logger.error("Unable to start key-sound engine: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func mechanicalBuffer(
        keyCode: UInt16,
        style: KeySoundStyle,
        phase: MechanicalPhase
    ) -> AVAudioPCMBuffer? {
        guard let switchName = style.kbsimIdentifier else { return nil }

        let preferredSample = Self.mechanicalSampleName(keyCode: keyCode, phase: phase)
        if let buffer = loadMechanicalBuffer(
            style: style,
            switchName: switchName,
            phase: phase,
            sampleName: preferredSample
        ) {
            return buffer
        }

        let fallbackSample = phase == .press
            ? "GENERIC_R\(Self.mechanicalRow(for: keyCode))"
            : "GENERIC"
        guard fallbackSample != preferredSample else { return nil }
        return loadMechanicalBuffer(
            style: style,
            switchName: switchName,
            phase: phase,
            sampleName: fallbackSample
        )
    }

    private func loadMechanicalBuffer(
        style: KeySoundStyle,
        switchName: String,
        phase: MechanicalPhase,
        sampleName: String
    ) -> AVAudioPCMBuffer? {
        let key = MechanicalBufferKey(
            style: style,
            sampleName: "\(phase.rawValue)_\(sampleName)"
        )
        if let cached = mechanicalBuffers[key] { return cached }
        if unavailableMechanicalBuffers.contains(key) { return nil }

        let resourceName = "\(switchName)_\(phase.rawValue)_\(sampleName)"
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "mp3") else {
            unavailableMechanicalBuffers.insert(key)
            logger.error("Missing kbsim sample: \(resourceName, privacy: .public).mp3")
            return nil
        }

        do {
            let file = try AVAudioFile(forReading: url)
            let frameCapacity = AVAudioFrameCount(file.length)
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: frameCapacity
            ) else {
                unavailableMechanicalBuffers.insert(key)
                return nil
            }
            try file.read(into: buffer)
            mechanicalBuffers[key] = buffer
            return buffer
        } catch {
            unavailableMechanicalBuffers.insert(key)
            logger.error(
                "Unable to load kbsim sample \(resourceName, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    static func mechanicalSampleName(keyCode: UInt16, isRelease: Bool) -> String {
        mechanicalSampleName(keyCode: keyCode, phase: isRelease ? .release : .press)
    }

    private static func mechanicalSampleName(
        keyCode: UInt16,
        phase: MechanicalPhase
    ) -> String {
        switch keyCode {
        case 49:
            return "SPACE"
        case 36, 76:
            return "ENTER"
        case 51, 117:
            return "BACKSPACE"
        default:
            return phase == .press ? "GENERIC_R\(mechanicalRow(for: keyCode))" : "GENERIC"
        }
    }

    static func mechanicalRow(for keyCode: UInt16) -> Int {
        switch keyCode {
        case 53, 64, 79, 80, 90, 96, 97, 98, 99, 100, 101, 103,
                105, 106, 107, 109, 111, 113, 114, 115, 116, 118, 119,
                120, 121, 122:
            0
        case 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 50, 51:
            1
        case 12, 13, 14, 15, 16, 17, 30, 31, 32, 33, 34, 35, 42, 48, 117:
            2
        case 0, 1, 2, 3, 4, 5, 36, 37, 38, 39, 40, 41, 57:
            3
        default:
            4
        }
    }

    private static func makePianoBuffer(
        voice: PianoKeyVoice,
        colorSeed: UInt16,
        format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let duration = 1.2
        let frameCount = AVAudioFrameCount(duration * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let samples = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frameCount

        let frequency = 440.0 * pow(2.0, Double(voice.midiNote - 69) / 12.0)
        var generator = SeededNoise(seed: UInt64(0xC0FFEE + Int(colorSeed) * 1_009))
        let keyColor = 0.94 + Double(colorSeed % 7) * 0.018

        for frame in 0..<Int(frameCount) {
            let time = Double(frame) / sampleRate
            let attack = min(time / 0.0045, 1)
            let release = exp(-time * (voice.decayRate + frequency / 2_400.0))
            let fundamental = sin(2 * .pi * frequency * time) * 0.66
            let second = sin(2 * .pi * frequency * 2.006 * time + 0.18)
                * 0.22 * voice.brightness * exp(-time * 0.7)
            let third = sin(2 * .pi * frequency * 3.018 * time + 0.4)
                * 0.11 * voice.brightness * keyColor * exp(-time * 1.25)
            let fourth = sin(2 * .pi * frequency * 4.04 * time + 0.62)
                * 0.055 * voice.brightness * keyColor * exp(-time * 1.9)
            let hammer = generator.next() * exp(-time * 145.0) * 0.12
            let mixed = (fundamental + second + third + fourth + hammer) * attack * release
            samples[frame] = Float(tanh(mixed * 1.12) * 0.72)
        }
        return buffer
    }

    private static let pentatonicIntervals = [0, 2, 4, 7, 9]

    private static func voice(
        _ midiNote: Int,
        role: PianoKeyRole
    ) -> PianoKeyVoice {
        switch role {
        case .frequent:
            PianoKeyVoice(midiNote: midiNote, role: role, brightness: 0.84, decayRate: 3.2, gain: 0.76)
        case .supporting:
            PianoKeyVoice(midiNote: midiNote, role: role, brightness: 0.94, decayRate: 2.85, gain: 0.84)
        case .accent:
            PianoKeyVoice(midiNote: midiNote, role: role, brightness: 1.1, decayRate: 2.35, gain: 0.92)
        case .structural:
            PianoKeyVoice(midiNote: midiNote, role: role, brightness: 0.72, decayRate: 3.45, gain: 0.68)
        case .auxiliary:
            PianoKeyVoice(midiNote: midiNote, role: role, brightness: 0.96, decayRate: 2.55, gain: 0.84)
        case .performance:
            PianoKeyVoice(midiNote: midiNote, role: role, brightness: 1.02, decayRate: 2.4, gain: 0.86)
        case .melody:
            PianoKeyVoice(midiNote: midiNote, role: role, brightness: 0.92, decayRate: 2.7, gain: 0.84)
        }
    }

    private static let pianoVoiceMap: [UInt16: PianoKeyVoice] = [
        // High-frequency English and pinyin letters stay in one central
        // pentatonic register. Their shorter, softer voices keep prose musical
        // instead of turning fast typing into a dense wall of sound.
        14: voice(64, role: .frequent), // E
        17: voice(67, role: .frequent), // T
        0: voice(60, role: .frequent),  // A
        31: voice(69, role: .frequent), // O
        34: voice(62, role: .frequent), // I
        45: voice(67, role: .frequent), // N
        1: voice(62, role: .frequent),  // S
        4: voice(64, role: .frequent),  // H
        15: voice(60, role: .frequent), // R
        2: voice(69, role: .frequent),  // D
        37: voice(67, role: .frequent), // L
        32: voice(64, role: .frequent), // U
        5: voice(62, role: .frequent),  // G

        // Medium-frequency letters fill out nearby chord tones without leaving
        // the scale. This set also covers common pinyin initials and finals.
        8: voice(64, role: .supporting),  // C
        46: voice(60, role: .supporting), // M
        3: voice(67, role: .supporting),  // F
        35: voice(62, role: .supporting), // P
        11: voice(69, role: .supporting), // B
        16: voice(69, role: .supporting), // Y
        13: voice(60, role: .supporting), // W
        40: voice(64, role: .supporting), // K
        9: voice(72, role: .supporting),  // V

        // Rare letters become occasional upper-register highlights.
        12: voice(76, role: .accent), // Q
        38: voice(74, role: .accent), // J
        7: voice(79, role: .accent),  // X
        6: voice(81, role: .accent),  // Z

        // Word and sentence boundaries act like bass punctuation and cadences.
        49: voice(48, role: .structural), // Space: C3
        36: voice(43, role: .structural), // Return: G2
        76: voice(43, role: .structural), // Keypad Enter: G2
        48: voice(52, role: .structural), // Tab: E3
        51: voice(50, role: .structural), // Delete: D3
        117: voice(50, role: .structural), // Forward Delete: D3
        53: voice(45, role: .structural), // Escape: A2

        // Modifiers create a compatible bass layer when held with a letter.
        54: voice(48, role: .structural), 55: voice(48, role: .structural), // Command
        56: voice(55, role: .structural), 60: voice(55, role: .structural), // Shift
        58: voice(57, role: .structural), 61: voice(57, role: .structural), // Option
        59: voice(52, role: .structural), 62: voice(52, role: .structural), // Control
        57: voice(60, role: .structural), 63: voice(50, role: .structural), // Caps / Fn

        // Punctuation supplies phrase-ending color in the upper register.
        41: voice(74, role: .accent), 39: voice(81, role: .accent), // ; '
        43: voice(72, role: .accent), 47: voice(76, role: .accent), 44: voice(79, role: .accent), // , . /
        33: voice(76, role: .accent), 30: voice(79, role: .accent), 42: voice(72, role: .accent), // [ ] \
        50: voice(67, role: .accent), 27: voice(69, role: .accent), 24: voice(72, role: .accent), // ` - =

        // Number row climbs through two octaves of the same pentatonic scale.
        18: voice(72, role: .auxiliary), 19: voice(74, role: .auxiliary),
        20: voice(76, role: .auxiliary), 21: voice(79, role: .auxiliary),
        23: voice(81, role: .auxiliary), 22: voice(84, role: .auxiliary),
        26: voice(86, role: .auxiliary), 28: voice(88, role: .auxiliary),
        25: voice(91, role: .auxiliary), 29: voice(93, role: .auxiliary),

        // Navigation keys form a small consonant answering phrase.
        123: voice(55, role: .auxiliary), 124: voice(57, role: .auxiliary),
        125: voice(60, role: .auxiliary), 126: voice(62, role: .auxiliary)
    ]

    /// A familiar two-row virtual-piano layout. The lower row starts at C3 and
    /// the upper row starts at C4; the interleaved keys provide the black notes.
    private static let keyboardPianoMap: [UInt16: Int] = [
        // Lower manual: Z S X D C V G B H N J M , L . ; /
        6: 48, 1: 49, 7: 50, 2: 51, 8: 52,
        9: 53, 5: 54, 11: 55, 4: 56, 45: 57,
        38: 58, 46: 59, 43: 60, 37: 61, 47: 62,
        41: 63, 44: 64,

        // Upper manual: Q 2 W 3 E R 5 T 6 Y 7 U I 9 O 0 P [ ] \
        12: 60, 19: 61, 13: 62, 20: 63, 14: 64,
        15: 65, 23: 66, 17: 67, 22: 68, 16: 69,
        26: 70, 32: 71, 34: 72, 25: 73, 31: 74,
        29: 75, 35: 76, 33: 77, 30: 78, 42: 79,

        // Phrase and navigation keys remain useful notes when performing.
        49: 48, 48: 55, 36: 60, 76: 60,
        123: 48, 124: 50, 125: 52, 126: 53
    ]

    /// A composed, looping phrase. Key identity is deliberately ignored in this
    /// mode: every press advances one step, making arbitrary typing sound like a
    /// coherent performance while timing and rhythm still belong to the user.
    private static let melodyNotes = [
        60, 64, 67, 69, 67, 64, 62, 64,
        67, 69, 72, 69, 67, 64, 62, 60,
        64, 67, 69, 72, 74, 72, 69, 67,
        64, 62, 60, 62, 64, 67, 64, 62,
        60, 64, 67, 72, 69, 67, 64, 69,
        67, 64, 62, 67, 64, 62, 60, 60
    ]

    private static let melodyDynamics = [0.82, 0.7, 0.76, 0.9, 0.78, 0.72, 0.76, 0.86]
}

private struct SeededNoise {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 1 : seed
    }

    mutating func next() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1
        let unit = Double((state >> 33) & 0x7FFF_FFFF) / Double(0x7FFF_FFFF)
        return unit * 2 - 1
    }
}
