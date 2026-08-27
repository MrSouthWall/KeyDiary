//
//  PlaybackTiming.swift
//  KeyDiary
//

import Foundation

nonisolated enum PlaybackTiming {
    static let speedRange = 1.0...16.0
    static let speedPresets = [1.0, 2.0, 4.0, 8.0, 16.0]

    static let minimumGap: TimeInterval = 0.06
    static let maximumGap: TimeInterval = 0.65
    static let finalKeyHold: TimeInterval = 0.18

    static func delay(from previous: Date, to current: Date, speed: Double) -> TimeInterval {
        let naturalGap = current.timeIntervalSince(previous)
        let boundedGap = min(max(naturalGap, minimumGap), maximumGap)
        return boundedGap / normalized(speed)
    }

    static func finalKeyHold(at speed: Double) -> TimeInterval {
        finalKeyHold / normalized(speed)
    }

    private static func normalized(_ speed: Double) -> Double {
        max(speed, 0.01)
    }
}
