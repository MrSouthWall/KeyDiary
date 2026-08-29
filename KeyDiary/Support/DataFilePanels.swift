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
        panel.title = L10n.text("导入键盘日记数据")
        panel.message = L10n.text("选择 JSON、CSV 或 Excel 文件。导入前会校验全部记录。")
        panel.prompt = L10n.text("导入")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = DataTransferFormat.allCases.map(\.contentType)
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseExportFile(format: DataTransferFormat) -> URL? {
        let panel = NSSavePanel()
        panel.title = L10n.text("导出键盘日记数据")
        panel.message = L10n.text("导出的文件包含按键和应用信息，请妥善保管。")
        panel.prompt = L10n.text("导出")
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [format.contentType]
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = defaultFilename(format: format)
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func choosePlaybackVideoFile(settings: PlaybackVideoSettings) -> URL? {
        let panel = NSSavePanel()
        panel.title = L10n.text("录制键盘回放视频")
        panel.message = settings.exportDescription
        panel.prompt = L10n.text("开始录制")
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [settings.container == .mp4 ? .mpeg4Movie : .quickTimeMovie]
        panel.isExtensionHidden = false
        let date = String(ISO8601DateFormatter().string(from: .now).prefix(10))
        panel.nameFieldStringValue = L10n.format(
            "键盘日记-回放-%@.%@",
            date,
            settings.filenameExtension
        )
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseKeyboardCinemaVideo() -> URL? {
        let panel = NSOpenPanel()
        panel.title = L10n.text("选择键盘像素影院视频")
        panel.message = L10n.text("视频会实时缩小为 6×14 个键帽像素，并保留原声。")
        panel.prompt = L10n.text("载入并播放")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseKeyboardCinemaExportFile(settings: PlaybackVideoSettings) -> URL? {
        let panel = NSSavePanel()
        panel.title = L10n.text("导出键盘像素视频")
        panel.message = settings.exportDescription + L10n.text(" 若原片包含音轨，导出文件会保留原声。")
        panel.prompt = L10n.text("开始导出")
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [settings.container == .mp4 ? .mpeg4Movie : .quickTimeMovie]
        panel.isExtensionHidden = false
        let date = String(ISO8601DateFormatter().string(from: .now).prefix(10))
        panel.nameFieldStringValue = L10n.format(
            "键盘日记-像素影院-%@.%@",
            date,
            settings.filenameExtension
        )
        return panel.runModal() == .OK ? panel.url : nil
    }

    private static func defaultFilename(format: DataTransferFormat) -> String {
        let date = String(ISO8601DateFormatter().string(from: .now).prefix(10))
        return L10n.format("键盘日记-%@.%@", date, format.filenameExtension)
    }
}
