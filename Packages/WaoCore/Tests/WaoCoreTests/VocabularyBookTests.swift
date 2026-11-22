import WaoCore
import WaoInference
import XCTest

final class VocabularyBookTests: XCTestCase {
    func testSeedsOneGroupPerHeadingAndSkipsTheGuidance() {
        let book = VocabularyBook(seedList: """
            # From somewhere, MIT licence.
            # - works best at about 150-350 words
            #
            # One per line.
            # Companies
            Google
            Nvidia

            # Terms
            GPU
            """)
        XCTAssertEqual(book.groups.map(\.name), ["Companies", "Terms"])
        XCTAssertEqual(book.groups.map(\.words), [["Google", "Nvidia"], ["GPU"]])
        XCTAssertTrue(book.groups.allSatisfy(\.isEnabled))
    }

    func testSeedsTheBundledListIntoItsSections() {
        let book = VocabularyBook.bundled
        XCTAssertEqual(book.groups.map(\.name), ["Companies", "Products and platforms", "Terms"])
        XCTAssertFalse(book.groups.contains { $0.name.contains("PoodPim") || $0.name.contains("licence") })
        XCTAssertEqual(book.effectiveWords, Hotwords.bundled.words.reduce(into: [String]()) { out, w in
            if !out.contains(where: { $0.lowercased() == w.lowercased() }) { out.append(w) }
        })
    }

    func testEffectiveWordsAreEnabledGroupsDeduplicatedFirstSpellingWins() {
        var book = VocabularyBook(groups: [
            VocabularyGroup(name: "a", words: ["OpenAI", "GPU"]),
            VocabularyGroup(name: "b", isEnabled: false, words: ["Vercel"]),
            VocabularyGroup(name: "c", words: ["gpu", "Stripe"]),
        ])
        XCTAssertEqual(book.effectiveWords, ["OpenAI", "GPU", "Stripe"])
        book.groups[0].isEnabled = false
        XCTAssertEqual(book.effectiveWords, ["gpu", "Stripe"])
        XCTAssertEqual(book.hotwords.words, ["gpu", "Stripe"])
    }

    func testImportSplitsOnCommasAndNewLinesKeepingCase() {
        let book = VocabularyBook(groups: [VocabularyGroup(name: "a", isEnabled: false, words: ["Stripe"])])
        let preview = book.previewImport(" Supabase,vercel， Next.js\n# a note, not words\n\nstripe, , Supabase\r\nReact Native ")
        XCTAssertEqual(preview.added, ["Supabase", "vercel", "Next.js", "React Native"])
        XCTAssertEqual(preview.duplicates, ["stripe", "Supabase"], "in a disabled group, or earlier in the same text")
    }

    func testImportAddsOnlyNewWordsToTheChosenGroup() {
        var book = VocabularyBook(groups: [VocabularyGroup(name: "a", words: ["GPU"]), VocabularyGroup(name: "b")])
        XCTAssertEqual(book.importWords("gpu, Vercel, Stripe", into: book.groups[1].id), 2)
        XCTAssertEqual(book.groups.map(\.words), [["GPU"], ["Vercel", "Stripe"]])
        XCTAssertEqual(book.importWords("Vercel", into: UUID()), 0)
    }

    func testRoundTripsThroughJSON() throws {
        let book = VocabularyBook.bundled
        XCTAssertEqual(try JSONDecoder().decode(VocabularyBook.self, from: JSONEncoder().encode(book)), book)
    }

    /// The clip is "วันนี้ต้องแก้ Redis ก่อนส่งงานนะครับ", Thai and English system voices spliced; with Redis on, the
    /// beam takes a different path. One transcriber throughout: edits must not need the model reloaded.
    func testEditsReachTheLiveTranscriber() throws {
        let transcriber = try Transcriber(modelDirectory: try Paths.modelDirectory())
        let audio = try AudioFile.load16kMono(Paths.fixtures.appendingPathComponent("hotword-redis.wav"))
        func decode(_ book: VocabularyBook) throws -> Transcription {
            let hotwords = book.hotwords
            transcriber.use(hotwords: hotwords, cleanup: TextCleanup(hotwords: hotwords, corrections: .bundled))
            return try transcriber.transcribe(audio, language: .thaiEnglishMix)
        }
        var book = VocabularyBook(groups: [VocabularyGroup(name: "Cloud", words: ["Kubernetes"])])
        let before = try decode(book)
        let databases = VocabularyGroup(name: "ฐานข้อมูล")
        book.groups.append(databases)
        book.importWords("Redis", into: databases.id)
        let enabled = try decode(book)
        XCTAssertEqual(transcriber.hotwords.words, ["Kubernetes", "Redis"])
        book.groups[1].isEnabled = false
        let disabled = try decode(book)
        XCTAssertEqual(transcriber.hotwords.words, ["Kubernetes"])
        print("before: \(before.text)\nenabled: \(enabled.text)\ndisabled: \(disabled.text)")

        XCTAssertNotEqual(enabled.tokens, before.tokens, enabled.text)
        XCTAssertEqual(disabled.tokens, before.tokens, disabled.text)
    }
}
