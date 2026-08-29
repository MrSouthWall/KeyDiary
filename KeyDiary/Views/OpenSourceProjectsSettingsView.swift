//
//  OpenSourceProjectsSettingsView.swift
//  KeyDiary
//

import Foundation
import SwiftUI

struct OpenSourceProjectsSettingsView: View {
    private static let repositoryURL = URL(string: "https://github.com/tplai/kbsim")!

    var body: some View {
        Form {
            Section("kbsim") {
                LabeledContent("项目") {
                    Link("Mechanical Keyboard Simulator", destination: Self.repositoryURL)
                }

                LabeledContent("作者") {
                    Text("Thomas Lai")
                        .foregroundStyle(.secondary)
                }

                LabeledContent("许可证") {
                    Text("MIT License")
                        .foregroundStyle(.secondary)
                }

                Text("键盘日记使用了 kbsim 提供的 13 套机械键盘按下与松开音频采样。音频文件依照 MIT 许可证随应用分发。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("MIT 许可证") {
                ScrollView {
                    Text(licenseText)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                }
                .frame(minHeight: 300)
            }
        }
        .formStyle(.grouped)
    }

    private var licenseText: String {
        guard let url = Bundle.main.url(forResource: "kbsim-LICENSE", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return L10n.text("许可证文本未能载入。请访问 kbsim 项目页面查看 MIT License。")
        }
        return text
    }
}

#Preview {
    OpenSourceProjectsSettingsView()
        .frame(width: 540, height: 720)
}
