import XCTest
@testable import RdpVirtualBoxAppCore

final class RdpBuilderTests: XCTestCase {
    private var builder: RdpBuilder!

    override func setUp() {
        super.setUp()
        builder = RdpBuilder()
    }

    func testGenerateContainsMandatoryFields() {
        let opts = RdpBuilderOptions(
            server: "192.168.0.106",
            appAlias: "erp",
            appName: "ERP Uygulaması",
            username: "FIRMA\\kullanici"
        )
        let rdp = builder.generate(opts)

        XCTAssertTrue(rdp.contains("full address:s:192.168.0.106:3389"))
        XCTAssertTrue(rdp.contains("remoteapplicationmode:i:1"))
        XCTAssertTrue(rdp.contains("remoteapplicationname:s:ERP Uygulaması"))
        XCTAssertTrue(rdp.contains("remoteapplicationprogram:s:||erp"))
        XCTAssertTrue(rdp.contains("username:s:FIRMA\\kullanici"))
    }

    func testTailscaleIPOverridesServer() {
        var opts = RdpBuilderOptions(
            server: "192.168.0.106",
            appAlias: "erp",
            appName: "ERP",
            username: "user"
        )
        opts.useTailscale = true
        opts.tailscaleIP = "100.64.0.1"
        let rdp = builder.generate(opts)

        XCTAssertTrue(rdp.contains("full address:s:100.64.0.1:3389"))
        XCTAssertFalse(rdp.contains("192.168.0.106:3389"))
    }

    func testEmptyGatewayFieldsAreOmitted() {
        let opts = RdpBuilderOptions(
            server: "10.0.0.5",
            appAlias: "notepad",
            appName: "Notepad",
            username: "u"
        )
        let rdp = builder.generate(opts)

        XCTAssertFalse(rdp.contains("gatewayhostname:s:"))
        XCTAssertFalse(rdp.contains("gatewayusagemethod:i:"))
    }

    func testGatewayEnabledProducesGatewayFields() {
        var opts = RdpBuilderOptions(
            server: "10.0.0.5",
            appAlias: "notepad",
            appName: "Notepad",
            username: "u"
        )
        opts.useGateway = true
        opts.gatewayHost = "gw.firma.local"
        opts.gatewayDomain = "FIRMA"
        let rdp = builder.generate(opts)

        XCTAssertTrue(rdp.contains("gatewayhostname:s:gw.firma.local"))
        XCTAssertTrue(rdp.contains("gatewaydomain:s:FIRMA"))
        XCTAssertTrue(rdp.contains("gatewayusagemethod:i:1"))
        XCTAssertTrue(rdp.contains("gatewaycredentialssource:i:0"))
    }

    func testWriteProducesValidFile() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rdp_test_\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let opts = RdpBuilderOptions(
            server: "192.168.0.106",
            appAlias: "erp",
            appName: "ERP",
            username: "u"
        )
        let url = try builder.write(opts, toDirectory: tmp.path)

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(builder.validate(url))

        let content = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(content.contains("||erp"))
    }

    func testInvalidPortThrows() {
        var opts = RdpBuilderOptions(
            server: "192.168.0.106",
            appAlias: "erp",
            appName: "ERP",
            username: "u"
        )
        opts.port = 99999

        XCTAssertThrowsError(try builder.write(opts, toDirectory: NSTemporaryDirectory())) { error in
            guard case RdpBuilderError.invalidPort = error else {
                XCTFail("Expected invalidPort, got \(error)")
                return
            }
        }
    }
}