import Foundation
@testable import WaoCore
import XCTest

final class EmojiTests: XCTestCase {
    func testTheCatalogHasEveryCategoryInTheOrderOfTheIOSKeyboard() throws {
        let catalog = try XCTUnwrap(EmojiCatalog.bundled)
        XCTAssertEqual(catalog.sections.map(\.category), EmojiCategory.allCases)
        XCTAssertEqual(catalog.sections.map(\.emoji.count).reduce(0, +), 1870)
        XCTAssertEqual(catalog.sections[0].emoji.first?.glyph, "😀")
        XCTAssertEqual(catalog.sections.last?.emoji.last?.name, "flag: Wales")
    }

    func testToneVariantsLeadBackToTheirEmoji() throws {
        let catalog = try XCTUnwrap(EmojiCatalog.bundled)
        let wave = try XCTUnwrap(catalog.lookup("👋"))
        XCTAssertNil(wave.tone)
        XCTAssertEqual(wave.emoji.tones, ["👋🏻", "👋🏼", "👋🏽", "👋🏾", "👋🏿"])
        let dark = try XCTUnwrap(catalog.lookup("👋🏿"))
        XCTAssertEqual(dark.emoji, wave.emoji)
        XCTAssertEqual(dark.tone, 4)
        XCTAssertEqual(dark.emoji.name(tone: dark.tone), "waving hand: dark skin tone")
        XCTAssertEqual(catalog.lookup("🧑🏽‍🤝‍🧑🏽")?.emoji.glyph, "🧑‍🤝‍🧑")
        XCTAssertNil(catalog.lookup("🧑🏻‍🤝‍🧑🏿"), "mixed tones are left out")
        XCTAssertEqual(catalog.lookup("❤️")?.emoji.tones, [])
    }

    func testEmojiCarryTheirThaiNameThenKeywords() throws {
        let catalog = try XCTUnwrap(EmojiCatalog.bundled)
        let cat = try XCTUnwrap(catalog.lookup("🐱")?.emoji)
        XCTAssertEqual(cat.keywords.first, "หน้าแมว")
        XCTAssertTrue(cat.keywords.contains("แมว"))
        XCTAssertEqual(catalog.lookup("👋🏽")?.emoji.keywords.first, "โบกมือ")
    }

    func testAnEmojiWithoutThaiKeywordsStillParses() throws {
        let text = EmojiCategory.allCases.map(\.rawValue).joined(separator: "\n")
            .replacingOccurrences(of: "smileys", with: "smileys\n😀\tgrinning face\t\n👋\twaving hand\tโบกมือ\t👋🏻\t👋🏼\t👋🏽\t👋🏾\t👋🏿")
        let catalog = try XCTUnwrap(EmojiCatalog(text))
        XCTAssertEqual(catalog.lookup("😀")?.emoji.keywords, [])
        XCTAssertEqual(catalog.lookup("👋🏿")?.tone, 4)
        XCTAssertNil(EmojiCatalog("smileys\n😀\tgrinning face"), "the keyword field is required")
    }

    func testEveryGlyphIsOneCharacter() throws {
        let catalog = try XCTUnwrap(EmojiCatalog.bundled)
        for emoji in catalog.sections.flatMap(\.emoji) {
            for glyph in [emoji.glyph] + emoji.tones {
                XCTAssertEqual(glyph.count, 1, emoji.name)
            }
        }
    }

    func testSearchFindsEmojiByTheirThaiWords() throws {
        let catalog = try XCTUnwrap(EmojiCatalog.bundled)
        let hearts = catalog.search("หัวใจ").map(\.glyph)
        XCTAssertTrue(hearts.prefix(10).contains("❤️"), "\(hearts.prefix(10))")
        XCTAssertEqual(catalog.search("แมว").first?.glyph, "🐈")
        XCTAssertTrue(catalog.search("แมว").contains { $0.glyph == "🐱" })
        XCTAssertEqual(catalog.search("  แมว \n").map(\.glyph), catalog.search("แมว").map(\.glyph))
        XCTAssertTrue(catalog.search("ไทย").contains { $0.glyph == "🇹🇭" })
    }

    func testSearchRanksNamesBeforeKeywordsAndWholeWordsBeforeParts() throws {
        let catalog = try XCTUnwrap(EmojiCatalog.bundled)
        let results = catalog.search("แมว").map(\.glyph)
        let order = try ["🐈", "😺", "🐱", "🦉"].map { glyph in try XCTUnwrap(results.firstIndex(of: glyph), glyph) }
        XCTAssertEqual(order, order.sorted(), "named แมว, named แมวยิ้ม…, keyword แมว, a keyword holding แมว")
    }

    func testSearchMatchesAConsonantBeforeItsVowelIsTyped() throws {
        let catalog = try XCTUnwrap(EmojiCatalog.bundled)
        XCTAssertFalse(catalog.search("ก").isEmpty)
        XCTAssertTrue(catalog.search("ก").contains { $0.keywords.contains { $0.hasPrefix("กิ") } })
    }

    func testSearchWithNothingToFindReturnsNothing() throws {
        let catalog = try XCTUnwrap(EmojiCatalog.bundled)
        XCTAssertEqual(catalog.search(""), [])
        XCTAssertEqual(catalog.search("   "), [])
        XCTAssertEqual(catalog.search("ฏฏฏฏฏ"), [])
    }

    func testRecentEmojiComeNewestFirstWithoutRepeats() {
        var history = EmojiHistory()
        let smile = Emoji(glyph: "😀", name: "grinning face", tones: [])
        let heart = Emoji(glyph: "❤️", name: "red heart", tones: [])
        history.use(smile, tone: nil)
        history.use(heart, tone: nil)
        history.use(smile, tone: nil)
        XCTAssertEqual(history.recent, ["😀", "❤️"])
        for i in 0..<40 { history.use(Emoji(glyph: "\(i)", name: "", tones: []), tone: nil) }
        XCTAssertEqual(history.recent.count, EmojiHistory.capacity)
        XCTAssertEqual(history.recent.first, "39")
    }

    func testTheGridShowsTheToneLastPicked() throws {
        let wave = try XCTUnwrap(EmojiCatalog.bundled?.lookup("👋")?.emoji)
        var history = EmojiHistory()
        XCTAssertEqual(history.shown(wave), "👋")
        history.use(wave, tone: 2)
        XCTAssertEqual(history.shown(wave), "👋🏽")
        XCTAssertEqual(history.recent, ["👋🏽"])
        history.use(wave, tone: nil)
        XCTAssertEqual(history.shown(wave), "👋")
    }

    func testHistorySurvivesARoundTrip() throws {
        var history = EmojiHistory()
        history.use(Emoji(glyph: "👍", name: "thumbs up", tones: ["👍🏻", "👍🏼", "👍🏽", "👍🏾", "👍🏿"]), tone: 0)
        let data = try JSONEncoder().encode(history)
        XCTAssertEqual(try JSONDecoder().decode(EmojiHistory.self, from: data), history)
    }

    func testParsingTheCatalogTakesMilliseconds() throws {
        let url = Paths.repo.appendingPathComponent("Packages/WaoCore/Sources/WaoCore/Resources/emoji.txt")
        let text = try String(contentsOf: url, encoding: .utf8)
        let start = Date()
        XCTAssertNotNil(EmojiCatalog(text))
        let elapsed = Date().timeIntervalSince(start)
        print("emoji.txt: \(text.utf8.count) bytes parsed in \(Int(elapsed * 1000)) ms")
        XCTAssertLessThan(elapsed, 0.5)
    }
}
