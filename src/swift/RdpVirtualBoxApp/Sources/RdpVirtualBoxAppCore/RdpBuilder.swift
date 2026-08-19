import Foundation

// =====================================================================
//  RdpBuilder.swift
//  Rdp Virtual Box App - macOS Native Client .rdp dosyasi ureticisi.
//
//  PowerShell RdpBuilder.ps1 + src/config/client/rdp.template.txt'in
//  Swift karsiligi. Uretilen .rdp dosyalari Microsoft Remote Desktop.app
//  tarafindan okunabilir (rdp:// URL semasi).
//
//  Bos degerler uretilen dosyaya yazilmaz (Windows sihirbaz davranisi).
// =====================================================================

public struct RdpBuilderOptions: Equatable, Sendable {
    public var server: String
    public var port: Int
    public var appAlias: String
    public var appName: String
    public var username: String

    public var useGateway: Bool = false
    public var gatewayHost: String = ""
    public var gatewayDomain: String = ""

    public var useTailscale: Bool = false
    public var tailscaleIP: String = ""

    public var fullScreen: Bool = true
    public var redirectDrives: Bool = false
    public var redirectPrinters: Bool = true
    public var redirectClipboard: Bool = true
    public var redirectSmartCards: Bool = false
    public var audioMode: Int = 2 // 0=local, 1=remote, 2=disable

    public var width: Int = 1920
    public var height: Int = 1080

    public init(
        server: String,
        port: Int = 3389,
        appAlias: String,
        appName: String,
        username: String
    ) {
        self.server = server
        self.port = port
        self.appAlias = appAlias
        self.appName = appName
        self.username = username
    }
}

public enum RdpBuilderError: Error, LocalizedError {
    case invalidPort
    case writeFailed(URL, Error)

    public var errorDescription: String? {
        switch self {
        case .invalidPort: return "RDP port must be between 1 and 65535."
        case .writeFailed(let url, let err):
            return "Failed to write \(url.path): \(err.localizedDescription)"
        }
    }
}

public struct RdpBuilder {
    public init() {}

    /// .rdp icerigini String olarak uretir.
    public func generate(_ opts: RdpBuilderOptions) -> String {
        let primaryAddress: String = {
            if opts.useTailscale, !opts.tailscaleIP.isEmpty { return opts.tailscaleIP }
            return opts.server
        }()

        let fullAddress = "\(primaryAddress):\(opts.port)"
        let screenModeId = opts.fullScreen ? "2" : "1"
        let multiMon = opts.fullScreen ? "1" : "0"

        let gatewayUsage: String = (opts.useGateway && !opts.gatewayHost.isEmpty) ? "1" : ""
        let gatewayHost: String = (opts.useGateway && !opts.gatewayHost.isEmpty) ? opts.gatewayHost : ""
        let gatewayDomain: String = gatewayHost.isEmpty ? "" : opts.gatewayDomain
        let gatewayCredSource: String = gatewayHost.isEmpty ? "" : "0"

        let alternateAddress = fullAddress // Bos ise primary ile ayni

        // Bos olmayan satirlari birlestir
        let lines: [String] = [
            "full address:s:\(fullAddress)",
            "username:s:\(opts.username)",
            "domain:s:",
            "remoteapplicationmode:i:1",
            "remoteapplicationname:s:\(opts.appName)",
            "remoteapplicationprogram:s:||\(opts.appAlias)",
            "alternate full address:s:\(alternateAddress)",
            nonEmpty("gatewayhostname:s:", gatewayHost),
            nonEmpty("gatewaydomain:s:", gatewayDomain),
            nonEmpty("gatewayusagemethod:i:", gatewayUsage),
            nonEmpty("gatewaycredentialssource:i:", gatewayCredSource),
            "drivestoredirect:s:\(opts.redirectDrives ? "*" : "")",
            "redirectclipboard:i:\(opts.redirectClipboard ? 1 : 0)",
            "redirectprinters:i:\(opts.redirectPrinters ? 1 : 0)",
            "redirectsmartcards:i:\(opts.redirectSmartCards ? 1 : 0)",
            "audiomode:i:\(opts.audioMode)",
            "screen mode id:i:\(screenModeId)",
            "use multimon:i:\(multiMon)",
            "authentication level:i:2",
            "enablecredsspsupport:i:1",
            "videoplaybackmode:i:1",
            "networkautodetect:i:1",
            "bandwidthautodetect:i:1",
            "connection type:i:6",
            "displayconnectionbar:i:1",
            "keyboardhook:i:2",
            "redirectposdevices:i:0",
            "redirectdirectx:i:1",
            "disableremoteappcapscheck:i:0",
            "prompt for credentials:i:1",
            "span monitors:i:1",
            "desktopwidth:i:\(opts.width)",
            "desktopheight:i:\(opts.height)"
        ].filter { !$0.isEmpty }

        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// .rdp dosyasini belirtilen klasore yazar.
    public func write(_ opts: RdpBuilderOptions, toDirectory outputDir: String) throws -> URL {
        guard (1...65535).contains(opts.port) else { throw RdpBuilderError.invalidPort }

        let dirURL = URL(fileURLWithPath: outputDir, isDirectory: true)
        let fm = FileManager.default
        if !fm.fileExists(atPath: dirURL.path) {
            try fm.createDirectory(at: dirURL, withIntermediateDirectories: true)
        }

        let safeName = sanitize(opts.appName)
        let url = dirURL.appendingPathComponent("\(safeName).rdp")
        let content = generate(opts)
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw RdpBuilderError.writeFailed(url, error)
        }
        return url
    }

    /// Uretilen .rdp dosyasinin minimum gecerlilik kontrolu.
    public func validate(_ url: URL) -> Bool {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return false }
        let required = [
            "full address:s:",
            "remoteapplicationmode:i:",
            "remoteapplicationname:s:",
            "remoteapplicationprogram:s:"
        ]
        return required.allSatisfy { content.contains($0) }
    }

    // MARK: - Helpers

    private func nonEmpty(_ key: String, _ value: String) -> String {
        value.isEmpty ? "" : "\(key)\(value)"
    }

    private func sanitize(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "\\/:*?\"<>|")
        return name.components(separatedBy: invalid).joined(separator: "_")
    }
}