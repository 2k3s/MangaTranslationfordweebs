import Foundation
import AppKit
import Vision
import VisionKit
import CoreGraphics
import SwiftUI

struct RecognizedBlock: Identifiable {
    let id = UUID()
    let index: Int
    let japaneseText: String
    var englishText: String
    /// Normalized 0...1 top-left bounding box within the captured image
    let boundingBox: CGRect
    /// Oriented center & dimensions in normalized 0...1 coordinates
    let centerX: CGFloat
    let centerY: CGFloat
    let orientedWidth: CGFloat
    let orientedHeight: CGFloat
    let rotationRadians: Double
    /// Individual oriented line masks (including furigana) so all original ink is covered
    var lineMasks: [OrientedLineMask]
}

struct GlossaryEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var japanese: String
    var english: String
}

enum ScreenCapture {
    /// Captures strictly beneath `belowWindowID` (the overlay NSPanel) when valid,
    /// so our own translation bubbles and top-right menu are never captured!
    static func captureRegion(_ rect: CGRect, belowWindowID: CGWindowID = kCGNullWindowID) -> CGImage? {
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
}

enum MangaOCR {
    private struct RawLine {
        let text: String
        let box: CGRect
        let corners: [CGPoint]
        let rotationRadians: Double
        let mask: OrientedLineMask
    }

    static func recognizeBubbleClusters(from cgImage: CGImage) async throws -> [RecognizedBlock] {
        guard ImageAnalyzer.isSupported else {
            return try recognizeHorizontalFallback(from: cgImage)
        }

        let analyzer = ImageAnalyzer()
        var configuration = ImageAnalyzer.Configuration([.text])
        configuration.locales = ["ja-JP", "ja", "en-US"]

        let nsImage = NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )
        let analysis = try await analyzer.analyze(nsImage, orientation: .up, configuration: configuration)

        let rawLines = extractRecognizedLines(
            from: analysis,
            imageWidth: CGFloat(cgImage.width),
            imageHeight: CGFloat(cgImage.height)
        )
        if !rawLines.isEmpty {
            let panelRects = detectHorizontalPanelRects(in: cgImage)
            let clusters = groupLinesIntoSpeechBubbles(
                rawLines,
                panelRects: panelRects,
                imageWidth: CGFloat(cgImage.width),
                imageHeight: CGFloat(cgImage.height)
            )
            if !clusters.isEmpty {
                return clusters
            }
        }

        let fullTranscript = analysis.transcript
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

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
    ) -> [RawLine] {
        var results: [RawLine] = []
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
                guard !trimmed.isEmpty else { continue }

                if line.responds(to: NSSelectorFromString("quad")),
                   let quad = line.value(forKey: "quad") as? NSObject,
                   quad.responds(to: NSSelectorFromString("boundingBox")),
                   let rectVal = quad.value(forKey: "boundingBox") as? NSValue {
                    let rect = rectVal.rectValue
                    guard rect.width > 0.004, rect.height > 0.004 else { continue }

                    let corners = extractQuadCorners(from: quad, fallbackRect: rect)
                    let angle = computeSlantAngleRadians(
                        corners: corners,
                        imageWidth: imageWidth,
                        imageHeight: imageHeight
                    )
                    let mask = computeOrientedMask(
                        corners: corners,
                        angle: angle,
                        sampleBox: rect,
                        imageWidth: imageWidth,
                        imageHeight: imageHeight
                    )

                    results.append(
                        RawLine(
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

    private static func extractQuadCorners(from quad: NSObject, fallbackRect: CGRect) -> [CGPoint] {
        let keys = ["topLeft", "topRight", "bottomRight", "bottomLeft"]
        var pts: [CGPoint] = []
        for key in keys {
            if quad.responds(to: NSSelectorFromString(key)),
               let val = quad.value(forKey: key) as? NSValue {
                pts.append(val.pointValue)
            }
        }
        if pts.count == 4 {
            return pts
        }
        return [
            CGPoint(x: fallbackRect.minX, y: fallbackRect.minY),
            CGPoint(x: fallbackRect.maxX, y: fallbackRect.minY),
            CGPoint(x: fallbackRect.maxX, y: fallbackRect.maxY),
            CGPoint(x: fallbackRect.minX, y: fallbackRect.maxY)
        ]
    }

    private static func computeSlantAngleRadians(
        corners: [CGPoint],
        imageWidth: CGFloat,
        imageHeight: CGFloat
    ) -> Double {
        guard corners.count == 4 else { return 0 }
        let p0 = CGPoint(x: corners[0].x * imageWidth, y: corners[0].y * imageHeight)
        let p1 = CGPoint(x: corners[1].x * imageWidth, y: corners[1].y * imageHeight)
        let p3 = CGPoint(x: corners[3].x * imageWidth, y: corners[3].y * imageHeight)

        let dx1 = p1.x - p0.x
        let dy1 = p1.y - p0.y
        let len1 = hypot(dx1, dy1)

        let dx2 = p3.x - p0.x
        let dy2 = p3.y - p0.y
        let len2 = hypot(dx2, dy2)

        let rawAngle = len1 >= len2
            ? atan2(Double(dy1), Double(dx1))
            : atan2(Double(dy2), Double(dx2))

        var folded = rawAngle
        while folded > Double.pi / 4 { folded -= Double.pi / 2 }
        while folded < -Double.pi / 4 { folded += Double.pi / 2 }

        if abs(folded) < 0.044 {
            return 0
        }
        return folded
    }

    private static func computeOrientedMask(
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
            minU = min(minU, u)
            maxU = max(maxU, u)
            minV = min(minV, v)
            maxV = max(maxV, v)
        }

        let midU = (minU + maxU) * 0.5
        let midV = (minV + maxV) * 0.5
        let centerPxX = midU * cosA - midV * sinA
        let centerPxY = midU * sinA + midV * cosA

        let wPx = max(4, maxU - minU)
        let hPx = max(4, maxV - minV)

        return OrientedLineMask(
            centerX: centerPxX / max(imageWidth, 1),
            centerY: centerPxY / max(imageHeight, 1),
            width: wPx / max(imageWidth, 1),
            height: hPx / max(imageHeight, 1),
            rotationRadians: angle,
            sampleBox: sampleBox
        )
    }

    private static func detectHorizontalPanelRects(in cgImage: CGImage) -> [CGRect] {
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
            let brightRatio = Double(brightCount) / Double(span)
            let darkRatio = Double(darkCount) / Double(span)
            gutterRows[y] = (brightRatio > 0.93 || darkRatio > 0.93)
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
                            x: 0.0,
                            y: CGFloat(start) / CGFloat(sampleH),
                            width: 1.0,
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
                    x: 0.0,
                    y: CGFloat(start) / CGFloat(sampleH),
                    width: 1.0,
                    height: CGFloat(sampleH - start) / CGFloat(sampleH)
                )
            )
        }

        return panelBands.isEmpty ? [CGRect(x: 0, y: 0, width: 1, height: 1)] : panelBands
    }

    private static func groupLinesIntoSpeechBubbles(
        _ lines: [RawLine],
        panelRects: [CGRect],
        imageWidth: CGFloat,
        imageHeight: CGFloat
    ) -> [RecognizedBlock] {
        guard !lines.isEmpty else { return [] }

        var clusters: [[RawLine]] = lines.map { [$0] }
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
            let maxColLength = cluster.map { max($0.mask.width, $0.mask.height) }.max() ?? 0

            let filteredLines: [RawLine]
            if cluster.count > 1 {
                let mainColumns = cluster.filter { line in
                    let thickness = min(line.mask.width, line.mask.height)
                    let length = max(line.mask.width, line.mask.height)
                    let isTinyFurigana = thickness < maxColThickness * 0.52
                        && length < maxColLength * 0.55
                        && line.text.count <= 4
                        && isPureHiragana(line.text)
                    return !isTinyFurigana
                }
                filteredLines = mainColumns.isEmpty ? cluster : mainColumns
            } else {
                filteredLines = cluster
            }

            let avgAngle = filteredLines.map(\.rotationRadians).reduce(0.0, +) / Double(filteredLines.count)
            let isHorizontalOrSlanted = filteredLines.contains { $0.mask.width > $0.mask.height * 1.35 }

            let sortedLines: [RawLine]
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

            let combinedText = sortedLines.map(\.text).joined()
            guard !combinedText.isEmpty else { continue }

            let allCorners = cluster.flatMap(\.corners)
            let clusterMask = computeOrientedMask(
                corners: allCorners,
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

    private static func isPureHiragana(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        for scalar in text.unicodeScalars {
            if !(0x3040...0x309F).contains(scalar.value) {
                return false
            }
        }
        return true
    }

    private static func shouldMergeClusters(
        _ c1: [RawLine],
        _ c2: [RawLine],
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
        _ a: RawLine,
        _ b: RawLine,
        panelRects: [CGRect]
    ) -> Bool {
        if let panelA = panelIndex(for: a.box, in: panelRects),
           let panelB = panelIndex(for: b.box, in: panelRects),
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

    private static func panelIndex(for box: CGRect, in panels: [CGRect]) -> Int? {
        let midY = box.midY
        return panels.firstIndex { $0.minY <= midY && midY <= $0.maxY }
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

        let text = lines.joined(separator: " ")
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

enum LocalTranslator {
    struct ChatRequest: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
        }
        struct Options: Encodable {
            let temperature: Double
        }
        let model: String
        let messages: [Message]
        let stream: Bool
        let keep_alive: String
        let options: Options
    }

    struct ChatResponse: Decodable {
        struct Message: Decodable {
            let content: String
        }
        let message: Message
    }

    static func translateBubbles(
        _ japaneseBubbles: [String],
        glossary: [GlossaryEntry] = []
    ) async -> [String] {
        guard !japaneseBubbles.isEmpty else { return [] }
        guard let url = URL(string: "http://127.0.0.1:11434/api/chat") else {
            return japaneseBubbles.map { _ in "Invalid Ollama URL" }
        }

        let numberedInput = japaneseBubbles.enumerated()
            .map { "[\($0.offset + 1)] \($0.element)" }
            .joined(separator: "\n")

        var glossaryInstruction = ""
        let activeGlossary = glossary.filter {
            !$0.japanese.trimmingCharacters(in: .whitespaces).isEmpty &&
            !$0.english.trimmingCharacters(in: .whitespaces).isEmpty
        }
        if !activeGlossary.isEmpty {
            let terms = activeGlossary
                .map { "- \($0.japanese) = \($0.english)" }
                .joined(separator: "\n")
            glossaryInstruction = "\nAlways use these exact character/term translations when they appear:\n\(terms)\n"
        }

        let systemPrompt = """
        You are a professional Japanese-to-English manga localization translator.
        Translate each numbered Japanese manga speech bubble into natural, concise English dialogue that fits inside a comic speech bubble.
        STRICT RULES:
        - Output strictly in English using the Latin alphabet ONLY.
        - NEVER output any Chinese (Hanzi) or Japanese (Kanji, Hiragana, Katakana) characters under any circumstances.
        - Keep the exact [1], [2], ... numbering on separate lines, with no extra commentary or notes.\(glossaryInstruction)
        """

        let payload = ChatRequest(
            model: "qwen2.5:7b",
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: numberedInput)
            ],
            stream: false,
            keep_alive: "30m",
            options: .init(temperature: 0.1)
        )

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 30
            request.httpBody = try JSONEncoder().encode(payload)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return japaneseBubbles.map { _ in "Ollama error (is 'ollama serve' running?)" }
            }

            let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
            let rawReply = decoded.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return parseNumberedLines(rawReply, expectedCount: japaneseBubbles.count)
        } catch {
            return japaneseBubbles.map { _ in "Connection failed: run 'ollama pull qwen2.5:7b'" }
        }
    }

    private static func parseNumberedLines(_ reply: String, expectedCount: Int) -> [String] {
        let lines = reply
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var results = Array(repeating: "", count: expectedCount)

        for line in lines {
            if let closeBracket = line.firstIndex(of: "]"),
               line.hasPrefix("[") {
                let numStr = String(line[line.index(after: line.startIndex)..<closeBracket])
                if let index = Int(numStr), index >= 1, index <= expectedCount {
                    let textStart = line.index(after: closeBracket)
                    let cleaned = String(line[textStart...]).trimmingCharacters(in: .whitespaces)
                    results[index - 1] = stripCJKCharacters(from: cleaned)
                }
            }
        }

        for i in 0..<expectedCount where results[i].isEmpty {
            if i < lines.count {
                results[i] = stripCJKCharacters(from: lines[i])
            } else {
                results[i] = "..."
            }
        }

        return results
    }

    private static func stripCJKCharacters(from text: String) -> String {
        let filteredScalars = text.unicodeScalars.filter { scalar in
            let v = scalar.value
            let isCJK = (0x4E00...0x9FFF).contains(v)
                || (0x3400...0x4DBF).contains(v)
                || (0x3040...0x309F).contains(v)
                || (0x30A0...0x30FF).contains(v)
                || (0xFF66...0xFF9F).contains(v)
            return !isCJK
        }
        let cleaned = String(String.UnicodeScalarView(filteredScalars))
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "..." : cleaned
    }
}

@MainActor
final class TransMangaModel: ObservableObject {
    @Published var blocks: [RecognizedBlock] = []
    @Published var statusMessage = "Flip ON to show the translation box, then press ⌃⌥M."
    @Published var isBusy = false
    @Published var lastCapturedImage: NSImage?
    @Published var isAutoWatching = false
    @Published var glossary: [GlossaryEntry] = [] {
        didSet { saveGlossary() }
    }

    let store = OverlaySelectionStore.shared

    private var bubbleCache: [String: String] = [:]
    private var watchTimer: Timer?
    private var lastVisualFingerprint: [UInt8]?
    private var pendingStableTicks = 0
    private var lastTranslatedFingerprint: [UInt8]?
    private let glossaryStorageKey = "TransManga.Glossary.v1"

    init() {
        loadGlossary()
        store.onTranslateRequested = { [weak self] in
            Task { @MainActor in
                self?.captureAndTranslate()
            }
        }
        store.onToggleAutoWatch = { [weak self] in
            Task { @MainActor in
                self?.toggleAutoWatch()
            }
        }
        store.onToggleClickThrough = { [weak self] in
            Task { @MainActor in
                self?.toggleClickThrough()
            }
        }
        store.onManualSubBoxSelected = { [weak self] normSubRect in
            Task { @MainActor in
                self?.translateManualSubRegion(normSubRect)
            }
        }
        store.onRemoveBox = { [weak self] id in
            self?.blocks.removeAll { $0.id == id }
        }
    }

    func addGlossaryEntry() {
        glossary.append(GlossaryEntry(japanese: "", english: ""))
    }

    func removeGlossaryEntry(id: UUID) {
        glossary.removeAll { $0.id == id }
        bubbleCache.removeAll()
    }

    private func loadGlossary() {
        guard let data = UserDefaults.standard.data(forKey: glossaryStorageKey),
              let decoded = try? JSONDecoder().decode([GlossaryEntry].self, from: data) else {
            return
        }
        glossary = decoded
    }

    private func saveGlossary() {
        if let encoded = try? JSONEncoder().encode(glossary) {
            UserDefaults.standard.set(encoded, forKey: glossaryStorageKey)
        }
    }

    func toggleClickThrough() {
        store.isClickThrough.toggle()
        statusMessage = store.isClickThrough
            ? "Reading mode locked (click-through ON). Press ⌃⌥O to edit box."
            : "Edit mode active. Drag or resize the box."
    }

    func toggleOverlayCards() {
        store.showTranslationCards.toggle()
        statusMessage = store.showTranslationCards
            ? "Showing English overlay bubbles."
            : "Peeking at original Japanese page (⌃⌥H to show English)."
    }

    func toggleAutoWatch() {
        isAutoWatching.toggle()
        store.isAutoWatching = isAutoWatching

        if isAutoWatching {
            statusMessage = "Auto-Watch ON (⌃⌥W): scrolling or turning pages will auto-translate."
            startAutoWatchLoop()
        } else {
            statusMessage = "Auto-Watch paused."
            stopAutoWatchLoop()
        }
    }

    private func startAutoWatchLoop() {
        stopAutoWatchLoop()
        pendingStableTicks = 0
        watchTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkScreenForChanges()
            }
        }
    }

    private func stopAutoWatchLoop() {
        watchTimer?.invalidate()
        watchTimer = nil
    }

    private func currentCaptureRect() -> CGRect? {
        guard let screen = NSScreen.main else { return nil }
        let screenFrame = screen.frame
        let sel = store.normalizedSelection

        let x = screenFrame.minX + sel.minX * screenFrame.width
        let width = sel.width * screenFrame.width
        let height = sel.height * screenFrame.height

        let screenTopY = NSScreen.screens.first?.frame.height ?? screenFrame.height
        let topDownScreenMinY = screenTopY - screenFrame.maxY
        let y = topDownScreenMinY + sel.minY * screenFrame.height

        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func checkScreenForChanges() {
        guard isAutoWatching, store.isVisible, !isBusy else { return }
        guard let captureRect = currentCaptureRect() else { return }

        // Capture strictly beneath the overlay window so our own bubbles never trigger false page changes
        guard let cgImage = ScreenCapture.captureRegion(
            captureRect,
            belowWindowID: store.overlayWindowID
        ) else {
            return
        }

        let currentFP = Self.computeFingerprint(for: cgImage)

        if let lastFP = lastVisualFingerprint {
            let diff = Self.fingerprintDifference(lastFP, currentFP)
            if diff > 0.025 {
                lastVisualFingerprint = currentFP
                pendingStableTicks = 1
                store.overlayBoxes = []
                return
            }
        } else {
            lastVisualFingerprint = currentFP
            pendingStableTicks = 1
            return
        }

        if pendingStableTicks > 0 {
            pendingStableTicks += 1
            if pendingStableTicks >= 2 {
                pendingStableTicks = 0
                if let lastTranslated = lastTranslatedFingerprint,
                   Self.fingerprintDifference(lastTranslated, currentFP) <= 0.020 {
                    return
                }
                lastTranslatedFingerprint = currentFP
                captureAndTranslate()
            }
        }
    }

    private static func computeFingerprint(for cgImage: CGImage) -> [UInt8] {
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

    private static func fingerprintDifference(_ a: [UInt8], _ b: [UInt8]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 1.0 }
        var totalDiff = 0
        for i in 0..<a.count {
            totalDiff += abs(Int(a[i]) - Int(b[i]))
        }
        return Double(totalDiff) / Double(a.count * 255)
    }

    private static func sampleBubbleAppearance(in cgImage: CGImage, normalizedBox: CGRect) -> (bg: Color, fg: Color) {
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

    func captureAndTranslate() {
        guard !isBusy else { return }
        guard store.isVisible else {
            statusMessage = "Turn ON the translation box first."
            return
        }
        guard let captureRect = currentCaptureRect() else {
            statusMessage = "Unable to determine screen capture region."
            return
        }

        isBusy = true
        statusMessage = "Capturing selected region..."

        Task {
            guard let cgImage = ScreenCapture.captureRegion(
                captureRect,
                belowWindowID: store.overlayWindowID
            ) else {
                statusMessage = "Screen capture failed. Check Screen Recording permission in System Settings."
                isBusy = false
                return
            }

            let fp = Self.computeFingerprint(for: cgImage)
            lastVisualFingerprint = fp
            lastTranslatedFingerprint = fp
            lastCapturedImage = NSImage(cgImage: cgImage, size: captureRect.size)

            do {
                statusMessage = "Detecting Japanese speech bubbles..."
                var detectedBlocks = try await MangaOCR.recognizeBubbleClusters(from: cgImage)

                if detectedBlocks.isEmpty {
                    blocks = []
                    store.overlayBoxes = []
                    statusMessage = "No Japanese text detected in the selected area."
                    isBusy = false
                    return
                }

                var appearances: [(bg: Color, fg: Color)] = []
                for i in 0..<detectedBlocks.count {
                    let bubbleColor = Self.sampleBubbleAppearance(
                        in: cgImage,
                        normalizedBox: detectedBlocks[i].boundingBox
                    )
                    appearances.append(bubbleColor)

                    for mIdx in 0..<detectedBlocks[i].lineMasks.count {
                        let lineSample = Self.sampleBubbleAppearance(
                            in: cgImage,
                            normalizedBox: detectedBlocks[i].lineMasks[mIdx].sampleBox
                        )
                        detectedBlocks[i].lineMasks[mIdx].backgroundColor = lineSample.bg
                    }
                }

                var uncachedIndices: [Int] = []
                var uncachedJapanese: [String] = []

                for (i, block) in detectedBlocks.enumerated() {
                    if let cachedEnglish = bubbleCache[block.japaneseText] {
                        detectedBlocks[i].englishText = cachedEnglish
                    } else {
                        uncachedIndices.append(i)
                        uncachedJapanese.append(block.japaneseText)
                    }
                }

                blocks = detectedBlocks

                if !uncachedJapanese.isEmpty {
                    statusMessage = "Translating \(uncachedJapanese.count) bubble(s) (\(detectedBlocks.count - uncachedJapanese.count) cached)..."
                    let freshTranslations = await LocalTranslator.translateBubbles(
                        uncachedJapanese,
                        glossary: glossary
                    )
                    for (offset, blockIdx) in uncachedIndices.enumerated() where offset < freshTranslations.count {
                        let english = freshTranslations[offset]
                        detectedBlocks[blockIdx].englishText = english
                        bubbleCache[detectedBlocks[blockIdx].japaneseText] = english
                    }
                }

                blocks = detectedBlocks
                store.overlayBoxes = detectedBlocks.enumerated().map { i, block in
                    OverlayTranslationBox(
                        index: block.index,
                        text: block.englishText,
                        boundingBox: block.boundingBox,
                        centerX: block.centerX,
                        centerY: block.centerY,
                        orientedWidth: block.orientedWidth,
                        orientedHeight: block.orientedHeight,
                        rotationRadians: block.rotationRadians,
                        lineMasks: block.lineMasks,
                        backgroundColor: appearances[i].bg,
                        textColor: appearances[i].fg,
                        isManualSelection: false
                    )
                }
                store.showTranslationCards = true
                statusMessage = "Translated \(detectedBlocks.count) speech bubble(s)."
            } catch {
                statusMessage = "OCR Error: \(error.localizedDescription)"
            }

            isBusy = false
        }
    }

    func translateManualSubRegion(_ normSubRect: CGRect) {
        guard !isBusy else { return }
        guard let fullCaptureRect = currentCaptureRect() else { return }

        isBusy = true
        statusMessage = "Translating manually selected box..."

        Task {
            guard let fullCGImage = ScreenCapture.captureRegion(
                fullCaptureRect,
                belowWindowID: store.overlayWindowID
            ) else {
                statusMessage = "Screen capture failed."
                isBusy = false
                return
            }

            let imgW = CGFloat(fullCGImage.width)
            let imgH = CGFloat(fullCGImage.height)
            let cropRect = CGRect(
                x: max(0, normSubRect.minX * imgW),
                y: max(0, normSubRect.minY * imgH),
                width: min(imgW - max(0, normSubRect.minX * imgW), max(8, normSubRect.width * imgW)),
                height: min(imgH - max(0, normSubRect.minY * imgH), max(8, normSubRect.height * imgH))
            ).integral

            guard let subCGImage = fullCGImage.cropping(to: cropRect) else {
                statusMessage = "Manual selection was too small."
                isBusy = false
                return
            }

            do {
                let subClusters = try await MangaOCR.recognizeBubbleClusters(from: subCGImage)
                let combinedJP = subClusters
                    .map(\.japaneseText)
                    .joined(separator: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                guard !combinedJP.isEmpty else {
                    statusMessage = "No Japanese text detected inside the manual box."
                    isBusy = false
                    return
                }

                let english: String
                if let cached = bubbleCache[combinedJP] {
                    english = cached
                } else {
                    let translated = await LocalTranslator.translateBubbles([combinedJP], glossary: glossary)
                    english = translated.first ?? "..."
                    bubbleCache[combinedJP] = english
                }

                let appearance = Self.sampleBubbleAppearance(in: fullCGImage, normalizedBox: normSubRect)
                let nextIndex = (store.overlayBoxes.map(\.index).max() ?? 0) + 1

                let manualMask = OrientedLineMask(
                    centerX: normSubRect.midX,
                    centerY: normSubRect.midY,
                    width: normSubRect.width,
                    height: normSubRect.height,
                    rotationRadians: 0,
                    sampleBox: normSubRect,
                    backgroundColor: appearance.bg
                )

                let newBox = OverlayTranslationBox(
                    index: nextIndex,
                    text: english,
                    boundingBox: normSubRect,
                    centerX: normSubRect.midX,
                    centerY: normSubRect.midY,
                    orientedWidth: normSubRect.width,
                    orientedHeight: normSubRect.height,
                    rotationRadians: 0,
                    lineMasks: [manualMask],
                    backgroundColor: appearance.bg,
                    textColor: appearance.fg,
                    isManualSelection: true
                )

                let newBlock = RecognizedBlock(
                    index: nextIndex,
                    japaneseText: combinedJP,
                    englishText: english,
                    boundingBox: normSubRect,
                    centerX: normSubRect.midX,
                    centerY: normSubRect.midY,
                    orientedWidth: normSubRect.width,
                    orientedHeight: normSubRect.height,
                    rotationRadians: 0,
                    lineMasks: [manualMask]
                )

                blocks.append(newBlock)
                store.overlayBoxes.append(newBox)
                store.showTranslationCards = true
                statusMessage = "Added manual translation #\(nextIndex)."
            } catch {
                statusMessage = "Manual OCR Error: \(error.localizedDescription)"
            }

            isBusy = false
        }
    }
}
