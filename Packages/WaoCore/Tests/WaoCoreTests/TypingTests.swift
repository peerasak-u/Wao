import WaoCore
import XCTest

final class TypingTests: XCTestCase {
    func testKedmaneeCoversTheThaiAlphabet() {
        let typed = Set(Typing().rows.joined().flatMap { [$0.output, $0.shifted] })
        let consonants = (0x0E01...0x0E2E).compactMap { Unicode.Scalar($0).map { String($0) } }
        XCTAssertEqual(consonants.filter { !typed.contains($0) }, [])
        XCTAssertTrue(typed.isSuperset(of: ["ฯ", "฿", "ๆ", "๐", "๙"]))
    }

    func testNoRowIsWiderThanTwelveKeys() {
        var typing = Typing()
        XCTAssertLessThanOrEqual(typing.rows.map(\.count).max() ?? 0, 12)
        typing.togglePage()
        XCTAssertLessThanOrEqual(typing.rows.map(\.count).max() ?? 0, 12)
    }

    func testShiftLastsOneLetter() {
        var typing = Typing()
        let ch = typing.rows[3][2]
        typing.toggleShift()
        XCTAssertEqual(typing.type(ch), "ฉ")
        XCTAssertEqual(typing.type(ch), "แ")
    }

    func testShiftStaysOnTheSymbolsPage() {
        var typing = Typing()
        typing.togglePage()
        typing.toggleShift()
        let key = typing.rows[0][0]
        XCTAssertEqual(typing.type(key), "[")
        XCTAssertEqual(typing.type(key), "[")
        XCTAssertEqual(typing.shiftLabel, "123")
    }

    func testTheNumbersPageReturnsToTheThaiLetters() {
        var typing = Typing()
        XCTAssertEqual(typing.pageLabel, "123")
        typing.togglePage()
        XCTAssertEqual(typing.pageLabel, "กขค")
        XCTAssertEqual(typing.type(typing.rows[0][0]), "1")
        XCTAssertFalse(typing.decodes)
        typing.toggleShift()
        typing.togglePage()
        XCTAssertEqual(typing.page, .letters)
        XCTAssertFalse(typing.shifted)
        XCTAssertEqual(typing.type(typing.rows[0][0]), "ๅ")
    }
}
