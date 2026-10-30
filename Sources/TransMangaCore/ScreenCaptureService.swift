import Foundation
import CoreGraphics
import SwiftUI

protocol ScreenCapturing {
    func captureRegion(_ rect: CGRect, belowWindowID: CGWindowID) -> CGImage?
    func computeFingerprint(for cgImage: CGImage) -> [UInt8]
    func fingerprintDifference(_ a: [UInt8], _ b: [UInt8]) -> Double
    func sampleBubbleAppearance(in cgImage: CGImage, normalizedBox: CGRect) -> (bg: Color, fg: Color)
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

        var sumR = 0.0
        var sumG = 0.0
        var sumB = 0.0
        var sumLum = 0.0
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
