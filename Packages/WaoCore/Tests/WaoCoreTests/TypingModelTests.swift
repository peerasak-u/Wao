import Foundation
import WaoTyping
import XCTest

final class TypingModelTests: XCTestCase {
    private var model: TypingModel { get throws { try XCTUnwrap(TypingModel.bundled, "thai-typing.bin missing or corrupt") } }

    func testEverySymbolIsAKedmaneeKeyOrTheSpace() throws {
        let keys = Set(Typing().rows.joined().flatMap { [$0.output, $0.shifted] })
        XCTAssertEqual(Set(try model.symbols.map(String.init)), keys.union([" "]))
    }

    func testMatchesTheBuildersUnquantisedModel() throws {
        struct Golden: Decodable { let context: String; let char: String; let logp: Float }
        let golden = try String(contentsOf: Paths.fixtures.appendingPathComponent("typing-golden.jsonl"), encoding: .utf8)
            .split(separator: "\n").map { try JSONDecoder().decode(Golden.self, from: Data($0.utf8)) }
        let errors = try golden.map { abs(try model.nextCharacter(after: $0.context).logP($0.char) - $0.logp) }.sorted()
        XCTAssertEqual(errors.count, 500)
        XCTAssertLessThan(errors[errors.count / 2], 0.05)
        XCTAssertLessThan(errors.last!, 0.2)
    }

    func testEachContextIsADistribution() throws {
        let model = try model
        for context in ["", "สวัส", "ฉันจะไปกินข้า", "555 ", "ครับ ", "เ"] {
            let next = model.nextCharacter(after: context)
            let total = model.symbols.reduce(Float(0)) { $0 + exp(next.logP(String($1))) }
            XCTAssertEqual(total, 1, accuracy: 0.05, context)
        }
    }

    func testAnythingOffTheKeysReadsAsASpace() throws {
        let model = try model
        for (context, same) in [("ok ไป", " ไป"), ("ไป🙂", "ไป "), ("hello\nสวั", "สวั"), ("ไป  \t ", "ไป ")] {
            XCTAssertEqual(model.nextCharacter(after: context).logP("ส"), model.nextCharacter(after: same).logP("ส"), context)
        }
        XCTAssertEqual(model.nextCharacter(after: "x").logP("x"), -.infinity)
    }

    func testFitsTheKeyboardsMemoryBudget() throws {
        let url = Paths.repo.appendingPathComponent("Packages/WaoCore/Sources/WaoTyping/Resources/thai-typing.bin")
        let size = try XCTUnwrap(try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int)
        XCTAssertLessThanOrEqual(size, 8_000_000)
        XCTAssertTrue(try model.buildInfo.contains("sentence-collector.txt"))
    }

    func testCompletesTheWordBeingTyped() throws {
        let model = try model
        let hello = model.completions(after: "สวัส").map { [$0.word, $0.remainder] }
        XCTAssertTrue(hello.contains(["สวัสดี", "ดี"]), "\(hello)")
        let rice = model.completions(after: "ฉันจะไปกินข้า")
        XCTAssertTrue(rice.contains { $0.word.hasPrefix("ข้าว") && $0.remainder.hasPrefix("ว") }, "\(rice)")
        XCTAssertLessThanOrEqual(rice.count, 3)
    }

    func testCompletesTheWordStartedAfterTheLastWholeWord() throws {
        let model = try model
        XCTAssertEqual(model.completions(after: "ไม่ร").first?.word, "รู้")
        XCTAssertEqual(model.completions(after: "ฉันไม่ร").first?.remainder, "ู้")
        XCTAssertEqual(Set(model.completions(after: "ไม่ค").prefix(2).map(\.remainder)), ["วร", "่อย"])
        XCTAssertTrue(model.completions(after: "กินข").contains { $0.remainder == "้าว" })
    }

    func testAWordThatStartsWithAShorterOneIsStillCompletedWhole() throws {
        let model = try model
        XCTAssertEqual(model.completions(after: "ขอบ").first?.word, "ขอบคุณ")
        XCTAssertEqual(model.completions(after: "โทร").first?.word, "โทรศัพท์")
        XCTAssertEqual(model.completions(after: "ประเ").first?.word, "ประเทศ")
        XCTAssertEqual(model.completions(after: "ขอบค").first?.word, "ขอบคุณ", "shows the whole word, not คุณ")
    }

    func testAFinishedWordIsNotSplicedOntoItsLastLetters() throws {
        let model = try model
        XCTAssertEqual(model.completions(after: "ขอบคุณ"), [])
        XCTAssertEqual(model.completions(after: "สวัสดี"), [])
        XCTAssertTrue(model.completions(after: "ข้าว").allSatisfy { $0.word.hasPrefix("ข้าว") })
        XCTAssertTrue(model.completions(after: "ต้องก").contains { $0.word.hasPrefix("ก") }, "a word begun at ก")
    }

    func testAWordBegunAtTheStartIsStillCompletedWhole() throws {
        let model = try model
        XCTAssertTrue(try XCTUnwrap(model.completions(after: "ไม").first).word.hasPrefix("ไม่"))
        XCTAssertTrue(try XCTUnwrap(model.completions(after: "วันนี้ไม").first).remainder.hasPrefix("่"))
    }

    func testAWordThatSavesNoTapRanksLast() throws {
        let offered = try model.completions(after: "ไม")
        XCTAssertFalse(offered.dropLast().contains { $0.remainder.unicodeScalars.count == 1 }, "\(offered)")
    }

    func testOffersNothingOutsideAThaiWord() throws {
        let model = try model
        XCTAssertEqual(model.completions(after: ""), [])
        XCTAssertEqual(model.completions(after: "ไปกิน "), [])
        XCTAssertEqual(model.completions(after: "hello"), [])
        XCTAssertFalse(model.completions(after: "ข้าว").contains { $0.remainder.isEmpty })
    }
}
