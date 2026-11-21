@testable import WaoCore
import XCTest

final class TextCleanupTests: XCTestCase {
    func testHotwordMatchesAnySplitAndTakesBackBrokenMatches() {
        let h = Hotwords(list: "Nvidia\nGPU")
        let (s1, d1) = h.advance(.init(), piece: "\u{2581}N", bonus: 2)
        let (s2, d2) = h.advance(s1, piece: "vid", bonus: 2)
        let (s3, d3) = h.advance(s2, piece: "ia", bonus: 2)
        XCTAssertEqual([d1, d2, d3], [2, 2, 2])
        XCTAssertEqual(s3.pending, 0, "a finished hotword keeps its bonus")
        let (g, _) = h.advance(.init(), piece: "G", bonus: 2)
        XCTAssertEqual(g.pending, 2)
        let (broken, d) = h.advance(g, piece: "อา", bonus: 2)
        XCTAssertEqual(d, -2, "a broken match gives the bonus back")
        XCTAssertEqual(broken.pending, 0)
    }

    func testBrokenMatchCanStartAnotherHotword() {
        let h = Hotwords(list: "GPU\nNvidia")
        let (g, _) = h.advance(.init(), piece: "G", bonus: 2)
        let (n, d) = h.advance(g, piece: "N", bonus: 2)
        XCTAssertEqual(d, 0, "loses G's 2, earns N's 2")
        XCTAssertEqual(n.pending, 2)
    }

    func testEmptyListAndSpacePiecesScoreNothing() {
        XCTAssertEqual(Hotwords(list: "# only a comment\n\n").advance(.init(), piece: "GPU", bonus: 2).1, 0)
        let h = Hotwords(list: "GPU")
        let (g, _) = h.advance(.init(), piece: "G", bonus: 2)
        XCTAssertEqual(h.advance(g, piece: "\u{2581}", bonus: 2).0, g)
    }

    func testWritesHotwordsAndAcronymsTheUsualWay() {
        let h = Hotwords(list: "Nvidia\nOpenAI")
        XCTAssertEqual(h.canonicalCase("ซื้อ nvidia กับ openai ไม่ใช่ nvidiax"), "ซื้อ Nvidia กับ OpenAI ไม่ใช่ nvidiax")
        XCTAssertEqual(Acronyms.toLatin("ใช้จีพียูกับซีพียู ดีมาก"), "ใช้ GPU กับ CPU ดีมาก")
        let m = Hotwords(list: "MVP\nNvidia")
        XCTAssertEqual(m.fixDoubledLetters("ของ MVPP กับ GPUU และ CCPU แต่ COOL กับ SSS ไม่แตะ"),
                       "ของ MVP กับ GPU และ CPU แต่ COOL กับ SSS ไม่แตะ")
    }

    func testSpacesThaiAndLatinApart() {
        XCTAssertEqual(TextCleanup.spaceThaiLatin("ต้องhotfixด่วน ที่postคิว L"), "ต้อง hotfix ด่วน ที่ post คิว L")
        XCTAssertEqual(TextCleanup.spaceThaiLatin("ข้อ3 กับ v2 ใน API ปี2026"), "ข้อ 3 กับ v2 ใน API ปี 2026")
        XCTAssertEqual(TextCleanup.spaceThaiLatin("ได้50%แล้ว ม.6"), "ได้ 50% แล้ว ม.6")
        XCTAssertEqual(TextCleanup.spaceThaiLatin("ใช้ GPU กับ CPU"), "ใช้ GPU กับ CPU", "already spaced")
    }

    func testCorrectionsReplaceLongestFirstWithSpaces() {
        let c = Corrections(list: "# comment\nอินฟา, อินฟรา = infra\nอินฟราสตรัคเจอร์ = infrastructure\ndepop = DevOps\n")
        XCTAssertEqual(c.apply("ทีมอินฟาดูแลอินฟราสตรัคเจอร์"), "ทีม infra ดูแล infrastructure")
        XCTAssertEqual(c.apply("ทีม depop กับ Depop"), "ทีม DevOps กับ DevOps")
        XCTAssertEqual(c.apply("depopulate"), "depopulate", "whole words only for Latin")
    }

    func testThaiMatchesInsideClustersTheModelSplits() {
        XCTAssertEqual(TextCleanup.saraAm("ท\u{0E4D}\u{0E32}งาน"), "ทำงาน")
        XCTAssertTrue(Acronyms.toLatin("จีพียู่").hasPrefix("GPU"), "matches by code point, not by grapheme")
    }

    func testStandardCleanupRunsEveryStage() {
        let text = TextCleanup.standard("ใช้จีพียูกับ nvidia ท\u{0E4D}\u{0E32}งานบนอินฟา")
        XCTAssertEqual(text, "ใช้ GPU กับ Nvidia ทำงานบน infra")
    }

    func testBundledListsLoad() {
        XCTAssertGreaterThan(Hotwords.bundled.words.count, 100)
        XCTAssertFalse(Hotwords.bundled.words.contains { $0 == "LINE" || $0 == "Grab" }, "ambiguous with Thai words")
        XCTAssertGreaterThan(Corrections.bundled.pairs.count, 50)
        XCTAssertTrue(BundledLists.vocabulary.hasPrefix("# From PoodPim"))
    }
}
