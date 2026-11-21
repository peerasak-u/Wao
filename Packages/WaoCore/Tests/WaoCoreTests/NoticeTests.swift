import WaoInference
import XCTest

final class NoticeTests: XCTestCase {
    func testEveryNoticeShipsWithItsLicence() {
        XCTAssertTrue(Notice.openThaiASR.text().contains("OpenMDW License Agreement, version 1.1"))
        XCTAssertTrue(Notice.openThaiASR.text().contains("iApp Technology"))
        XCTAssertTrue(Notice.onnxRuntime.text().contains("Copyright (c) Microsoft Corporation"))
        XCTAssertTrue(Notice.onnxRuntimeThirdParty.text().contains("THIRD PARTY SOFTWARE NOTICES"))
        XCTAssertTrue(Notice.poodPim.text().contains("Copyright (c) 2026 Thirawat Sutalungka"))
    }

    func testLineEndingsAreUnix() {
        XCTAssertFalse(Notice.onnxRuntimeThirdParty.text().contains("\r"))
    }
}
