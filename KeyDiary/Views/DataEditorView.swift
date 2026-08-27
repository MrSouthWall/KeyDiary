//
//  DataEditorView.swift
//  KeyDiary
//

import Observation
import SwiftUI

private enum DataEditorRangePreset: String, CaseIterable, Identifiable {
    case today
    case recent7Days
    case recent30Days
    case all
    case custom

    var id: Self { self }

    var title: String {
        switch self {
        case .today: "今天"
        case .recent7Days: "最近 7 天"
        case .recent30Days: "最近 30 天"
        case .all: "全部时间"
        case .custom: "自定义"
        }
    }
}

private struct DataEditorNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

@MainActor
@Observable
private final class DataEditorViewModel {
    let pageSize = 250
    let store: KeyDiaryStore

    var rangePreset: DataEditorRangePreset = .recent7Days
    var customFromDate: Date
    var customToDate: Date
    var selectedApplication: String?
    var issueFilter: DataIssueFilter = .potentialIssues
    var searchText = ""
    var records: [EditableKeyPressRecord] = []
    var totalCount = 0
    var pageIndex = 0
    var selection: Set<UUID> = []
    var operationStatus: String?
    var notice: DataEditorNotice?

    init(store: KeyDiaryStore, now: Date = .now) {
        self.store = store
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        customFromDate = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        customToDate = now
    }

    var applicationOptions: [String] {
        store.applications.filter { $0 != "All apps" }
    }

    var pageCount: Int {
        max(Int(ceil(Double(totalCount) / Double(pageSize))), 1)
    }

    var canMoveBackward: Bool { pageIndex > 0 }
    var canMoveForward: Bool { pageIndex + 1 < pageCount }
    var isDeleteUnavailable: Bool {
        store.isDataTransferInProgress || store.isPlaybackVideoExportInProgress
    }

    var filterHint: String {
        switch issueFilter {
        case .potentialIssues:
            "包含缺少 App、缺少按键、未来时间和疑似重复；缺少 Bundle ID 可单独筛选。"
        case .suspectedDuplicate:
            "时间、按键、App 和 Bundle ID 完全相同的记录会标记为疑似重复。"
        case .all:
            "显示当前时间和 App 范围内的全部原始记录。"
        default:
            "只显示符合“\(issueFilter.title)”规则的记录。"
        }
    }

    func reload(resetPage: Bool = true, clearSelection: Bool = true) {
        if resetPage { pageIndex = 0 }
        if clearSelection { selection.removeAll() }

        do {
            let page = try store.dataEditorPage(
                query: currentQuery,
                limit: pageSize,
                offset: pageIndex * pageSize
            )
            totalCount = page.totalCount

            let maximumPageIndex = max(pageCount - 1, 0)
            if pageIndex > maximumPageIndex {
                pageIndex = maximumPageIndex
                let adjustedPage = try store.dataEditorPage(
                    query: currentQuery,
                    limit: pageSize,
                    offset: pageIndex * pageSize
                )
                records = adjustedPage.records
                totalCount = adjustedPage.totalCount
            } else {
                records = page.records
            }
        } catch {
            records = []
            totalCount = 0
            notice = DataEditorNotice(title: "无法读取数据", message: error.localizedDescription)
        }
    }

    func movePage(by offset: Int) {
        let destination = min(max(pageIndex + offset, 0), pageCount - 1)
        guard destination != pageIndex else { return }
        pageIndex = destination
        reload(resetPage: false)
    }

    func toggleCurrentPageSelection() {
        let currentIDs = Set(records.map(\.id))
        if currentIDs.isSubset(of: selection) {
            selection.subtract(currentIDs)
        } else {
            selection.formUnion(currentIDs)
        }
    }

    func deleteSelection() {
        let ids = selection
        guard !ids.isEmpty else { return }

        do {
            let deleted = try store.deleteRecords(ids: ids)
            selection.removeAll()
            operationStatus = "已删除 \(deleted.formatted()) 条记录"
            if let selectedApplication,
               !applicationOptions.contains(selectedApplication) {
                self.selectedApplication = nil
            }
            reload(resetPage: false, clearSelection: false)
        } catch {
            notice = DataEditorNotice(title: "无法删除记录", message: error.localizedDescription)
        }
    }

    private var currentQuery: DataEditorQuery {
        let bounds = dateBounds
        return DataEditorQuery(
            fromDate: bounds.from,
            toDate: bounds.to,
            applicationName: selectedApplication,
            searchText: searchText,
            issueFilter: issueFilter,
            referenceDate: .now
        )
    }

    private var dateBounds: (from: Date?, to: Date?) {
        let calendar = Calendar.current
        let now = Date.now
        let today = calendar.startOfDay(for: now)

        switch rangePreset {
        case .today:
            return (today, Self.endOfDay(today, calendar: calendar))
        case .recent7Days:
            return (calendar.date(byAdding: .day, value: -6, to: today), Self.endOfDay(now, calendar: calendar))
        case .recent30Days:
            return (calendar.date(byAdding: .day, value: -29, to: today), Self.endOfDay(now, calendar: calendar))
        case .all:
            return (nil, nil)
        case .custom:
            return (min(customFromDate, customToDate), max(customFromDate, customToDate))
        }
    }

    private static func endOfDay(_ date: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))?
            .addingTimeInterval(-0.001) ?? date
    }
}

struct DataEditorView: View {
    @State private var model: DataEditorViewModel
    @State private var isShowingDeleteConfirmation = false

    init(store: KeyDiaryStore) {
        _model = State(initialValue: DataEditorViewModel(store: store))
    }

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 0) {
            filterPanel
            Divider()
            recordsTable
            Divider()
            footer
        }
        .frame(minWidth: 980, minHeight: 620)
        .navigationTitle("数据编辑")
        .onAppear {
            model.reload()
        }
        .confirmationDialog(
            "删除选中的 \(model.selection.count.formatted()) 条记录？",
            isPresented: $isShowingDeleteConfirmation
        ) {
            Button("永久删除", role: .destructive) {
                model.deleteSelection()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后无法撤销。只有当前明确选中的记录会被删除。")
        }
        .alert(item: $model.notice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("好"))
            )
        }
    }

    private var filterPanel: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 12) {
                Picker("时间", selection: rangePresetBinding) {
                    ForEach(DataEditorRangePreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .frame(width: 170)

                Picker("App", selection: applicationBinding) {
                    Text("全部 App").tag(String?.none)
                    ForEach(model.applicationOptions, id: \.self) { application in
                        Text(applicationTitle(application)).tag(Optional(application))
                    }
                }
                .frame(minWidth: 190, idealWidth: 230)

                Picker("数据", selection: issueFilterBinding) {
                    ForEach(DataIssueFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .frame(width: 190)

                Spacer(minLength: 8)

                Button {
                    model.reload()
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
            }

            HStack(spacing: 10) {
                if model.rangePreset == .custom {
                    DatePicker(
                        "从",
                        selection: customFromDateBinding,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    DatePicker(
                        "到",
                        selection: customToDateBinding,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    Divider().frame(height: 20)
                }

                TextField("搜索按键、App 或 Bundle ID", text: $model.searchText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        model.reload()
                    }

                Button("筛选") {
                    model.reload()
                }
                .keyboardShortcut(.return, modifiers: [])
            }

            Label(model.filterHint, systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.regularMaterial)
    }

    private var recordsTable: some View {
        ZStack {
            Table(model.records, selection: selectionBinding) {
                TableColumn("时间") { item in
                    Text(item.record.timestamp.formatted(date: .numeric, time: .standard))
                        .monospacedDigit()
                        .lineLimit(1)
                }
                .width(min: 150, ideal: 175)

                TableColumn("按键") { item in
                    Text(emptyFallback(item.record.key))
                        .fontWeight(.medium)
                        .lineLimit(1)
                }
                .width(min: 80, ideal: 110)

                TableColumn("键码") { item in
                    Text(item.record.keyCode.formatted())
                        .monospacedDigit()
                }
                .width(min: 55, ideal: 65, max: 80)

                TableColumn("App") { item in
                    Text(applicationTitle(item.record.applicationName))
                        .lineLimit(1)
                }
                .width(min: 120, ideal: 170)

                TableColumn("Bundle ID") { item in
                    Text(emptyFallback(item.record.bundleIdentifier))
                        .foregroundStyle(item.record.bundleIdentifier == nil ? .secondary : .primary)
                        .lineLimit(1)
                }
                .width(min: 170, ideal: 230)

                TableColumn("问题") { item in
                    issueLabel(for: item)
                }
                .width(min: 140, ideal: 190)
            }

            if model.records.isEmpty {
                ContentUnavailableView(
                    "没有符合条件的记录",
                    systemImage: "checkmark.circle",
                    description: Text("调整时间、App、搜索内容或异常规则后再试。")
                )
                .allowsHitTesting(false)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text("共 \(model.totalCount.formatted()) 条")
                .foregroundStyle(.secondary)

            if let operationStatus = model.operationStatus {
                Text(operationStatus)
                    .foregroundStyle(.green)
                    .transition(.opacity)
            }

            Spacer()

            Button(currentPageIsSelected ? "取消本页选择" : "选择本页") {
                model.toggleCurrentPageSelection()
            }
            .disabled(model.records.isEmpty)

            Text("第 \((model.pageIndex + 1).formatted()) / \(model.pageCount.formatted()) 页")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Button {
                model.movePage(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!model.canMoveBackward)
            .help("上一页")

            Button {
                model.movePage(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!model.canMoveForward)
            .help("下一页")

            Divider().frame(height: 22)

            Button("删除选中项…", role: .destructive) {
                isShowingDeleteConfirmation = true
            }
            .disabled(model.selection.isEmpty || model.isDeleteUnavailable)
            .help(
                model.isDeleteUnavailable
                    ? "请等待导入、导出或视频生成结束"
                    : "永久删除选中的记录"
            )
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(.regularMaterial)
    }

    private var rangePresetBinding: Binding<DataEditorRangePreset> {
        Binding(
            get: { model.rangePreset },
            set: { preset in
                model.rangePreset = preset
                model.reload()
            }
        )
    }

    private var applicationBinding: Binding<String?> {
        Binding(
            get: { model.selectedApplication },
            set: { application in
                model.selectedApplication = application
                model.reload()
            }
        )
    }

    private var issueFilterBinding: Binding<DataIssueFilter> {
        Binding(
            get: { model.issueFilter },
            set: { filter in
                model.issueFilter = filter
                model.reload()
            }
        )
    }

    private var customFromDateBinding: Binding<Date> {
        Binding(
            get: { model.customFromDate },
            set: { date in
                model.customFromDate = date
                model.reload()
            }
        )
    }

    private var customToDateBinding: Binding<Date> {
        Binding(
            get: { model.customToDate },
            set: { date in
                model.customToDate = date
                model.reload()
            }
        )
    }

    private var selectionBinding: Binding<Set<UUID>> {
        Binding(
            get: { model.selection },
            set: { model.selection = $0 }
        )
    }

    private var currentPageIsSelected: Bool {
        let currentIDs = Set(model.records.map(\.id))
        return !currentIDs.isEmpty && currentIDs.isSubset(of: model.selection)
    }

    private func issueLabel(for item: EditableKeyPressRecord) -> some View {
        let titles = DataQualityIssue.allCases
            .filter(item.issues.contains)
            .map(\.title)

        return HStack(spacing: 6) {
            Image(systemName: titles.isEmpty ? "checkmark.circle" : "exclamationmark.triangle.fill")
                .foregroundStyle(titles.isEmpty ? Color.secondary : Color.orange)
            Text(titles.isEmpty ? "—" : titles.joined(separator: "、"))
                .lineLimit(1)
                .help(titles.joined(separator: "、"))
        }
    }

    private func applicationTitle(_ application: String) -> String {
        application.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "（未标记 App）"
            : application
    }

    private func emptyFallback(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "—" }
        return value
    }
}

#Preview {
    DataEditorView(store: KeyDiaryStore())
}
