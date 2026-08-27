//
//  PlaybackVideoExportPanel.swift
//  KeyDiary
//

import SwiftUI

struct PlaybackVideoExportPanel: View {
    @AppStorage("playbackVideo.container") private var containerRawValue = PlaybackVideoContainer.mp4.rawValue
    @AppStorage("playbackVideo.codec") private var codecRawValue = PlaybackVideoCodec.h264.rawValue
    @AppStorage("playbackVideo.resolution") private var resolutionRawValue = PlaybackVideoResolution.fullHD1080.rawValue
    @AppStorage("playbackVideo.frameRate") private var frameRateRawValue = PlaybackVideoFrameRate.fps30.rawValue

    let onExport: (PlaybackVideoSettings) -> Void

    var body: some View {
        StatusSelectionPanel(title: "视频录制设置", systemImage: "video.fill") {
            VStack(spacing: 9) {
                settingRow("封装") {
                    Picker("封装", selection: containerBinding) {
                        ForEach(PlaybackVideoContainer.allCases) { container in
                            Text(container.title).tag(container)
                        }
                    }
                }

                settingRow("编码") {
                    Picker("编码", selection: codecBinding) {
                        ForEach(PlaybackVideoCodec.allCases) { codec in
                            Text(codec.title).tag(codec)
                                .disabled(!codec.supports(container))
                        }
                    }
                }

                settingRow("分辨率") {
                    Picker("分辨率", selection: resolutionBinding) {
                        ForEach(PlaybackVideoResolution.allCases) { resolution in
                            Text("\(resolution.title) · \(resolution.dimensionsTitle)").tag(resolution)
                        }
                    }
                }

                settingRow("帧率") {
                    Picker("帧率", selection: frameRateBinding) {
                        Section("常用帧率") {
                            ForEach(PlaybackVideoFrameRate.commonCases) { frameRate in
                                Text(frameRate.title).tag(frameRate)
                            }
                        }

                        Section("NTSC / 丢帧帧率") {
                            ForEach(PlaybackVideoFrameRate.dropFrameCases) { frameRate in
                                Text(frameRate.title).tag(frameRate)
                            }
                        }
                    }
                }
            }
            .pickerStyle(.menu)

            Divider()
                .padding(.vertical, 5)

            Text(settings.exportDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)

            Button {
                onExport(settings)
            } label: {
                Label("选择位置并开始录制…", systemImage: "record.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 8)
            .padding(.top, 5)
        }
    }

    private var container: PlaybackVideoContainer {
        PlaybackVideoContainer(rawValue: containerRawValue) ?? .mp4
    }

    private var codec: PlaybackVideoCodec {
        PlaybackVideoCodec(rawValue: codecRawValue) ?? .h264
    }

    private var resolution: PlaybackVideoResolution {
        PlaybackVideoResolution(rawValue: resolutionRawValue) ?? .fullHD1080
    }

    private var frameRate: PlaybackVideoFrameRate {
        PlaybackVideoFrameRate(rawValue: frameRateRawValue) ?? .fps30
    }

    private var settings: PlaybackVideoSettings {
        PlaybackVideoSettings(
            container: container,
            codec: codec,
            resolution: resolution,
            frameRate: frameRate
        )
    }

    private var containerBinding: Binding<PlaybackVideoContainer> {
        Binding(
            get: { container },
            set: { newValue in
                containerRawValue = newValue.rawValue
                if !codec.supports(newValue) {
                    codecRawValue = PlaybackVideoCodec.h264.rawValue
                }
            }
        )
    }

    private var codecBinding: Binding<PlaybackVideoCodec> {
        Binding(
            get: { codec },
            set: { newValue in
                codecRawValue = newValue.rawValue
                if !newValue.supports(container) {
                    containerRawValue = PlaybackVideoContainer.mov.rawValue
                }
            }
        )
    }

    private var resolutionBinding: Binding<PlaybackVideoResolution> {
        Binding(
            get: { resolution },
            set: { resolutionRawValue = $0.rawValue }
        )
    }

    private var frameRateBinding: Binding<PlaybackVideoFrameRate> {
        Binding(
            get: { frameRate },
            set: { frameRateRawValue = $0.rawValue }
        )
    }

    private func settingRow<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        LabeledContent(title) {
            content()
                .labelsHidden()
                .frame(width: 230)
        }
        .font(.system(size: 13))
        .padding(.horizontal, 8)
    }
}
