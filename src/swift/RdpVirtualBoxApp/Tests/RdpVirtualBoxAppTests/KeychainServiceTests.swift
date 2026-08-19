import XCTest
@testable import RdpVirtualBoxAppCore

final class KeychainServiceTests: XCTestCase {
    private var service: KeychainService!
    private let testService = "RdpVirtualBoxAppTest"

    override func setUp() {
        super.setUp()
        service = KeychainService(service: testService)
        // Test keychain'ini temizle
        for target in (try? service.listTargets()) ?? [] {
            try? service.deletePassword(target: target)
        }
    }

    override func tearDown() {
        for target in (try? service.listTargets()) ?? [] {
            try? service.deletePassword(target: target)
        }
        super.tearDown()
    }

    func testStoreLoadDeleteRoundTrip() throws {
        let target = "test-roundtrip"
        try service.storePassword("SecretP@ss", target: target, username: "alice")

        let loaded = try service.loadPassword(target: target)
        XCTAssertEqual(loaded, "SecretP@ss")

        try service.deletePassword(target: target)
        XCTAssertNil(try service.loadPassword(target: target))
    }

    func testStoreOrUpdate() throws {
        try service.storeOrUpdate("p1", server: "10.0.0.1", appId: "erp", username: "u")
        try service.storeOrUpdate("p2", server: "10.0.0.1", appId: "erp", username: "u")

        let loaded = try service.load(server: "10.0.0.1", appId: "erp")
        XCTAssertEqual(loaded, "p2", "storeOrUpdate must replace existing entry")
    }

    func testTargetFormatMatchesPowerShellConvention() {
        let target = KeychainTarget.make(server: "192.168.0.106", appId: "erp")
        XCTAssertEqual(target, "RdpVirtualBoxApp:192.168.0.106:erp")

        let parsed = KeychainTarget.parse(target)
        XCTAssertEqual(parsed?.server, "192.168.0.106")
        XCTAssertEqual(parsed?.appId, "erp")
    }

    func testLoadReturnsNilForMissingItem() throws {
        let loaded = try service.loadPassword(target: "nonexistent-\(UUID().uuidString)")
        XCTAssertNil(loaded)
    }

    func testDeleteMissingItemDoesNotThrow() throws {
        XCTAssertNoThrow(try service.deletePassword(target: "nonexistent-\(UUID().uuidString)"))
    }
}