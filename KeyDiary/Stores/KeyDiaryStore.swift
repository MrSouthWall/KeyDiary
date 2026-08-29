//
//  KeyDiaryStore.swift
//  KeyDiary
//

import AppKit
import Foundation
import Observation
import OSLog
import SwiftUI

struct DataTransferNotice: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
}

@MainActor
@Observable
final class KeyDiaryStore {
    enum DateRangeSelection: Equatable, Sendable {
        case recentDays(Int)
        case all
        case custom
    }

    private let recorder = KeyboardRecorder()
    private let playbackKeySoundPlayer = KeySoundPlayer()
    private let database: KeyDiaryDatabase
    private let dataTransferService = DataTransferService()
    private let playbackVideoExporter = PlaybackVideoExporter()
    private let logger = Logger(subsystem: "com.MrSouthWall.KeyDiary", category: "Store")
    private var playbackTask: Task<Void, Never>?
    private var playbackVideoExportTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var dayRolloverTask: Task<Void, Never>?
    private var pendingRecords: [KeyPressRecord] = []
    private var rangeSelection: DateRangeSelection = .recentDays(1)
    private var currentDayStart: Date
    private var lastFilteredTimestamp: Date?
    private var wantsRecording = true

    private(set) var recordCount = 0
    private(set) var filteredRecordCount = 0
    private(set) var filteredKeyCounts: [UInt16: Int] = [:]
    private(set) var pressesToday = 0
    private(set) var applications: [String] = ["All apps"]
    private(set) var isRecording = false
    private(set) var hasInputMonitoringPermission = false
    private(set) var activeLiveKeys: [UInt16: String] = [:]
    private(set) var isPlaying = false
    private(set) var activePlaybackKey: String?
    private(set) var activePlaybackKeyCode: UInt16?
    private(set) var isDataTransferInProgress = false
    private(set) var isPlaybackVideoExportInProgress = false
    private(set) var playbackVideoExportProgress = 0.0
    private(set) var playbackRecordCount = 0
    private(set) var playbackTimelineStart: Date?
    private(set) var playbackTimelineEnd: Date?
    private(set) var playbackSelectionStart: Date?
    private(set) var playbackSelectionEnd: Date?
    var dataTransferNotice: DataTransferNotice?

    var playbackSpeed = 1.0 {
        didSet {
            guard playbackSpeed != oldValue else { return }
            rebuildEstimatedPlaybackDuration()
        }
    }
    private(set) var estimatedPlaybackDuration: TimeInterval = 0
    private(set) var fromDate: Date
    private(set) var toDate: Date
    var selectedApplication = "All apps" {
        didSet {
            guard selectedApplication != oldValue else { return }
            rebuildFilteredState()
        }
    }

    var selectedDateRangeTitle: String {
        switch rangeSelection {
        case .recentDays(1):
            return L10n.text("今天")
        case .recentDays(let dayCount):
            return L10n.format("近 %lld 天", Int64(dayCount))
        case .all:
            return L10n.text("全部时间")
        case .custom:
            let start = fromDate.formatted(.dateTime.month().day())
            let end = toDate.formatted(.dateTime.month().day())
            return Calendar.current.isDate(fromDate, inSameDayAs: toDate)
                ? start
                : "\(start)–\(end)"
        }
    }

    var selectedDateRangeSelection: DateRangeSelection { rangeSelection }

    var isFullPlaybackRangeSelected: Bool {
        playbackSelectionStart == playbackTimelineStart &&
        playbackSelectionEnd == playbackTimelineEnd
    }

    var playbackSelectionStartFraction: Double {
        playbackFraction(for: playbackSelectionStart, fallback: 0)
    }

    var playbackSelectionEndFraction: Double {
        playbackFraction(for: playbackSelectionEnd, fallback: 1)
    }

    var playbackExportRangeTitle: String {
        guard let start = playbackSelectionStart, let end = playbackSelectionEnd else {
            return selectedDateRangeTitle
        }
        return "\(selectedDateRangeTitle) · \(playbackDateTitle(start, relativeTo: end))–\(playbackDateTitle(end, relativeTo: start))"
    }

    var estimatedPlaybackDurationTitle: String {
        guard playbackRecordCount > 0 else { return "--" }

        let seconds = max(Int(estimatedPlaybackDuration.rounded(.up)), 1)
        if seconds < 60 { return L10n.format("%lld 秒", Int64(seconds)) }

        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        if minutes < 60 {
            return remainingSeconds == 0
                ? L10n.format("%lld 分钟", Int64(minutes))
                : L10n.format("%lld分 %lld秒", Int64(minutes), Int64(remainingSeconds))
        }

        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return remainingMinutes == 0
            ? L10n.format("%lld 小时", Int64(hours))
            : L10n.format("%lld小时 %lld分", Int64(hours), Int64(remainingMinutes))
    }

    init(database: KeyDiaryDatabase? = nil, now: Date = .now) {
        var startupError: Error?
        if let database {
            self.database = database
        } else {
            do {
                self.database = try KeyDiaryDatabase()
            } catch {
                startupError = error
                self.database = try! KeyDiaryDatabase(inMemory: true)
            }
        }

        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: now)
        currentDayStart = dayStart
        fromDate = dayStart
        toDate = Self.endOfDay(containing: now, calendar: calendar)

        recorder.onKeyPress = { [weak self] record in
            self?.append(record)
        }
        recorder.onPressedKeysChanged = { [weak self] pressedKeys in
            withAnimation(.spring(response: 0.12, dampingFraction: 0.65)) {
                self?.activeLiveKeys = pressedKeys
            }
        }

        rebuildDerivedState(now: now)
        scheduleDayRollover(from: now)
        if let startupError {
            dataTransferNotice = DataTransferNotice(
                title: L10n.text("本地数据库不可用"),
                message: L10n.format(
                    "本次运行将使用临时内存存储。%@",
                    startupError.localizedDescription
                )
            )
        }
    }

    func refreshInputMonitoringStatus() {
        hasInputMonitoringPermission = recorder.hasInputMonitoringPermission()
        if !hasInputMonitoringPermission { stopRecorderAndFlush() }
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
        if wantsRecording { startRecorderIfPossible() }
    }

    func stopRecording() {
        wantsRecording = false
        stopRecorderAndFlush()
    }

    func previewKeySound(styleRawValue: String, volume: Double) {
        let style = KeySoundStyle(rawValue: styleRawValue) ?? KeySoundPreferences.defaultStyle
        recorder.previewKeySound(style: style, volume: volume)
    }

    func prepareForTermination() {
        playbackVideoExportTask?.cancel()
        recorder.stop()
        flushPersistence()
        database.checkpoint()
    }

    func clearAllRecords() {
        cancelPlaybackVideoExport()
        stopPlayback()
        saveTask?.cancel()
        saveTask = nil
        pendingRecords.removeAll(keepingCapacity: false)
        do {
            try database.deleteAll()
            selectedApplication = "All apps"
            rebuildDerivedState()
        } catch {
            present(error: error, title: "无法清除数据")
        }
    }

    func dataEditorPage(
        query: DataEditorQuery,
        limit: Int,
        offset: Int
    ) throws -> DataEditorPage {
        flushPersistence()
        return try database.editorPage(query: query, limit: limit, offset: offset)
    }

    @discardableResult
    func deleteRecords(ids: Set<UUID>) throws -> Int {
        guard !ids.isEmpty else { return 0 }
        guard !isDataTransferInProgress, !isPlaybackVideoExportInProgress else {
            throw DataEditorError.operationInProgress
        }
        stopPlayback()
        flushPersistence()
        let deleted = try database.delete(ids: ids)
        rebuildDerivedState()
        return deleted
    }

    func selectRecentDays(_ dayCount: Int, now: Date = .now) {
        rangeSelection = .recentDays(max(dayCount, 1))
        applyRollingDateRange(now: now)
    }

    func selectAllRecords(now: Date = .now) {
        rangeSelection = .all
        fromDate = (try? database.earliestTimestamp()) ?? now
        toDate = Self.endOfDay(containing: now)
        rebuildFilteredState()
    }

    func selectCustomRange(from: Date, to: Date) {
        rangeSelection = .custom
        fromDate = min(from, to)
        toDate = max(from, to)
        rebuildFilteredState()
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
            rebuildFilteredState()
        case .custom:
            break
        }
        rebuildTodayCount(now: now)
        scheduleDayRollover(from: now)
    }

    func playbackDate(at fraction: Double) -> Date? {
        guard let start = playbackTimelineStart, let end = playbackTimelineEnd else { return nil }
        let span = end.timeIntervalSince(start)
        guard span > 0 else { return start }
        return start.addingTimeInterval(span * min(max(fraction, 0), 1))
    }

    func setPlaybackRange(startFraction: Double, endFraction: Double) {
        guard playbackTimelineStart != nil, playbackTimelineEnd != nil else { return }
        let lower = min(max(min(startFraction, endFraction), 0), 1)
        let upper = min(max(max(startFraction, endFraction), 0), 1)
        guard let start = playbackDate(at: lower), let end = playbackDate(at: upper) else { return }
        guard start != playbackSelectionStart || end != playbackSelectionEnd else { return }

        stopPlayback()
        playbackSelectionStart = start
        playbackSelectionEnd = end
        rebuildEstimatedPlaybackDuration()
    }

    func resetPlaybackRange() {
        guard !isFullPlaybackRangeSelected else { return }
        stopPlayback()
        playbackSelectionStart = playbackTimelineStart
        playbackSelectionEnd = playbackTimelineEnd
        rebuildEstimatedPlaybackDuration()
    }

    func playFilteredRecords() {
        guard playbackRecordCount > 0, !isPlaybackVideoExportInProgress else { return }

        stopPlayback()
        playbackKeySoundPlayer.resetSequence()
        let query = currentPlaybackQuery
        isPlaying = true
        playbackTask = Task { [weak self] in
            guard let self else { return }
            var cursor: KeyPressRecordCursor?
            var previousTimestamp: Date?

            while !Task.isCancelled {
                let records: [KeyPressRecord]
                do {
                    records = try self.database.records(query: query, after: cursor, limit: 1_000)
                } catch {
                    self.present(error: error, title: "无法读取回放数据")
                    break
                }
                guard !records.isEmpty else { break }

                for record in records {
                    guard !Task.isCancelled else { return }
                    let previous = previousTimestamp ?? record.timestamp
                    let delay = self.playbackDelay(from: previous, to: record.timestamp)
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    guard !Task.isCancelled else { return }
                    withAnimation(.spring(response: 0.18, dampingFraction: 0.62)) {
                        self.activePlaybackKey = record.key
                        self.activePlaybackKeyCode = record.keyCode
                    }
                    self.playbackKeySoundPlayer.playUsingPreferences(keyCode: record.keyCode)
                    previousTimestamp = record.timestamp
                }

                guard let last = records.last else { break }
                cursor = KeyPressRecordCursor(
                    timestampMilliseconds: Self.milliseconds(from: last.timestamp),
                    id: last.id
                )
            }

            let finalHold = PlaybackTiming.finalKeyHold(at: self.playbackSpeed)
            try? await Task.sleep(nanoseconds: UInt64(finalHold * 1_000_000_000))
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
        playbackKeySoundPlayer.stopAllSounds()
        isPlaying = false
        activePlaybackKey = nil
        activePlaybackKeyCode = nil
    }

    func stopPlaybackSounds() {
        playbackKeySoundPlayer.stopAllSounds()
    }

    func exportPlaybackVideo(settings: PlaybackVideoSettings, to url: URL) {
        guard playbackRecordCount > 0,
              !isPlaybackVideoExportInProgress,
              !isDataTransferInProgress else { return }

        stopPlayback()
        flushPersistence()
        isPlaybackVideoExportInProgress = true
        playbackVideoExportProgress = 0

        let database = database
        let query = currentPlaybackQuery
        let speed = playbackSpeed
        let dateRangeTitle = playbackExportRangeTitle
        let applicationTitle = selectedApplication
        let keySoundConfiguration = KeySoundConfiguration.current
        let exporter = playbackVideoExporter

        playbackVideoExportTask = Task { [weak self] in
            guard let self else { return }
            do {
                let loadTask = Task.detached {
                    try Self.loadRecords(database: database, query: query)
                }
                let records = try await withTaskCancellationHandler {
                    try await loadTask.value
                } onCancel: {
                    loadTask.cancel()
                }
                try Task.checkCancellation()
                try await exporter.export(
                    records: records,
                    speed: speed,
                    dateRangeTitle: dateRangeTitle,
                    applicationTitle: applicationTitle,
                    settings: settings,
                    keySoundConfiguration: keySoundConfiguration,
                    to: url
                ) { [weak self] progress in
                    self?.playbackVideoExportProgress = progress
                }
                self.dataTransferNotice = DataTransferNotice(
                    title: L10n.text("视频已导出"),
                    message: L10n.format(
                        "已录制 %@ 次按键的 %@ 回放视频。",
                        records.count.formatted(),
                        settings.shortTitle
                    )
                )
            } catch is CancellationError {
                self.dataTransferNotice = DataTransferNotice(
                    title: L10n.text("已取消录制"),
                    message: L10n.text("未完成的视频文件已移除。")
                )
            } catch {
                self.present(error: error, title: "视频导出失败")
            }
            self.isPlaybackVideoExportInProgress = false
            self.playbackVideoExportProgress = 0
            self.playbackVideoExportTask = nil
        }
    }

    func cancelPlaybackVideoExport() {
        playbackVideoExportTask?.cancel()
    }

    func exportData(format: DataTransferFormat, to url: URL) {
        guard !isDataTransferInProgress, !isPlaybackVideoExportInProgress else { return }
        flushPersistence()
        isDataTransferInProgress = true
        let database = database
        let service = dataTransferService

        Task {
            let result = await Task.detached {
                Result { try service.export(format: format, to: url, database: database) }
            }.value
            self.isDataTransferInProgress = false
            switch result {
            case .success(let report):
                self.dataTransferNotice = DataTransferNotice(
                    title: L10n.text("导出完成"),
                    message: L10n.format(
                        "已将 %@ 条记录导出为 %@。",
                        report.exported.formatted(),
                        format.title
                    )
                )
            case .failure(let error):
                self.present(error: error, title: "导出失败")
            }
        }
    }

    func importData(from url: URL, mode: DataImportMode) {
        guard !isDataTransferInProgress, !isPlaybackVideoExportInProgress else { return }
        stopPlayback()
        flushPersistence()
        isDataTransferInProgress = true
        let shouldResumeRecording = isRecording
        if shouldResumeRecording { recorder.stop() }
        isRecording = false
        let database = database
        let service = dataTransferService

        Task {
            let result: Result<(DataImportResult, URL?), Error> = await Task.detached {
                Result {
                    let backupURL = mode == .replace
                        ? try service.createPreReplacementBackup(database: database)
                        : nil
                    let report = try service.importRecords(from: url, mode: mode, database: database)
                    return (report, backupURL)
                }
            }.value
            self.isDataTransferInProgress = false
            self.rebuildDerivedState()
            if shouldResumeRecording { self.startRecorderIfPossible() }

            switch result {
            case .success(let payload):
                let (report, backupURL) = payload
                let duplicateText = report.duplicates > 0
                    ? L10n.format("，跳过 %@ 条重复记录", report.duplicates.formatted())
                    : ""
                let backupText = backupURL == nil
                    ? ""
                    : L10n.text("替换前的数据已自动备份为 JSON。")
                self.dataTransferNotice = DataTransferNotice(
                    title: L10n.text("导入完成"),
                    message: L10n.format(
                        "已导入 %@ 条记录%@。%@",
                        report.inserted.formatted(),
                        duplicateText,
                        backupText
                    )
                )
            case .failure(let error):
                self.present(error: error, title: "导入失败")
            }
        }
    }

    var activeLiveKeyCodes: Set<UInt16> { Set(activeLiveKeys.keys) }

    var activeLiveKeySummary: String? {
        guard !activeLiveKeys.isEmpty else { return nil }
        return activeLiveKeys
            .sorted { $0.key < $1.key }
            .map(\.value)
            .joined(separator: " + ")
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

    private func append(_ record: KeyPressRecord) {
        refreshDateDependentState(now: record.timestamp)
        pendingRecords.append(record)
        recordCount += 1
        addToDerivedState(record, now: record.timestamp)
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
        let selectedFullRange = isFullPlaybackRangeSelected
        filteredRecordCount += 1
        filteredKeyCounts[record.keyCode, default: 0] += 1
        let previousTimestamp = lastFilteredTimestamp ?? record.timestamp
        if filteredRecordCount == 1 {
            playbackTimelineStart = record.timestamp
            playbackTimelineEnd = record.timestamp
            playbackSelectionStart = record.timestamp
            playbackSelectionEnd = record.timestamp
            playbackRecordCount = 1
            estimatedPlaybackDuration = playbackDelay(from: record.timestamp, to: record.timestamp)
                + PlaybackTiming.finalKeyHold(at: playbackSpeed)
        } else {
            playbackTimelineStart = min(playbackTimelineStart ?? record.timestamp, record.timestamp)
            playbackTimelineEnd = max(playbackTimelineEnd ?? record.timestamp, record.timestamp)
            if selectedFullRange {
                playbackSelectionStart = playbackTimelineStart
                playbackSelectionEnd = playbackTimelineEnd
                playbackRecordCount += 1
                estimatedPlaybackDuration += playbackDelay(from: previousTimestamp, to: record.timestamp)
            }
        }
        lastFilteredTimestamp = record.timestamp
    }

    private func rebuildDerivedState(now: Date = .now) {
        do {
            recordCount = try database.count()
            applications = ["All apps"] + (try database.applicationNames())
            if !applications.contains(selectedApplication) {
                selectedApplication = "All apps"
            }
            rebuildTodayCount(now: now)
            rebuildFilteredState()
        } catch {
            present(error: error, title: "无法读取本地数据")
        }
    }

    private func rebuildTodayCount(now: Date) {
        let calendar = Calendar.current
        currentDayStart = calendar.startOfDay(for: now)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: currentDayStart) ?? .distantFuture
        let query = KeyDiaryRecordQuery(
            fromDate: currentDayStart,
            toDate: nextDay.addingTimeInterval(-0.001),
            applicationName: nil
        )
        pressesToday = (try? database.count(query: query)) ?? 0
    }

    private func rebuildFilteredState() {
        stopPlayback()
        do {
            let query = currentQuery
            filteredKeyCounts = try database.keyCounts(query: query)
            let metrics = try database.playbackMetrics(query: query, speed: playbackSpeed)
            filteredRecordCount = metrics.count
            playbackRecordCount = metrics.count
            estimatedPlaybackDuration = metrics.duration
            playbackTimelineStart = metrics.firstTimestamp
            playbackTimelineEnd = metrics.lastTimestamp
            playbackSelectionStart = metrics.firstTimestamp
            playbackSelectionEnd = metrics.lastTimestamp
            lastFilteredTimestamp = metrics.lastTimestamp
        } catch {
            filteredRecordCount = 0
            playbackRecordCount = 0
            filteredKeyCounts = [:]
            estimatedPlaybackDuration = 0
            playbackTimelineStart = nil
            playbackTimelineEnd = nil
            playbackSelectionStart = nil
            playbackSelectionEnd = nil
            present(error: error, title: "无法筛选本地数据")
        }
    }

    private var currentQuery: KeyDiaryRecordQuery {
        KeyDiaryRecordQuery(
            fromDate: fromDate,
            toDate: toDate,
            applicationName: selectedApplication == "All apps" ? nil : selectedApplication
        )
    }

    private var currentPlaybackQuery: KeyDiaryRecordQuery {
        KeyDiaryRecordQuery(
            fromDate: playbackSelectionStart ?? fromDate,
            toDate: playbackSelectionEnd ?? toDate,
            applicationName: selectedApplication == "All apps" ? nil : selectedApplication
        )
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
        rebuildFilteredState()
    }

    private func playbackDelay(from previous: Date, to current: Date) -> TimeInterval {
        PlaybackTiming.delay(from: previous, to: current, speed: playbackSpeed)
    }

    nonisolated private static func loadRecords(
        database: KeyDiaryDatabase,
        query: KeyDiaryRecordQuery
    ) throws -> [KeyPressRecord] {
        var allRecords: [KeyPressRecord] = []
        var cursor: KeyPressRecordCursor?

        while !Task.isCancelled {
            let records = try database.records(query: query, after: cursor, limit: 5_000)
            guard !records.isEmpty else { break }
            allRecords.append(contentsOf: records)
            guard let last = records.last else { break }
            cursor = KeyPressRecordCursor(
                timestampMilliseconds: milliseconds(from: last.timestamp),
                id: last.id
            )
        }

        try Task.checkCancellation()
        return allRecords
    }

    private func rebuildEstimatedPlaybackDuration() {
        do {
            let metrics = try database.playbackMetrics(query: currentPlaybackQuery, speed: playbackSpeed)
            estimatedPlaybackDuration = metrics.duration
            playbackRecordCount = metrics.count
        } catch {
            estimatedPlaybackDuration = 0
            playbackRecordCount = 0
            present(error: error, title: "无法计算回放时长")
        }
    }

    private func playbackFraction(for date: Date?, fallback: Double) -> Double {
        guard let date, let start = playbackTimelineStart, let end = playbackTimelineEnd else {
            return fallback
        }
        let span = end.timeIntervalSince(start)
        guard span > 0 else { return fallback }
        return min(max(date.timeIntervalSince(start) / span, 0), 1)
    }

    private func playbackDateTitle(_ date: Date, relativeTo otherDate: Date) -> String {
        if Calendar.current.isDate(date, inSameDayAs: otherDate) {
            return date.formatted(.dateTime.hour().minute().second())
        }
        return date.formatted(.dateTime.month().day().hour().minute())
    }

    private func scheduleSave() {
        guard saveTask == nil else { return }
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled, let self else { return }
            let batch = self.pendingRecords
            self.pendingRecords.removeAll(keepingCapacity: true)
            self.saveTask = nil
            self.database.insertAsync(batch) { [weak self] result in
                guard case .failure(let error) = result else { return }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.pendingRecords.insert(contentsOf: batch, at: 0)
                    self.logger.error(
                        "Unable to persist key presses: \(error.localizedDescription, privacy: .public)"
                    )
                    self.scheduleSave()
                }
            }
        }
    }

    private func persistPendingRecords() {
        guard !pendingRecords.isEmpty else { return }
        let batch = pendingRecords
        pendingRecords.removeAll(keepingCapacity: true)
        do {
            _ = try database.insert(batch)
        } catch {
            pendingRecords.insert(contentsOf: batch, at: 0)
            logger.error("Unable to persist key presses: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func flushPersistence() {
        saveTask?.cancel()
        saveTask = nil
        persistPendingRecords()
    }

    private func scheduleDayRollover(from now: Date) {
        dayRolloverTask?.cancel()
        let calendar = Calendar.current
        let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
            ?? now.addingTimeInterval(86_400)
        let nanoseconds = UInt64(max(nextDay.timeIntervalSince(now), 1) * 1_000_000_000)
        dayRolloverTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            self?.refreshDateDependentState()
        }
    }

    private func present(error: Error, title: String) {
        dataTransferNotice = DataTransferNotice(
            title: L10n.text(title),
            message: error.localizedDescription
        )
    }

    private static func endOfDay(containing date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))?
            .addingTimeInterval(-0.001) ?? date
    }

    nonisolated private static func milliseconds(from date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000).rounded())
    }
}
