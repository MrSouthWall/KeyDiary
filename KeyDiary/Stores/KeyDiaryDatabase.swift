//
//  KeyDiaryDatabase.swift
//  KeyDiary
//

import Foundation
import OSLog
import SQLite3

nonisolated struct KeyDiaryRecordQuery: Sendable {
    let fromDate: Date?
    let toDate: Date?
    let applicationNames: [String]?

    static let all = KeyDiaryRecordQuery(fromDate: nil, toDate: nil, applicationNames: nil)
}

nonisolated enum DataImportMode: Sendable {
    case merge
    case replace
}

nonisolated struct DataImportResult: Equatable, Sendable {
    let inserted: Int
    let duplicates: Int
    let total: Int
}

nonisolated struct KeyPressRecordCursor: Sendable {
    let timestampMilliseconds: Int64
    let id: UUID
}

nonisolated struct PlaybackMetrics: Sendable {
    let count: Int
    let duration: TimeInterval
    let firstTimestamp: Date?
    let lastTimestamp: Date?
}

nonisolated enum KeyDiaryDatabaseError: LocalizedError {
    case open(String)
    case statement(String)
    case invalidRecord

    var errorDescription: String? {
        switch self {
        case .open(let message):
            L10n.format("无法打开本地数据库：%@", message)
        case .statement(let message):
            L10n.format("数据库操作失败：%@", message)
        case .invalidRecord:
            L10n.text("数据文件中包含无法写入的记录。")
        }
    }
}

/// A single-connection SQLite store. Every operation is serialized on `queue`,
/// which keeps SQLite access off the main actor and makes transactions atomic.
nonisolated final class KeyDiaryDatabase: @unchecked Sendable {
    typealias RecordReceiver = (KeyPressRecord) throws -> Void
    typealias MouseClickRecordReceiver = (MouseClickRecord) throws -> Void
    typealias RecordProducer = (_ receive: @escaping RecordReceiver) throws -> Void
    typealias InputProducer = (
        _ receiveKeyPress: @escaping RecordReceiver,
        _ receiveMouseClick: @escaping MouseClickRecordReceiver
    ) throws -> Void

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private let queue = DispatchQueue(label: "com.MrSouthWall.KeyDiary.database", qos: .utility)
    private let logger = Logger(subsystem: "com.MrSouthWall.KeyDiary", category: "Database")
    private let databaseURL: URL?
    private var connection: OpaquePointer?

    static var defaultDatabaseURL: URL {
        applicationSupportFolder.appendingPathComponent("key-diary.sqlite")
    }

    static var legacyJSONURL: URL {
        applicationSupportFolder.appendingPathComponent("key-presses.json")
    }

    private static var applicationSupportFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KeyDiary", isDirectory: true)
    }

    init(databaseURL: URL, legacyJSONURL: URL? = nil) throws {
        self.databaseURL = databaseURL
        try Self.prepareFolder(for: databaseURL)
        try open(path: databaseURL.path)
        try configure()
        try createSchema()
        try migrateLegacyJSONIfNeeded(from: legacyJSONURL)
        Self.protectDatabaseFiles(at: databaseURL)
    }

    init(inMemory: Bool) throws {
        precondition(inMemory)
        databaseURL = nil
        try open(path: ":memory:")
        try configure()
        try createSchema()
    }

    convenience init() throws {
        try self.init(
            databaseURL: Self.defaultDatabaseURL,
            legacyJSONURL: Self.legacyJSONURL
        )
    }

    deinit {
        if let connection {
            sqlite3_close_v2(connection)
        }
    }

    func insert(_ records: [KeyPressRecord]) throws -> DataImportResult {
        guard !records.isEmpty else {
            return DataImportResult(inserted: 0, duplicates: 0, total: 0)
        }

        return try queue.sync {
            try withTransaction {
                try insertRecords(records)
            }
        }
    }

    func insert(_ records: [MouseClickRecord]) throws {
        guard !records.isEmpty else { return }
        try queue.sync {
            try withTransaction {
                try insertMouseClickRecords(records)
            }
        }
    }

    func insertInputsAsync(
        keyPresses: [KeyPressRecord],
        mouseClicks: [MouseClickRecord],
        completion: @escaping @Sendable (Result<Void, Error>) -> Void
    ) {
        guard !keyPresses.isEmpty || !mouseClicks.isEmpty else {
            completion(.success(()))
            return
        }

        queue.async { [self] in
            do {
                try withTransaction {
                    _ = try insertRecords(keyPresses)
                    try insertMouseClickRecords(mouseClicks)
                }
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        }
    }

    func insertInputs(
        keyPresses: [KeyPressRecord],
        mouseClicks: [MouseClickRecord]
    ) throws {
        guard !keyPresses.isEmpty || !mouseClicks.isEmpty else { return }
        try queue.sync {
            try withTransaction {
                _ = try insertRecords(keyPresses)
                try insertMouseClickRecords(mouseClicks)
            }
        }
    }

    func importRecords(mode: DataImportMode, producer: RecordProducer) throws -> DataImportResult {
        try importInputs(mode: mode) { receiveKeyPress, _ in
            try producer(receiveKeyPress)
        }
    }

    func importInputs(mode: DataImportMode, producer: InputProducer) throws -> DataImportResult {
        try queue.sync {
            try withTransaction {
                if mode == .replace {
                    try execute("DELETE FROM key_press_records;")
                    try execute("DELETE FROM mouse_click_records;")
                }

                let keyPressStatement = try prepare(Self.insertSQL)
                defer { sqlite3_finalize(keyPressStatement) }
                let mouseClickStatement = try prepare(Self.insertMouseClickSQL)
                defer { sqlite3_finalize(mouseClickStatement) }

                var total = 0
                var inserted = 0
                try producer({ [self] record in
                    total += 1
                    try bind(record, to: keyPressStatement)
                    guard sqlite3_step(keyPressStatement) == SQLITE_DONE else {
                        throw statementError()
                    }
                    if sqlite3_changes(connection) > 0 {
                        inserted += 1
                    }
                    sqlite3_reset(keyPressStatement)
                    sqlite3_clear_bindings(keyPressStatement)
                }, { [self] record in
                    total += 1
                    try bind(record, to: mouseClickStatement)
                    guard sqlite3_step(mouseClickStatement) == SQLITE_DONE else {
                        throw statementError()
                    }
                    if sqlite3_changes(connection) > 0 {
                        inserted += 1
                    }
                    sqlite3_reset(mouseClickStatement)
                    sqlite3_clear_bindings(mouseClickStatement)
                })

                return DataImportResult(
                    inserted: inserted,
                    duplicates: total - inserted,
                    total: total
                )
            }
        }
    }

    func deleteAll() throws {
        try queue.sync {
            try withTransaction {
                try execute("DELETE FROM key_press_records;")
                try execute("DELETE FROM mouse_click_records;")
            }
        }
    }

    @discardableResult
    func delete(ids: Set<UUID>) throws -> Int {
        guard !ids.isEmpty else { return 0 }

        return try queue.sync {
            try withTransaction {
                let statement = try prepare("DELETE FROM key_press_records WHERE id = ?;")
                defer { sqlite3_finalize(statement) }
                var deleted = 0

                for id in ids {
                    guard sqlite3_bind_text(
                        statement,
                        1,
                        id.uuidString.lowercased(),
                        -1,
                        Self.transient
                    ) == SQLITE_OK else {
                        throw statementError()
                    }
                    guard sqlite3_step(statement) == SQLITE_DONE else {
                        throw statementError()
                    }
                    deleted += Int(sqlite3_changes(connection))
                    sqlite3_reset(statement)
                    sqlite3_clear_bindings(statement)
                }

                return deleted
            }
        }
    }

    @discardableResult
    func deleteKeyPresses(query: KeyDiaryRecordQuery) throws -> Int {
        try queue.sync {
            try withTransaction {
                let clause = whereClause(for: query)
                let statement = try prepare("DELETE FROM key_press_records\(clause.sql);")
                defer { sqlite3_finalize(statement) }
                try bind(clause.bindings, to: statement)
                guard sqlite3_step(statement) == SQLITE_DONE else {
                    throw statementError()
                }
                return Int(sqlite3_changes(connection))
            }
        }
    }

    func count(query: KeyDiaryRecordQuery = .all) throws -> Int {
        try queue.sync {
            let clause = whereClause(for: query)
            let statement = try prepare("SELECT COUNT(*) FROM key_press_records\(clause.sql);")
            defer { sqlite3_finalize(statement) }
            try bind(clause.bindings, to: statement)
            guard sqlite3_step(statement) == SQLITE_ROW else { throw statementError() }
            return Int(sqlite3_column_int64(statement, 0))
        }
    }

    func mouseClickCount(query: KeyDiaryRecordQuery = .all) throws -> Int {
        try queue.sync {
            let clause = whereClause(for: query)
            let statement = try prepare("SELECT COUNT(*) FROM mouse_click_records\(clause.sql);")
            defer { sqlite3_finalize(statement) }
            try bind(clause.bindings, to: statement)
            guard sqlite3_step(statement) == SQLITE_ROW else { throw statementError() }
            return Int(sqlite3_column_int64(statement, 0))
        }
    }

    func earliestTimestamp() throws -> Date? {
        try queue.sync {
            let statement = try prepare(
                """
                SELECT MIN(timestamp_ms) FROM (
                    SELECT timestamp_ms FROM key_press_records
                    UNION ALL
                    SELECT timestamp_ms FROM mouse_click_records
                );
                """
            )
            defer { sqlite3_finalize(statement) }
            guard sqlite3_step(statement) == SQLITE_ROW else { throw statementError() }
            guard sqlite3_column_type(statement, 0) != SQLITE_NULL else { return nil }
            return Self.date(fromMilliseconds: sqlite3_column_int64(statement, 0))
        }
    }

    func applicationNames() throws -> [String] {
        try queue.sync {
            let statement = try prepare(
                """
                SELECT DISTINCT application_name FROM (
                    SELECT application_name FROM key_press_records
                    UNION ALL
                    SELECT application_name FROM mouse_click_records
                ) ORDER BY application_name COLLATE NOCASE;
                """
            )
            defer { sqlite3_finalize(statement) }

            var names: [String] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                names.append(string(from: statement, column: 0))
            }
            return names
        }
    }

    func keyCounts(query: KeyDiaryRecordQuery) throws -> [UInt16: Int] {
        try queue.sync {
            let clause = whereClause(for: query)
            let statement = try prepare(
                "SELECT key_code, COUNT(*) FROM key_press_records\(clause.sql) GROUP BY key_code;"
            )
            defer { sqlite3_finalize(statement) }
            try bind(clause.bindings, to: statement)

            var counts: [UInt16: Int] = [:]
            while sqlite3_step(statement) == SQLITE_ROW {
                let keyCode = UInt16(clamping: sqlite3_column_int(statement, 0))
                counts[keyCode] = Int(sqlite3_column_int64(statement, 1))
            }
            return counts
        }
    }

    func mouseClickCounts(query: KeyDiaryRecordQuery) throws -> MouseClickCounts {
        try queue.sync {
            let clause = whereClause(for: query)
            let statement = try prepare(
                "SELECT button, COUNT(*) FROM mouse_click_records\(clause.sql) GROUP BY button;"
            )
            defer { sqlite3_finalize(statement) }
            try bind(clause.bindings, to: statement)

            var counts = MouseClickCounts()
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let button = MouseButton(rawValue: Int(sqlite3_column_int(statement, 0))) else {
                    continue
                }
                counts[button] = Int(sqlite3_column_int64(statement, 1))
            }
            return counts
        }
    }

    func playbackMetrics(query: KeyDiaryRecordQuery, speed: Double) throws -> PlaybackMetrics {
        try queue.sync {
            let clause = whereClause(for: query)
            let statement = try prepare(
                "SELECT timestamp_ms FROM key_press_records\(clause.sql) ORDER BY timestamp_ms, id;"
            )
            defer { sqlite3_finalize(statement) }
            try bind(clause.bindings, to: statement)

            var count = 0
            var duration: TimeInterval = PlaybackTiming.finalKeyHold(at: speed)
            var first: Int64?
            var previous: Int64?
            while sqlite3_step(statement) == SQLITE_ROW {
                let current = sqlite3_column_int64(statement, 0)
                if first == nil { first = current }
                if let previous {
                    let previousDate = Self.date(fromMilliseconds: previous)
                    let currentDate = Self.date(fromMilliseconds: current)
                    duration += PlaybackTiming.delay(from: previousDate, to: currentDate, speed: speed)
                } else {
                    duration += PlaybackTiming.minimumGap / max(speed, 0.01)
                }
                previous = current
                count += 1
            }
            return PlaybackMetrics(
                count: count,
                duration: count == 0 ? 0 : duration,
                firstTimestamp: first.map(Self.date(fromMilliseconds:)),
                lastTimestamp: previous.map(Self.date(fromMilliseconds:))
            )
        }
    }

    func records(
        query: KeyDiaryRecordQuery,
        after cursor: KeyPressRecordCursor?,
        limit: Int
    ) throws -> [KeyPressRecord] {
        try queue.sync {
            var clause = whereClause(for: query)
            if let cursor {
                let cursorClause = "(timestamp_ms > ? OR (timestamp_ms = ? AND id > ?))"
                clause.sql += clause.sql.isEmpty ? " WHERE \(cursorClause)" : " AND \(cursorClause)"
                clause.bindings.append(.integer(cursor.timestampMilliseconds))
                clause.bindings.append(.integer(cursor.timestampMilliseconds))
                clause.bindings.append(.text(cursor.id.uuidString.lowercased()))
            }

            let statement = try prepare(
                Self.selectColumns + clause.sql + " ORDER BY timestamp_ms, id LIMIT ?;"
            )
            defer { sqlite3_finalize(statement) }
            var bindings = clause.bindings
            bindings.append(.integer(Int64(max(limit, 1))))
            try bind(bindings, to: statement)

            var records: [KeyPressRecord] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                records.append(try record(from: statement))
            }
            return records
        }
    }

    func editorPage(query: DataEditorQuery, limit: Int, offset: Int) throws -> DataEditorPage {
        try queue.sync {
            let clause = editorWhereClause(for: query)
            let duplicateExpression = suspectedDuplicateExpression(alias: "r")
            let countStatement = try prepare(
                "SELECT COUNT(*) FROM key_press_records r\(clause.sql);"
            )
            defer { sqlite3_finalize(countStatement) }
            try bind(clause.bindings, to: countStatement)
            guard sqlite3_step(countStatement) == SQLITE_ROW else { throw statementError() }
            let totalCount = Int(sqlite3_column_int64(countStatement, 0))

            let recordsStatement = try prepare(
                """
                SELECT r.id, r.timestamp_ms, r.key_code, r.key, r.application_name,
                       r.bundle_identifier, CASE WHEN \(duplicateExpression) THEN 1 ELSE 0 END
                FROM key_press_records r\(clause.sql)
                ORDER BY r.timestamp_ms DESC, r.id DESC
                LIMIT ? OFFSET ?;
                """
            )
            defer { sqlite3_finalize(recordsStatement) }
            var bindings = clause.bindings
            bindings.append(.integer(Int64(max(limit, 1))))
            bindings.append(.integer(Int64(max(offset, 0))))
            try bind(bindings, to: recordsStatement)

            var records: [EditableKeyPressRecord] = []
            while sqlite3_step(recordsStatement) == SQLITE_ROW {
                let record = try record(from: recordsStatement)
                var issues = qualityIssues(for: record, referenceDate: query.referenceDate)
                if sqlite3_column_int(recordsStatement, 6) != 0 {
                    issues.insert(.suspectedDuplicate)
                }
                records.append(EditableKeyPressRecord(record: record, issues: issues))
            }

            return DataEditorPage(records: records, totalCount: totalCount)
        }
    }

    func forEachRecord(
        query: KeyDiaryRecordQuery = .all,
        _ body: (KeyPressRecord) throws -> Void
    ) throws {
        try queue.sync {
            let clause = whereClause(for: query)
            let statement = try prepare(Self.selectColumns + clause.sql + " ORDER BY timestamp_ms, id;")
            defer { sqlite3_finalize(statement) }
            try bind(clause.bindings, to: statement)

            while sqlite3_step(statement) == SQLITE_ROW {
                try body(try record(from: statement))
            }
        }
    }

    func forEachMouseClickRecord(
        query: KeyDiaryRecordQuery = .all,
        _ body: (MouseClickRecord) throws -> Void
    ) throws {
        try queue.sync {
            let clause = whereClause(for: query)
            let statement = try prepare(
                Self.selectMouseClickColumns + clause.sql + " ORDER BY timestamp_ms, id;"
            )
            defer { sqlite3_finalize(statement) }
            try bind(clause.bindings, to: statement)

            while sqlite3_step(statement) == SQLITE_ROW {
                try body(try mouseClickRecord(from: statement))
            }
        }
    }

    func checkpoint() {
        queue.sync {
            guard let connection else { return }
            sqlite3_wal_checkpoint_v2(connection, nil, SQLITE_CHECKPOINT_PASSIVE, nil, nil)
            if let databaseURL {
                Self.protectDatabaseFiles(at: databaseURL)
            }
        }
    }

    private static let selectColumns = """
        SELECT id, timestamp_ms, key_code, key, application_name, bundle_identifier
        FROM key_press_records
        """

    private static let selectMouseClickColumns = """
        SELECT id, timestamp_ms, button, application_name, bundle_identifier
        FROM mouse_click_records
        """

    private static let insertSQL = """
        INSERT OR IGNORE INTO key_press_records
        (id, timestamp_ms, key_code, key, application_name, bundle_identifier)
        VALUES (?, ?, ?, ?, ?, ?);
        """

    private static let insertMouseClickSQL = """
        INSERT OR IGNORE INTO mouse_click_records
        (id, timestamp_ms, button, application_name, bundle_identifier)
        VALUES (?, ?, ?, ?, ?);
        """

    private enum Binding {
        case integer(Int64)
        case text(String)
    }

    private func editorWhereClause(
        for query: DataEditorQuery
    ) -> (sql: String, bindings: [Binding]) {
        var conditions: [String] = []
        var bindings: [Binding] = []

        if let fromDate = query.fromDate {
            conditions.append("r.timestamp_ms >= ?")
            bindings.append(.integer(Self.milliseconds(from: fromDate)))
        }
        if let toDate = query.toDate {
            conditions.append("r.timestamp_ms <= ?")
            bindings.append(.integer(Self.milliseconds(from: toDate)))
        }
        if let applicationName = query.applicationName {
            conditions.append("r.application_name = ?")
            bindings.append(.text(applicationName))
        }

        let searchText = query.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !searchText.isEmpty {
            let escaped = searchText
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "%", with: "\\%")
                .replacingOccurrences(of: "_", with: "\\_")
            conditions.append(
                """
                (r.key LIKE ? ESCAPE '\\' COLLATE NOCASE OR
                 r.application_name LIKE ? ESCAPE '\\' COLLATE NOCASE OR
                 COALESCE(r.bundle_identifier, '') LIKE ? ESCAPE '\\' COLLATE NOCASE)
                """
            )
            let pattern = "%\(escaped)%"
            bindings.append(contentsOf: [.text(pattern), .text(pattern), .text(pattern)])
        }

        let missingApplication = "TRIM(r.application_name) = '' OR LOWER(TRIM(r.application_name)) IN ('unknown', 'unknown app')"
        let missingKey = "TRIM(r.key) = '' OR LOWER(TRIM(r.key)) = 'unknown'"
        let missingBundleIdentifier = "r.bundle_identifier IS NULL OR TRIM(r.bundle_identifier) = ''"
        let futureTimestamp = "r.timestamp_ms > ?"
        let suspectedDuplicate = suspectedDuplicateExpression(alias: "r")

        switch query.issueFilter {
        case .all:
            break
        case .potentialIssues:
            conditions.append(
                "((\(missingApplication)) OR (\(missingKey)) OR (\(futureTimestamp)) OR (\(suspectedDuplicate)))"
            )
            bindings.append(.integer(Self.milliseconds(from: query.referenceDate)))
        case .missingApplication:
            conditions.append("(\(missingApplication))")
        case .missingKey:
            conditions.append("(\(missingKey))")
        case .missingBundleIdentifier:
            conditions.append("(\(missingBundleIdentifier))")
        case .futureTimestamp:
            conditions.append(futureTimestamp)
            bindings.append(.integer(Self.milliseconds(from: query.referenceDate)))
        case .suspectedDuplicate:
            conditions.append(suspectedDuplicate)
        }

        return conditions.isEmpty
            ? ("", bindings)
            : (" WHERE " + conditions.joined(separator: " AND "), bindings)
    }

    private func suspectedDuplicateExpression(alias: String) -> String {
        """
        EXISTS (
            SELECT 1 FROM key_press_records duplicate
            WHERE duplicate.id != \(alias).id
              AND duplicate.timestamp_ms = \(alias).timestamp_ms
              AND duplicate.key_code = \(alias).key_code
              AND duplicate.key = \(alias).key
              AND duplicate.application_name = \(alias).application_name
              AND COALESCE(duplicate.bundle_identifier, '') = COALESCE(\(alias).bundle_identifier, '')
        )
        """
    }

    private func qualityIssues(
        for record: KeyPressRecord,
        referenceDate: Date
    ) -> Set<DataQualityIssue> {
        var issues: Set<DataQualityIssue> = []
        let application = record.applicationName.trimmingCharacters(in: .whitespacesAndNewlines)
        if application.isEmpty || ["unknown", "unknown app"].contains(application.lowercased()) {
            issues.insert(.missingApplication)
        }
        let key = record.key.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty || key.lowercased() == "unknown" {
            issues.insert(.missingKey)
        }
        if record.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            issues.insert(.missingBundleIdentifier)
        }
        if record.timestamp > referenceDate {
            issues.insert(.futureTimestamp)
        }
        return issues
    }

    private func whereClause(for query: KeyDiaryRecordQuery) -> (sql: String, bindings: [Binding]) {
        var conditions: [String] = []
        var bindings: [Binding] = []

        if let fromDate = query.fromDate {
            conditions.append("timestamp_ms >= ?")
            bindings.append(.integer(Self.milliseconds(from: fromDate)))
        }
        if let toDate = query.toDate {
            conditions.append("timestamp_ms <= ?")
            bindings.append(.integer(Self.milliseconds(from: toDate)))
        }
        if let applicationNames = query.applicationNames, !applicationNames.isEmpty {
            let placeholders = Array(repeating: "?", count: applicationNames.count).joined(separator: ", ")
            conditions.append("application_name IN (\(placeholders))")
            bindings.append(contentsOf: applicationNames.map(Binding.text))
        }

        return conditions.isEmpty
            ? ("", bindings)
            : (" WHERE " + conditions.joined(separator: " AND "), bindings)
    }

    private func insertRecords(_ records: [KeyPressRecord]) throws -> DataImportResult {
        let statement = try prepare(Self.insertSQL)
        defer { sqlite3_finalize(statement) }
        var inserted = 0

        for record in records {
            try bind(record, to: statement)
            guard sqlite3_step(statement) == SQLITE_DONE else { throw statementError() }
            if sqlite3_changes(connection) > 0 {
                inserted += 1
            }
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
        }

        return DataImportResult(
            inserted: inserted,
            duplicates: records.count - inserted,
            total: records.count
        )
    }

    private func insertMouseClickRecords(_ records: [MouseClickRecord]) throws {
        guard !records.isEmpty else { return }
        let statement = try prepare(Self.insertMouseClickSQL)
        defer { sqlite3_finalize(statement) }

        for record in records {
            try bind(record, to: statement)
            guard sqlite3_step(statement) == SQLITE_DONE else { throw statementError() }
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
        }
    }

    private func bind(_ record: KeyPressRecord, to statement: OpaquePointer?) throws {
        let id = record.id.uuidString.lowercased()
        guard
            sqlite3_bind_text(statement, 1, id, -1, Self.transient) == SQLITE_OK,
            sqlite3_bind_int64(statement, 2, Self.milliseconds(from: record.timestamp)) == SQLITE_OK,
            sqlite3_bind_int(statement, 3, Int32(record.keyCode)) == SQLITE_OK,
            sqlite3_bind_text(statement, 4, record.key, -1, Self.transient) == SQLITE_OK,
            sqlite3_bind_text(statement, 5, record.applicationName, -1, Self.transient) == SQLITE_OK
        else {
            throw statementError()
        }

        if let bundleIdentifier = record.bundleIdentifier {
            guard sqlite3_bind_text(statement, 6, bundleIdentifier, -1, Self.transient) == SQLITE_OK else {
                throw statementError()
            }
        } else {
            sqlite3_bind_null(statement, 6)
        }
    }

    private func bind(_ record: MouseClickRecord, to statement: OpaquePointer?) throws {
        guard
            sqlite3_bind_text(
                statement,
                1,
                record.id.uuidString.lowercased(),
                -1,
                Self.transient
            ) == SQLITE_OK,
            sqlite3_bind_int64(statement, 2, Self.milliseconds(from: record.timestamp)) == SQLITE_OK,
            sqlite3_bind_int(statement, 3, Int32(record.button.rawValue)) == SQLITE_OK,
            sqlite3_bind_text(statement, 4, record.applicationName, -1, Self.transient) == SQLITE_OK
        else {
            throw statementError()
        }

        if let bundleIdentifier = record.bundleIdentifier {
            guard sqlite3_bind_text(statement, 5, bundleIdentifier, -1, Self.transient) == SQLITE_OK else {
                throw statementError()
            }
        } else {
            sqlite3_bind_null(statement, 5)
        }
    }

    private func bind(_ bindings: [Binding], to statement: OpaquePointer?) throws {
        for (offset, binding) in bindings.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch binding {
            case .integer(let value):
                result = sqlite3_bind_int64(statement, index, value)
            case .text(let value):
                result = sqlite3_bind_text(statement, index, value, -1, Self.transient)
            }
            guard result == SQLITE_OK else { throw statementError() }
        }
    }

    private func record(from statement: OpaquePointer?) throws -> KeyPressRecord {
        guard let id = UUID(uuidString: string(from: statement, column: 0)) else {
            throw KeyDiaryDatabaseError.invalidRecord
        }
        let bundleIdentifier = sqlite3_column_type(statement, 5) == SQLITE_NULL
            ? nil
            : string(from: statement, column: 5)

        return KeyPressRecord(
            id: id,
            timestamp: Self.date(fromMilliseconds: sqlite3_column_int64(statement, 1)),
            keyCode: UInt16(clamping: sqlite3_column_int(statement, 2)),
            key: string(from: statement, column: 3),
            applicationName: string(from: statement, column: 4),
            bundleIdentifier: bundleIdentifier
        )
    }

    private func mouseClickRecord(from statement: OpaquePointer?) throws -> MouseClickRecord {
        guard let id = UUID(uuidString: string(from: statement, column: 0)),
              let button = MouseButton(rawValue: Int(sqlite3_column_int(statement, 2))) else {
            throw KeyDiaryDatabaseError.invalidRecord
        }
        let bundleIdentifier = sqlite3_column_type(statement, 4) == SQLITE_NULL
            ? nil
            : string(from: statement, column: 4)

        return MouseClickRecord(
            id: id,
            timestamp: Self.date(fromMilliseconds: sqlite3_column_int64(statement, 1)),
            button: button,
            applicationName: string(from: statement, column: 3),
            bundleIdentifier: bundleIdentifier
        )
    }

    private func string(from statement: OpaquePointer?, column: Int32) -> String {
        guard let pointer = sqlite3_column_text(statement, column) else { return "" }
        return String(cString: pointer)
    }

    private func open(path: String) throws {
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &connection, flags, nil) == SQLITE_OK else {
            let message = connection.map { String(cString: sqlite3_errmsg($0)) }
                ?? L10n.text("未知错误")
            if let connection {
                sqlite3_close_v2(connection)
                self.connection = nil
            }
            throw KeyDiaryDatabaseError.open(message)
        }
        sqlite3_busy_timeout(connection, 5_000)
    }

    private func configure() throws {
        try execute("PRAGMA foreign_keys = ON;")
        try execute("PRAGMA synchronous = NORMAL;")
        if databaseURL != nil {
            try execute("PRAGMA journal_mode = WAL;")
        }
    }

    private func createSchema() throws {
        try execute("""
            CREATE TABLE IF NOT EXISTS key_press_records (
                id TEXT PRIMARY KEY NOT NULL,
                timestamp_ms INTEGER NOT NULL,
                key_code INTEGER NOT NULL CHECK (key_code BETWEEN 0 AND 65535),
                key TEXT NOT NULL,
                application_name TEXT NOT NULL,
                bundle_identifier TEXT
            );
            CREATE INDEX IF NOT EXISTS idx_records_timestamp
                ON key_press_records(timestamp_ms);
            CREATE INDEX IF NOT EXISTS idx_records_app_timestamp
                ON key_press_records(application_name, timestamp_ms);
            CREATE INDEX IF NOT EXISTS idx_records_duplicate_check
                ON key_press_records(timestamp_ms, key_code, application_name, key, bundle_identifier);
            CREATE TABLE IF NOT EXISTS mouse_click_records (
                id TEXT PRIMARY KEY NOT NULL,
                timestamp_ms INTEGER NOT NULL,
                button INTEGER NOT NULL CHECK (button IN (0, 1)),
                application_name TEXT NOT NULL,
                bundle_identifier TEXT
            );
            CREATE INDEX IF NOT EXISTS idx_mouse_clicks_timestamp
                ON mouse_click_records(timestamp_ms);
            CREATE INDEX IF NOT EXISTS idx_mouse_clicks_app_timestamp
                ON mouse_click_records(application_name, timestamp_ms);
            PRAGMA user_version = 2;
            """)
    }

    private func migrateLegacyJSONIfNeeded(from legacyURL: URL?) throws {
        guard let legacyURL, FileManager.default.fileExists(atPath: legacyURL.path) else { return }
        guard try count() == 0 else { return }

        let data = try Data(contentsOf: legacyURL)
        let records = try JSONDecoder().decode([KeyPressRecord].self, from: data)
        guard !records.isEmpty else { return }
        _ = try insert(records)

        let backupURL = uniqueMigrationBackupURL(for: legacyURL)
        do {
            try FileManager.default.moveItem(at: legacyURL, to: backupURL)
        } catch {
            logger.error(
                "Migrated legacy JSON but could not rename the backup: \(error.localizedDescription, privacy: .public)"
            )
        }
        logger.notice("Migrated \(records.count) legacy JSON records into SQLite")
    }

    private func uniqueMigrationBackupURL(for legacyURL: URL) -> URL {
        let folder = legacyURL.deletingLastPathComponent()
        let base = folder.appendingPathComponent("key-presses.migrated.json")
        guard FileManager.default.fileExists(atPath: base.path) else { return base }
        return folder.appendingPathComponent("key-presses.migrated-\(UUID().uuidString).json")
    }

    private func withTransaction<T>(_ operation: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE;")
        do {
            let result = try operation()
            try execute("COMMIT;")
            return result
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    private func execute(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(connection, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? currentErrorMessage
            sqlite3_free(errorMessage)
            throw KeyDiaryDatabaseError.statement(message)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK else {
            throw statementError()
        }
        return statement
    }

    private func statementError() -> KeyDiaryDatabaseError {
        .statement(currentErrorMessage)
    }

    private var currentErrorMessage: String {
        guard let connection else { return L10n.text("数据库连接不可用") }
        return String(cString: sqlite3_errmsg(connection))
    }

    private static func milliseconds(from date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000).rounded())
    }

    private static func date(fromMilliseconds milliseconds: Int64) -> Date {
        Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
    }

    private static func prepareFolder(for databaseURL: URL) throws {
        let folder = databaseURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
    }

    private static func protectDatabaseFiles(at databaseURL: URL) {
        let paths = [databaseURL.path, databaseURL.path + "-wal", databaseURL.path + "-shm"]
        for path in paths where FileManager.default.fileExists(atPath: path) {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
        }
    }
}
