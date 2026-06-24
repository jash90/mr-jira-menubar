import XCTest
@testable import MenuBarCore

final class SecretStoreTests: XCTestCase {
    func testInMemoryRoundTrips() throws {
        let store = InMemorySecretStore()
        XCTAssertNil(store.string(forKey: "k"))
        try store.set("secret", forKey: "k")
        XCTAssertEqual(store.string(forKey: "k"), "secret")
    }

    func testInMemorySetNilRemoves() throws {
        let store = InMemorySecretStore(["k": "v"])
        try store.set(nil, forKey: "k")
        XCTAssertNil(store.string(forKey: "k"))
    }

    func testInMemoryStoresEmptyStringDistinctFromNil() throws {
        let store = InMemorySecretStore()
        try store.set("", forKey: "k")
        XCTAssertEqual(store.string(forKey: "k"), "")
        try store.set(nil, forKey: "k")
        XCTAssertNil(store.string(forKey: "k"))
    }
}
