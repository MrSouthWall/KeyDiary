import Foundation
import XCTest
@testable import KeyDiary

@MainActor
final class KeyDiaryStoreTests: XCTestCase {
    func testRecentRangeRollsForwardAtMidnight() throws {
        let calendar = Calendar.current
        let firstDay = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 26,
            hour: 12
        )))
        let secondDay = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: firstDay))
        let archive = makeArchive()
        archive.flush([
            makeRecord(at: firstDay, keyCode: 0, key: "A"),
            makeRecord(at: secondDay, keyCode: 1, key: "S")
        ])

        let store = KeyDiaryStore(archive: archive, now: firstDay)
        store.selectRecentDays(7, now: firstDay)
        store.refreshDateDependentState(now: secondDay)

        XCTAssertEqual(store.pressesToday, 1)
        XCTAssertEqual(store.filteredRecords.count, 2)
        XCTAssertEqual(store.toDate, endOfDay(secondDay, calendar: calendar))
        XCTAssertEqual(
            store.fromDate,
            calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: secondDay))
        )
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
        let store = KeyDiaryStore(archive: makeArchive(), now: start)

        store.selectCustomRange(from: start, to: end)
        store.refreshDateDependentState(now: nextDay)

        XCTAssertEqual(store.fromDate, start)
        XCTAssertEqual(store.toDate, end)
    }

    func testApplicationFilterUsesCachedRecords() throws {
        let now = Date()
        let archive = makeArchive()
        archive.flush([
            makeRecord(at: now, keyCode: 0, key: "A", application: "Notes"),
            makeRecord(at: now, keyCode: 1, key: "S", application: "Safari")
        ])
        let store = KeyDiaryStore(archive: archive, now: now)

        store.selectedApplication = "Safari"

        XCTAssertEqual(store.applications, ["All apps", "Notes", "Safari"])
        XCTAssertEqual(store.filteredRecords.map(\.applicationName), ["Safari"])
        XCTAssertEqual(store.filteredKeyCounts, [1: 1])
    }

    func testSynchronousFlushWinsOverQueuedSave() {
        let archive = makeArchive()
        let oldRecord = makeRecord(at: .now, keyCode: 0, key: "A")
        let latestRecord = makeRecord(at: .now, keyCode: 1, key: "S")

        archive.save([oldRecord])
        archive.flush([latestRecord])

        XCTAssertEqual(archive.load(), [latestRecord])
    }

    private func makeArchive() -> KeyPressArchive {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("KeyDiaryTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: folder)
        }
        return KeyPressArchive(fileURL: folder.appendingPathComponent("records.json"))
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

    private func endOfDay(_ date: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))?
            .addingTimeInterval(-1) ?? date
    }
}
