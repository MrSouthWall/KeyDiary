//
//  DataFilePanels.swift
//  KeyDiary
//

import AppKit
import UniformTypeIdentifiers

@MainActor
enum DataFilePanels {
    static func chooseImportFile() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "导入 KeyDiary 数据"
        panel.message = "选择 JSON、CSV 或 Excel 文件。导入前会校验全部记录。"
        panel.prompt = "导入"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = DataTransferFormat.allCases.map(\.contentType)
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseExportFile(format: DataTransferFormat) -> URL? {
        let panel = NSSavePanel()
        panel.title = "导出 KeyDiary 数据"
        panel.message = "导出的文件包含按键和应用信息，请妥善保管。"
        panel.prompt = "导出"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [format.contentType]
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = defaultFilename(format: format)
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func choosePlaybackVideoFile(settings: PlaybackVideoSettings) -> URL? {
        let panel = NSSavePanel()
        panel.title = "录制键盘回放视频"
        panel.message = settings.exportDescription
        panel.prompt = "开始录制"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [settings.container == .mp4 ? .mpeg4Movie : .quickTimeMovie]
        panel.isExtensionHidden = false
        let date = String(ISO8601DateFormatter().string(from: .now).prefix(10))
        panel.nameFieldStringValue = "KeyDiary-Playback-\(date).\(settings.filenameExtension)"
        return panel.runModal() == .OK ? panel.url : nil
    }

    private static func defaultFilename(format: DataTransferFormat) -> String {
        let date = String(ISO8601DateFormatter().string(from: .now).prefix(10))
        return "KeyDiary-\(date).\(format.filenameExtension)"
    }
}
