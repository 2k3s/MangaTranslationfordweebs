import XCTest
@testable import TransMangaCore

final class TransMangaSmokeTests: XCTestCase {
    func testKanaLongVowelArtifactCleanup() {
        let raw = "なんでもな一い"
        let cleaned = MangaTextSanitizer.cleanVerticalOCRArtifacts(raw)
        XCTAssertEqual(cleaned, "なんでもなーい")
    }

    func testCJKCharacterStripping() {
        let parser = TranslationResponseParser()
        let result = parser.stripCJKCharacters(from: "See you tomorrow! 明日")
        XCTAssertEqual(result, "See you tomorrow!")
    }
}
