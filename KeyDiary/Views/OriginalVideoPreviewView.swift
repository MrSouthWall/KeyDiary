//
//  OriginalVideoPreviewView.swift
//  KeyDiary
//

import AppKit
import AVKit
import SwiftUI

struct OriginalVideoPreviewView: View {
    @Bindable var player: KeyboardVideoPlayer
    @Environment(\.keyDiaryAccentColor) private var themeColor

    var body: some View {
        VStack(spacing: 0) {
            OriginalVideoPlayerView(
                player: player.avPlayer,
                framingMode: player.framingMode
            )
                .aspectRatio(CGFloat(KeyboardPixelFrame.columnCount) / CGFloat(KeyboardPixelFrame.rowCount), contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black)

            HStack(spacing: 8) {
                Image(systemName: "film.fill")
                    .foregroundStyle(themeColor)

                Text(player.videoTitle ?? L10n.text("原片对照"))
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text("\(player.currentTimeTitle) / \(player.durationTitle)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(.regularMaterial)
        }
        .frame(minWidth: 280, minHeight: 250)
        .background {
            OriginalVideoWindowBridge()
        }
        .accessibilityLabel("原片对照窗口")
    }
}

private struct OriginalVideoPlayerView: NSViewRepresentable {
    let player: AVPlayer
    let framingMode: KeyboardVideoFramingMode

    func makeNSView(context: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        playerView.player = player
        playerView.controlsStyle = .floating
        playerView.videoGravity = videoGravity
        return playerView
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
        nsView.videoGravity = videoGravity
    }

    private var videoGravity: AVLayerVideoGravity {
        switch framingMode {
        case .fit: .resizeAspect
        case .fill: .resizeAspectFill
        case .stretch: .resize
        }
    }
}

private struct OriginalVideoWindowBridge: NSViewRepresentable {
    func makeNSView(context: Context) -> OriginalVideoWindowConfigurationView {
        OriginalVideoWindowConfigurationView()
    }

    func updateNSView(_ nsView: OriginalVideoWindowConfigurationView, context: Context) {
        nsView.applyConfiguration()
    }
}

private final class OriginalVideoWindowConfigurationView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyConfiguration()
        DispatchQueue.main.async { [weak self] in
            self?.applyConfiguration()
        }
    }

    func applyConfiguration() {
        guard let window else { return }
        window.level = .floating
        window.hidesOnDeactivate = false
        window.tabbingMode = .disallowed
        window.collectionBehavior.formUnion([.canJoinAllSpaces, .fullScreenAuxiliary])
        window.contentMinSize = CGSize(width: 280, height: 250)
    }
}

#Preview {
    OriginalVideoPreviewView(player: KeyboardVideoPlayer())
        .frame(width: 360, height: 320)
}
