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
        try skipIfKeychainUnavailable()

        let target = "test-roundtrip"
        try service.storePassword("SecretP@ss", target: target, username: "alice")

        let loaded = try service.loadPassword(target: target)
        XCTAssertEqual(loaded, "SecretP@ss")

        try service.deletePassword(target: target)
        XCTAssertNil(try service.loadPassword(target: target))
    }

    func testStoreOrUpdate() throws {
        try skipIfKeychainUnavailable()

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
        try skipIfKeychainUnavailable()

        let loaded = try service.loadPassword(target: "nonexistent-\(UUID().uuidString)")
        XCTAssertNil(loaded)
    }

    func testDeleteMissingItemDoesNotThrow() throws {
        try skipIfKeychainUnavailable()

        XCTAssertNoThrow(try service.deletePassword(target: "nonexistent-\(UUID().uuidString)"))
    }

    /// GitHub Actions macos-latest runner'inda Keychain entitlements / user
    /// interaction olmadan SecItem* cagrilari hata verir. Job'u kirmamak icin
    /// store/load testlerini atla; target-format unit testleri Keychain'siz kalir.
    private func skipIfKeychainUnavailable() throws {
        let probeTarget = "__ci_probe_\(UUID().uuidString)"
        do {
            try service.storePassword("probe", target: probeTarget, username: "ci")
            try service.deletePassword(target: probeTarget)
        } catch {
            throw XCTSkip("Keychain unavailable (missing entitlement / interaction not allowed)")
        }
    }
}