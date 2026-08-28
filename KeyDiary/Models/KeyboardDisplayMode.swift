//
//  KeyboardDisplayMode.swift
//  KeyDiary
//

import Foundation

enum KeyboardDisplayMode: String, CaseIterable, Identifiable {
    case live
    case statistics
    case playback
    case cinema

    var id: Self { self }

    var title: String {
        switch self {
        case .live: "实时"
        case .statistics: "统计"
        case .playback: "回放"
        case .cinema: "像素影院"
        }
    }

    var systemImage: String {
        switch self {
        case .live: "bolt.fill"
        case .statistics: "chart.bar.fill"
        case .playback: "play.fill"
        case .cinema: "film.stack.fill"
        }
    }
}
