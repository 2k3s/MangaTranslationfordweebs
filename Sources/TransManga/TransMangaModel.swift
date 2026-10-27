import AppKit
@preconcurrency import Vision
import VisionKit
import ImageIO

@MainActor
final class TransMangaModel: ObservableObject {
    @Published var recognizedText = ""
    @Published var translatedText = ""
    @Published var error: String? {
        didSet {
            OverlaySelectionStore.shared.statusError = error
        }
    }
    @Published var isWorking = false {
        didSet {
            OverlaySelectionStore.shared.isWorking = isWorking
        }
    }
    @Published var isAutoWatching = true {
        didSet {
            OverlaySelectionStore.shared.isAutoWatching = isAutoWatching
        }
    }

    private var watchTask: Task<Void, Never>?
    private var captureTask: Task<Void, Never>?
    private var lastTranslatedFingerprint: [UInt8]?
    private var lastTranslatedSelectionRect: CGRect?

    init() {
        OverlaySelectionStore.shared.isAutoWatching = isAutoWatching
        print("Auto-Watch: enabled (monitoring selection for page changes)")
        startWatching()
    }

    func reset() {
        captureTask?.cancel()
        recognizedText = ""
        translatedText = ""
        error = nil
        lastTranslatedFingerprint = nil
        OverlaySelectionStore.shared.translationBoxes = []
    }

    func clearTranslationCache() {
        LocalTranslator.clearCache()
    }

    func toggleAutoWatch() {
        isAutoWatching.toggle()
        if isAutoWatching {
            print("Auto-Watch: enabled")
            startWatching()
        } else {
            print("Auto-Watch: disabled")
            watchTask?.cancel()
            watchTask = nil
        }
    }

    func captureAndRecognize() async {
        captureTask?.cancel()
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let image = try ScreenCapture.captureSelectedRegion()
                let fp = ScreenCapture.fingerprint(of: image)
                self.lastTranslatedFingerprint = fp
                self.lastTranslatedSelectionRect = OverlaySelectionStore.shared.normalizedRect
                await self.processCapturedImage(image)
            } catch {
                self.error = error.localizedDescription
            }
        }
        captureTask = task
        await task.value
    }

    private func startWatching() {
        watchTask?.cancel()
        watchTask = Task { [weak self] in
            guard let self else { return }
            var previousTickFP: [UInt8]?
            var isWaitingToSettle = false

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 350_000_000) // 0.35s tick
                guard !Task.isCancelled, self.isAutoWatching else { break }

                guard let image = try? ScreenCapture.captureSelectedRegion() else {
                    continue
                }

                let currentFP = ScreenCapture.fingerprint(of: image)
                let currentRect = OverlaySelectionStore.shared.normalizedRect

                if let lastFP = self.lastTranslatedFingerprint {
                    let pageChanged = ScreenCapture.hasPageChanged(currentFP, lastFP)
                    let rectChanged = (self.lastTranslatedSelectionRect != currentRect)

                    if pageChanged || rectChanged {
                        if !OverlaySelectionStore.shared.translationBoxes.isEmpty {
                            OverlaySelectionStore.shared.translationBoxes = []
                            print("Auto-Watch: page change detected, hiding overlay cards")
                        }
                        self.captureTask?.cancel()
                        isWaitingToSettle = true
                    }
                }

                if isWaitingToSettle, let prevFP = previousTickFP {
                    if ScreenCapture.hasPageSettled(currentFP, prevFP) {
                        isWaitingToSettle = false
                        self.lastTranslatedFingerprint = currentFP
                        self.lastTranslatedSelectionRect = currentRect

                        print("Auto-Watch: page settled, running OCR & translation")
                        self.captureTask?.cancel()
                        self.captureTask = Task { [weak self] in
                            await self?.processCapturedImage(image)
                        }
                    }
                }

                previousTickFP = currentFP
            }
        }
    }

    private func processCapturedImage(_ image: CGImage) async {
        isWorking = true
        error = nil
        defer { isWorking = false }

        do {
            let regions = try await JapaneseOCR.recognizeRegions(in: image)
            try Task.checkCancellation()

            if regions.isEmpty {
                recognizedText = "No Japanese text was detected. Try zooming in or capturing a page with larger text."
                translatedText = ""
                OverlaySelectionStore.shared.translationBoxes = []
                return
            }

            recognizedText = regions.map(\.japaneseText).joined(separator: "\n\n")

            let englishBlocks = try await LocalTranslator.translateRegions(
                regions.map(\.japaneseText)
            )
            try Task.checkCancellation()

            translatedText = englishBlocks.joined(separator: "\n\n")
            OverlaySelectionStore.shared.areCardsHidden = false

            OverlaySelectionStore.shared.translationBoxes = zip(regions, englishBlocks).map { region, english in
                OverlayTranslationBox(
                    normalizedRect: region.normalizedRect,
                    text: english
                )
            }
        } catch is CancellationError {
            // Cancelled by a newer page turn or scroll; ignore quietly.
        } catch {
            self.error = error.localizedDescription
        }
    }
}

enum ScreenCaptureError: LocalizedError {
    case noDisplayImage

    var errorDescription: String? {
        switch self {
        case .noDisplayImage:
            return "Couldn't capture the display. Grant Screen Recording permission in System Settings → Privacy & Security."
        }
    }
}

enum ScreenCapture {
    static func captureSelectedRegion() throws -> CGImage {
        guard let screen = NSScreen.main,
              let windowID = OverlaySelectionStore.shared.overlayWindowID else {
            throw ScreenCaptureError.noDisplayImage
        }

        let selection = OverlaySelectionStore.shared.normalizedRect
        let screenFrame = screen.frame
        let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? screenFrame.height
        let screenTopY = primaryScreenHeight - screenFrame.maxY

        let captureRect = CGRect(
            x: screenFrame.minX + selection.minX * screenFrame.width,
            y: screenTopY + selection.minY * screenFrame.height,
            width: selection.width * screenFrame.width,
            height: selection.height * screenFrame.height
        )

        guard let image = CGWindowListCreateImage(
            captureRect,
            .optionOnScreenBelowWindow,
            windowID,
            [.bestResolution, .boundsIgnoreFraming]
        ) else {
            throw ScreenCaptureError.noDisplayImage
        }

        return image
    }

    static func fingerprint(of image: CGImage) -> [UInt8] {
        let size = 32
        var pixels = [UInt8](repeating: 0, count: size * size)
        let colorSpace = CGColorSpaceCreateDeviceGray()

        guard let context = CGContext(
            data: &pixels,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return pixels
        }

        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        return pixels
    }

    static func hasPageChanged(_ a: [UInt8], _ b: [UInt8]) -> Bool {
        guard a.count == b.count, !a.isEmpty else { return true }
        var totalDiff = 0
        var changedCells = 0

        for i in 0..<a.count {
            let diff = abs(Int(a[i]) - Int(b[i]))
            totalDiff += diff
            if diff >= 18 {
                changedCells += 1
            }
        }

        let meanDiff = Double(totalDiff) / Double(a.count)
        return meanDiff >= 2.5 || changedCells >= 28
    }

    static func hasPageSettled(_ a: [UInt8], _ b: [UInt8]) -> Bool {
        guard a.count == b.count, !a.isEmpty else { return false }
        var totalDiff = 0
        var changedCells = 0

        for i in 0..<a.count {
            let diff = abs(Int(a[i]) - Int(b[i]))
            totalDiff += diff
            if diff >= 12 {
                changedCells += 1
            }
        }

        let meanDiff = Double(totalDiff) / Double(a.count)
        return meanDiff < 1.0 && changedCells <= 6
    }
}

struct RecognizedBubbleRegion {
    let normalizedRect: CGRect
    let japaneseText: String
}

enum JapaneseOCR {
    private static let sharedAnalyzer = ImageAnalyzer()

    private struct RecognizedLine {
        let text: String
        // Normalized 0...1 top-left coordinates in the full captured image.
        let rect: CGRect
    }

    static func recognizeRegions(in image: CGImage) async throws -> [RecognizedBubbleRegion] {
        guard ImageAnalyzer.isSupported else {
            return []
        }

        var configuration = ImageAnalyzer.Configuration([.text])
        configuration.locales = ["ja-JP"]

        let imageW = CGFloat(image.width)
        let imageH = CGFloat(image.height)
        let panelStrips = detectHorizontalPanelRects(in: image)
        print("Analyzing \(panelStrips.count) horizontal strip(s) (\(image.width)×\(image.height))")

        var allLines: [RecognizedLine] = []

        for stripRect in panelStrips {
            try Task.checkCancellation()
            guard let croppedImage = image.cropping(to: stripRect) else {
                continue
            }

            let analysis = try await sharedAnalyzer.analyze(
                croppedImage,
                orientation: .up,
                configuration: configuration
            )

            let stripLines = extractRecognizedLines(
                from: analysis,
                in: stripRect,
                imageWidth: imageW,
                imageHeight: imageH
            )
            allLines.append(contentsOf: stripLines)
        }

        if allLines.isEmpty && panelStrips.count > 1 {
            try Task.checkCancellation()
            let fullRect = CGRect(x: 0, y: 0, width: imageW, height: imageH)
            let fullAnalysis = try await sharedAnalyzer.analyze(
                image,
                orientation: .up,
                configuration: configuration
            )
            allLines = extractRecognizedLines(
                from: fullAnalysis,
                in: fullRect,
                imageWidth: imageW,
                imageHeight: imageH
            )
        }

        let bubbles = groupLinesIntoSpeechBubbles(allLines)
        print("Grouped \(allLines.count) line(s) into \(bubbles.count) speech bubble(s)")

        for (index, bubble) in bubbles.enumerated() {
            print("Bubble \(index + 1): \(bubble.japaneseText.replacingOccurrences(of: "\n", with: " / "))")
        }

        return bubbles
    }

    private static func extractRecognizedLines(
        from analysis: ImageAnalysis,
        in cropRect: CGRect,
        imageWidth: CGFloat,
        imageHeight: CGFloat
    ) -> [RecognizedLine] {
        var extracted: [RecognizedLine] = []

        for child in Mirror(reflecting: analysis).children {
            guard let vkAnalysis = child.value as? NSObject,
                  vkAnalysis.responds(to: NSSelectorFromString("allLines")),
                  let lines = vkAnalysis.value(forKey: "allLines") as? [NSObject] else {
                continue
            }

            for line in lines {
                guard let rawText = line.value(forKey: "string") as? String else {
                    continue
                }
                let cleaned = cleanTranscript(rawText)
                guard !cleaned.isEmpty,
                      let quad = line.value(forKey: "quad") as? NSObject,
                      let bboxValue = quad.value(forKey: "boundingBox") as? NSValue else {
                    continue
                }

                let localBox = bboxValue.rectValue
                let globalBox = CGRect(
                    x: (cropRect.minX + localBox.minX * cropRect.width) / imageWidth,
                    y: (cropRect.minY + localBox.minY * cropRect.height) / imageHeight,
                    width: (localBox.width * cropRect.width) / imageWidth,
                    height: (localBox.height * cropRect.height) / imageHeight
                )

                extracted.append(RecognizedLine(text: cleaned, rect: globalBox))
            }
        }

        return extracted
    }

    private static func groupLinesIntoSpeechBubbles(
        _ lines: [RecognizedLine]
    ) -> [RecognizedBubbleRegion] {
        guard !lines.isEmpty else { return [] }

        var remaining = lines
        var clusters: [[RecognizedLine]] = []

        func linesBelongToSameBubble(_ a: CGRect, _ b: CGRect) -> Bool {
            let aIsHorizontal = a.width > a.height * 1.3
            let bIsHorizontal = b.width > b.height * 1.3
            if aIsHorizontal != bIsHorizontal {
                return false
            }

            let horizontalGap = max(0, max(a.minX - b.maxX, b.minX - a.maxX))
            let verticalGap = max(0, max(a.minY - b.maxY, b.minY - a.maxY))
            let colWidth = min(0.035, min(a.width, b.width))

            let verticalOverlap = min(a.maxY, b.maxY) - max(a.minY, b.minY)
            if verticalOverlap > 0 && horizontalGap <= max(0.026, colWidth * 1.1) {
                return true
            }

            return horizontalGap <= 0.018 && verticalGap <= 0.022
        }

        while !remaining.isEmpty {
            var cluster = [remaining.removeFirst()]
            var index = 0

            while index < cluster.count {
                let current = cluster[index].rect
                index += 1

                var i = 0
                while i < remaining.count {
                    if linesBelongToSameBubble(current, remaining[i].rect) {
                        cluster.append(remaining.remove(at: i))
                    } else {
                        i += 1
                    }
                }
            }

            clusters.append(cluster)
        }

        var regions: [RecognizedBubbleRegion] = clusters.compactMap { cluster in
            let unionRect = cluster.dropFirst().reduce(cluster[0].rect) {
                $0.union($1.rect)
            }

            // Filter out tiny furigana (ruby) columns alongside main kanji columns.
            let maxColThickness = cluster
                .map { min($0.rect.width, $0.rect.height) }
                .max() ?? 0

            let mainLines: [RecognizedLine]
            if cluster.count >= 2 && maxColThickness > 0 {
                let filtered = cluster.filter { line in
                    let thickness = min(line.rect.width, line.rect.height)
                    if isPureHiragana(line.text) && thickness < maxColThickness * 0.60 {
                        return false
                    }
                    return true
                }
                mainLines = filtered.isEmpty ? cluster : filtered
            } else {
                mainLines = cluster
            }

            let sortedLines = mainLines.sorted { lhs, rhs in
                let a = lhs.rect
                let b = rhs.rect
                let minW = min(a.width, b.width)

                if abs(a.midX - b.midX) > max(0.012, minW * 0.5) {
                    return a.midX > b.midX
                }
                return a.minY < b.minY
            }

            let paddedRect = unionRect
                .insetBy(dx: -0.014, dy: -0.012)
                .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))

            let text = sortedLines.map(\.text).joined(separator: "\n")
            guard !text.isEmpty else { return nil }

            return RecognizedBubbleRegion(
                normalizedRect: paddedRect,
                japaneseText: text
            )
        }

        regions.sort { lhs, rhs in
            let a = lhs.normalizedRect
            let b = rhs.normalizedRect
            let verticalOverlap = min(a.maxY, b.maxY) - max(a.minY, b.minY)
            let minHeight = min(a.height, b.height)

            if verticalOverlap > minHeight * 0.25 {
                return a.midX > b.midX
            }
            return a.midY < b.midY
        }

        return regions
    }

    private static func isPureHiragana(_ text: String) -> Bool {
        var hasHiragana = false
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x3040...0x309F: // Hiragana
                hasHiragana = true
            case 0x0020, 0x3000, 0x30FB, 0x30FC: // Spaces / middle dot / long vowel mark
                continue
            default:
                return false
            }
        }
        return hasHiragana
    }

    private static func detectHorizontalPanelRects(in image: CGImage) -> [CGRect] {
        let width = image.width
        let height = image.height
        let fullRect = CGRect(x: 0, y: 0, width: width, height: height)

        guard width >= 64, height >= 64 else {
            return [fullRect]
        }

        var pixels = [UInt8](repeating: 0, count: width * height)
        let colorSpace = CGColorSpaceCreateDeviceGray()

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return [fullRect]
        }

        context.draw(image, in: fullRect)

        let xStart = Int(Double(width) * 0.10)
        let xEnd = max(xStart + 1, Int(Double(width) * 0.90))
        let sampleWidth = xEnd - xStart
        let gutterThresholdCount = Int(Double(sampleWidth) * 0.985)
        let minGutterHeight = 6
        let minPanelHeight = max(48, Int(Double(height) * 0.06))

        var rawGutterRow = [Bool](repeating: false, count: height)
        for y in 0..<height {
            let rowOffset = y * width
            var brightCount = 0
            for x in xStart..<xEnd {
                if pixels[rowOffset + x] >= 238 {
                    brightCount += 1
                }
            }
            if brightCount >= gutterThresholdCount {
                rawGutterRow[y] = true
            }
        }

        var confirmedGutterRow = [Bool](repeating: false, count: height)
        var gutterRunStart: Int?
        for y in 0..<height {
            if rawGutterRow[y] {
                if gutterRunStart == nil { gutterRunStart = y }
            } else if let start = gutterRunStart {
                if y - start >= minGutterHeight {
                    for gy in start..<y { confirmedGutterRow[gy] = true }
                }
                gutterRunStart = nil
            }
        }
        if let start = gutterRunStart, height - start >= minGutterHeight {
            for gy in start..<height { confirmedGutterRow[gy] = true }
        }

        var rowRects: [CGRect] = []
        var bandStartY: Int?

        for y in 0..<height {
            if !confirmedGutterRow[y] {
                if bandStartY == nil {
                    bandStartY = y
                }
            } else if let startY = bandStartY {
                let bandHeight = y - startY
                if bandHeight >= minPanelHeight {
                    rowRects.append(
                        CGRect(x: 0, y: startY, width: width, height: bandHeight)
                    )
                }
                bandStartY = nil
            }
        }

        if let startY = bandStartY {
            let bandHeight = height - startY
            if bandHeight >= minPanelHeight {
                rowRects.append(
                    CGRect(x: 0, y: startY, width: width, height: bandHeight)
                )
            }
        }

        return rowRects.isEmpty ? [fullRect] : rowRects
    }

    private static func cleanTranscript(_ raw: String) -> String {
        let lines = raw
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { line in
                guard !line.isEmpty else { return false }
                return containsJapaneseCharacters(line)
            }
        return lines.joined(separator: "\n")
    }

    private static func containsJapaneseCharacters(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x3040...0x309F, // Hiragana
                 0x30A0...0x30FF, // Katakana
                 0x4E00...0x9FFF, // CJK Unified Ideographs (Kanji)
                 0x3400...0x4DBF: // CJK Extension A
                return true
            default:
                continue
            }
        }
        return false
    }
}

enum TranslationError: LocalizedError {
    case ollamaUnavailable
    case serverError(Int, String)

    var errorDescription: String? {
        switch self {
        case .ollamaUnavailable:
            return "Couldn't connect to Ollama on 127.0.0.1:11434. Make sure 'ollama serve' is running."
        case .serverError(let code, let body):
            return "Ollama returned HTTP \(code): \(body)"
        }
    }
}

@MainActor
enum LocalTranslator {
    private struct Message: Codable {
        let role: String
        let content: String
    }

    private struct Options: Encodable {
        let temperature: Double
    }

    private struct ChatRequest: Encodable {
        let model: String
        let messages: [Message]
        let stream: Bool
        let keep_alive: String
        let options: Options
    }

    private struct ChatResponse: Decodable {
        let message: Message
    }

    private static var bubbleCache: [String: String] = [:]
    private static let maxCacheEntries = 500

    static func clearCache() {
        bubbleCache.removeAll()
        print("Translation cache cleared")
    }

    static func translateRegions(_ japaneseRegions: [String]) async throws -> [String] {
        guard !japaneseRegions.isEmpty else { return [] }

        var results = Array(repeating: "", count: japaneseRegions.count)
        var uncachedIndices: [Int] = []
        var uncachedTexts: [String] = []

        for (index, japanese) in japaneseRegions.enumerated() {
            if let cached = bubbleCache[japanese] {
                results[index] = cached
            } else {
                uncachedIndices.append(index)
                uncachedTexts.append(japanese)
            }
        }

        if uncachedTexts.isEmpty {
            print("Served all \(japaneseRegions.count) bubble(s) instantly from cache")
            return results
        }

        print("Translating \(uncachedTexts.count) new bubble(s) (\(japaneseRegions.count - uncachedTexts.count) cached)")

        let numberedInput = uncachedTexts.enumerated().map { idx, text in
            "[\(idx + 1)] \(text.replacingOccurrences(of: "\n", with: " "))"
        }.joined(separator: "\n")

        let rawOutput = try await requestTranslation(
            prompt: """
            Translate each numbered Japanese manga speech bubble below into natural, concise English.
            Rules:
            - Keep the exact [1], [2], ... numbering, one per line, matching the input count (\(uncachedTexts.count)).
            - Write 100% in English using the Latin alphabet. NEVER output any Chinese or Japanese characters.
            - Output ONLY the numbered English lines with no extra commentary.

            \(numberedInput)
            """
        )

        let translatedNew = parseNumberedLines(rawOutput, expectedCount: uncachedTexts.count)

        if bubbleCache.count > maxCacheEntries {
            bubbleCache.removeAll(keepingCapacity: true)
        }

        for (offset, originalIndex) in uncachedIndices.enumerated() {
            let cleanEnglish = stripCJKCharacters(from: translatedNew[offset])
            results[originalIndex] = cleanEnglish
            if !cleanEnglish.isEmpty {
                bubbleCache[japaneseRegions[originalIndex]] = cleanEnglish
            }
        }

        return results
    }

    private static func requestTranslation(prompt: String) async throws -> String {
        guard let url = URL(string: "http://127.0.0.1:11434/api/chat") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        let payload = ChatRequest(
            model: "qwen2.5:7b",
            messages: [
                Message(
                    role: "system",
                    content: "You are a professional Japanese-to-English manga translator. You always write exclusively in natural English and never output Chinese or Japanese characters."
                ),
                Message(role: "user", content: prompt)
            ],
            stream: false,
            keep_alive: "30m",
            options: Options(temperature: 0.1)
        )

        request.httpBody = try JSONEncoder().encode(payload)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let urlError as URLError {
            switch urlError.code {
            case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .timedOut:
                throw TranslationError.ollamaUnavailable
            default:
                throw urlError
            }
        }

        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw TranslationError.serverError(httpResponse.statusCode, body)
        }

        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        let translation = decoded.message.content
            .trimmingCharacters(in: .whitespacesAndNewlines)

        print("Translated text:\n\(translation)")
        return translation
    }

    private static func parseNumberedLines(_ raw: String, expectedCount: Int) -> [String] {
        let nonEmptyLines = raw
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var cleanedLines: [String] = []
        for line in nonEmptyLines {
            if let closingBracket = line.firstIndex(of: "]"),
               line.hasPrefix("[") {
                let after = line[line.index(after: closingBracket)...]
                    .trimmingCharacters(in: .whitespaces)
                cleanedLines.append(after)
            } else {
                cleanedLines.append(line)
            }
        }

        if cleanedLines.count == expectedCount {
            return cleanedLines
        }

        if cleanedLines.count > expectedCount {
            return Array(cleanedLines.prefix(expectedCount))
        }
        while cleanedLines.count < expectedCount {
            cleanedLines.append("")
        }
        return cleanedLines
    }

    private static func stripCJKCharacters(from text: String) -> String {
        let filtered = text.unicodeScalars.filter { scalar in
            switch scalar.value {
            case 0x3040...0x30FF, // Hiragana & Katakana
                 0x3400...0x4DBF, // CJK Extension A
                 0x4E00...0x9FFF: // CJK Unified Ideographs
                return false
            default:
                return true
            }
        }
        return String(String.UnicodeScalarView(filtered))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
