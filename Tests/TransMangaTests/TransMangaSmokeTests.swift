import XCTest
import CoreGraphics
@testable import TransMangaCore

final class TransMangaSmokeTests: XCTestCase {

    // MARK: - 1. OCR Sanitization & Vertical Artifact Cleanup

    func testContainsJapaneseCharactersRejectsPunctuationNoise() {
        XCTAssertFalse(MangaTextSanitizer.containsJapaneseCharacters("..."))
        XCTAssertFalse(MangaTextSanitizer.containsJapaneseCharacters("---"))
        XCTAssertFalse(MangaTextSanitizer.containsJapaneseCharacters("12345"))
        XCTAssertFalse(MangaTextSanitizer.containsJapaneseCharacters("ENGLISH ONLY"))

        XCTAssertTrue(MangaTextSanitizer.containsJapaneseCharacters("すみません"))
        XCTAssertTrue(MangaTextSanitizer.containsJapaneseCharacters("カタカナ"))
        XCTAssertTrue(MangaTextSanitizer.containsJapaneseCharacters("明日"))
    }

    func testContainsKanjiAndIsPureHiraganaClassification() {
        XCTAssertTrue(MangaTextSanitizer.containsKanji("明日"))
        XCTAssertTrue(MangaTextSanitizer.containsKanji("行くぞ"))
        XCTAssertFalse(MangaTextSanitizer.containsKanji("あした"))
        XCTAssertFalse(MangaTextSanitizer.containsKanji("カタカナ"))

        XCTAssertTrue(MangaTextSanitizer.isPureHiragana("あした"))
        XCTAssertTrue(MangaTextSanitizer.isPureHiragana("うんめい"))
        XCTAssertFalse(MangaTextSanitizer.isPureHiragana("明日"))
        XCTAssertFalse(MangaTextSanitizer.isPureHiragana("カタカナ"))
    }

    func testKanaLongVowelArtifactCleanup() {
        // Kanji "一" (U+4E00) adjacent to kana in vertical OCR should normalize to "ー" (U+30FC)
        XCTAssertEqual(
            MangaTextSanitizer.cleanVerticalOCRArtifacts("なんでもな一い"),
            "なんでもなーい"
        )
        XCTAssertEqual(
            MangaTextSanitizer.cleanVerticalOCRArtifacts("ス一パ一"),
            "スーパー"
        )

        // Genuine Kanji compounds where "一" is only adjacent to Kanji must remain untouched
        XCTAssertEqual(
            MangaTextSanitizer.cleanVerticalOCRArtifacts("一人"),
            "一人"
        )
        XCTAssertEqual(
            MangaTextSanitizer.cleanVerticalOCRArtifacts("一番"),
            "一番"
        )
    }

    // MARK: - 2. Panel Gutter Detection

    func testPanelBandDetectorFindsHorizontalGutters() throws {
        let width = 240
        let height = 360
        var pixels = [UInt8](repeating: 255, count: width * height)

        // Fill two distinct manga panel regions with mid-tone gray (128), leaving white gutters (255)
        for y in 20..<160 {
            for x in 0..<width {
                pixels[y * width + x] = 128
            }
        }
        for y in 200..<340 {
            for x in 0..<width {
                pixels[y * width + x] = 128
            }
        }

        let colorSpace = CGColorSpaceCreateDeviceGray()
        let cgImage: CGImage = try pixels.withUnsafeMutableBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress,
                  let context = CGContext(
                      data: baseAddress,
                      width: width,
                      height: height,
                      bitsPerComponent: 8,
                      bytesPerRow: width,
                      space: colorSpace,
                      bitmapInfo: CGImageAlphaInfo.none.rawValue
                  ),
                  let image = context.makeImage() else {
                throw NSError(domain: "TransMangaTests", code: 1)
            }
            return image
        }

        let bands = PanelBandDetector.detectHorizontalPanelRects(in: cgImage)
        XCTAssertEqual(bands.count, 2)
        XCTAssertLessThan(bands[0].midY, bands[1].midY)
    }

    // MARK: - 3. Prompt Construction

    func testBuildNumberedUserPromptFormatsIndexedLines() {
        let builder = MangaPromptBuilder()
        let prompt = builder.buildNumberedUserPrompt(for: [
            "おはようございます",
            "どこ行くの？"
        ])
        XCTAssertEqual(prompt, "[1] おはようございます\n[2] どこ行くの？")
    }

    func testBuildBreakdownSystemPromptIsNonEmpty() {
        let builder = MangaPromptBuilder()
        let breakdownPrompt = builder.buildBreakdownSystemPrompt()
        XCTAssertFalse(breakdownPrompt.isEmpty)
        XCTAssertTrue(breakdownPrompt.localizedCaseInsensitiveContains("romaji"))
    }

    // MARK: - 4. Response Parsing & CJK Stripping

    func testParseNumberedLinesExtractsIndexedTranslationsInOrder() {
        let parser = TranslationResponseParser()
        let rawReply = """
        [1] Good morning!
        [2] Where are you going?
        """
        let parsed = parser.parseNumberedLines(rawReply, expectedCount: 2)
        XCTAssertEqual(parsed, ["Good morning!", "Where are you going?"])
    }

    func testParseNumberedLinesHandlesOutOfOrderIndices() {
        let parser = TranslationResponseParser()
        let rawReply = """
        [2] That makes sense.
        [1] Wait a second!
        """
        let parsed = parser.parseNumberedLines(rawReply, expectedCount: 2)
        XCTAssertEqual(parsed, ["Wait a second!", "That makes sense."])
    }

    func testCJKCharacterStripping() {
        let parser = TranslationResponseParser()
        let result = parser.stripCJKCharacters(from: "See you tomorrow! 明日ね カタカナ")
        XCTAssertEqual(result, "See you tomorrow!")
    }

    // MARK: - 5. Domain Models & Typed Errors

    func testTranslationErrorProvidesActionableLocalizedDescriptions() {
        let errors: [TranslationError] = [
            .invalidEndpointURL,
            .serverUnreachable,
            .modelNotInstalled("qwen2.5:7b"),
            .requestTimedOut("qwen2.5:14b"),
            .httpStatus(503),
            .emptyOrInvalidResponse
        ]

        for error in errors {
            let message = error.errorDescription ?? ""
            XCTAssertFalse(message.isEmpty, "Expected non-empty description for \(error)")
        }

        XCTAssertTrue(TranslationError.modelNotInstalled("qwen2.5:7b").errorDescription?.contains("qwen2.5:7b") == true)
        XCTAssertTrue(TranslationError.requestTimedOut("qwen2.5:14b").errorDescription?.contains("qwen2.5:14b") == true)
        XCTAssertTrue(TranslationError.httpStatus(503).errorDescription?.contains("503") == true)
    }

    func testGlossaryEntryCodableRoundTrip() throws {
        let original = [
            GlossaryEntry(japanese: "ルフィ", english: "Luffy"),
            GlossaryEntry(japanese: "仲間", english: "crewmate")
        ]
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode([GlossaryEntry].self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testAppTabOrderingAndIcons() {
        XCTAssertEqual(AppTab.allCases, [.home, .log, .glossary])
        XCTAssertEqual(AppTab.home.iconName, "house.fill")
        XCTAssertEqual(AppTab.log.iconName, "text.bubble.fill")
        XCTAssertEqual(AppTab.glossary.iconName, "character.book.closed.fill")
    }
}
