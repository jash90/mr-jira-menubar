import XCTest
@testable import MenuBarCore

final class SecretCryptoTests: XCTestCase {
    func testSealOpenRoundTrip() throws {
        let plain = Data("hello-token".utf8)
        let sealed = try SecretCrypto.seal(plain)
        XCTAssertNotEqual(sealed, plain)
        XCTAssertEqual(try SecretCrypto.open(sealed), plain)
    }

    func testSealIsNonDeterministic() throws {
        let plain = Data("same-input".utf8)
        XCTAssertNotEqual(try SecretCrypto.seal(plain), try SecretCrypto.seal(plain))
    }

    func testOpenRejectsTamperedData() {
        XCTAssertThrowsError(try SecretCrypto.open(Data("not-a-valid-box".utf8)))
    }
}
