import Foundation
import AppKit
import CoreGraphics
import SwiftUI

protocol ScreenCapturing {
    func captureRegion(_ rect: CGRect, belowWindowID: CGWindowID) -> CGImage?
    func computeFingerprint(for cgImage: CGImage) -> [UInt8]
    func fingerprintDifference(_ a: [UInt8], _ b: [UInt8]) -> Double
    func sampleBubbleAppearance(in cgImage: CGImage, normalizedBox: CGRect) -> (bg: Color, fg: Color)
}

@MainActor
protocol SnapshotExporting {
    func exportSnapshot(
        baseCGImage: CGImage,
        boxes: [OverlayTranslationBox],
        displaySize: CGSize
    ) -> URL?
}

struct CoreGraphicsScreenCaptureService: ScreenCapturing {
    func captureRegion(_ rect: CGRect, belowWindowID: CGWindowID = kCGNullWindowID) -> CGImage? {
        if belowWindowID != kCGNullWindowID {
            return CGWindowListCreateImage(
                rect,
                .optionOnScreenBelowWindow,
                belowWindowID,
                [.boundsIgnoreFraming, .bestResolution]
            )
        } else {
            return CGWindowListCreateImage(
                rect,
                .optionOnScreenOnly,
                kCGNullWindowID,
                [.boundsIgnoreFraming, .bestResolution]
            )
        }
    }

    func computeFingerprint(for cgImage: CGImage) -> [UInt8] {
        let gridW = 32
        let gridH = 32
        var pixels = [UInt8](repeating: 0, count: gridW * gridH)
        guard let context = CGContext(
            data: &pixels,
            width: gridW,
            height: gridH,
            bitsPerComponent: 8,
            bytesPerRow: gridW,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return pixels
        }
        context.interpolationQuality = .low
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: gridW, height: gridH))
        return pixels
    }

    func fingerprintDifference(_ a: [UInt8], _ b: [UInt8]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 1.0 }
        var totalDiff = 0
        for i in 0..<a.count {
            totalDiff += abs(Int(a[i]) - Int(b[i]))
        }
        return Double(totalDiff) / Double(a.count * 255)
    }

    func sampleBubbleAppearance(in cgImage: CGImage, normalizedBox: CGRect) -> (bg: Color, fg: Color) {
        let imgW = CGFloat(cgImage.width)
        let imgH = CGFloat(cgImage.height)
        let cropRect = CGRect(
            x: max(0, normalizedBox.minX * imgW),
            y: max(0, normalizedBox.minY * imgH),
            width: min(imgW - max(0, normalizedBox.minX * imgW), max(6, normalizedBox.width * imgW)),
            height: min(imgH - max(0, normalizedBox.minY * imgH), max(6, normalizedBox.height * imgH))
        ).integral

        guard cropRect.width >= 2, cropRect.height >= 2,
              let cropped = cgImage.cropping(to: cropRect) else {
            return (.white, .black)
        }

        let sampleSize = 20
        var rgba = [UInt8](repeating: 0, count: sampleSize * sampleSize * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &rgba,
            width: sampleSize,
            height: sampleSize,
            bitsPerComponent: 8,
            bytesPerRow: sampleSize * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return (.white, .black)
        }
        ctx.interpolationQuality = .medium
        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: sampleSize, height: sampleSize))

        var pixels: [(r: Double, g: Double, b: Double, lum: Double)] = []
        pixels.reserveCapacity(sampleSize * sampleSize)
        for i in 0..<(sampleSize * sampleSize) {
            let idx = i * 4
            let r = Double(rgba[idx]) / 255.0
            let g = Double(rgba[idx + 1]) / 255.0
            let b = Double(rgba[idx + 2]) / 255.0
            let lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
            pixels.append((r, g, b, lum))
        }

        guard !pixels.isEmpty else { return (.white, .black) }
        pixels.sort { $0.lum < $1.lum }

        let medianLum = pixels[pixels.count / 2].lum
        let startIdx: Int
        let endIdx: Int

        if medianLum >= 0.36 {
            startIdx = Int(Double(pixels.count - 1) * 0.65)
            endIdx = max(startIdx, Int(Double(pixels.count - 1) * 0.85))
        } else {
            startIdx = Int(Double(pixels.count - 1) * 0.15)
            endIdx = max(startIdx, Int(Double(pixels.count - 1) * 0.35))
        }

        var sumR = 0.0, sumG = 0.0, sumB = 0.0, sumLum = 0.0
        let count = Double(endIdx - startIdx + 1)

        for i in startIdx...endIdx {
            sumR += pixels[i].r
            sumG += pixels[i].g
            sumB += pixels[i].b
            sumLum += pixels[i].lum
        }

        let avgR = sumR / count
        let avgG = sumG / count
        let avgB = sumB / count
        let avgLum = sumLum / count

        let bgColor = Color(red: avgR, green: avgG, blue: avgB)
        let fgColor = avgLum >= 0.42
            ? Color(red: 0.08, green: 0.08, blue: 0.10)
            : Color(red: 0.96, green: 0.96, blue: 0.98)

        return (bg: bgColor, fg: fgColor)
    }
}

@MainActor
struct MangaSnapshotExporter: SnapshotExporting {
    func exportSnapshot(
        baseCGImage: CGImage,
        boxes: [OverlayTranslationBox],
        displaySize: CGSize
    ) -> URL? {
        let boxWidth = max(120, displaySize.width)
        let boxHeight = max(120, displaySize.height)

        let compositeView = SnapshotCompositeView(
            baseCGImage: baseCGImage,
            boxes: boxes,
            boxWidth: boxWidth,
            boxHeight: boxHeight
        )

        let renderer = ImageRenderer(content: compositeView)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2.0

        guard let nsImage = renderer.nsImage else { return nil }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([nsImage])

        guard let tiffData = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let filename = "TransManga_\(formatter.string(from: Date())).png"

        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let fileURL = downloadsURL.appendingPathComponent(filename)

        do {
            try pngData.write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            return nil
        }
    }
}

private struct SnapshotCompositeView: View {
    let baseCGImage: CGImage
    let boxes: [OverlayTranslationBox]
    let boxWidth: CGFloat
    let boxHeight: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(decorative: baseCGImage, scale: 1.0)
                .resizable()
                .frame(width: boxWidth, height: boxHeight)

            ForEach(boxes) { box in
                let cx = box.centerX * boxWidth
                let cy = box.centerY * boxHeight
                let rawW = max(22, box.orientedWidth * boxWidth)
                let rawH = max(18, box.orientedHeight * boxHeight)

                let textFrameW = box.isManualSelection ? rawW : max(rawW + 2, 34)
                let textFrameH = box.isManualSelection ? rawH : max(rawH + 2, 18)

                let layout = SelectionOverlayView.layoutMangaText(
                    box.text.uppercased(),
                    width: textFrameW,
                    height: textFrameH
                )

                ZStack {
                    ForEach(box.lineMasks) { mask in
                        let pad: CGFloat = box.isManualSelection ? 0 : 3
                        let mW = max(8, mask.width * boxWidth + pad)
                        let mH = max(8, mask.height * boxHeight + pad)
                        RoundedRectangle(cornerRadius: min(mW, mH) * 0.22, style: .continuous)
                            .fill(mask.backgroundColor)
                            .frame(width: mW, height: mH)
                            .rotationEffect(.radians(mask.rotationRadians))
                            .position(
                                x: mask.centerX * boxWidth,
                                y: mask.centerY * boxHeight
                            )
                    }

                    VStack(spacing: 1) {
                        ForEach(Array(layout.lines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(
                                    size: layout.fontSize,
                                    weight: .bold,
                                    design: .rounded
                                ))
                                .foregroundColor(box.textColor)
                                .lineLimit(1)
                                .minimumScaleFactor(0.35)
                                .allowsTightening(true)
                        }
                    }
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1.5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(box.backgroundColor)
                    )
                    .frame(width: textFrameW, height: textFrameH, alignment: .center)
                    .rotationEffect(.radians(box.rotationRadians))
                    .position(x: cx, y: cy)
                }
            }
        }
        .frame(width: boxWidth, height: boxHeight)
    }
}
