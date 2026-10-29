import Foundation
import AppKit
import Vision
import VisionKit
import CoreGraphics

protocol OCRRecognizing {
    func recognizeBubbleClusters(from cgImage: CGImage) async throws -> [RecognizedBlock]
}

struct OCRRawLine {
    let text: String
    let box: CGRect
    let corners: [CGPoint]
    let rotationRadians: Double
    let mask: OrientedLineMask
}

// MARK: - 1. Quad Geometry Calculator (Single Responsibility: Rotated Quad Math)

enum QuadGeometryCalculator {
    static func extractQuadCorners(from quad: NSObject, fallbackRect: CGRect) -> [CGPoint] {
        let keys = ["topLeft", "topRight", "bottomRight", "bottomLeft"]
        var pts: [CGPoint] = []
        for key in keys {
            if quad.responds(to: NSSelectorFromString(key)),
               let val = quad.value(forKey: key) as? NSValue {
                pts.append(val.pointValue)
            }
        }
        guard pts.count == 4 else {
            return [
                CGPoint(x: fallbackRect.minX, y: fallbackRect.minY),
                CGPoint(x: fallbackRect.maxX, y: fallbackRect.minY),
                CGPoint(x: fallbackRect.maxX, y: fallbackRect.maxY),
                CGPoint(x: fallbackRect.minX, y: fallbackRect.maxY)
            ]
        }
        return pts
    }

    static func computeSlantAngleRadians(
        corners: [CGPoint],
        imageWidth: CGFloat,
        imageHeight: CGFloat
    ) -> Double {
        guard corners.count == 4 else { return 0 }
        let p0 = CGPoint(x: corners[0].x * imageWidth, y: corners[0].y * imageHeight)
        let p1 = CGPoint(x: corners[1].x * imageWidth, y: corners[1].y * imageHeight)
        let p3 = CGPoint(x: corners[3].x * imageWidth, y: corners[3].y * imageHeight)

        let dx1 = p1.x - p0.x, dy1 = p1.y - p0.y
        let dx2 = p3.x - p0.x, dy2 = p3.y - p0.y

        let rawAngle = hypot(dx1, dy1) >= hypot(dx2, dy2)
            ? atan2(Double(dy1), Double(dx1))
            : atan2(Double(dy2), Double(dx2))

        var folded = rawAngle
        while folded > Double.pi / 4 { folded -= Double.pi / 2 }
        while folded < -Double.pi / 4 { folded += Double.pi / 2 }

        return abs(folded) < 0.044 ? 0 : folded
    }

    static func computeOrientedMask(
        corners: [CGPoint],
        angle: Double,
        sampleBox: CGRect,
        imageWidth: CGFloat,
        imageHeight: CGFloat
    ) -> OrientedLineMask {
        let cosA = CGFloat(cos(angle))
        let sinA = CGFloat(sin(angle))

        var minU = CGFloat.greatestFiniteMagnitude
        var maxU = -CGFloat.greatestFiniteMagnitude
        var minV = CGFloat.greatestFiniteMagnitude
        var maxV = -CGFloat.greatestFiniteMagnitude

        for pt in corners {
            let px = pt.x * imageWidth
            let py = pt.y * imageHeight
            let u = px * cosA + py * sinA
            let v = -px * sinA + py * cosA
            minU = min(minU, u); maxU = max(maxU, u)
            minV = min(minV, v); maxV = max(maxV, v)
        }

        let midU = (minU + maxU) * 0.5
        let midV = (minV + maxV) * 0.5
        let centerPxX = midU * cosA - midV * sinA
        let centerPxY = midU * sinA + midV * cosA

        return OrientedLineMask(
            centerX: centerPxX / max(imageWidth, 1),
            centerY: centerPxY / max(imageHeight, 1),
            width: max(4, maxU - minU) / max(imageWidth, 1),
            height: max(4, maxV - minV) / max(imageHeight, 1),
            rotationRadians: angle,
            sampleBox: sampleBox
        )
    }
}

// MARK: - 2. Manga Text Sanitizer (Single Responsibility: Furigana & Script Filtering)

enum MangaTextSanitizer {
    static func containsJapaneseCharacters(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            let v = scalar.value
            if (0x3040...0x309F).contains(v)
                || (0x30A0...0x30FF).contains(v)
                || (0x4E00...0x9FFF).contains(v)
                || (0x3400...0x4DBF).contains(v) {
                return true
            }
        }
        return false
    }

    static func containsKanji(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            let v = scalar.value
            if (0x4E00...0x9FFF).contains(v) || (0x3400...0x4DBF).contains(v) {
                return true
            }
        }
        return false
    }

    static func isPureHiragana(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        for scalar in text.unicodeScalars {
            if !(0x3040...0x309F).contains(scalar.value) {
                return false
            }
        }
        return true
    }

    static func isFuriganaGloss(
        _ line: OCRRawLine,
        kanjiLines: [OCRRawLine],
        maxColThickness: CGFloat
    ) -> Bool {
        guard isPureHiragana(line.text), line.text.count <= 5 else { return false }
        let thickness = min(line.mask.width, line.mask.height)
        guard thickness < maxColThickness * 0.68 else { return false }

        for kLine in kanjiLines {
            let kThickness = min(kLine.mask.width, kLine.mask.height)
            guard thickness < kThickness * 0.78 else { continue }

            let horizGap = max(0, max(line.box.minX, kLine.box.minX) - min(line.box.maxX, kLine.box.maxX))
            let vertOverlap = min(line.box.maxY, kLine.box.maxY) - max(line.box.minY, kLine.box.minY)

            if horizGap < kThickness * 0.95 && vertOverlap > line.box.height * 0.45 {
                return true
            }
        }
        return false
    }

    static func cleanVerticalOCRArtifacts(_ text: String) -> String {
        let chars = Array(text)
        guard chars.count >= 2 else { return text }
        var out = chars

        for i in 0..<out.count where out[i] == "一" {
            let prevIsKana = i > 0 && isKana(out[i - 1])
            let nextIsKana = (i + 1 < out.count) && isKana(out[i + 1])
            if prevIsKana && (nextIsKana || i == out.count - 1) {
                out[i] = "ー"
            }
        }
        return String(out)
    }

    private static func isKana(_ ch: Character) -> Bool {
        guard let scalar = ch.unicodeScalars.first else { return false }
        let v = scalar.value
        return (0x3040...0x309F).contains(v) || (0x30A0...0x30FF).contains(v)
    }
}

// MARK: - 3. Panel Band Detector (Single Responsibility: Horizontal Panel Gutter Detection)

enum PanelBandDetector {
    static func detectHorizontalPanelRects(in cgImage: CGImage) -> [CGRect] {
        let width = cgImage.width
        let height = cgImage.height
        guard width > 40, height > 40 else {
            return [CGRect(x: 0, y: 0, width: 1, height: 1)]
        }

        let sampleW = min(width, 240)
        let sampleH = min(height, 360)
        var pixels = [UInt8](repeating: 0, count: sampleW * sampleH)

        guard let context = CGContext(
            data: &pixels,
            width: sampleW,
            height: sampleH,
            bitsPerComponent: 8,
            bytesPerRow: sampleW,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return [CGRect(x: 0, y: 0, width: 1, height: 1)]
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: sampleW, height: sampleH))

        let xStart = Int(Double(sampleW) * 0.05)
        let xEnd = Int(Double(sampleW) * 0.95)
        let span = max(1, xEnd - xStart)

        var gutterRows = [Bool](repeating: false, count: sampleH)
        for y in 0..<sampleH {
            var brightCount = 0
            var darkCount = 0
            let rowOffset = y * sampleW
            for x in xStart..<xEnd {
                let lum = pixels[rowOffset + x]
                if lum >= 242 { brightCount += 1 }
                if lum <= 25 { darkCount += 1 }
            }
            gutterRows[y] = (Double(brightCount) / Double(span) > 0.93)
                || (Double(darkCount) / Double(span) > 0.93)
        }

        var panelBands: [CGRect] = []
        var bandStart: Int? = nil
        let minBandHeight = max(4, Int(Double(sampleH) * 0.08))

        for y in 0..<sampleH {
            if !gutterRows[y] {
                if bandStart == nil { bandStart = y }
            } else if let start = bandStart {
                if y - start >= minBandHeight {
                    panelBands.append(
                        CGRect(
                            x: 0,
                            y: CGFloat(start) / CGFloat(sampleH),
                            width: 1,
                            height: CGFloat(y - start) / CGFloat(sampleH)
                        )
                    )
                }
                bandStart = nil
            }
        }
        if let start = bandStart, sampleH - start >= minBandHeight {
            panelBands.append(
                CGRect(
                    x: 0,
                    y: CGFloat(start) / CGFloat(sampleH),
                    width: 1,
                    height: CGFloat(sampleH - start) / CGFloat(sampleH)
                )
            )
        }

        return panelBands.isEmpty ? [CGRect(x: 0, y: 0, width: 1, height: 1)] : panelBands
    }
}

// MARK: - 4. Bubble Clusterer (Single Responsibility: Grouping Lines & Manga Reading Order)

enum BubbleClusterer {
    static func groupLinesIntoSpeechBubbles(
        _ lines: [OCRRawLine],
        panelRects: [CGRect],
        imageWidth: CGFloat,
        imageHeight: CGFloat
    ) -> [RecognizedBlock] {
        guard !lines.isEmpty else { return [] }

        var clusters: [[OCRRawLine]] = lines.map { [$0] }
        var didMerge = true

        while didMerge {
            didMerge = false
            outer: for i in 0..<clusters.count {
                for j in (i + 1)..<clusters.count {
                    if shouldMergeClusters(clusters[i], clusters[j], panelRects: panelRects) {
                        clusters[i].append(contentsOf: clusters[j])
                        clusters.remove(at: j)
                        didMerge = true
                        break outer
                    }
                }
            }
        }

        struct RawCluster {
            let text: String
            let box: CGRect
            let centerX: CGFloat
            let centerY: CGFloat
            let orientedWidth: CGFloat
            let orientedHeight: CGFloat
            let rotationRadians: Double
            let lineMasks: [OrientedLineMask]
        }

        var rawClusters: [RawCluster] = []
        for cluster in clusters {
            let unionBox = cluster.reduce(cluster[0].box) { $0.union($1.box) }
            let maxColThickness = cluster.map { min($0.mask.width, $0.mask.height) }.max() ?? 0
            let kanjiLines = cluster.filter { MangaTextSanitizer.containsKanji($0.text) }

            let filteredLines: [OCRRawLine]
            if cluster.count > 1 {
                let mainColumns = cluster.filter { line in
                    !MangaTextSanitizer.isFuriganaGloss(
                        line,
                        kanjiLines: kanjiLines,
                        maxColThickness: maxColThickness
                    )
                }
                filteredLines = mainColumns.isEmpty ? cluster : mainColumns
            } else {
                filteredLines = cluster
            }

            let avgAngle = filteredLines.map(\.rotationRadians).reduce(0.0, +) / Double(filteredLines.count)
            let isHorizontalOrSlanted = filteredLines.contains { $0.mask.width > $0.mask.height * 1.35 }

            let sortedLines: [OCRRawLine]
            if isHorizontalOrSlanted {
                sortedLines = filteredLines.sorted { $0.box.midY < $1.box.midY }
            } else {
                sortedLines = filteredLines.sorted { a, b in
                    if abs(a.box.midX - b.box.midX) > 0.015 {
                        return a.box.midX > b.box.midX
                    }
                    return a.box.minY < b.box.minY
                }
            }

            let combinedText = MangaTextSanitizer.cleanVerticalOCRArtifacts(
                sortedLines.map(\.text).joined()
            )
            guard !combinedText.isEmpty else { continue }

            let clusterMask = QuadGeometryCalculator.computeOrientedMask(
                corners: cluster.flatMap(\.corners),
                angle: avgAngle,
                sampleBox: unionBox,
                imageWidth: imageWidth,
                imageHeight: imageHeight
            )

            rawClusters.append(
                RawCluster(
                    text: combinedText,
                    box: unionBox,
                    centerX: clusterMask.centerX,
                    centerY: clusterMask.centerY,
                    orientedWidth: clusterMask.width,
                    orientedHeight: clusterMask.height,
                    rotationRadians: avgAngle,
                    lineMasks: cluster.map(\.mask)
                )
            )
        }

        rawClusters.sort { a, b in
            let verticalOverlap = min(a.box.maxY, b.box.maxY) - max(a.box.minY, b.box.minY)
            let minH = min(a.box.height, b.box.height)
            if verticalOverlap > minH * 0.25 {
                return a.box.midX > b.box.midX
            }
            return a.box.minY < b.box.minY
        }

        return rawClusters.enumerated().map { idx, item in
            RecognizedBlock(
                index: idx + 1,
                japaneseText: item.text,
                englishText: "Translating...",
                boundingBox: item.box,
                centerX: item.centerX,
                centerY: item.centerY,
                orientedWidth: item.orientedWidth,
                orientedHeight: item.orientedHeight,
                rotationRadians: item.rotationRadians,
                lineMasks: item.lineMasks
            )
        }
    }

    private static func shouldMergeClusters(
        _ c1: [OCRRawLine],
        _ c2: [OCRRawLine],
        panelRects: [CGRect]
    ) -> Bool {
        for a in c1 {
            for b in c2 {
                if areLinesInSameBubble(a, b, panelRects: panelRects) {
                    return true
                }
            }
        }
        return false
    }

    private static func areLinesInSameBubble(
        _ a: OCRRawLine,
        _ b: OCRRawLine,
        panelRects: [CGRect]
    ) -> Bool {
        if let panelA = panelRects.firstIndex(where: { $0.minY <= a.box.midY && a.box.midY <= $0.maxY }),
           let panelB = panelRects.firstIndex(where: { $0.minY <= b.box.midY && b.box.midY <= $0.maxY }),
           panelA != panelB {
            return false
        }

        if abs(a.rotationRadians - b.rotationRadians) > 0.14 {
            return false
        }

        let aIsHoriz = a.mask.width > a.mask.height * 1.25
        let bIsHoriz = b.mask.width > b.mask.height * 1.25
        if aIsHoriz && bIsHoriz {
            let lineH = max(min(a.mask.height, b.mask.height), 0.012)
            let verticalCenterDist = abs(a.mask.centerY - b.mask.centerY)
            let horizOverlap = min(a.box.maxX, b.box.maxX) - max(a.box.minX, b.box.minX)
            let minW = min(a.box.width, b.box.width)
            return horizOverlap > minW * 0.35 && verticalCenterDist < lineH * 1.75
        }

        let colWidth = max(min(a.box.width, b.box.width), 0.014)
        let horizontalGap = max(0, max(a.box.minX, b.box.minX) - min(a.box.maxX, b.box.maxX))
        let verticalOverlap = min(a.box.maxY, b.box.maxY) - max(a.box.minY, b.box.minY)
        let minHeight = min(a.box.height, b.box.height)
        let topAlignmentDiff = abs(a.box.minY - b.box.minY)
        let maxHeight = max(a.box.height, b.box.height)

        let isVerticallyAligned = (verticalOverlap > minHeight * 0.35) || (topAlignmentDiff < maxHeight * 0.30)
        let isHorizontallyAdjacent = horizontalGap < colWidth * 1.65

        return isVerticallyAligned && isHorizontallyAdjacent
    }
}

// MARK: - 5. VisionKit Manga OCR Service (Single Responsibility: VisionKit Execution)

struct VisionKitMangaOCRService: OCRRecognizing {
    func recognizeBubbleClusters(from cgImage: CGImage) async throws -> [RecognizedBlock] {
        guard ImageAnalyzer.isSupported else {
            return try Self.recognizeHorizontalFallback(from: cgImage)
        }

        let analyzer = ImageAnalyzer()
        var configuration = ImageAnalyzer.Configuration([.text])
        configuration.locales = ["ja-JP", "ja", "en-US"]

        let nsImage = NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )
        let analysis = try await analyzer.analyze(nsImage, orientation: .up, configuration: configuration)

        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)
        let rawLines = Self.extractRecognizedLines(
            from: analysis,
            imageWidth: imageWidth,
            imageHeight: imageHeight
        )

        if !rawLines.isEmpty {
            let panelRects = PanelBandDetector.detectHorizontalPanelRects(in: cgImage)
            let clusters = BubbleClusterer.groupLinesIntoSpeechBubbles(
                rawLines,
                panelRects: panelRects,
                imageWidth: imageWidth,
                imageHeight: imageHeight
            )
            if !clusters.isEmpty {
                return clusters
            }
        }

        let fullTranscript = MangaTextSanitizer.cleanVerticalOCRArtifacts(
            analysis.transcript
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { MangaTextSanitizer.containsJapaneseCharacters($0) }
                .joined(separator: " ")
        )

        guard !fullTranscript.isEmpty else { return [] }
        let fallbackBox = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
        return [
            RecognizedBlock(
                index: 1,
                japaneseText: fullTranscript,
                englishText: "Translating...",
                boundingBox: fallbackBox,
                centerX: 0.5,
                centerY: 0.5,
                orientedWidth: 0.8,
                orientedHeight: 0.8,
                rotationRadians: 0,
                lineMasks: [
                    OrientedLineMask(
                        centerX: 0.5,
                        centerY: 0.5,
                        width: 0.8,
                        height: 0.8,
                        rotationRadians: 0,
                        sampleBox: fallbackBox
                    )
                ]
            )
        ]
    }

    private static func extractRecognizedLines(
        from analysis: ImageAnalysis,
        imageWidth: CGFloat,
        imageHeight: CGFloat
    ) -> [OCRRawLine] {
        var results: [OCRRawLine] = []
        let mirror = Mirror(reflecting: analysis)

        for child in mirror.children {
            guard let vkAnalysis = child.value as? NSObject,
                  vkAnalysis.responds(to: NSSelectorFromString("allLines")),
                  let allLines = vkAnalysis.value(forKey: "allLines") as? [NSObject] else {
                continue
            }

            for line in allLines {
                guard line.responds(to: NSSelectorFromString("string")),
                      let text = line.value(forKey: "string") as? String else {
                    continue
                }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard MangaTextSanitizer.containsJapaneseCharacters(trimmed) else { continue }

                if line.responds(to: NSSelectorFromString("quad")),
                   let quad = line.value(forKey: "quad") as? NSObject,
                   quad.responds(to: NSSelectorFromString("boundingBox")),
                   let rectVal = quad.value(forKey: "boundingBox") as? NSValue {
                    let rect = rectVal.rectValue
                    guard rect.width > 0.004, rect.height > 0.004 else { continue }

                    let corners = QuadGeometryCalculator.extractQuadCorners(from: quad, fallbackRect: rect)
                    let angle = QuadGeometryCalculator.computeSlantAngleRadians(
                        corners: corners,
                        imageWidth: imageWidth,
                        imageHeight: imageHeight
                    )
                    let mask = QuadGeometryCalculator.computeOrientedMask(
                        corners: corners,
                        angle: angle,
                        sampleBox: rect,
                        imageWidth: imageWidth,
                        imageHeight: imageHeight
                    )

                    results.append(
                        OCRRawLine(
                            text: trimmed,
                            box: rect,
                            corners: corners,
                            rotationRadians: angle,
                            mask: mask
                        )
                    )
                }
            }
        }
        return results
    }

    private static func recognizeHorizontalFallback(from cgImage: CGImage) throws -> [RecognizedBlock] {
        var lines: [String] = []
        let request = VNRecognizeTextRequest { req, _ in
            guard let observations = req.results as? [VNRecognizedTextObservation] else { return }
            lines = observations.compactMap { $0.topCandidates(1).first?.string }
        }
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ja-JP", "en-US"]
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        let text = MangaTextSanitizer.cleanVerticalOCRArtifacts(lines.joined(separator: " "))
        guard !text.isEmpty else { return [] }
        let box = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
        return [
            RecognizedBlock(
                index: 1,
                japaneseText: text,
                englishText: "Translating...",
                boundingBox: box,
                centerX: 0.5,
                centerY: 0.5,
                orientedWidth: 0.8,
                orientedHeight: 0.8,
                rotationRadians: 0,
                lineMasks: [
                    OrientedLineMask(
                        centerX: 0.5,
                        centerY: 0.5,
                        width: 0.8,
                        height: 0.8,
                        rotationRadians: 0,
                        sampleBox: box
                    )
                ]
            )
        ]
    }
}
