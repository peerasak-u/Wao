import WaoCore
import XCTest

final class KeyboardLayoutTests: XCTestCase {
    func testKedmaneeCoversTheThaiAlphabet() {
        let typed = Set(KeyboardLayout.thai.rows.joined().flatMap { [$0.output, $0.shifted] })
        let consonants = (0x0E01...0x0E2E).compactMap { Unicode.Scalar($0).map { String($0) } }
        XCTAssertEqual(consonants.filter { !typed.contains($0) }, [])
    }

    func testCombiningMarksShowADottedCircle() {
        let key = KeyboardLayout.thai.rows[0][5]
        XCTAssertEqual(key.output, "ุ")
        XCTAssertEqual(key.label(shifted: false), "◌ุ")
        XCTAssertEqual(KeyboardLayout.thai.rows[0][3].label(shifted: false), "ภ")
    }

    func testLayoutPicksTheDictationLanguage() {
        XCTAssertEqual(KeyboardLayout.thai.language, .thai)
        XCTAssertEqual(KeyboardLayout.english.language, .thaiEnglishMix)
    }
}
