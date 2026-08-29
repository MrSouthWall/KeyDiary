//
//  DataTransferService.swift
//  KeyDiary
//

import Foundation
import UniformTypeIdentifiers
import ZIPFoundation

nonisolated enum DataTransferFormat: String, CaseIterable, Identifiable, Sendable {
    case json
    case csv
    case xlsx

    var id: Self { self }

    var title: String {
        switch self {
        case .json: "JSON"
        case .csv: "CSV"
        case .xlsx: "Excel"
        }
    }

    var filenameExtension: String { rawValue }

    var contentType: UTType {
        switch self {
        case .json: .json
        case .csv: .commaSeparatedText
        case .xlsx:
            UTType(filenameExtension: "xlsx") ?? .data
        }
    }

    static func format(for url: URL) -> DataTransferFormat? {
        DataTransferFormat(rawValue: url.pathExtension.lowercased())
    }
}

nonisolated struct DataExportResult: Equatable, Sendable {
    let exported: Int
    let fileURL: URL
}

nonisolated enum DataTransferError: LocalizedError {
    case unsupportedFormat
    case invalidFile(String)
    case unableToCreateFile
    case unableToCreateWorkbook

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            L10n.text("不支持这种文件格式。请选择 JSON、CSV 或 XLSX 文件。")
        case .invalidFile(let detail):
            L10n.format("无法导入数据：%@", detail)
        case .unableToCreateFile:
            L10n.text("无法创建导出文件。")
        case .unableToCreateWorkbook:
            L10n.text("无法创建或读取 Excel 工作簿。")
        }
    }
}

private nonisolated struct TransferEnvelope: Codable {
    let formatVersion: Int
    let exportedAt: String
    let records: [TransferRecord]
}

private nonisolated struct TransferRecord: Codable {
    let id: String
    let timestamp: String
    let keyCode: UInt16
    let key: String
    let applicationName: String
    let bundleIdentifier: String?
}

nonisolated final class DataTransferService: @unchecked Sendable {
    private static let headers = [
        "id", "timestamp", "keyCode", "key", "applicationName", "bundleIdentifier"
    ]
    private static let excelMaximumDataRows = 1_048_575

    private let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private let fallbackTimestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    func export(
        format: DataTransferFormat,
        to url: URL,
        database: KeyDiaryDatabase,
        query: KeyDiaryRecordQuery = .all
    ) throws -> DataExportResult {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }

        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        do {
            let count: Int
            switch format {
            case .json:
                count = try exportJSON(to: url, database: database, query: query)
            case .csv:
                count = try exportCSV(to: url, database: database, query: query)
            case .xlsx:
                count = try exportXLSX(to: url, database: database, query: query)
            }
            return DataExportResult(exported: count, fileURL: url)
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    func importRecords(
        from url: URL,
        mode: DataImportMode,
        database: KeyDiaryDatabase
    ) throws -> DataImportResult {
        guard let format = DataTransferFormat.format(for: url) else {
            throw DataTransferError.unsupportedFormat
        }

        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }

        return try database.importRecords(mode: mode) { [self] receive in
            switch format {
            case .json:
                try readJSON(from: url, receive: receive)
            case .csv:
                try readCSV(from: url, receive: receive)
            case .xlsx:
                try readXLSX(from: url, receive: receive)
            }
        }
    }

    func createPreReplacementBackup(database: KeyDiaryDatabase) throws -> URL {
        let folder = KeyDiaryDatabase.defaultDatabaseURL
            .deletingLastPathComponent()
            .appendingPathComponent("Backups", isDirectory: true)
        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
        let timestamp = timestampFormatter.string(from: .now)
            .replacingOccurrences(of: ":", with: "-")
        let url = folder.appendingPathComponent(
            "before-replace-\(timestamp)-\(UUID().uuidString).json"
        )
        _ = try export(format: .json, to: url, database: database)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return url
    }

    private func exportJSON(
        to url: URL,
        database: KeyDiaryDatabase,
        query: KeyDiaryRecordQuery
    ) throws -> Int {
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw DataTransferError.unableToCreateFile
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }

        let exportedAt = timestampFormatter.string(from: .now)
        try handle.write(contentsOf: Data(
            "{\n  \"formatVersion\": 1,\n  \"exportedAt\": \"\(exportedAt)\",\n  \"records\": [\n"
                .utf8
        ))

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var count = 0
        try database.forEachRecord(query: query) { [self] record in
            if count > 0 {
                try handle.write(contentsOf: Data(",\n".utf8))
            }
            let data = try encoder.encode(transferRecord(from: record))
            try handle.write(contentsOf: Data("    ".utf8))
            try handle.write(contentsOf: data)
            count += 1
        }
        try handle.write(contentsOf: Data("\n  ]\n}\n".utf8))
        return count
    }

    private func exportCSV(
        to url: URL,
        database: KeyDiaryDatabase,
        query: KeyDiaryRecordQuery
    ) throws -> Int {
        guard FileManager.default.createFile(atPath: url.path, contents: Data([0xEF, 0xBB, 0xBF])) else {
            throw DataTransferError.unableToCreateFile
        }
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        defer { try? handle.close() }

        try writeCSVRow(Self.headers, to: handle)
        var count = 0
        try database.forEachRecord(query: query) { [self] record in
            try writeCSVRow(csvFields(for: record), to: handle)
            count += 1
        }
        return count
    }

    private func exportXLSX(
        to url: URL,
        database: KeyDiaryDatabase,
        query: KeyDiaryRecordQuery
    ) throws -> Int {
        let fileManager = FileManager.default
        let temporaryRoot = fileManager.temporaryDirectory
            .appendingPathComponent("KeyDiary-XLSX-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temporaryRoot) }

        let total = try database.count(query: query)
        let sheetCount = max(Int(ceil(Double(total) / Double(Self.excelMaximumDataRows))), 1)
        try createWorkbookScaffold(at: temporaryRoot, sheetCount: sheetCount)

        var sheetIndex = 1
        var rowInSheet = 1
        var writer = try WorksheetStreamWriter(
            url: worksheetURL(root: temporaryRoot, index: sheetIndex),
            headers: Self.headers
        )

        try database.forEachRecord(query: query) { [self] record in
            if rowInSheet > Self.excelMaximumDataRows {
                try writer.finish()
                sheetIndex += 1
                rowInSheet = 1
                writer = try WorksheetStreamWriter(
                    url: worksheetURL(root: temporaryRoot, index: sheetIndex),
                    headers: Self.headers
                )
            }
            try writer.append(fields(for: record))
            rowInSheet += 1
        }
        try writer.finish()

        let archive = try Archive(url: url, accessMode: .create)
        let paths = try recursiveFilePaths(at: temporaryRoot)
        guard paths.contains("_rels/.rels") else {
            throw DataTransferError.unableToCreateWorkbook
        }
        for path in paths {
            try archive.addEntry(with: path, relativeTo: temporaryRoot, compressionMethod: .deflate)
        }
        return total
    }

    private func readJSON(from url: URL, receive: KeyDiaryDatabase.RecordReceiver) throws {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let decoder = JSONDecoder()
        if let envelope = try? decoder.decode(TransferEnvelope.self, from: data) {
            guard envelope.formatVersion == 1 else {
                throw DataTransferError.invalidFile(L10n.text("JSON 格式版本不受支持。"))
            }
            for record in envelope.records {
                try receive(try keyPressRecord(from: record))
            }
            return
        }

        // Compatibility with the JSON array used by KeyDiary before SQLite.
        let legacyDecoder = JSONDecoder()
        do {
            let legacyRecords = try legacyDecoder.decode([KeyPressRecord].self, from: data)
            for record in legacyRecords {
                try receive(record)
            }
        } catch {
            throw DataTransferError.invalidFile(L10n.text("JSON 结构或字段不正确。"))
        }
    }

    private func readCSV(from url: URL, receive: KeyDiaryDatabase.RecordReceiver) throws {
        let stream = try CSVRowStream(url: url)
        var headerMap: [String: Int]?
        var rowNumber = 0

        try stream.forEachRow { [self] row in
            rowNumber += 1
            if headerMap == nil {
                headerMap = try makeHeaderMap(row)
                return
            }
            guard !row.allSatisfy({ $0.isEmpty }) else { return }
            do {
                try receive(try record(
                    from: row.map(removeCSVFormulaProtection),
                    headerMap: headerMap!
                ))
            } catch {
                throw DataTransferError.invalidFile(
                    L10n.format("CSV 第 %lld 行无效：%@", Int64(rowNumber), error.localizedDescription)
                )
            }
        }
        guard headerMap != nil else {
            throw DataTransferError.invalidFile(L10n.text("CSV 文件没有表头。"))
        }
    }

    private func readXLSX(
        from url: URL,
        receive: @escaping KeyDiaryDatabase.RecordReceiver
    ) throws {
        let archive: Archive
        do {
            archive = try Archive(url: url, accessMode: .read)
        } catch {
            throw DataTransferError.unableToCreateWorkbook
        }

        let fileManager = FileManager.default
        let temporaryRoot = fileManager.temporaryDirectory
            .appendingPathComponent("KeyDiary-XLSX-Read-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temporaryRoot) }

        var sharedStrings: [String] = []
        if let entry = archive["xl/sharedStrings.xml"] {
            let sharedURL = temporaryRoot.appendingPathComponent("sharedStrings.xml")
            _ = try archive.extract(entry, to: sharedURL)
            let parser = SharedStringsParser()
            sharedStrings = try parser.parse(url: sharedURL)
        }

        let worksheetEntries = archive
            .filter { $0.path.hasPrefix("xl/worksheets/") && $0.path.hasSuffix(".xml") }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        guard !worksheetEntries.isEmpty else {
            throw DataTransferError.invalidFile(L10n.text("Excel 文件没有工作表。"))
        }

        var importedSheet = false
        for (offset, entry) in worksheetEntries.enumerated() {
            let sheetURL = temporaryRoot.appendingPathComponent("sheet-\(offset + 1).xml")
            _ = try archive.extract(entry, to: sheetURL)
            let parser = WorksheetRecordParser(
                sharedStrings: sharedStrings,
                makeHeaderMap: makeHeaderMap,
                makeRecord: { [self] row, headerMap in
                    try record(from: row, headerMap: headerMap)
                },
                receive: receive
            )
            do {
                try parser.parse(url: sheetURL)
                importedSheet = true
            } catch DataTransferError.invalidFile(let detail) where detail.contains(L10n.text("缺少字段")) {
                // Metadata or unrelated sheets are ignored. At least one records sheet is required.
                continue
            }
        }

        guard importedSheet else {
            throw DataTransferError.invalidFile(L10n.text("Excel 工作表中没有键盘日记记录。"))
        }
    }

    private func transferRecord(from record: KeyPressRecord) -> TransferRecord {
        TransferRecord(
            id: record.id.uuidString.lowercased(),
            timestamp: timestampFormatter.string(from: record.timestamp),
            keyCode: record.keyCode,
            key: record.key,
            applicationName: record.applicationName,
            bundleIdentifier: record.bundleIdentifier
        )
    }

    private func keyPressRecord(from record: TransferRecord) throws -> KeyPressRecord {
        guard let id = UUID(uuidString: record.id) else {
            throw DataTransferError.invalidFile(L10n.text("记录 ID 不是有效 UUID。"))
        }
        guard let timestamp = parseTimestamp(record.timestamp) else {
            throw DataTransferError.invalidFile(L10n.text("记录时间不是有效 ISO 8601 时间。"))
        }
        return KeyPressRecord(
            id: id,
            timestamp: timestamp,
            keyCode: record.keyCode,
            key: record.key,
            applicationName: record.applicationName,
            bundleIdentifier: record.bundleIdentifier
        )
    }

    private func fields(for record: KeyPressRecord) -> [String] {
        [
            record.id.uuidString.lowercased(),
            timestampFormatter.string(from: record.timestamp),
            String(record.keyCode),
            record.key,
            record.applicationName,
            record.bundleIdentifier ?? ""
        ]
    }

    private func csvFields(for record: KeyPressRecord) -> [String] {
        let values = fields(for: record)
        return values.enumerated().map { index, value in
            // UUID, timestamp and keyCode are controlled scalar fields. User/app text
            // is protected against spreadsheet formula execution when CSV is opened.
            index < 3 ? value : addCSVFormulaProtection(to: value)
        }
    }

    private func addCSVFormulaProtection(to value: String) -> String {
        guard let first = value.first,
              ["=", "+", "-", "@", "'", "\t", "\r"].contains(first) else {
            return value
        }
        return "'" + value
    }

    private func removeCSVFormulaProtection(from value: String) -> String {
        guard value.first == "'", value.count > 1 else { return value }
        let second = value[value.index(after: value.startIndex)]
        guard ["=", "+", "-", "@", "'", "\t", "\r"].contains(second) else {
            return value
        }
        return String(value.dropFirst())
    }

    private func record(from row: [String], headerMap: [String: Int]) throws -> KeyPressRecord {
        func value(_ header: String) -> String {
            guard let index = headerMap[header], row.indices.contains(index) else { return "" }
            return row[index]
        }

        guard let id = UUID(uuidString: value("id")) else {
            throw DataTransferError.invalidFile(L10n.text("ID 不是有效 UUID。"))
        }
        guard let timestamp = parseTimestamp(value("timestamp")) else {
            throw DataTransferError.invalidFile(L10n.text("时间不是有效 ISO 8601 时间。"))
        }
        guard let numericKeyCode = Int(value("keycode")),
              let keyCode = UInt16(exactly: numericKeyCode) else {
            throw DataTransferError.invalidFile(L10n.text("keyCode 超出范围。"))
        }

        return KeyPressRecord(
            id: id,
            timestamp: timestamp,
            keyCode: keyCode,
            key: value("key"),
            applicationName: value("applicationname"),
            bundleIdentifier: value("bundleidentifier").nilIfEmpty
        )
    }

    private func makeHeaderMap(_ row: [String]) throws -> [String: Int] {
        var map: [String: Int] = [:]
        for (index, header) in row.enumerated() {
            let normalized = header
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingPrefix("\u{feff}")
                .lowercased()
            map[normalized] = index
        }
        let required = ["id", "timestamp", "keycode", "key", "applicationname"]
        let missing = required.filter { map[$0] == nil }
        guard missing.isEmpty else {
            throw DataTransferError.invalidFile(
                L10n.format("缺少字段：%@。", missing.joined(separator: ", "))
            )
        }
        return map
    }

    private func parseTimestamp(_ string: String) -> Date? {
        timestampFormatter.date(from: string) ?? fallbackTimestampFormatter.date(from: string)
    }

    private func writeCSVRow(_ fields: [String], to handle: FileHandle) throws {
        let row = fields.map(csvEscaped).joined(separator: ",") + "\r\n"
        try handle.write(contentsOf: Data(row.utf8))
    }

    private func csvEscaped(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else {
            return value
        }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private func worksheetURL(root: URL, index: Int) -> URL {
        root.appendingPathComponent("xl/worksheets/sheet\(index).xml")
    }

    private func createWorkbookScaffold(at root: URL, sheetCount: Int) throws {
        let fileManager = FileManager.default
        let directories = ["_rels", "xl", "xl/_rels", "xl/worksheets"]
        for path in directories {
            try fileManager.createDirectory(
                at: root.appendingPathComponent(path),
                withIntermediateDirectories: true
            )
        }

        let worksheetOverrides = (1...sheetCount).map {
            "<Override PartName=\"/xl/worksheets/sheet\($0).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"
        }.joined()
        try write(
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
              <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
              <Default Extension="xml" ContentType="application/xml"/>
              <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
              <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
              \(worksheetOverrides)
            </Types>
            """,
            to: root.appendingPathComponent("[Content_Types].xml")
        )
        try write(
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
              <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
            </Relationships>
            """,
            to: root.appendingPathComponent("_rels/.rels")
        )

        let sheets = (1...sheetCount).map {
            let title = sheetCount == 1 ? "Records" : "Records \($0)"
            return "<sheet name=\"\(title)\" sheetId=\"\($0)\" r:id=\"rId\($0)\"/>"
        }.joined()
        try write(
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
              <sheets>\(sheets)</sheets>
            </workbook>
            """,
            to: root.appendingPathComponent("xl/workbook.xml")
        )

        let relationships = (1...sheetCount).map {
            "<Relationship Id=\"rId\($0)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet\($0).xml\"/>"
        }.joined()
        try write(
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
              \(relationships)
              <Relationship Id="rId\(sheetCount + 1)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
            </Relationships>
            """,
            to: root.appendingPathComponent("xl/_rels/workbook.xml.rels")
        )
        try write(
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
              <fonts count="1"><font><sz val="11"/><name val="Aptos"/></font></fonts>
              <fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>
              <borders count="1"><border/></borders>
              <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
              <cellXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/></cellXfs>
            </styleSheet>
            """,
            to: root.appendingPathComponent("xl/styles.xml")
        )
    }

    private func recursiveFilePaths(at root: URL) throws -> [String] {
        let resolvedRoot = root.resolvingSymlinksInPath()
        guard let enumerator = FileManager.default.enumerator(
            at: resolvedRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: []
        ) else { return [] }

        var paths: [String] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            let resolvedPath = url.resolvingSymlinksInPath().path
            paths.append(String(resolvedPath.dropFirst(resolvedRoot.path.count + 1)))
        }
        return paths.sorted()
    }

    private func write(_ string: String, to url: URL) throws {
        try Data(string.utf8).write(to: url, options: .atomic)
    }
}

private nonisolated final class WorksheetStreamWriter {
    private let handle: FileHandle
    private var rowNumber = 0
    private var isFinished = false

    init(url: URL, headers: [String]) throws {
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw DataTransferError.unableToCreateFile
        }
        handle = try FileHandle(forWritingTo: url)
        try handle.write(contentsOf: Data(
            "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetData>".utf8
        ))
        try append(headers)
    }

    deinit {
        try? handle.close()
    }

    func append(_ fields: [String]) throws {
        rowNumber += 1
        var xml = "<row r=\"\(rowNumber)\">"
        for (column, value) in fields.enumerated() {
            let reference = Self.columnName(column + 1) + String(rowNumber)
            xml += "<c r=\"\(reference)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(Self.escape(value))</t></is></c>"
        }
        xml += "</row>"
        try handle.write(contentsOf: Data(xml.utf8))
    }

    func finish() throws {
        guard !isFinished else { return }
        isFinished = true
        try handle.write(contentsOf: Data("</sheetData></worksheet>".utf8))
        try handle.close()
    }

    private static func columnName(_ number: Int) -> String {
        var number = number
        var result = ""
        while number > 0 {
            number -= 1
            result = String(UnicodeScalar(65 + number % 26)!) + result
            number /= 26
        }
        return result
    }

    private static func escape(_ value: String) -> String {
        let xmlSafe = String(value.unicodeScalars.filter { scalar in
            scalar.value == 0x09 || scalar.value == 0x0A || scalar.value == 0x0D || scalar.value >= 0x20
        })
        return xmlSafe
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

private nonisolated final class CSVRowStream {
    private let inputStream: InputStream

    init(url: URL) throws {
        guard let inputStream = InputStream(url: url) else {
            throw DataTransferError.invalidFile(L10n.text("无法读取 CSV 文件。"))
        }
        self.inputStream = inputStream
    }

    func forEachRow(_ body: ([String]) throws -> Void) throws {
        inputStream.open()
        defer { inputStream.close() }

        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        var field: [UInt8] = []
        var row: [String] = []
        var insideQuotes = false
        var quotePending = false
        var pendingCarriageReturn = false

        func finishField() throws {
            guard let string = String(bytes: field, encoding: .utf8) else {
                throw DataTransferError.invalidFile(L10n.text("CSV 不是有效的 UTF-8 文件。"))
            }
            row.append(string)
            field.removeAll(keepingCapacity: true)
        }

        func finishRow() throws {
            try finishField()
            try body(row)
            row.removeAll(keepingCapacity: true)
        }

        while inputStream.hasBytesAvailable {
            let readCount = inputStream.read(&buffer, maxLength: buffer.count)
            if readCount < 0 {
                throw inputStream.streamError ?? DataTransferError.invalidFile(L10n.text("CSV 读取失败。"))
            }
            if readCount == 0 { break }

            for byte in buffer.prefix(readCount) {
                if pendingCarriageReturn {
                    pendingCarriageReturn = false
                    if byte == 0x0A { continue }
                }

                if insideQuotes {
                    if quotePending {
                        if byte == 0x22 {
                            field.append(byte)
                            quotePending = false
                        } else {
                            insideQuotes = false
                            quotePending = false
                            if byte == 0x2C {
                                try finishField()
                            } else if byte == 0x0A {
                                try finishRow()
                            } else if byte == 0x0D {
                                try finishRow()
                                pendingCarriageReturn = true
                            } else if byte != 0x20 && byte != 0x09 {
                                throw DataTransferError.invalidFile(L10n.text("CSV 引号后的字符无效。"))
                            }
                        }
                    } else if byte == 0x22 {
                        quotePending = true
                    } else {
                        field.append(byte)
                    }
                    continue
                }

                switch byte {
                case 0x22 where field.isEmpty:
                    insideQuotes = true
                case 0x2C:
                    try finishField()
                case 0x0A:
                    try finishRow()
                case 0x0D:
                    try finishRow()
                    pendingCarriageReturn = true
                default:
                    field.append(byte)
                }
            }
        }

        guard !insideQuotes || quotePending else {
            throw DataTransferError.invalidFile(L10n.text("CSV 中有未闭合的引号。"))
        }
        if !field.isEmpty || !row.isEmpty {
            try finishRow()
        }
    }
}

private nonisolated final class SharedStringsParser: NSObject, XMLParserDelegate {
    private var strings: [String] = []
    private var currentString = ""
    private var isInsideStringItem = false
    private var isInsideText = false

    func parse(url: URL) throws -> [String] {
        guard let parser = XMLParser(contentsOf: url) else {
            throw DataTransferError.invalidFile(L10n.text("无法读取 Excel 共享文本。"))
        }
        parser.delegate = self
        guard parser.parse() else {
            throw parser.parserError ?? DataTransferError.invalidFile(L10n.text("Excel 共享文本无效。"))
        }
        return strings
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if elementName == "si" {
            isInsideStringItem = true
            currentString = ""
        } else if elementName == "t", isInsideStringItem {
            isInsideText = true
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isInsideText { currentString += string }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName == "t" {
            isInsideText = false
        } else if elementName == "si" {
            strings.append(currentString)
            isInsideStringItem = false
        }
    }
}

private nonisolated final class WorksheetRecordParser: NSObject, XMLParserDelegate {
    private let sharedStrings: [String]
    private let makeHeaderMap: ([String]) throws -> [String: Int]
    private let makeRecord: ([String], [String: Int]) throws -> KeyPressRecord
    private let receive: KeyDiaryDatabase.RecordReceiver

    private var currentRow: [Int: String] = [:]
    private var currentColumn = 0
    private var currentCellType: String?
    private var currentValue = ""
    private var isReadingValue = false
    private var rowNumber = 0
    private var headerMap: [String: Int]?
    private var capturedError: Error?

    init(
        sharedStrings: [String],
        makeHeaderMap: @escaping ([String]) throws -> [String: Int],
        makeRecord: @escaping ([String], [String: Int]) throws -> KeyPressRecord,
        receive: @escaping KeyDiaryDatabase.RecordReceiver
    ) {
        self.sharedStrings = sharedStrings
        self.makeHeaderMap = makeHeaderMap
        self.makeRecord = makeRecord
        self.receive = receive
    }

    func parse(url: URL) throws {
        guard let parser = XMLParser(contentsOf: url) else {
            throw DataTransferError.invalidFile(L10n.text("无法读取 Excel 工作表。"))
        }
        parser.delegate = self
        let succeeded = parser.parse()
        if let capturedError { throw capturedError }
        guard succeeded else {
            throw parser.parserError ?? DataTransferError.invalidFile(L10n.text("Excel 工作表 XML 无效。"))
        }
        guard headerMap != nil else {
            throw DataTransferError.invalidFile(L10n.text("Excel 工作表缺少字段。"))
        }
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch elementName {
        case "row":
            currentRow = [:]
        case "c":
            currentColumn = Self.columnIndex(from: attributeDict["r"] ?? "A1")
            currentCellType = attributeDict["t"]
            currentValue = ""
        case "v", "t":
            isReadingValue = true
            currentValue = ""
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isReadingValue { currentValue += string }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch elementName {
        case "v", "t":
            isReadingValue = false
        case "c":
            if currentCellType == "s", let index = Int(currentValue), sharedStrings.indices.contains(index) {
                currentRow[currentColumn] = sharedStrings[index]
            } else {
                currentRow[currentColumn] = currentValue
            }
        case "row":
            do {
                rowNumber += 1
                let width = (currentRow.keys.max() ?? -1) + 1
                let row = (0..<width).map { currentRow[$0] ?? "" }
                if headerMap == nil {
                    headerMap = try makeHeaderMap(row)
                } else if !row.allSatisfy({ $0.isEmpty }) {
                    try receive(try makeRecord(row, headerMap!))
                }
            } catch {
                capturedError = DataTransferError.invalidFile(
                    L10n.format("Excel 第 %lld 行无效：%@", Int64(rowNumber), error.localizedDescription)
                )
                parser.abortParsing()
            }
        default:
            break
        }
    }

    private static func columnIndex(from reference: String) -> Int {
        var result = 0
        for scalar in reference.uppercased().unicodeScalars {
            guard scalar.value >= 65 && scalar.value <= 90 else { break }
            result = result * 26 + Int(scalar.value - 64)
        }
        return max(result - 1, 0)
    }
}

private extension String {
    nonisolated var nilIfEmpty: String? { isEmpty ? nil : self }
}
