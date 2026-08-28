//
//  KeyboardCinemaVideoExporter.swift
//  KeyDiary
//

@preconcurrency import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import SwiftUI

nonisolated struct KeyboardCinemaExportSource: Sendable {
    let url: URL
    let title: String
    let colorMode: KeyboardPixelColorMode
    let framingMode: KeyboardVideoFramingMode
    let isInverted: Bool
}

@MainActor
final class KeyboardCinemaVideoExporter {
    typealias ProgressHandler = @MainActor (Double) -> Void

    private let configurationOverride: PlaybackVideoConfiguration?
    private let maximumDuration: TimeInterval?

    init(
        configuration: PlaybackVideoConfiguration? = nil,
        maximumDuration: TimeInterval? = nil
    ) {
        configurationOverride = configuration
        self.maximumDuration = maximumDuration
    }

    func export(
        source: KeyboardCinemaExportSource,
        settings: PlaybackVideoSettings = .default,
        to outputURL: URL,
        progress: ProgressHandler = { _ in }
    ) async throws {
        let accessedSource = source.url.startAccessingSecurityScopedResource()
        let accessedOutput = outputURL.startAccessingSecurityScopedResource()
        defer {
            if accessedSource { source.url.stopAccessingSecurityScopedResource() }
            if accessedOutput { outputURL.stopAccessingSecurityScopedResource() }
        }

        let asset = AVURLAsset(url: source.url)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw PlaybackVideoExportError.noVideo
        }
        let loadedDuration = try await asset.load(.duration).seconds
        guard loadedDuration.isFinite, loadedDuration > 0 else {
            throw PlaybackVideoExportError.cannotReadSource("视频时长无效。")
        }
        let duration = min(loadedDuration, maximumDuration ?? loadedDuration)
        let hasAudio = try await !asset.loadTracks(withMediaType: .audio).isEmpty
        let configuration = configurationOverride ?? PlaybackVideoConfiguration(settings: settings)
        let accentHex = UserDefaults.standard.string(forKey: KeyDiaryTheme.accentColorStorageKey)
            ?? KeyDiaryTheme.defaultAccentHex

        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("KeyDiaryCinemaExport-\(UUID().uuidString)", isDirectory: true)
        let videoURL = hasAudio
            ? temporaryDirectory.appendingPathComponent("video.\(settings.filenameExtension)")
            : outputURL
        if hasAudio {
            do {
                try FileManager.default.createDirectory(
                    at: temporaryDirectory,
                    withIntermediateDirectories: true
                )
            } catch {
                throw PlaybackVideoExportError.cannotCreateWriter(error.localizedDescription)
            }
        }
        defer {
            if hasAudio {
                try? FileManager.default.removeItem(at: temporaryDirectory)
            }
        }

        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw PlaybackVideoExportError.cannotReadSource(error.localizedDescription)
        }
        let readerOutput = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
            ]
        )
        readerOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(readerOutput) else {
            throw PlaybackVideoExportError.cannotReadSource("无法创建视频帧解码器。")
        }
        reader.add(readerOutput)
        guard reader.startReading() else {
            throw PlaybackVideoExportError.cannotReadSource(
                reader.error?.localizedDescription ?? "视频帧解码器无法启动。"
            )
        }
        defer { reader.cancelReading() }

        let videoWriter = PlaybackVideoWriter(configuration: configuration, settings: settings)
        do {
            try await videoWriter.start(to: videoURL)
            let frameDuration = settings.frameRate.frameDuration.seconds
            let frameCount = max(Int(ceil(duration / frameDuration)), 1)
            var heldSample: CMSampleBuffer?
            var nextSample = readerOutput.copyNextSampleBuffer()

            for frameIndex in 0..<frameCount {
                try Task.checkCancellation()
                let presentationTime = settings.frameRate.presentationTime(forFrame: frameIndex)
                let seconds = presentationTime.seconds

                while let sample = nextSample,
                      CMSampleBufferGetPresentationTimeStamp(sample).seconds <= seconds + 0.000_000_1 {
                    heldSample = sample
                    nextSample = readerOutput.copyNextSampleBuffer()
                }

                guard let sample = heldSample ?? nextSample,
                      let pixelBuffer = CMSampleBufferGetImageBuffer(sample) else {
                    throw PlaybackVideoExportError.cannotReadSource(
                        reader.error?.localizedDescription ?? "视频中没有可解码的画面。"
                    )
                }
                let keyboardFrame = KeyboardPixelFrame(
                    pixelBuffer: pixelBuffer,
                    colorMode: source.colorMode,
                    framingMode: source.framingMode,
                    isInverted: source.isInverted
                )
                try await renderAndAppendFrame(
                    keyboardFrame: keyboardFrame,
                    source: source,
                    settings: settings,
                    configuration: configuration,
                    duration: duration,
                    at: presentationTime,
                    accentHex: accentHex,
                    videoWriter: videoWriter
                )

                let videoProgress = Double(frameIndex + 1) / Double(frameCount)
                progress(hasAudio ? videoProgress * 0.94 : videoProgress)
                await Task.yield()
            }

            try await videoWriter.finish(at: duration)
            if hasAudio {
                progress(0.96)
                try await muxOriginalAudio(
                    videoAt: videoURL,
                    sourceAt: source.url,
                    duration: duration,
                    settings: settings,
                    to: outputURL
                )
                progress(1)
            }
        } catch {
            await videoWriter.cancel(removing: videoURL)
            if hasAudio {
                try? FileManager.default.removeItem(at: outputURL)
            }
            throw error
        }
    }

    private func renderAndAppendFrame(
        keyboardFrame: KeyboardPixelFrame,
        source: KeyboardCinemaExportSource,
        settings: PlaybackVideoSettings,
        configuration: PlaybackVideoConfiguration,
        duration: TimeInterval,
        at presentationTime: CMTime,
        accentHex: String,
        videoWriter: PlaybackVideoWriter
    ) async throws {
        let seconds = min(max(presentationTime.seconds, 0), duration)
        let view = KeyboardCinemaVideoFrame(
            pixelFrame: keyboardFrame,
            progress: seconds / duration,
            currentTime: seconds,
            duration: duration,
            videoTitle: source.title,
            colorMode: source.colorMode,
            framingMode: source.framingMode,
            isInverted: source.isInverted,
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

    private func muxOriginalAudio(
        videoAt videoURL: URL,
        sourceAt sourceURL: URL,
        duration: TimeInterval,
        settings: PlaybackVideoSettings,
        to outputURL: URL
    ) async throws {
        do {
            let videoAsset = AVURLAsset(url: videoURL)
            let sourceAsset = AVURLAsset(url: sourceURL)
            guard let sourceVideoTrack = try await videoAsset.loadTracks(withMediaType: .video).first,
                  let sourceAudioTrack = try await sourceAsset.loadTracks(withMediaType: .audio).first else {
                throw PlaybackVideoExportError.cannotMuxAudio("临时视频或原片音轨不可用。")
            }

            let composition = AVMutableComposition()
            guard let videoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ), let audioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                throw PlaybackVideoExportError.cannotMuxAudio("无法创建音视频合成轨道。")
            }

            let videoDuration = try await videoAsset.load(.duration)
            try videoTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: videoDuration),
                of: sourceVideoTrack,
                at: .zero
            )
            videoTrack.preferredTransform = try await sourceVideoTrack.load(.preferredTransform)

            let audioAssetDuration = try await sourceAsset.load(.duration).seconds
            let audioDuration = CMTime(
                seconds: min(duration, audioAssetDuration),
                preferredTimescale: 120_000
            )
            try audioTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: audioDuration),
                of: sourceAudioTrack,
                at: .zero
            )

            if FileManager.default.fileExists(atPath: outputURL.path) {
                try FileManager.default.removeItem(at: outputURL)
            }
            guard let exportSession = AVAssetExportSession(
                asset: composition,
                presetName: AVAssetExportPresetPassthrough
            ) else {
                throw PlaybackVideoExportError.cannotMuxAudio("无法创建音视频合成器。")
            }
            try await exportSession.export(to: outputURL, as: settings.container.fileType)
        } catch let error as PlaybackVideoExportError {
            throw error
        } catch {
            throw PlaybackVideoExportError.cannotMuxAudio(error.localizedDescription)
        }
    }
}
