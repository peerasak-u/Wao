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

    func testEveryGlyphIsOneCharacter() throws {
        let catalog = try XCTUnwrap(EmojiCatalog.bundled)
        for emoji in catalog.sections.flatMap(\.emoji) {
            for glyph in [emoji.glyph] + emoji.tones {
                XCTAssertEqual(glyph.count, 1, emoji.name)
            }
        }
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
