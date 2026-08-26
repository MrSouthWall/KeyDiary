//
//  DateRangeSheet.swift
//  KeyDiary
//

import SwiftUI

struct DateRangeSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var fromDate: Date
    @State private var toDate: Date

    let apply: (Date, Date) -> Void

    init(
        initialFrom: Date,
        initialTo: Date,
        apply: @escaping (Date, Date) -> Void
    ) {
        _fromDate = State(initialValue: initialFrom)
        _toDate = State(initialValue: initialTo)
        self.apply = apply
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 5) {
                Text("自定义时间范围")
                    .font(.title2.weight(.semibold))
                Text("键盘热力图与回放都会使用这个范围。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 14) {
                GridRow {
                    Text("开始")
                    DatePicker(
                        "开始",
                        selection: $fromDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .labelsHidden()
                }

                GridRow {
                    Text("结束")
                    DatePicker(
                        "结束",
                        selection: $toDate,
                        in: fromDate...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .labelsHidden()
                }
            }

            HStack {
                Spacer()
                Button("取消", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("应用") {
                    apply(fromDate, toDate)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(26)
        .frame(width: 430)
        .onChange(of: fromDate) { _, newValue in
            if toDate < newValue {
                toDate = newValue
            }
        }
    }
}
