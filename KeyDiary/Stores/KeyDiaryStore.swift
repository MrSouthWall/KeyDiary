//
//  KeyDiaryStore.swift
//  KeyDiary
//

import AppKit
import Foundation
import Observation
import OSLog
import SwiftUI

@MainActor
@Observable
final class KeyDiaryStore {
    enum DateRangeSelection: Equatable, Sendable {
        case recentDays(Int)
        case all
        case custom
    }

    private let recorder = KeyboardRecorder()
    private let archive: KeyPressArchive
    private var playbackTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var dayRolloverTask: Task<Void, Never>?
    private var rangeSelection: DateRangeSelection = .recentDays(7)
    private var currentDayStart: Date
    private var wantsRecording = true

    private(set) var records: [KeyPressRecord]
    private(set) var filteredRecords: [KeyPressRecord] = []
    private(set) var filteredKeyCounts: [UInt16: Int] = [:]
    private(set) var pressesToday = 0
    private(set) var applications: [String] = ["All apps"]
    private(set) var isRecording = false
    private(set) var hasInputMonitoringPermission = false
    private(set) var isPlaying = false
    private(set) var activePlaybackKey: String?
    private(set) var activePlaybackKeyCode: UInt16?

    var playbackSpeed = 1.0
    private(set) var fromDate: Date
    private(set) var toDate: Date
    var selectedApplication = "All apps" {
        didSet {
            guard selectedApplication != oldValue else { return }
            rebuildFilteredRecords()
        }
    }

    init(archive: KeyPressArchive = KeyPressArchive(), now: Date = .now) {
        self.archive = archive
        records = archive.load()

        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: now)
        currentDayStart = dayStart
        fromDate = calendar.date(byAdding: .day, value: -6, to: dayStart) ?? dayStart
        toDate = Self.endOfDay(containing: now, calendar: calendar)

        recorder.onKeyPress = { [weak self] record in
            self?.append(record)
        }

        rebuildDerivedState(now: now)
        scheduleDayRollover(from: now)
    }

    func refreshInputMonitoringStatus() {
        hasInputMonitoringPermission = recorder.hasInputMonitoringPermission()
        if !hasInputMonitoringPermission {
            stopRecorderAndFlush()
        }
    }

    func requestAccessAndStart() {
        wantsRecording = true
        if !recorder.requestInputMonitoringPermission() {
            recorder.openInputMonitoringSettings()
        }
        resumeAutomaticRecordingIfPossible()
    }

    func startRecording() {
        wantsRecording = true
        startRecorderIfPossible()
    }

    func resumeAutomaticRecordingIfPossible() {
        refreshInputMonitoringStatus()
        if wantsRecording {
            startRecorderIfPossible()
        }
    }

    func stopRecording() {
        wantsRecording = false
        stopRecorderAndFlush()
    }

    private func startRecorderIfPossible() {
        guard hasInputMonitoringPermission else { return }
        recorder.start()
        isRecording = recorder.isRunning
    }

    private func stopRecorderAndFlush() {
        recorder.stop()
        isRecording = false
        flushPersistence()
    }

    func prepareForTermination() {
        recorder.stop()
        saveTask?.cancel()
        saveTask = nil
        archive.flush(records)
    }

    func clearAllRecords() {
        stopPlayback()
        saveTask?.cancel()
        saveTask = nil
        records.removeAll(keepingCapacity: false)
        selectedApplication = "All apps"
        rebuildDerivedState()
        archive.flush(records)
    }

    func selectRecentDays(_ dayCount: Int, now: Date = .now) {
        rangeSelection = .recentDays(max(dayCount, 1))
        applyRollingDateRange(now: now)
    }

    func selectAllRecords(now: Date = .now) {
        rangeSelection = .all
        fromDate = records.map(\.timestamp).min() ?? now
        toDate = Self.endOfDay(containing: now)
        rebuildFilteredRecords()
    }

    func selectCustomRange(from: Date, to: Date) {
        rangeSelection = .custom
        fromDate = min(from, to)
        toDate = max(from, to)
        rebuildFilteredRecords()
    }

    func refreshDateDependentState(now: Date = .now) {
        let calendar = Calendar.current
        let newDayStart = calendar.startOfDay(for: now)
        guard newDayStart != currentDayStart else { return }

        currentDayStart = newDayStart
        switch rangeSelection {
        case .recentDays:
            applyRollingDateRange(now: now)
        case .all:
            toDate = Self.endOfDay(containing: now, calendar: calendar)
            rebuildFilteredRecords()
        case .custom:
            break
        }
        rebuildTodayCount(now: now)
        scheduleDayRollover(from: now)
    }

    func playFilteredRecords() {
        let replay = filteredRecords.sorted { $0.timestamp < $1.timestamp }
        guard !replay.isEmpty else { return }

        stopPlayback()
        isPlaying = true
        playbackTask = Task { [weak self] in
            guard let self else { return }
            var previous = replay[0].timestamp
            for record in replay {
                guard !Task.isCancelled else { return }
                let naturalGap = record.timestamp.timeIntervalSince(previous) / self.playbackSpeed
                let delay = min(max(naturalGap, 0.06), 0.65)
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.18, dampingFraction: 0.62)) {
                    self.activePlaybackKey = record.key
                    self.activePlaybackKeyCode = record.keyCode
                }
                previous = record.timestamp
            }
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.14)) {
                self.activePlaybackKey = nil
                self.activePlaybackKeyCode = nil
            }
            self.isPlaying = false
        }
    }

    func stopPlayback() {
        playbackTask?.cancel()
        playbackTask = nil
        isPlaying = false
        activePlaybackKey = nil
        activePlaybackKeyCode = nil
    }

    private func append(_ record: KeyPressRecord) {
        refreshDateDependentState(now: record.timestamp)
        records.append(record)

        let overflow = records.count - 100_000
        if overflow > 0 {
            records.removeFirst(overflow)
            rebuildDerivedState(now: record.timestamp)
        } else {
            addToDerivedState(record, now: record.timestamp)
        }
        scheduleSave()
    }

    private func addToDerivedState(_ record: KeyPressRecord, now: Date) {
        if !applications.contains(record.applicationName) {
            applications.append(record.applicationName)
            applications.sort {
                if $0 == "All apps" { return true }
                if $1 == "All apps" { return false }
                return $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
            }
        }

        let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: currentDayStart) ?? now
        if record.timestamp >= currentDayStart && record.timestamp < nextDay {
            pressesToday += 1
        }

        guard matchesCurrentFilter(record) else { return }
        filteredRecords.append(record)
        filteredKeyCounts[record.keyCode, default: 0] += 1
    }

    private func rebuildDerivedState(now: Date = .now) {
        applications = ["All apps"] + Array(Set(records.map(\.applicationName))).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
        if !applications.contains(selectedApplication) {
            selectedApplication = "All apps"
        }
        rebuildTodayCount(now: now)
        rebuildFilteredRecords()
    }

    private func rebuildTodayCount(now: Date) {
        let calendar = Calendar.current
        currentDayStart = calendar.startOfDay(for: now)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: currentDayStart) ?? .distantFuture
        pressesToday = records.lazy.filter {
            $0.timestamp >= self.currentDayStart && $0.timestamp < nextDay
        }.count
    }

    private func rebuildFilteredRecords() {
        filteredRecords = records.filter(matchesCurrentFilter)
        filteredKeyCounts = filteredRecords.reduce(into: [:]) { counts, record in
            counts[record.keyCode, default: 0] += 1
        }
    }

    private func matchesCurrentFilter(_ record: KeyPressRecord) -> Bool {
        record.timestamp >= fromDate &&
        record.timestamp <= toDate &&
        (selectedApplication == "All apps" || record.applicationName == selectedApplication)
    }

    private func applyRollingDateRange(now: Date) {
        guard case .recentDays(let dayCount) = rangeSelection else { return }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        fromDate = calendar.date(byAdding: .day, value: -(dayCount - 1), to: today) ?? today
        toDate = Self.endOfDay(containing: now, calendar: calendar)
        rebuildFilteredRecords()
    }

    private func scheduleSave() {
        // Throttle rather than debounce: continuous typing still reaches disk twice
        // per second, while rapid bursts are coalesced into one snapshot.
        guard saveTask == nil else { return }
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled, let self else { return }
            let snapshot = self.records
            self.saveTask = nil
            self.archive.save(snapshot)
        }
    }

    private func flushPersistence() {
        saveTask?.cancel()
        saveTask = nil
        archive.flush(records)
    }

    private func scheduleDayRollover(from now: Date) {
        dayRolloverTask?.cancel()
        let calendar = Calendar.current
        let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(86_400)
        let nanoseconds = UInt64(max(nextDay.timeIntervalSince(now), 1) * 1_000_000_000)
        dayRolloverTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            self?.refreshDateDependentState()
        }
    }

    private static func endOfDay(containing date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))?
            .addingTimeInterval(-1) ?? date
    }
}

final class KeyPressArchive: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.MrSouthWall.KeyDiary.archive", qos: .utility)
    private let fileURL: URL
    private let logger = Logger(subsystem: "com.MrSouthWall.KeyDiary", category: "Persistence")

    nonisolated init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("KeyDiary", isDirectory: true)
            self.fileURL = folder.appendingPathComponent("key-presses.json")
        }
    }

    nonisolated func load() -> [KeyPressRecord] {
        queue.sync {
            guard let data = try? Data(contentsOf: fileURL) else { return [] }
            do {
                return try JSONDecoder().decode([KeyPressRecord].self, from: data)
            } catch {
                logger.error("Unable to decode key press archive: \(error.localizedDescription, privacy: .public)")
                return []
            }
        }
    }

    nonisolated func save(_ records: [KeyPressRecord]) {
        queue.async { [self] in
            write(records)
        }
    }

    nonisolated func flush(_ records: [KeyPressRecord]) {
        queue.sync { [self] in
            write(records)
        }
    }

    private nonisolated func write(_ records: [KeyPressRecord]) {
        do {
            let data = try JSONEncoder().encode(records)
            let folder = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: folder,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try data.write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            logger.error("Unable to save key press archive: \(error.localizedDescription, privacy: .public)")
        }
    }
}
