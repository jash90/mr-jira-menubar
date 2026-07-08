import XCTest
@testable import MenuBarCore

final class SemVerTests: XCTestCase {
    func testStripsLeadingV() {
        XCTAssertTrue(SemVer.isNewer("v1.3.0", than: "1.2.0"))
        XCTAssertTrue(SemVer.isNewer("1.3.0", than: "v1.2.0"))
    }

    func testEqualIsNotNewer() {
        XCTAssertFalse(SemVer.isNewer("1.2.0", than: "1.2.0"))
        XCTAssertFalse(SemVer.isNewer("v1.2.0", than: "1.2.0"))
    }

    func testOlderIsNotNewer() {
        XCTAssertFalse(SemVer.isNewer("1.1.9", than: "1.2.0"))
        XCTAssertFalse(SemVer.isNewer("0.9.0", than: "1.0.0"))
    }

    func testMajorMinorPatchOrdering() {
        XCTAssertTrue(SemVer.isNewer("2.0.0", than: "1.9.9"))
        XCTAssertTrue(SemVer.isNewer("1.3.0", than: "1.2.9"))
        XCTAssertTrue(SemVer.isNewer("1.2.1", than: "1.2.0"))
    }

    func testDifferentComponentCounts() {
        XCTAssertTrue(SemVer.isNewer("1.2", than: "1.1.9"))
        XCTAssertFalse(SemVer.isNewer("1.2", than: "1.2.0"))
        XCTAssertTrue(SemVer.isNewer("1.2.0.1", than: "1.2.0"))
    }
}
