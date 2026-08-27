//
//  DataEditorModels.swift
//  KeyDiary
//

import Foundation

nonisolated enum DataEditorError: LocalizedError {
    case operationInProgress

    var errorDescription: String? {
        switch self {
        case .operationInProgress:
            "请等待当前导入、导出或视频生成结束后再删除记录。"
        }
    }
}

nonisolated enum DataQualityIssue: String, CaseIterable, Hashable, Sendable {
    case missingApplication
    case missingKey
    case missingBundleIdentifier
    case futureTimestamp
    case suspectedDuplicate

    var title: String {
        switch self {
        case .missingApplication: "缺少 App"
        case .missingKey: "缺少按键"
        case .missingBundleIdentifier: "缺少 Bundle ID"
        case .futureTimestamp: "时间在未来"
        case .suspectedDuplicate: "疑似重复"
        }
    }
}

nonisolated enum DataIssueFilter: String, CaseIterable, Identifiable, Hashable, Sendable {
    case all
    case potentialIssues
    case missingApplication
    case missingKey
    case missingBundleIdentifier
    case futureTimestamp
    case suspectedDuplicate

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "全部记录"
        case .potentialIssues: "潜在异常"
        case .missingApplication: "缺少 App"
        case .missingKey: "缺少按键"
        case .missingBundleIdentifier: "缺少 Bundle ID"
        case .futureTimestamp: "时间在未来"
        case .suspectedDuplicate: "疑似重复"
        }
    }
}

nonisolated struct DataEditorQuery: Hashable, Sendable {
    let fromDate: Date?
    let toDate: Date?
    let applicationName: String?
    let searchText: String
    let issueFilter: DataIssueFilter
    let referenceDate: Date
}

nonisolated struct EditableKeyPressRecord: Identifiable, Hashable, Sendable {
    let record: KeyPressRecord
    let issues: Set<DataQualityIssue>

    var id: UUID { record.id }
}

nonisolated struct DataEditorPage: Sendable {
    let records: [EditableKeyPressRecord]
    let totalCount: Int
}
