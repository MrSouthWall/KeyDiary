@preconcurrency import AVFoundation
import XCTest
@testable import KeyDiary

final class KeyboardPixelFrameTests: XCTestCase {
    @MainActor
    func testBundledBadAppleDecodesIntoChangingKeyboardPixels() async throws {
        let player = KeyboardVideoPlayer()
        player.loadBundledBadAppleIfNeeded(autoplay: false)

        for _ in 0..<80 where player.duration == 0 {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertGreaterThan(player.duration, 200)

        player.seek(to: 0.1)
        player.play()
        for _ in 0..<80 {
            let distinctColors = Set(player.pixelFrame.pixels)
            if player.currentTime > 1, distinctColors.count > 1 { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        player.pause()

        XCTAssertGreaterThan(player.currentTime, 1)
        XCTAssertGreaterThan(Set(player.pixelFrame.pixels).count, 1)
        XCTAssertEqual(player.colorMode, .binary)
        XCTAssertTrue(player.pixelFrame.pixels.allSatisfy { $0 == .black || $0 == .white })
        XCTAssertNil(player.errorMessage)
    }

    func testSamplerMapsFourteenBySixSourceDirectlyToKeys() {
        let frame = KeyboardPixelFrame.sampling(
            sourceWidth: 14,
            sourceHeight: 6,
            colorMode: .color,
            framingMode: .fill,
            isInverted: false
        ) { x, y in
            (x == 7 || y == 3)
                ? KeyboardPixel(red: 1, green: 1, blue: 1)
                : .black
        }

        XCTAssertEqual(frame[0, 7].luminance, 1)
        XCTAssertEqual(frame[3, 0].luminance, 1)
        XCTAssertEqual(frame[3, 13].luminance, 1)
        XCTAssertEqual(frame[0, 0].luminance, 0)
        XCTAssertEqual(frame[5, 13].luminance, 0)
    }

    func testSamplerCropsFourByThreeVideoForWideKeyboard() {
        let frame = KeyboardPixelFrame.sampling(
            sourceWidth: 512,
            sourceHeight: 384,
            colorMode: .color,
            framingMode: .fill,
            isInverted: false
        ) { _, y in
            let level = Double(y) / 383
            return KeyboardPixel(red: level, green: level, blue: level)
        }

        // Aspect-fill crops the top and bottom rather than wasting keys on side bars.
        XCTAssertGreaterThan(frame[0, 0].luminance, 0.2)
        XCTAssertLessThan(frame[5, 0].luminance, 0.8)
        XCTAssertLessThan(frame[0, 0].luminance, frame[5, 0].luminance)
    }

    func testRGBSamplingAndInversionPreserveColorChannels() {
        let normal = KeyboardPixelFrame.sampling(
            sourceWidth: 14,
            sourceHeight: 6,
            colorMode: .color,
            framingMode: .fill,
            isInverted: false
        ) { x, _ in
            x < 7
                ? KeyboardPixel(red: 1, green: 0, blue: 0)
                : KeyboardPixel(red: 0, green: 0.25, blue: 1)
        }
        let inverted = KeyboardPixelFrame.sampling(
            sourceWidth: 14,
            sourceHeight: 6,
            colorMode: .color,
            framingMode: .fill,
            isInverted: true
        ) { x, _ in
            x < 7
                ? KeyboardPixel(red: 1, green: 0, blue: 0)
                : KeyboardPixel(red: 0, green: 0.25, blue: 1)
        }

        XCTAssertEqual(normal[2, 1], KeyboardPixel(red: 1, green: 0, blue: 0))
        XCTAssertEqual(normal[2, 12], KeyboardPixel(red: 0, green: 0.25, blue: 1))
        XCTAssertEqual(inverted[2, 1], KeyboardPixel(red: 0, green: 1, blue: 1))
        XCTAssertEqual(inverted[2, 12], KeyboardPixel(red: 1, green: 0.75, blue: 0))
    }

    func testBinaryModeProducesOnlyBlackAndWhitePixels() {
        let frame = KeyboardPixelFrame.sampling(
            sourceWidth: 14,
            sourceHeight: 6,
            colorMode: .binary,
            framingMode: .stretch,
            isInverted: false
        ) { x, _ in
            let level = x < 7 ? 0.49 : 0.51
            return KeyboardPixel(red: level, green: level, blue: level)
        }

        XCTAssertEqual(frame[2, 1], .black)
        XCTAssertEqual(frame[2, 12], .white)
        XCTAssertTrue(frame.pixels.allSatisfy { $0 == .black || $0 == .white })
    }

    func testFitKeepsWholeImageAndAddsBlackBars() {
        let frame = KeyboardPixelFrame.sampling(
            sourceWidth: 6,
            sourceHeight: 6,
            colorMode: .color,
            framingMode: .fit,
            isInverted: false
        ) { _, _ in .white }

        XCTAssertEqual(frame[2, 0], .black)
        XCTAssertEqual(frame[2, 13], .black)
        XCTAssertEqual(frame[2, 6], .white)
        XCTAssertEqual(frame[2, 7], .white)
    }

    func testStretchUsesTheWholeSourceWithoutCropping() {
        let frame = KeyboardPixelFrame.sampling(
            sourceWidth: 512,
            sourceHeight: 384,
            colorMode: .color,
            framingMode: .stretch,
            isInverted: false
        ) { _, y in
            let level = Double(y) / 383
            return KeyboardPixel(red: level, green: level, blue: level)
        }

        XCTAssertLessThan(frame[0, 0].luminance, 0.1)
        XCTAssertGreaterThan(frame[5, 0].luminance, 0.9)
    }

    func testKeycapMappingAvoidsFlatBlackAndWhiteWhileKeepingHue() {
        let blackKeycap = KeyboardPixel.black.keycapColor
        let whiteKeycap = KeyboardPixel(red: 1, green: 1, blue: 1).keycapColor
        let redKeycap = KeyboardPixel(red: 1, green: 0, blue: 0).keycapColor

        XCTAssertLessThanOrEqual(blackKeycap.luminance, 0.05)
        XCTAssertGreaterThanOrEqual(whiteKeycap.luminance, 0.95)
        XCTAssertGreaterThan(whiteKeycap.luminance - blackKeycap.luminance, 0.9)
        XCTAssertGreaterThan(redKeycap.red, redKeycap.green)
        XCTAssertGreaterThan(redKeycap.red, redKeycap.blue)
    }

    @MainActor
    func testCinemaExporterCreatesReadableMP4WithOriginalAudio() async throws {
        let sourceURL = try XCTUnwrap(
            Bundle.main.url(forResource: "BadApple", withExtension: "mp4")
        )
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("KeyDiaryCinemaTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: folder)
        }
        let outputURL = folder.appendingPathComponent("cinema.mp4")
        let exporter = KeyboardCinemaVideoExporter(
            configuration: PlaybackVideoConfiguration(
                width: 640,
                height: 360,
                averageBitRate: 1_000_000
            ),
            maximumDuration: 0.25
        )
        var latestProgress = 0.0

        try await exporter.export(
            source: KeyboardCinemaExportSource(
                url: sourceURL,
                title: "Bad Apple!! 影絵 PV",
                colorMode: .binary,
                framingMode: .fill,
                isInverted: false
            ),
            settings: PlaybackVideoSettings(
                container: .mp4,
                codec: .h264,
                resolution: .hd720,
                frameRate: .fps24
            ),
            to: outputURL
        ) { progress in
            latestProgress = progress
        }

        let asset = AVURLAsset(url: outputURL)
        let duration = try await asset.load(.duration)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let videoTrack = try XCTUnwrap(videoTracks.first)
        let size = try await videoTrack.load(.naturalSize)
        let generator = AVAssetImageGenerator(asset: asset)
        _ = try await generator.image(at: CMTime(seconds: 0.1, preferredTimescale: 600)).image

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        XCTAssertEqual(duration.seconds, 0.25, accuracy: 0.05)
        XCTAssertEqual(size.width, 640)
        XCTAssertEqual(size.height, 360)
        XCTAssertEqual(audioTracks.count, 1)
        XCTAssertEqual(latestProgress, 1, accuracy: 0.001)
    }
}
