import Foundation
import AppKit

// =====================================================================
//  Launchers.swift
//  Rdp Virtual Box App - macOS Native Client RDP ve Web launcher'lari.
//
//  RdpLauncher.swift: .rdp dosyasi veya rdp:// URL'si Microsoft Remote
//  Desktop.app'e (com.microsoft.rdc.osx.beta) yonlendirilir. macOS
//  'open' komutu dosya iliskisini kullanir; alternatif olarak
//  rdp:// URL'si dogrudan RDP uygulamasini tetikler.
//
//  WebLauncher.swift: RD Web veya Guacamole URL'sini varsayilan
//  tarayicida acar. NSWorkspace.shared.open() kullanilir.
// =====================================================================

public enum LauncherError: Error, LocalizedError {
    case rdpAppNotInstalled
    case openFailed(URL)

    public var errorDescription: String? {
        switch self {
        case .rdpAppNotInstalled:
            return "Microsoft Remote Desktop is not installed. Download it from the Mac App Store."
        case .openFailed(let url):
            return "Failed to open \(url.absoluteString)."
        }
    }
}

public protocol RDPLaunching {
    func launch(rdpFile url: URL) throws
    func launchRDPURL(_ rdpURL: String) throws
}

public final class RdpLauncher: RDPLaunching {
    public static let shared = RdpLauncher()

    /// Microsoft Remote Desktop macOS bundle identifier'lari.
    /// Yeni surumde 'com.microsoft.rdc.macos' olarak degisti; eski surum 'com.microsoft.rdc.osx.beta'.
    private let appBundleIds: [String] = [
        "com.microsoft.rdc.macos",
        "com.microsoft.rdc.osx.beta",
        "com.microsoft.rdc.osx.beta2"
    ]

    public init() {}

    public func launch(rdpFile url: URL) throws {
        guard isRDPAppInstalled() else { throw LauncherError.rdpAppNotInstalled }
        let ok = NSWorkspace.shared.open(url)
        if !ok { throw LauncherError.openFailed(url) }
    }

    public func launchRDPURL(_ rdpURL: String) throws {
        guard let url = URL(string: rdpURL) else { throw LauncherError.openFailed(URL(string: "rdp://")!) }
        guard isRDPAppInstalled() else { throw LauncherError.rdpAppNotInstalled }
        let ok = NSWorkspace.shared.open(url)
        if !ok { throw LauncherError.openFailed(url) }
    }

    public func isRDPAppInstalled() -> Bool {
        for id in appBundleIds {
            if NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil {
                return true
            }
        }
        return false
    }

    /// .rdp dosyasi icin `rdp://` URL'si uretir.
    /// rdp:// scheme'i Microsoft RDP macOS tarafindan taninir; dosyayi
    /// acmak yerine dogrudan baglantiyi baslatir.
    public func makeRDPURL(server: String, port: Int, appAlias: String) -> String {
        let encodedAlias = appAlias.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? appAlias
        return "rdp://\(server):\(port)/%23|\(encodedAlias)"
    }
}

// MARK: - Web Launcher

public protocol WebLaunching {
    func open(_ url: URL) throws
    func openRDWeb(_ server: String, port: Int) throws
    func openGuacamole(_ server: String, port: Int, path: String) throws
}

public final class WebLauncher: WebLaunching {
    public static let shared = WebLauncher()

    public init() {}

    public func open(_ url: URL) throws {
        let ok = NSWorkspace.shared.open(url)
        if !ok { throw LauncherError.openFailed(url) }
    }

    public func openRDWeb(_ server: String, port: Int = 443) throws {
        let url = URL(string: "https://\(server):\(port)/RDWeb/webclient/index.html")
            ?? URL(string: "https://example.com")!
        try open(url)
    }

    public func openGuacamole(_ server: String, port: Int = 8443, path: String = "/guacamole/") throws {
        let url = URL(string: "https://\(server):\(port)\(path)")
            ?? URL(string: "https://example.com")!
        try open(url)
    }
}