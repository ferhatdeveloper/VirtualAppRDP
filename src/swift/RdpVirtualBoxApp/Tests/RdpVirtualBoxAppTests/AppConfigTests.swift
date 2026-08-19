import XCTest
@testable import RdpVirtualBoxAppCore

final class AppConfigTests: XCTestCase {
    func testValidIPv4Address() {
        let s = ServerInfo(ip: "192.168.0.106", port: 3389, username: "FIRMA\\u", password: "p")
        XCTAssertTrue(s.validate().isEmpty)
    }

    func testValidHostname() {
        let s = ServerInfo(ip: "rdp.firma.local", port: 3389, username: "u@firma.local", password: "p")
        XCTAssertTrue(s.validate().isEmpty)
    }

    func testInvalidIP() {
        let s = ServerInfo(ip: "999.999.999.999", port: 3389, username: "u", password: "p")
        XCTAssertTrue(s.validate().contains(.invalidHost))
    }

    func testInvalidPort() {
        let s = ServerInfo(ip: "192.168.0.1", port: 70000, username: "u", password: "p")
        XCTAssertTrue(s.validate().contains(.invalidPort))
    }

    func testInvalidUsername() {
        let s = ServerInfo(ip: "192.168.0.1", port: 3389, username: "no-domain-no-upn", password: "p")
        XCTAssertTrue(s.validate().contains(.invalidUsername))
    }

    func testEmptyPassword() {
        let s = ServerInfo(ip: "192.168.0.1", port: 3389, username: "FIRMA\\u", password: "")
        XCTAssertTrue(s.validate().contains(.missingPassword))
    }

    func testProbeResultDecodingFromJSON() throws {
        let json = """
        {
          "server": "192.168.0.106",
          "components": {
            "RDS_Role": { "status": "ok", "value": "Installed", "details": [] },
            "RDP_Port": { "status": "ok", "value": "3389 open", "details": [] }
          },
          "webEndpoint": {
            "rdWebAvailable": true,
            "guacamoleAvailable": false,
            "rdWebUrl": "https://192.168.0.106/RDWeb/webclient",
            "guacamoleUrl": null
          },
          "existingRemoteApps": [
            { "id": "erp", "name": "ERP", "alias": "erp" },
            { "id": "rapor", "name": "Rapor", "alias": "rapor" }
          ],
          "recommendations": ["HTML5 erisim aktif."],
          "generatedAt": "2026-08-20T00:00:00Z"
        }
        """.data(using: .utf8)!

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let probe = try dec.decode(ProbeResult.self, from: json)

        XCTAssertEqual(probe.server, "192.168.0.106")
        XCTAssertEqual(probe.components["RDS_Role"]?.status, .ok)
        XCTAssertTrue(probe.isComponentOK("RDS_Role"))
        XCTAssertEqual(probe.existingRemoteApps.count, 2)
        XCTAssertEqual(probe.webEndpoint?.rdWebUrl, "https://192.168.0.106/RDWeb/webclient")
    }

    func testAppRegistryRoundTrip() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("reg_test_\(UUID().uuidString).json")

        let registry = AppRegistry(fileURL: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let entry = RegisteredApp(
            id: "erp",
            name: "ERP",
            remoteAppAlias: "||erp",
            server: "192.168.0.106",
            port: 3389,
            rdpPath: "/tmp/erp.rdp",
            webUrl: nil,
            credentialTarget: "RdpVirtualBoxApp:192.168.0.106:erp",
            credentialMode: "Save",
            category: "erp"
        )
        try registry.register(entry)

        let loaded = try registry.find(id: "erp")
        XCTAssertEqual(loaded?.name, "ERP")

        try registry.unregister(id: "erp")
        XCTAssertNil(try registry.find(id: "erp"))
    }
}