//
//  KeyboardPixelFrame.swift
//  KeyDiary
//

import CoreVideo
import Foundation

enum KeyboardPixelColorMode: String, CaseIterable, Identifiable, Sendable {
    case color
    case binary

    var id: Self { self }

    var title: String {
        switch self {
        case .color: L10n.text("彩色")
        case .binary: L10n.text("黑白")
        }
    }
}

enum KeyboardVideoFramingMode: String, CaseIterable, Identifiable, Sendable {
    case fit
    case fill
    case stretch

    var id: Self { self }

    var title: String {
        switch self {
        case .fit: L10n.text("适合")
        case .fill: L10n.text("填充")
        case .stretch: L10n.text("拉伸")
        }
    }

    var helpText: String {
        switch self {
        case .fit: L10n.text("完整显示画面，空余键位使用黑色")
        case .fill: L10n.text("保持比例并裁切画面，铺满全部键位")
        case .stretch: L10n.text("不保持比例，将完整画面拉伸至全部键位")
        }
    }
}

struct KeyboardPixel: Equatable, Hashable, Sendable {
    static let black = KeyboardPixel(red: 0, green: 0, blue: 0)
    static let white = KeyboardPixel(red: 1, green: 1, blue: 1)

    let red: Double
    let green: Double
    let blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
    }

    var luminance: Double {
        red * 0.2126 + green * 0.7152 + blue * 0.0722
    }

    var inverted: KeyboardPixel {
        KeyboardPixel(red: 1 - red, green: 1 - green, blue: 1 - blue)
    }

    func binary(threshold: Double = 0.5) -> KeyboardPixel {
        luminance >= threshold
            ? .white
            : .black
    }

    /// Preserves source contrast and hue while keeping a small amount of headroom
    /// for the keycap's highlight and shadow gradient.
    var keycapColor: KeyboardPixel {
        let neutral = 0.04 + luminance * 0.92
        let saturation = 0.9
        return KeyboardPixel(
            red: neutral + (red - luminance) * saturation,
            green: neutral + (green - luminance) * saturation,
            blue: neutral + (blue - luminance) * saturation
        )
    }
}

struct KeyboardPixelFrame: Equatable, Sendable {
    static let columnCount = 14
    static let rowCount = 6
    static let blank = KeyboardPixelFrame(pixels: [])

    private(set) var pixels: [KeyboardPixel]

    init(pixels: [KeyboardPixel]) {
        let expectedCount = Self.columnCount * Self.rowCount
        self.pixels = (0..<expectedCount).map { index in
            pixels.indices.contains(index) ? pixels[index] : .black
        }
    }

    subscript(row: Int, column: Int) -> KeyboardPixel {
        guard (0..<Self.rowCount).contains(row),
              (0..<Self.columnCount).contains(column) else { return .black }
        return pixels[row * Self.columnCount + column]
    }

    init(
        pixelBuffer: CVPixelBuffer,
        colorMode: KeyboardPixelColorMode,
        framingMode: KeyboardVideoFramingMode,
        isInverted: Bool
    ) {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA,
              let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            self = .blank
            return
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)

        self = Self.sampling(
            sourceWidth: width,
            sourceHeight: height,
            colorMode: colorMode,
            framingMode: framingMode,
            isInverted: isInverted
        ) { x, y in
            let pixel = bytes + y * bytesPerRow + x * 4
            return KeyboardPixel(
                red: Double(pixel[2]) / 255,
                green: Double(pixel[1]) / 255,
                blue: Double(pixel[0]) / 255
            )
        }
    }

    static func sampling(
        sourceWidth: Int,
        sourceHeight: Int,
        colorMode: KeyboardPixelColorMode,
        framingMode: KeyboardVideoFramingMode,
        isInverted: Bool,
        colorAt: (_ x: Int, _ y: Int) -> KeyboardPixel
    ) -> KeyboardPixelFrame {
        guard sourceWidth > 0, sourceHeight > 0 else { return .blank }

        let sourceAspect = Double(sourceWidth) / Double(sourceHeight)
        let keyboardAspect = Double(columnCount) / Double(rowCount)

        var output: [KeyboardPixel] = []
        output.reserveCapacity(columnCount * rowCount)

        for row in 0..<rowCount {
            for column in 0..<columnCount {
                var red = 0.0
                var green = 0.0
                var blue = 0.0

                // Four samples per key soften compression artifacts while staying
                // inexpensive enough for 30 fps playback on the main actor.
                for sampleY in 0..<2 {
                    for sampleX in 0..<2 {
                        let normalizedX = (Double(column) + (Double(sampleX) + 0.5) / 2) / Double(columnCount)
                        let normalizedY = (Double(row) + (Double(sampleY) + 0.5) / 2) / Double(rowCount)
                        let color: KeyboardPixel
                        if let point = sourcePoint(
                            normalizedX: normalizedX,
                            normalizedY: normalizedY,
                            sourceAspect: sourceAspect,
                            keyboardAspect: keyboardAspect,
                            framingMode: framingMode
                        ) {
                            let x = min(max(Int(point.x * Double(sourceWidth)), 0), sourceWidth - 1)
                            let y = min(max(Int(point.y * Double(sourceHeight)), 0), sourceHeight - 1)
                            let sourceColor = colorAt(x, y)
                            color = isInverted ? sourceColor.inverted : sourceColor
                        } else {
                            color = .black
                        }
                        red += color.red
                        green += color.green
                        blue += color.blue
                    }
                }

                var color = KeyboardPixel(red: red / 4, green: green / 4, blue: blue / 4)
                if colorMode == .binary {
                    color = color.binary()
                }
                output.append(color)
            }
        }

        return KeyboardPixelFrame(pixels: output)
    }

    private static func sourcePoint(
        normalizedX: Double,
        normalizedY: Double,
        sourceAspect: Double,
        keyboardAspect: Double,
        framingMode: KeyboardVideoFramingMode
    ) -> (x: Double, y: Double)? {
        switch framingMode {
        case .stretch:
            return (normalizedX, normalizedY)

        case .fill:
            if sourceAspect < keyboardAspect {
                let visibleHeight = sourceAspect / keyboardAspect
                let originY = (1 - visibleHeight) / 2
                return (normalizedX, originY + normalizedY * visibleHeight)
            } else {
                let visibleWidth = keyboardAspect / sourceAspect
                let originX = (1 - visibleWidth) / 2
                return (originX + normalizedX * visibleWidth, normalizedY)
            }

        case .fit:
            if sourceAspect < keyboardAspect {
                let contentWidth = sourceAspect / keyboardAspect
                let originX = (1 - contentWidth) / 2
                guard normalizedX >= originX, normalizedX <= originX + contentWidth else {
                    return nil
                }
                return ((normalizedX - originX) / contentWidth, normalizedY)
            } else {
                let contentHeight = keyboardAspect / sourceAspect
                let originY = (1 - contentHeight) / 2
                guard normalizedY >= originY, normalizedY <= originY + contentHeight else {
                    return nil
                }
                return (normalizedX, (normalizedY - originY) / contentHeight)
            }
        }
    }
}
