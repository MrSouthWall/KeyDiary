//
//  PlaybackVideoExporter.swift
//  KeyDiary
//

@preconcurrency import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import SwiftUI

nonisolated enum PlaybackVideoContainer: String, CaseIterable, Identifiable, Sendable {
    case mp4
    case mov

    var id: Self { self }
    var title: String { rawValue.uppercased() }
    var filenameExtension: String { rawValue }
    var fileType: AVFileType { self == .mp4 ? .mp4 : .mov }
}

nonisolated enum PlaybackVideoCodec: String, CaseIterable, Identifiable, Sendable {
    case h264
    case h265
    case proRes4444Alpha

    var id: Self { self }

    var title: String {
        switch self {
        case .h264: "H.264"
        case .h265: "H.265 / HEVC"
        case .proRes4444Alpha: "ProRes 4444 · 透明"
        }
    }

    var shortTitle: String {
        switch self {
        case .h264: "H.264"
        case .h265: "H.265"
        case .proRes4444Alpha: "ProRes 4444"
        }
    }

    var videoCodecType: AVVideoCodecType {
        switch self {
        case .h264: .h264
        case .h265: .hevc
        case .proRes4444Alpha: .proRes4444
        }
    }

    var preservesAlpha: Bool { self == .proRes4444Alpha }

    func supports(_ container: PlaybackVideoContainer) -> Bool {
        self != .proRes4444Alpha || container == .mov
    }
}

nonisolated enum PlaybackVideoResolution: String, CaseIterable, Identifiable, Sendable {
    case hd720
    case fullHD1080
    case ultraHD4K

    var id: Self { self }

    var title: String {
        switch self {
        case .hd720: "720p"
        case .fullHD1080: "1080p"
        case .ultraHD4K: "4K"
        }
    }

    var dimensionsTitle: String { "\(width) × \(height)" }

    var width: Int {
        switch self {
        case .hd720: 1_280
        case .fullHD1080: 1_920
        case .ultraHD4K: 3_840
        }
    }

    var height: Int {
        switch self {
        case .hd720: 720
        case .fullHD1080: 1_080
        case .ultraHD4K: 2_160
        }
    }

    var baseBitRate: Int {
        switch self {
        case .hd720: 5_000_000
        case .fullHD1080: 10_000_000
        case .ultraHD4K: 35_000_000
        }
    }
}

nonisolated enum PlaybackVideoFrameRate: String, CaseIterable, Identifiable, Sendable {
    case fps24
    case fps25
    case fps30
    case fps50
    case fps60
    case fps120
    case fps23_976
    case fps29_97
    case fps59_94
    case fps119_88

    static let commonCases: [Self] = [.fps24, .fps25, .fps30, .fps50, .fps60, .fps120]
    static let dropFrameCases: [Self] = [.fps23_976, .fps29_97, .fps59_94, .fps119_88]

    var id: Self { self }

    var title: String {
        switch self {
        case .fps24: "24 fps"
        case .fps25: "25 fps"
        case .fps30: "30 fps"
        case .fps50: "50 fps"
        case .fps60: "60 fps"
        case .fps120: "120 fps"
        case .fps23_976: "23.976 fps"
        case .fps29_97: "29.97 fps"
        case .fps59_94: "59.94 fps"
        case .fps119_88: "119.88 fps"
        }
    }

    var isDropFrame: Bool { Self.dropFrameCases.contains(self) }

    var frameDuration: CMTime {
        switch self {
        case .fps24: CMTime(value: 1, timescale: 24)
        case .fps25: CMTime(value: 1, timescale: 25)
        case .fps30: CMTime(value: 1, timescale: 30)
        case .fps50: CMTime(value: 1, timescale: 50)
        case .fps60: CMTime(value: 1, timescale: 60)
        case .fps120: CMTime(value: 1, timescale: 120)
        case .fps23_976: CMTime(value: 1_001, timescale: 24_000)
        case .fps29_97: CMTime(value: 1_001, timescale: 30_000)
        case .fps59_94: CMTime(value: 1_001, timescale: 60_000)
        case .fps119_88: CMTime(value: 1_001, timescale: 120_000)
        }
    }

    var framesPerSecond: Double {
        Double(frameDuration.timescale) / Double(frameDuration.value)
    }

    var nominalFramesPerSecond: Int { Int(framesPerSecond.rounded()) }

    func presentationTime(forFrame index: Int) -> CMTime {
        CMTime(
            value: Int64(index) * frameDuration.value,
            timescale: frameDuration.timescale
        )
    }
}

nonisolated struct PlaybackVideoSettings: Sendable, Equatable {
    var container: PlaybackVideoContainer
    var codec: PlaybackVideoCodec
    var resolution: PlaybackVideoResolution
    var frameRate: PlaybackVideoFrameRate

    static let `default` = PlaybackVideoSettings(
        container: .mp4,
        codec: .h264,
        resolution: .fullHD1080,
        frameRate: .fps30
    )

    init(
        container: PlaybackVideoContainer,
        codec: PlaybackVideoCodec,
        resolution: PlaybackVideoResolution,
        frameRate: PlaybackVideoFrameRate
    ) {
        self.container = codec.supports(container) ? container : .mov
        self.codec = codec
        self.resolution = resolution
        self.frameRate = frameRate
    }

    var preservesAlpha: Bool { codec.preservesAlpha }
    var filenameExtension: String { container.filenameExtension }

    var shortTitle: String {
        "\(resolution.title) \(container.title) · \(codec.shortTitle) · \(frameRate.title)"
    }

    var exportDescription: String {
        let background = preservesAlpha ? "透明背景" : "KeyDiary UI 背景"
        return "导出为 \(resolution.title) \(container.title)，使用 \(codec.title)、\(frameRate.title) 和\(background)。"
    }
}

nonisolated struct PlaybackVideoEvent: Sendable {
    let record: KeyPressRecord
    let presentationTime: TimeInterval
}

nonisolated struct PlaybackVideoTimeline: Sendable {
    let events: [PlaybackVideoEvent]
    let duration: TimeInterval

    init(records: [KeyPressRecord], speed: Double) {
        let sortedRecords = records.sorted {
            if $0.timestamp == $1.timestamp {
                return $0.id.uuidString < $1.id.uuidString
            }
            return $0.timestamp < $1.timestamp
        }

        var elapsed: TimeInterval = 0
        var previousTimestamp: Date?
        var events: [PlaybackVideoEvent] = []
        events.reserveCapacity(sortedRecords.count)

        for record in sortedRecords {
            let previous = previousTimestamp ?? record.timestamp
            elapsed += PlaybackTiming.delay(from: previous, to: record.timestamp, speed: speed)
            events.append(PlaybackVideoEvent(record: record, presentationTime: elapsed))
            previousTimestamp = record.timestamp
        }

        self.events = events
        duration = events.isEmpty ? 0 : elapsed + PlaybackTiming.finalKeyHold(at: speed)
    }
}

nonisolated struct PlaybackVideoConfiguration: Sendable {
    let width: Int
    let height: Int
    let averageBitRate: Int

    init(width: Int, height: Int, averageBitRate: Int) {
        self.width = width
        self.height = height
        self.averageBitRate = averageBitRate
    }

    init(settings: PlaybackVideoSettings) {
        width = settings.resolution.width
        height = settings.resolution.height

        let frameRateMultiplier = max(settings.frameRate.framesPerSecond / 30, 1)
        let codecMultiplier = settings.codec == .h265 ? 0.65 : 1
        averageBitRate = Int(
            (Double(settings.resolution.baseBitRate) * frameRateMultiplier * codecMultiplier).rounded()
        )
    }

    static let fullHD = PlaybackVideoConfiguration(
        width: 1_920,
        height: 1_080,
        averageBitRate: 10_000_000
    )
}

nonisolated enum PlaybackVideoExportError: LocalizedError {
    case noRecords
    case cannotCreateWriter(String)
    case cannotStartWriter(String)
    case cannotCreateFrame
    case cannotAppendFrame(String)
    case cannotFinishWriter(String)

    var errorDescription: String? {
        switch self {
        case .noRecords:
            "当前筛选范围内没有可录制的按键。"
        case .cannotCreateWriter(let detail):
            "无法创建视频文件：\(detail)"
        case .cannotStartWriter(let detail):
            "无法开始写入视频：\(detail)"
        case .cannotCreateFrame:
            "无法渲染键盘视频画面。"
        case .cannotAppendFrame(let detail):
            "无法写入视频画面：\(detail)"
        case .cannotFinishWriter(let detail):
            "无法完成视频文件：\(detail)"
        }
    }
}

@MainActor
final class PlaybackVideoExporter {
    typealias ProgressHandler = @MainActor (Double) -> Void

    private let configurationOverride: PlaybackVideoConfiguration?

    init(configuration: PlaybackVideoConfiguration? = nil) {
        configurationOverride = configuration
    }

    func export(
        records: [KeyPressRecord],
        speed: Double,
        dateRangeTitle: String,
        applicationTitle: String,
        settings: PlaybackVideoSettings = .default,
        to url: URL,
        progress: ProgressHandler = { _ in }
    ) async throws {
        let timeline = PlaybackVideoTimeline(records: records, speed: speed)
        guard !timeline.events.isEmpty else { throw PlaybackVideoExportError.noRecords }
        let accentHex = UserDefaults.standard.string(forKey: KeyDiaryTheme.accentColorStorageKey)
            ?? KeyDiaryTheme.defaultAccentHex

        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }

        let configuration = configurationOverride ?? PlaybackVideoConfiguration(settings: settings)
        let videoWriter = PlaybackVideoWriter(configuration: configuration, settings: settings)

        do {
            try await videoWriter.start(to: url)
            let frameDuration = settings.frameRate.frameDuration.seconds
            let frameCount = max(Int(ceil(timeline.duration / frameDuration)), 1)
            var eventIndex = -1

            for frameIndex in 0..<frameCount {
                try Task.checkCancellation()
                let presentationTime = settings.frameRate.presentationTime(forFrame: frameIndex)
                let seconds = presentationTime.seconds

                while eventIndex + 1 < timeline.events.count,
                      timeline.events[eventIndex + 1].presentationTime <= seconds + 0.000_000_1 {
                    eventIndex += 1
                }

                let record = eventIndex >= 0 ? timeline.events[eventIndex].record : nil
                let timelineProgress = min(max(seconds / timeline.duration, 0), 1)
                try await renderAndAppendFrame(
                    record: record,
                    progress: timelineProgress,
                    dateRangeTitle: dateRangeTitle,
                    applicationTitle: applicationTitle,
                    speed: speed,
                    settings: settings,
                    accentHex: accentHex,
                    configuration: configuration,
                    at: presentationTime,
                    videoWriter: videoWriter
                )
                progress(Double(frameIndex + 1) / Double(frameCount))
                await Task.yield()
            }

            try await videoWriter.finish(at: timeline.duration)
        } catch {
            await videoWriter.cancel(removing: url)
            throw error
        }
    }

    private func renderAndAppendFrame(
        record: KeyPressRecord?,
        progress: Double,
        dateRangeTitle: String,
        applicationTitle: String,
        speed: Double,
        settings: PlaybackVideoSettings,
        accentHex: String,
        configuration: PlaybackVideoConfiguration,
        at presentationTime: CMTime,
        videoWriter: PlaybackVideoWriter
    ) async throws {
        let view = PlaybackVideoFrame(
            activeRecord: record,
            progress: progress,
            dateRangeTitle: dateRangeTitle,
            applicationTitle: applicationTitle,
            speed: speed,
            usesTransparentBackground: settings.preservesAlpha
        )
        .frame(width: CGFloat(configuration.width), height: CGFloat(configuration.height))
        .keyDiaryAccent(hex: accentHex)

        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(
            width: CGFloat(configuration.width),
            height: CGFloat(configuration.height)
        )
        renderer.scale = 1
        renderer.isOpaque = !settings.preservesAlpha
        guard let image = renderer.cgImage else {
            throw PlaybackVideoExportError.cannotCreateFrame
        }
        try await videoWriter.append(image: image, at: presentationTime)
    }
}

private actor PlaybackVideoWriter {
    private let configuration: PlaybackVideoConfiguration
    private let settings: PlaybackVideoSettings
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?

    init(configuration: PlaybackVideoConfiguration, settings: PlaybackVideoSettings) {
        self.configuration = configuration
        self.settings = settings
    }

    func start(to url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: url, fileType: settings.container.fileType)
        } catch {
            throw PlaybackVideoExportError.cannotCreateWriter(error.localizedDescription)
        }

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: makeVideoSettings())
        input.expectsMediaDataInRealTime = false
        input.mediaTimeScale = settings.frameRate.frameDuration.timescale
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: configuration.width,
                kCVPixelBufferHeightKey as String: configuration.height,
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
            ]
        )

        guard writer.canAdd(input) else {
            throw PlaybackVideoExportError.cannotCreateWriter("编码器不接受当前的封装、编码或分辨率组合。")
        }
        writer.add(input)
        guard writer.startWriting() else {
            throw PlaybackVideoExportError.cannotStartWriter(errorDescription(for: writer))
        }
        writer.startSession(atSourceTime: .zero)
        self.writer = writer
        self.input = input
        self.adaptor = adaptor
    }

    func append(image: CGImage, at presentationTime: CMTime) async throws {
        guard let writer, let input, let adaptor else {
            throw PlaybackVideoExportError.cannotStartWriter("视频编码器尚未启动。")
        }

        while !input.isReadyForMoreMediaData {
            try Task.checkCancellation()
            guard writer.status == .writing else {
                throw PlaybackVideoExportError.cannotAppendFrame(errorDescription(for: writer))
            }
            try await Task.sleep(nanoseconds: 2_000_000)
        }

        guard let pool = adaptor.pixelBufferPool else {
            throw PlaybackVideoExportError.cannotCreateFrame
        }
        var optionalPixelBuffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &optionalPixelBuffer) == kCVReturnSuccess,
              let pixelBuffer = optionalPixelBuffer,
              draw(image, into: pixelBuffer) else {
            throw PlaybackVideoExportError.cannotCreateFrame
        }

        guard adaptor.append(pixelBuffer, withPresentationTime: presentationTime) else {
            throw PlaybackVideoExportError.cannotAppendFrame(errorDescription(for: writer))
        }
    }

    func finish(at duration: TimeInterval) async throws {
        guard let writer, let input else {
            throw PlaybackVideoExportError.cannotFinishWriter("视频编码器尚未启动。")
        }

        writer.endSession(atSourceTime: CMTime(seconds: duration, preferredTimescale: 120_000))
        input.markAsFinished()
        await withCheckedContinuation { continuation in
            writer.finishWriting { continuation.resume() }
        }
        guard writer.status == .completed else {
            throw PlaybackVideoExportError.cannotFinishWriter(errorDescription(for: writer))
        }
        self.writer = nil
        self.input = nil
        adaptor = nil
    }

    func cancel(removing url: URL) {
        input?.markAsFinished()
        writer?.cancelWriting()
        writer = nil
        input = nil
        adaptor = nil
        try? FileManager.default.removeItem(at: url)
    }

    private func makeVideoSettings() -> [String: Any] {
        var result: [String: Any] = [
            AVVideoCodecKey: settings.codec.videoCodecType,
            AVVideoWidthKey: configuration.width,
            AVVideoHeightKey: configuration.height
        ]

        guard !settings.codec.preservesAlpha else { return result }

        var compressionProperties: [String: Any] = [
            AVVideoAverageBitRateKey: configuration.averageBitRate,
            AVVideoExpectedSourceFrameRateKey: settings.frameRate.framesPerSecond,
            AVVideoMaxKeyFrameIntervalKey: settings.frameRate.nominalFramesPerSecond * 2
        ]
        if settings.codec == .h264 {
            compressionProperties[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
        }
        result[AVVideoCompressionPropertiesKey] = compressionProperties
        return result
    }

    private func draw(_ image: CGImage, into pixelBuffer: CVPixelBuffer) -> Bool {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return false }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue |
            CGImageAlphaInfo.premultipliedFirst.rawValue
        guard let context = CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return false
        }

        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }

    private func errorDescription(for writer: AVAssetWriter) -> String {
        writer.error?.localizedDescription ?? "未知编码错误。"
    }
}
