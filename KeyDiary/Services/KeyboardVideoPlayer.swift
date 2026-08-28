//
//  KeyboardVideoPlayer.swift
//  KeyDiary
//

@preconcurrency import AVFoundation
import CoreVideo
import Foundation
import Observation

@MainActor
@Observable
final class KeyboardVideoPlayer {
    @ObservationIgnored private let player = AVPlayer()
    @ObservationIgnored private var videoOutput: AVPlayerItemVideoOutput?
    @ObservationIgnored private var frameTask: Task<Void, Never>?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var exportTask: Task<Void, Never>?
    @ObservationIgnored private var securityScopedURL: URL?
    @ObservationIgnored private let videoExporter = KeyboardCinemaVideoExporter()

    private(set) var pixelFrame = KeyboardPixelFrame.blank
    private(set) var videoURL: URL?
    private(set) var videoTitle: String?
    private(set) var duration: TimeInterval = 0
    private(set) var currentTime: TimeInterval = 0
    private(set) var isPlaying = false
    private(set) var isLoading = false
    private(set) var isVideoExportInProgress = false
    private(set) var videoExportProgress = 0.0
    private(set) var errorMessage: String?
    var exportNotice: DataTransferNotice?

    var loops = true
    var colorMode: KeyboardPixelColorMode = .color {
        didSet { renderCurrentFrame() }
    }
    var framingMode: KeyboardVideoFramingMode = .fill {
        didSet { renderCurrentFrame() }
    }
    var isInverted = false {
        didSet { renderCurrentFrame() }
    }

    var hasVideo: Bool { player.currentItem != nil }
    var avPlayer: AVPlayer { player }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }

    var currentTimeTitle: String { Self.timeTitle(currentTime) }
    var durationTitle: String { Self.timeTitle(duration) }

    init() {
        player.actionAtItemEnd = .pause
        player.preventsDisplaySleepDuringVideoPlayback = true
    }

    func loadBundledBadAppleIfNeeded(autoplay: Bool = true) {
        guard !hasVideo, !isLoading else {
            if autoplay, hasVideo, !isPlaying { play() }
            return
        }

        guard let url = Bundle.main.url(forResource: "BadApple", withExtension: "mp4") else {
            errorMessage = "找不到内置的 Bad Apple 视频。"
            return
        }
        framingMode = .fill
        loadVideo(
            from: url,
            title: "Bad Apple!! 影絵 PV",
            autoplay: autoplay,
            initialColorMode: .binary
        )
    }

    func loadVideo(
        from url: URL,
        title: String? = nil,
        autoplay: Bool = true,
        initialColorMode: KeyboardPixelColorMode = .color
    ) {
        guard !isVideoExportInProgress else { return }
        pause()
        loadTask?.cancel()
        stopAccessingSecurityScopedResource()
        colorMode = initialColorMode

        if url.startAccessingSecurityScopedResource() {
            securityScopedURL = url
        }

        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ])
        item.add(output)
        videoOutput = output
        player.replaceCurrentItem(with: item)

        videoURL = url
        videoTitle = title ?? url.deletingPathExtension().lastPathComponent
        duration = 0
        currentTime = 0
        pixelFrame = .blank
        errorMessage = nil
        isLoading = true

        loadTask = Task { @MainActor [weak self, weak item] in
            guard let self, let item else { return }
            do {
                let loadedDuration = try await asset.load(.duration)
                guard !Task.isCancelled, self.player.currentItem === item else { return }
                let seconds = loadedDuration.seconds
                guard seconds.isFinite, seconds > 0 else {
                    throw KeyboardVideoError.invalidDuration
                }
                self.duration = seconds
                self.isLoading = false
                await self.player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
                if autoplay {
                    self.play()
                } else {
                    self.renderSoon()
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self.isLoading = false
                self.errorMessage = "无法读取视频：\(error.localizedDescription)"
            }
        }
    }

    func togglePlayback() {
        isPlaying ? pause() : play()
    }

    func play() {
        guard hasVideo, !isLoading else { return }
        if duration > 0, currentTime >= duration - 0.05 {
            player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
            currentTime = 0
        }
        player.play()
        isPlaying = true
        startFrameUpdates()
    }

    func pause() {
        player.pause()
        isPlaying = false
        frameTask?.cancel()
        frameTask = nil
        renderCurrentFrame()
    }

    func seek(to fraction: Double) {
        guard duration > 0 else { return }
        let seconds = min(max(fraction, 0), 1) * duration
        currentTime = seconds
        player.seek(
            to: CMTime(seconds: seconds, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        renderSoon()
    }

    func restart() {
        seek(to: 0)
        play()
    }

    func stop() {
        pause()
        seek(to: 0)
    }

    func exportVideo(settings: PlaybackVideoSettings, to url: URL) {
        guard let videoURL,
              let videoTitle,
              hasVideo,
              !isLoading,
              !isVideoExportInProgress else { return }

        isVideoExportInProgress = true
        videoExportProgress = 0
        let source = KeyboardCinemaExportSource(
            url: videoURL,
            title: videoTitle,
            colorMode: colorMode,
            framingMode: framingMode,
            isInverted: isInverted
        )
        let exporter = videoExporter

        exportTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await exporter.export(
                    source: source,
                    settings: settings,
                    to: url
                ) { [weak self] progress in
                    self?.videoExportProgress = progress
                }
                self.exportNotice = DataTransferNotice(
                    title: "像素视频已导出",
                    message: "已导出 \(settings.shortTitle) 键盘像素视频；原片含音轨时已保留原声。"
                )
            } catch is CancellationError {
                self.exportNotice = DataTransferNotice(
                    title: "已取消录制",
                    message: "未完成的视频文件已移除。"
                )
            } catch {
                self.exportNotice = DataTransferNotice(
                    title: "像素视频导出失败",
                    message: error.localizedDescription
                )
            }
            self.isVideoExportInProgress = false
            self.videoExportProgress = 0
            self.exportTask = nil
        }
    }

    func cancelVideoExport() {
        exportTask?.cancel()
    }

    private func startFrameUpdates() {
        frameTask?.cancel()
        frameTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.updatePlaybackFrame()
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }

    private func updatePlaybackFrame() {
        let seconds = player.currentTime().seconds
        if seconds.isFinite {
            currentTime = min(max(seconds, 0), duration)
        }
        renderCurrentFrame()

        guard duration > 0, currentTime >= duration - 0.04 else { return }
        if loops {
            player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
            currentTime = 0
            player.play()
        } else {
            pause()
            currentTime = duration
        }
    }

    private func renderCurrentFrame() {
        guard let videoOutput else { return }
        let itemTime = player.currentTime()
        guard let pixelBuffer = videoOutput.copyPixelBuffer(
            forItemTime: itemTime,
            itemTimeForDisplay: nil
        ) else { return }

        pixelFrame = KeyboardPixelFrame(
            pixelBuffer: pixelBuffer,
            colorMode: colorMode,
            framingMode: framingMode,
            isInverted: isInverted
        )
    }

    private func renderSoon() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            self?.renderCurrentFrame()
        }
    }

    private func stopAccessingSecurityScopedResource() {
        securityScopedURL?.stopAccessingSecurityScopedResource()
        securityScopedURL = nil
    }

    private static func timeTitle(_ time: TimeInterval) -> String {
        guard time.isFinite, time >= 0 else { return "0:00" }
        let totalSeconds = Int(time.rounded(.down))
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

private enum KeyboardVideoError: LocalizedError {
    case invalidDuration

    var errorDescription: String? {
        switch self {
        case .invalidDuration: "视频时长无效"
        }
    }
}
