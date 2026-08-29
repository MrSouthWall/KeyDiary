import AppKit
import AVFoundation
import Foundation
import SwiftUI
import XCTest
@testable import KeyDiary

@MainActor
final class KeyDiaryStoreTests: XCTestCase {
    func testKeySoundStylesAndPianoLayoutAreStable() {
        XCTAssertEqual(KeySoundStyle.allCases, [
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
            .topre,
            .pianoImprovisation,
            .pianoKeyboard,
            .pianoMelody
        ])
        XCTAssertEqual(KeySoundPreferences.defaultStyle, .cherryMXBrown)
        XCTAssertEqual(KeySoundStyle(rawValue: "mechanicalRed"), .gateronRedInk)
        XCTAssertEqual(KeySoundStyle(rawValue: "physicalKeyboard"), .cherryMXBrown)
        XCTAssertEqual(KeySoundStyle(rawValue: "mechanicalBlue"), .cherryMXBlue)
        XCTAssertEqual(KeySoundStyle(rawValue: "piano"), .pianoImprovisation)
        XCTAssertEqual(KeySoundPlayer.pianoMIDINote(for: 0), 60)
        XCTAssertEqual(KeySoundPlayer.pianoMIDINote(for: 1), 62)
        XCTAssertEqual(KeySoundPlayer.pianoMIDINote(for: 14), 64)
        XCTAssertEqual(KeySoundPlayer.pianoMIDINote(for: 12), 76)
        XCTAssertEqual(KeySoundPlayer.pianoMIDINote(for: 49), 48)
        XCTAssertEqual(KeySoundPlayer.pianoMIDINote(for: 36), 43)
    }

    func testMechanicalAndPianoStyleGroupsAreComplete() {
        XCTAssertEqual(KeySoundStyle.mechanicalStyles, [
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
        ])
        XCTAssertEqual(KeySoundStyle.pianoStyles, [
            .pianoImprovisation,
            .pianoKeyboard,
            .pianoMelody
        ])
        XCTAssertTrue(KeySoundStyle.mechanicalStyles.allSatisfy(\.isMechanical))
        XCTAssertTrue(KeySoundStyle.pianoStyles.allSatisfy { !$0.isMechanical })
        XCTAssertEqual(Set(KeySoundStyle.mechanicalStyles.compactMap(\.kbsimIdentifier)).count, 13)
    }

    func testMechanicalSamplesResolveSpecialKeysAndPhysicalRows() {
        XCTAssertEqual(KeySoundPlayer.mechanicalSampleName(keyCode: 49, isRelease: false), "SPACE")
        XCTAssertEqual(KeySoundPlayer.mechanicalSampleName(keyCode: 36, isRelease: false), "ENTER")
        XCTAssertEqual(KeySoundPlayer.mechanicalSampleName(keyCode: 51, isRelease: false), "BACKSPACE")
        XCTAssertEqual(KeySoundPlayer.mechanicalSampleName(keyCode: 18, isRelease: false), "GENERIC_R1")
        XCTAssertEqual(KeySoundPlayer.mechanicalSampleName(keyCode: 12, isRelease: false), "GENERIC_R2")
        XCTAssertEqual(KeySoundPlayer.mechanicalSampleName(keyCode: 0, isRelease: false), "GENERIC_R3")
        XCTAssertEqual(KeySoundPlayer.mechanicalSampleName(keyCode: 6, isRelease: false), "GENERIC_R4")
        XCTAssertEqual(KeySoundPlayer.mechanicalSampleName(keyCode: 0, isRelease: true), "GENERIC")
    }

    func testAllKbsimStylesHaveBundledPressAndReleaseSamples() throws {
        for style in KeySoundStyle.mechanicalStyles {
            let identifier = try XCTUnwrap(style.kbsimIdentifier)
            var sampleNames = (0...4).map { "\(identifier)_press_GENERIC_R\($0)" }
            sampleNames.append("\(identifier)_release_GENERIC")

            if style != .cherryMXBlue {
                for specialKey in ["SPACE", "ENTER", "BACKSPACE"] {
                    sampleNames.append("\(identifier)_press_\(specialKey)")
                    sampleNames.append("\(identifier)_release_\(specialKey)")
                }
            }

            for sampleName in sampleNames {
                XCTAssertNotNil(
                    Bundle.main.url(forResource: sampleName, withExtension: "mp3"),
                    "Missing bundled kbsim sample \(sampleName).mp3"
                )
            }
        }

        let sampleURL = try XCTUnwrap(
            Bundle.main.url(forResource: "mxbrown_press_GENERIC_R2", withExtension: "mp3")
        )
        let audioFile = try AVAudioFile(forReading: sampleURL)
        XCTAssertGreaterThan(audioFile.length, 0)
        XCTAssertNotNil(Bundle.main.url(forResource: "kbsim-LICENSE", withExtension: "txt"))
    }

    func testPianoTypingMapUsesFrequencyRolesAndOnlyPentatonicNotes() {
        XCTAssertEqual(KeySoundPlayer.pianoVoice(for: 14).role, .frequent) // E
        XCTAssertEqual(KeySoundPlayer.pianoVoice(for: 8).role, .supporting) // C
        XCTAssertEqual(KeySoundPlayer.pianoVoice(for: 6).role, .accent) // Z
        XCTAssertEqual(KeySoundPlayer.pianoVoice(for: 49).role, .structural) // Space

        let pentatonicPitchClasses: Set<Int> = [0, 2, 4, 7, 9]
        for keyCode in UInt16(0)...UInt16(127) {
            let voice = KeySoundPlayer.pianoVoice(for: keyCode)
            XCTAssertTrue(
                pentatonicPitchClasses.contains(voice.midiNote % 12),
                "Key code \(keyCode) leaves the pentatonic scale"
            )
            XCTAssertTrue((43...93).contains(voice.midiNote))
        }

        let frequentLetterKeyCodes: [UInt16] = [14, 17, 0, 31, 34, 45, 1, 4, 15, 2, 37, 32, 5]
        XCTAssertTrue(frequentLetterKeyCodes.allSatisfy {
            (60...69).contains(KeySoundPlayer.pianoMIDINote(for: $0))
        })
    }

    func testKeyboardPianoMapProvidesWhiteAndBlackKeysAcrossTwoRows() {
        // Lower row: Z, S, X, D, C maps chromatically from C3.
        XCTAssertEqual(KeySoundPlayer.keyboardPianoVoice(for: 6).midiNote, 48)
        XCTAssertEqual(KeySoundPlayer.keyboardPianoVoice(for: 1).midiNote, 49)
        XCTAssertEqual(KeySoundPlayer.keyboardPianoVoice(for: 7).midiNote, 50)
        XCTAssertEqual(KeySoundPlayer.keyboardPianoVoice(for: 2).midiNote, 51)
        XCTAssertEqual(KeySoundPlayer.keyboardPianoVoice(for: 8).midiNote, 52)

        // Upper row: Q, 2, W, 3, E maps chromatically from C4.
        XCTAssertEqual(KeySoundPlayer.keyboardPianoVoice(for: 12).midiNote, 60)
        XCTAssertEqual(KeySoundPlayer.keyboardPianoVoice(for: 19).midiNote, 61)
        XCTAssertEqual(KeySoundPlayer.keyboardPianoVoice(for: 13).midiNote, 62)
        XCTAssertEqual(KeySoundPlayer.keyboardPianoVoice(for: 20).midiNote, 63)
        XCTAssertEqual(KeySoundPlayer.keyboardPianoVoice(for: 14).midiNote, 64)
    }

    func testAutomaticMelodyLoopsThroughAConsonantPresetPhrase() {
        let expectedOpening = [60, 64, 67, 69, 67, 64, 62, 64]
        XCTAssertEqual(
            (0..<expectedOpening.count).map { KeySoundPlayer.melodyPianoVoice(at: $0).midiNote },
            expectedOpening
        )
        XCTAssertEqual(
            KeySoundPlayer.melodyPianoVoice(at: 0).midiNote,
            KeySoundPlayer.melodyPianoVoice(at: 48).midiNote
        )

        let pentatonicPitchClasses: Set<Int> = [0, 2, 4, 7, 9]
        XCTAssertTrue((0..<48).allSatisfy {
            pentatonicPitchClasses.contains(KeySoundPlayer.melodyPianoVoice(at: $0).midiNote % 12)
        })
    }

    func testRecentRangeRollsForwardAtMidnight() throws {
        let calendar = Calendar.current
        let firstDay = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 26,
            hour: 12
        )))
        let secondDay = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: firstDay))
        let database = try makeDatabase()
        _ = try database.insert([
            makeRecord(at: firstDay, keyCode: 0, key: "A"),
            makeRecord(at: secondDay, keyCode: 1, key: "S")
        ])

        let store = KeyDiaryStore(database: database, now: firstDay)
        store.selectRecentDays(7, now: firstDay)
        store.refreshDateDependentState(now: secondDay)

        XCTAssertEqual(store.pressesToday, 1)
        XCTAssertEqual(store.filteredRecordCount, 2)
        XCTAssertEqual(store.toDate, endOfDay(secondDay, calendar: calendar))
        XCTAssertEqual(
            store.fromDate,
            calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: secondDay))
        )
    }

    func testDefaultDateRangeIsToday() throws {
        let calendar = Calendar.current
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 26,
            hour: 12
        )))
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: now))
        let database = try makeDatabase()
        _ = try database.insert([
            makeRecord(at: yesterday, keyCode: 0, key: "A"),
            makeRecord(at: now, keyCode: 1, key: "S")
        ])

        let store = KeyDiaryStore(database: database, now: now)

        XCTAssertEqual(store.selectedDateRangeSelection, .recentDays(1))
        XCTAssertEqual(store.selectedDateRangeTitle, L10n.text("今天"))
        XCTAssertEqual(store.fromDate, calendar.startOfDay(for: now))
        XCTAssertEqual(store.toDate, endOfDay(now, calendar: calendar))
        XCTAssertEqual(store.filteredRecordCount, 1)
        XCTAssertEqual(store.filteredKeyCounts, [1: 1])
    }

    func testCustomRangeDoesNotMoveAtMidnight() throws {
        let calendar = Calendar.current
        let start = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 26,
            hour: 10
        )))
        let end = start.addingTimeInterval(3_600)
        let nextDay = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: start))
        let store = KeyDiaryStore(database: try makeDatabase(), now: start)

        store.selectCustomRange(from: start, to: end)
        store.refreshDateDependentState(now: nextDay)

        XCTAssertEqual(store.fromDate, start)
        XCTAssertEqual(store.toDate, end)
    }

    func testApplicationFilterUsesDatabaseAggregates() throws {
        let now = Date()
        let database = try makeDatabase()
        _ = try database.insert([
            makeRecord(at: now, keyCode: 0, key: "A", application: "Notes"),
            makeRecord(at: now, keyCode: 1, key: "S", application: "Safari")
        ])
        let store = KeyDiaryStore(database: database, now: now)

        store.selectedApplication = "Safari"

        XCTAssertEqual(store.applications, ["All apps", "Notes", "Safari"])
        XCTAssertEqual(store.filteredRecordCount, 1)
        XCTAssertEqual(store.filteredKeyCounts, [1: 1])
    }

    func testPlaybackDurationMatchesDatabaseTimingAndSpeed() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let database = try makeDatabase()
        _ = try database.insert([
            makeRecord(at: now, keyCode: 0, key: "A"),
            makeRecord(at: now.addingTimeInterval(1), keyCode: 1, key: "S"),
            makeRecord(at: now.addingTimeInterval(4), keyCode: 2, key: "D")
        ])
        let store = KeyDiaryStore(database: database, now: now.addingTimeInterval(4))

        XCTAssertEqual(store.selectedDateRangeTitle, L10n.text("今天"))
        XCTAssertEqual(store.estimatedPlaybackDuration, 1.54, accuracy: 0.001)
        XCTAssertEqual(store.estimatedPlaybackDurationTitle, L10n.format("%lld 秒", Int64(2)))

        store.playbackSpeed = 2

        XCTAssertEqual(store.estimatedPlaybackDuration, 0.77, accuracy: 0.001)

        store.playbackSpeed = 0.5

        XCTAssertEqual(store.estimatedPlaybackDuration, 3.08, accuracy: 0.001)
    }

    func testPlaybackSpeedPresetsAndSliderRange() {
        XCTAssertEqual(PlaybackTiming.speedPresets, [1, 2, 4, 8, 16])
        XCTAssertEqual(PlaybackTiming.speedRange.lowerBound, 1)
        XCTAssertEqual(PlaybackTiming.speedRange.upperBound, 16)
    }

    func testPlaybackRangeControlsPlaybackCountAndDuration() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let database = try makeDatabase()
        _ = try database.insert([
            makeRecord(at: start, keyCode: 0, key: "A"),
            makeRecord(at: start.addingTimeInterval(10), keyCode: 1, key: "S"),
            makeRecord(at: start.addingTimeInterval(20), keyCode: 2, key: "D")
        ])
        let store = KeyDiaryStore(database: database, now: start.addingTimeInterval(20))

        store.setPlaybackRange(startFraction: 0.25, endFraction: 0.75)

        XCTAssertEqual(store.playbackSelectionStart, start.addingTimeInterval(5))
        XCTAssertEqual(store.playbackSelectionEnd, start.addingTimeInterval(15))
        XCTAssertEqual(store.playbackRecordCount, 1)
        XCTAssertEqual(store.estimatedPlaybackDuration, 0.24, accuracy: 0.001)
        XCTAssertFalse(store.isFullPlaybackRangeSelected)

        store.resetPlaybackRange()

        XCTAssertEqual(store.playbackRecordCount, 3)
        XCTAssertEqual(store.estimatedPlaybackDuration, 1.54, accuracy: 0.001)
        XCTAssertTrue(store.isFullPlaybackRangeSelected)
    }

    func testPlaybackVideoTimelineMatchesPlaybackDuration() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let records = [
            makeRecord(at: start, keyCode: 0, key: "A"),
            makeRecord(at: start.addingTimeInterval(1), keyCode: 1, key: "S"),
            makeRecord(at: start.addingTimeInterval(4), keyCode: 2, key: "D")
        ]

        let timeline = PlaybackVideoTimeline(records: records, speed: 1)

        XCTAssertEqual(timeline.events[0].presentationTime, 0.06, accuracy: 0.001)
        XCTAssertEqual(timeline.events[1].presentationTime, 0.71, accuracy: 0.001)
        XCTAssertEqual(timeline.events[2].presentationTime, 1.36, accuracy: 0.001)
        XCTAssertEqual(timeline.duration, 1.54, accuracy: 0.001)
        XCTAssertEqual(timeline.events.map(\.record.key), ["A", "S", "D"])
    }

    func testPlaybackVideoSettingsCoverContainersCodecsResolutionsAndFrameRates() {
        XCTAssertEqual(PlaybackVideoContainer.allCases, [.mp4, .mov])
        XCTAssertEqual(PlaybackVideoResolution.hd720.width, 1_280)
        XCTAssertEqual(PlaybackVideoResolution.fullHD1080.height, 1_080)
        XCTAssertEqual(PlaybackVideoResolution.ultraHD4K.width, 3_840)
        XCTAssertEqual(
            PlaybackVideoFrameRate.commonCases.map(\.nominalFramesPerSecond),
            [24, 25, 30, 50, 60, 120]
        )
        XCTAssertEqual(PlaybackVideoFrameRate.fps29_97.framesPerSecond, 29.97, accuracy: 0.001)

        let transparentSettings = PlaybackVideoSettings(
            container: .mp4,
            codec: .proRes4444Alpha,
            resolution: .ultraHD4K,
            frameRate: .fps60
        )
        XCTAssertEqual(transparentSettings.container, .mov)
        XCTAssertTrue(transparentSettings.preservesAlpha)

        for container in PlaybackVideoContainer.allCases {
            XCTAssertTrue(PlaybackVideoCodec.h264.supports(container))
            XCTAssertTrue(PlaybackVideoCodec.h265.supports(container))
        }
        XCTAssertFalse(PlaybackVideoCodec.proRes4444Alpha.supports(.mp4))
        XCTAssertTrue(PlaybackVideoCodec.proRes4444Alpha.supports(.mov))
    }

    func testPlaybackVideoExporterCreatesReadableMP4() async throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let records = [
            makeRecord(at: start, keyCode: 0, key: "A"),
            makeRecord(at: start.addingTimeInterval(0.2), keyCode: 1, key: "S")
        ]
        let folder = try makeTemporaryFolder()
        let url = folder.appendingPathComponent("playback.mp4")
        let configuration = PlaybackVideoConfiguration(
            width: 640,
            height: 360,
            averageBitRate: 1_000_000
        )

        try await PlaybackVideoExporter(configuration: configuration).export(
            records: records,
            speed: 1,
            dateRangeTitle: "今天",
            applicationTitle: "Notes",
            keySoundConfiguration: KeySoundConfiguration(
                isEnabled: true,
                style: .cherryMXBrown,
                volume: 0.55
            ),
            to: url
        )

        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let track = try XCTUnwrap(tracks.first)
        let size = try await track.load(.naturalSize)
        let nominalFrameRate = try await track.load(.nominalFrameRate)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let decodedFrame = try await generator.image(at: .zero).image
        let sourceView = PlaybackVideoFrame(
            activeRecord: nil,
            progress: 0,
            dateRangeTitle: "今天",
            applicationTitle: "Notes",
            speed: 1,
            usesTransparentBackground: false
        )
        .frame(width: 640, height: 360)
        let renderer = ImageRenderer(content: sourceView)
        renderer.proposedSize = ProposedViewSize(width: 640, height: 360)
        renderer.scale = 1
        renderer.isOpaque = true
        let sourceFrame = try XCTUnwrap(renderer.cgImage)

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertGreaterThan((try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0, 0)
        XCTAssertEqual(duration.seconds, 0.44, accuracy: 0.05)
        XCTAssertEqual(size.width, 640)
        XCTAssertEqual(size.height, 360)
        XCTAssertEqual(nominalFrameRate, 30, accuracy: 0.1)
        XCTAssertEqual(audioTracks.count, 1)
        XCTAssertLessThan(
            meanPixelDifference(sourceFrame, decodedFrame, verticallyMirrored: false),
            meanPixelDifference(sourceFrame, decodedFrame, verticallyMirrored: true)
        )
    }

    func testPlaybackVideoExporterCreatesTransparentProResMOV() async throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let records = [makeRecord(at: start, keyCode: 0, key: "A")]
        let folder = try makeTemporaryFolder()
        let url = folder.appendingPathComponent("playback.mov")
        let configuration = PlaybackVideoConfiguration(
            width: 640,
            height: 360,
            averageBitRate: 1_000_000
        )

        try await PlaybackVideoExporter(configuration: configuration).export(
            records: records,
            speed: 1,
            dateRangeTitle: "今天",
            applicationTitle: "Notes",
            settings: PlaybackVideoSettings(
                container: .mov,
                codec: .proRes4444Alpha,
                resolution: .fullHD1080,
                frameRate: .fps30
            ),
            to: url
        )

        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let descriptions = try await track.load(.formatDescriptions)
        let description = try XCTUnwrap(descriptions.first)
        let size = try await track.load(.naturalSize)

        XCTAssertEqual(CMFormatDescriptionGetMediaSubType(description), kCMVideoCodecType_AppleProRes4444)
        XCTAssertEqual(size.width, 640)
        XCTAssertEqual(size.height, 360)
        XCTAssertTrue(PlaybackVideoCodec.proRes4444Alpha.preservesAlpha)
        XCTAssertEqual(PlaybackVideoContainer.mov.filenameExtension, "mov")

        let topLeftAlpha = try await decodedTopLeftAlpha(in: url)
        XCTAssertEqual(topLeftAlpha, 0)
    }

    func testPlaybackVideoExporterCreatesH265MOV() async throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let records = [makeRecord(at: start, keyCode: 0, key: "A")]
        let folder = try makeTemporaryFolder()
        let url = folder.appendingPathComponent("playback.mov")
        let configuration = PlaybackVideoConfiguration(
            width: 320,
            height: 180,
            averageBitRate: 500_000
        )

        try await PlaybackVideoExporter(configuration: configuration).export(
            records: records,
            speed: 1,
            dateRangeTitle: "今天",
            applicationTitle: "Notes",
            settings: PlaybackVideoSettings(
                container: .mov,
                codec: .h265,
                resolution: .hd720,
                frameRate: .fps24
            ),
            to: url
        )

        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let descriptions = try await track.load(.formatDescriptions)
        let description = try XCTUnwrap(descriptions.first)
        let size = try await track.load(.naturalSize)

        XCTAssertEqual(CMFormatDescriptionGetMediaSubType(description), kCMVideoCodecType_HEVC)
        XCTAssertEqual(size.width, 320)
        XCTAssertEqual(size.height, 180)
    }

    func testSQLiteKeepsMoreThanOneHundredThousandRecords() throws {
        let database = try makeDatabase()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let records = (0...100_000).map { index in
            makeRecord(
                at: start.addingTimeInterval(Double(index) / 1_000),
                keyCode: UInt16(index % 100),
                key: "K\(index % 100)"
            )
        }

        let result = try database.insert(records)

        XCTAssertEqual(result.inserted, 100_001)
        XCTAssertEqual(try database.count(), 100_001)
    }

    func testDataEditorFiltersPotentialIssuesAndSpecificMissingBundleIDs() throws {
        let database = try makeDatabase()
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
        let duplicateTimestamp = referenceDate.addingTimeInterval(-20)
        let normal = makeRecord(
            at: referenceDate.addingTimeInterval(-30),
            keyCode: 0,
            key: "A",
            application: "Notes"
        )
        let missingApplication = makeRecord(
            at: referenceDate.addingTimeInterval(-10),
            keyCode: 1,
            key: "S",
            application: ""
        )
        let future = makeRecord(
            at: referenceDate.addingTimeInterval(60),
            keyCode: 2,
            key: "D",
            application: "Safari"
        )
        let duplicate1 = makeRecord(
            at: duplicateTimestamp,
            keyCode: 3,
            key: "F",
            application: "Xcode"
        )
        let duplicate2 = KeyPressRecord(
            timestamp: duplicate1.timestamp,
            keyCode: duplicate1.keyCode,
            key: duplicate1.key,
            applicationName: duplicate1.applicationName,
            bundleIdentifier: duplicate1.bundleIdentifier
        )
        let missingBundle = KeyPressRecord(
            timestamp: referenceDate.addingTimeInterval(-5),
            keyCode: 4,
            key: "G",
            applicationName: "Finder",
            bundleIdentifier: nil
        )
        _ = try database.insert([
            normal,
            missingApplication,
            future,
            duplicate1,
            duplicate2,
            missingBundle
        ])

        let potentialIssues = try database.editorPage(
            query: DataEditorQuery(
                fromDate: nil,
                toDate: nil,
                applicationName: nil,
                searchText: "",
                issueFilter: .potentialIssues,
                referenceDate: referenceDate
            ),
            limit: 50,
            offset: 0
        )
        let missingBundles = try database.editorPage(
            query: DataEditorQuery(
                fromDate: nil,
                toDate: nil,
                applicationName: nil,
                searchText: "Finder",
                issueFilter: .missingBundleIdentifier,
                referenceDate: referenceDate
            ),
            limit: 50,
            offset: 0
        )

        XCTAssertEqual(potentialIssues.totalCount, 4)
        XCTAssertEqual(Set(potentialIssues.records.map(\.id)), [
            missingApplication.id,
            future.id,
            duplicate1.id,
            duplicate2.id
        ])
        XCTAssertTrue(
            potentialIssues.records
                .filter { $0.id == duplicate1.id || $0.id == duplicate2.id }
                .allSatisfy { $0.issues.contains(.suspectedDuplicate) }
        )
        XCTAssertEqual(missingBundles.records.map(\.id), [missingBundle.id])
        XCTAssertTrue(missingBundles.records[0].issues.contains(.missingBundleIdentifier))
    }

    func testDataEditorDeletesOnlyExplicitRecordIDsAndRefreshesStoreCounts() throws {
        let database = try makeDatabase()
        let timestamp = Date(timeIntervalSince1970: 1_800_000_000)
        let notes = makeRecord(at: timestamp, keyCode: 0, key: "A", application: "Notes")
        let safari = makeRecord(at: timestamp.addingTimeInterval(1), keyCode: 1, key: "S", application: "Safari")
        _ = try database.insert([notes, safari])
        let store = KeyDiaryStore(database: database, now: timestamp)
        store.selectAllRecords(now: timestamp)

        let deleted = try store.deleteRecords(ids: [notes.id])

        XCTAssertEqual(deleted, 1)
        XCTAssertEqual(store.recordCount, 1)
        XCTAssertEqual(store.filteredRecordCount, 1)
        XCTAssertEqual(try allRecords(in: database), [safari])
    }

    func testLegacyJSONMigratesOnceAndKeepsBackup() throws {
        let folder = try makeTemporaryFolder()
        let legacyURL = folder.appendingPathComponent("key-presses.json")
        let databaseURL = folder.appendingPathComponent("key-diary.sqlite")
        let records = [makeRecord(at: .now, keyCode: 0, key: "A")]
        try JSONEncoder().encode(records).write(to: legacyURL)

        let database = try KeyDiaryDatabase(databaseURL: databaseURL, legacyJSONURL: legacyURL)

        XCTAssertEqual(try database.count(), 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: folder.appendingPathComponent("key-presses.migrated.json").path
        ))
    }

    func testJSONCSVAndXLSXRoundTrip() throws {
        let source = try makeDatabase()
        let timestamp = Date(timeIntervalSince1970: 1_800_000_000.125)
        let records = [
            makeRecord(at: timestamp, keyCode: 0, key: "A", application: "Notes"),
            makeRecord(at: timestamp.addingTimeInterval(1), keyCode: 36, key: "Return", application: "Safari"),
            KeyPressRecord(
                timestamp: timestamp.addingTimeInterval(2),
                keyCode: 43,
                key: ",\"测试\n",
                applicationName: "表格, App",
                bundleIdentifier: nil
            )
        ]
        _ = try source.insert(records)
        let service = DataTransferService()
        let folder = try makeTemporaryFolder()

        for format in DataTransferFormat.allCases {
            let url = folder.appendingPathComponent("round-trip.\(format.filenameExtension)")
            let exportResult = try service.export(format: format, to: url, database: source)
            XCTAssertEqual(exportResult.exported, records.count, "Format: \(format)")

            let destination = try makeDatabase()
            let importResult = try service.importRecords(from: url, mode: .merge, database: destination)
            XCTAssertEqual(importResult.inserted, records.count, "Format: \(format)")
            XCTAssertEqual(try allRecords(in: destination), records, "Format: \(format)")
        }
    }

    func testXLSXPackageIncludesRootRelationship() throws {
        let database = try makeDatabase()
        _ = try database.insert([makeRecord(at: .now, keyCode: 0, key: "A")])
        let url = try makeTemporaryFolder().appendingPathComponent("export.xlsx")

        _ = try DataTransferService().export(format: .xlsx, to: url, database: database)

        let archiveData = try Data(contentsOf: url)
        XCTAssertNotNil(
            archiveData.range(of: Data("_rels/.rels".utf8)),
            "XLSX must include the package-level relationship that points to xl/workbook.xml"
        )
    }

    func testMergeSkipsDuplicateIDs() throws {
        let database = try makeDatabase()
        let record = makeRecord(at: .now, keyCode: 0, key: "A")
        _ = try database.insert([record])

        let result = try database.importRecords(mode: .merge) { receive in
            try receive(record)
            try receive(makeRecord(at: .now, keyCode: 1, key: "S"))
        }

        XCTAssertEqual(result.inserted, 1)
        XCTAssertEqual(result.duplicates, 1)
        XCTAssertEqual(try database.count(), 2)
    }

    func testInvalidReplaceImportRollsBack() throws {
        let database = try makeDatabase()
        let existing = makeRecord(
            at: Date(timeIntervalSince1970: 1_800_000_000.125),
            keyCode: 0,
            key: "A"
        )
        _ = try database.insert([existing])
        let folder = try makeTemporaryFolder()
        let csvURL = folder.appendingPathComponent("invalid.csv")
        let csv = """
        id,timestamp,keyCode,key,applicationName,bundleIdentifier
        \(UUID().uuidString),2026-08-27T01:00:00.000Z,1,S,Notes,com.apple.Notes
        invalid-id,2026-08-27T01:00:00.000Z,2,D,Notes,com.apple.Notes
        """
        try Data(csv.utf8).write(to: csvURL)

        XCTAssertThrowsError(
            try DataTransferService().importRecords(from: csvURL, mode: .replace, database: database)
        )
        XCTAssertEqual(try allRecords(in: database), [existing])
    }

    func testRecorderTracksMultipleKeysUntilEachKeyIsReleased() throws {
        let recorder = KeyboardRecorder()
        var pressedKeys: [UInt16: String] = [:]
        recorder.onPressedKeysChanged = { pressedKeys = $0 }

        recorder.handle(try makeKeyEvent(type: .keyDown, keyCode: 0, characters: "a"))
        recorder.handle(try makeKeyEvent(type: .keyDown, keyCode: 1, characters: "s"))

        XCTAssertEqual(Set(pressedKeys.keys), [0, 1])

        recorder.handle(try makeKeyEvent(type: .keyUp, keyCode: 0, characters: "a"))
        XCTAssertEqual(Set(pressedKeys.keys), [1])

        recorder.handle(try makeKeyEvent(type: .keyUp, keyCode: 1, characters: "s"))
        XCTAssertTrue(pressedKeys.isEmpty)
    }

    func testRepeatedKeyDownStaysPressedUntilKeyUp() throws {
        let recorder = KeyboardRecorder()
        var pressedKeys: [UInt16: String] = [:]
        var recordedPressCount = 0
        recorder.onPressedKeysChanged = { pressedKeys = $0 }
        recorder.onKeyPress = { _ in recordedPressCount += 1 }

        recorder.handle(try makeKeyEvent(type: .keyDown, keyCode: 0, characters: "a"))
        recorder.handle(try makeKeyEvent(type: .keyDown, keyCode: 0, characters: "a", isARepeat: true))

        XCTAssertEqual(pressedKeys, [0: "A"])
        XCTAssertEqual(recordedPressCount, 2)

        recorder.handle(try makeKeyEvent(type: .keyUp, keyCode: 0, characters: "a"))
        XCTAssertTrue(pressedKeys.isEmpty)
    }

    func testRecorderPublishesCapsLockStateFromModifierFlags() throws {
        let recorder = KeyboardRecorder()
        let expectedState = !recorder.isCapsLockEnabled
        var observedState: Bool?
        recorder.onCapsLockStateChanged = { observedState = $0 }

        recorder.handle(
            try makeKeyEvent(
                type: .flagsChanged,
                keyCode: 57,
                characters: "",
                modifierFlags: expectedState ? [.capsLock] : []
            )
        )

        XCTAssertEqual(recorder.isCapsLockEnabled, expectedState)
        XCTAssertEqual(observedState, expectedState)
    }

    private func makeDatabase() throws -> KeyDiaryDatabase {
        let folder = try makeTemporaryFolder()
        return try KeyDiaryDatabase(databaseURL: folder.appendingPathComponent("key-diary.sqlite"))
    }

    private func makeTemporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("KeyDiaryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: folder)
        }
        return folder
    }

    private func allRecords(in database: KeyDiaryDatabase) throws -> [KeyPressRecord] {
        var records: [KeyPressRecord] = []
        try database.forEachRecord { records.append($0) }
        return records
    }

    private func meanPixelDifference(
        _ lhs: CGImage,
        _ rhs: CGImage,
        verticallyMirrored: Bool
    ) -> Double {
        let lhsBitmap = NSBitmapImageRep(cgImage: lhs)
        let rhsBitmap = NSBitmapImageRep(cgImage: rhs)
        let width = min(lhsBitmap.pixelsWide, rhsBitmap.pixelsWide)
        let height = min(lhsBitmap.pixelsHigh, rhsBitmap.pixelsHigh)
        var difference = 0.0
        var sampleCount = 0

        for y in stride(from: 6, to: height - 6, by: 12) {
            let rhsY = verticallyMirrored ? height - 1 - y : y
            for x in stride(from: 6, to: width - 6, by: 12) {
                guard let lhsColor = lhsBitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      let rhsColor = rhsBitmap.colorAt(x: x, y: rhsY)?.usingColorSpace(.deviceRGB) else {
                    continue
                }
                difference += abs(lhsColor.redComponent - rhsColor.redComponent)
                difference += abs(lhsColor.greenComponent - rhsColor.greenComponent)
                difference += abs(lhsColor.blueComponent - rhsColor.blueComponent)
                sampleCount += 3
            }
        }

        return sampleCount == 0 ? .infinity : difference / Double(sampleCount)
    }

    nonisolated private func decodedTopLeftAlpha(in url: URL) async throws -> UInt8 {
        try await Task.detached {
            let asset = AVURLAsset(url: url)
            guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(
                track: track,
                outputSettings: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ]
            )
            guard reader.canAdd(output) else { throw CocoaError(.featureUnsupported) }
            reader.add(output)
            guard reader.startReading(),
                  let sampleBuffer = output.copyNextSampleBuffer(),
                  let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                throw CocoaError(.fileReadCorruptFile)
            }

            CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
            guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return baseAddress.load(fromByteOffset: 3, as: UInt8.self)
        }.value
    }

    private func makeRecord(
        at date: Date,
        keyCode: UInt16,
        key: String,
        application: String = "Notes"
    ) -> KeyPressRecord {
        KeyPressRecord(
            timestamp: date,
            keyCode: keyCode,
            key: key,
            applicationName: application,
            bundleIdentifier: "com.example.\(application.lowercased())"
        )
    }

    private func makeKeyEvent(
        type: NSEvent.EventType,
        keyCode: UInt16,
        characters: String,
        modifierFlags: NSEvent.ModifierFlags = [],
        isARepeat: Bool = false
    ) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: type,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: isARepeat,
            keyCode: keyCode
        ))
    }

    private func endOfDay(_ date: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))?
            .addingTimeInterval(-0.001) ?? date
    }
}
