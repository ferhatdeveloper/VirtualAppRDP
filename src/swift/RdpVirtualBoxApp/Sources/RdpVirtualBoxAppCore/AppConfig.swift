import Foundation

// =====================================================================
//  AppConfig.swift
//  Rdp Virtual Box App - macOS Native Client veri modelleri.
//
//  Bu dosya Client tarafinda kullanilan tum konfigurasyon ve durum
//  modellerini icerir. PowerShell'deki SetupUI.ps1 + AppRegistry.ps1 +
//  RdpBuilder.ps1'in Swift karsiligi. JSON semasi Windows istemcisiyle
//  uyumludur (apps.json, probe.json).
// =====================================================================

// MARK: - Wizard State

/// 4 adimlik sihirbaz boyunca paylasilan durum konteyneri.
public struct WizardState: Codable, Equatable, Sendable {
    public var server: ServerInfo
    public var probe: ProbeResult?
    public var accessType: AccessType
    public var credentialMode: CredentialMode
    public var selectedApps: Set<String>
    public var customAppPath: String
    public var outputDir: String
    public var language: UILanguage

    public init(
        server: ServerInfo = ServerInfo(),
        probe: ProbeResult? = nil,
        accessType: AccessType = .native,
        credentialMode: CredentialMode = .ask,
        selectedApps: Set<String> = [],
        customAppPath: String = "",
        outputDir: String = NSHomeDirectory() + "/Documents/RdpVirtualBoxApp",
        language: UILanguage = .tr
    ) {
        self.server = server
        self.probe = probe
        self.accessType = accessType
        self.credentialMode = credentialMode
        self.selectedApps = selectedApps
        self.customAppPath = customAppPath
        self.outputDir = outputDir
        self.language = language
    }
}

// MARK: - Server Info

public struct ServerInfo: Codable, Equatable, Sendable {
    public var ip: String
    public var port: Int
    public var username: String
    public var password: String // RAM'de; Keychain'e yazilmadan once

    public init(
        ip: String = "",
        port: Int = 3389,
        username: String = "",
        password: String = ""
    ) {
        self.ip = ip
        self.port = port
        self.username = username
        self.password = password
    }

    public func validate() -> [ValidationError] {
        var errors: [ValidationError] = []
        if !Self.isValidHost(ip) {
            errors.append(.invalidHost)
        }
        if !(1...65535).contains(port) {
            errors.append(.invalidPort)
        }
        if !Self.isValidUsername(username) {
            errors.append(.invalidUsername)
        }
        if password.isEmpty {
            errors.append(.missingPassword)
        }
        return errors
    }

    private static func isValidHost(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return false }
        let ipv4 = #"^(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)$"#
        if trimmed.range(of: ipv4, options: .regularExpression) != nil { return true }
        let hostname = #"^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$"#
        return trimmed.range(of: hostname, options: .regularExpression) != nil
    }

    private static func isValidUsername(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return false }
        let domainUser = #"^[^\\\/\s]+\\[^\\\/\s]+$"#
        let upn = #"^[^@\s]+@[^@\s]+\.[^@\s]+$"#
        return trimmed.range(of: domainUser, options: .regularExpression) != nil
            || trimmed.range(of: upn, options: .regularExpression) != nil
    }

    public enum ValidationError: Error, LocalizedError {
        case invalidHost, invalidPort, invalidUsername, missingPassword
        public var errorDescription: String? {
            switch self {
            case .invalidHost: return "Please enter a valid IPv4 or hostname."
            case .invalidPort: return "Port must be between 1 and 65535."
            case .invalidUsername: return "Username must be in DOMAIN\\user or user@domain format."
            case .missingPassword: return "Password cannot be empty."
            }
        }
    }
}

// MARK: - Enums

public enum AccessType: String, Codable, CaseIterable, Sendable {
    case native = "Native"
    case web = "Web"
    case both = "Both"

    public var displayName: String {
        switch self {
        case .native: return "Native (.rdp) - RECOMMENDED"
        case .web: return "Web (HTML5, browser)"
        case .both: return "Both"
        }
    }

    public var localizedName: (tr: String, en: String) {
        switch self {
        case .native: return ("Native (.rdp dosyası) - ÖNERİLEN", "Native (.rdp file) - RECOMMENDED")
        case .web: return ("Web (HTML5, tarayıcı)", "Web (HTML5, browser)")
        case .both: return ("Her ikisi", "Both")
        }
    }
}

public enum CredentialMode: String, Codable, CaseIterable, Sendable {
    case ask = "Ask"
    case save = "Save"
    case embed = "Embed"

    public var localizedName: (tr: String, en: String) {
        switch self {
        case .ask: return ("Her bağlantıda sor", "Ask on every connection")
        case .save: return ("macOS Keychain'e kaydet", "Save to macOS Keychain")
        case .embed: return ("RDP dosyasına göm (önerilmez)", "Embed in RDP file (not recommended)")
        }
    }
}

public enum UILanguage: String, Codable, CaseIterable, Sendable {
    case tr, en
    public var code: String { rawValue }
    public var displayName: String {
        switch self {
        case .tr: return "Türkçe"
        case .en: return "English"
        }
    }
}

public enum ConnectionStrategy: String, Codable, CaseIterable, Sendable {
    case direct = "direct"
    case gateway = "gateway"
    case guacamole = "guacamole"
    case tailscale = "tailscale"
    case cloudflare = "cloudflare"

    public var displayName: String {
        switch self {
        case .direct: return "Direct RDP"
        case .gateway: return "RD Gateway"
        case .guacamole: return "Apache Guacamole"
        case .tailscale: return "Tailscale"
        case .cloudflare: return "Cloudflare Tunnel"
        }
    }
}

// MARK: - App Registry (apps.json semasi)

/// apps.json icindeki tek bir uygulama kaydi.
/// PowerShell AppRegistry.ps1 ile bire bir ayni sema.
public struct RegisteredApp: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var remoteAppAlias: String
    public var server: String
    public var port: Int
    public var rdpPath: String?
    public var webUrl: String?
    public var credentialTarget: String
    public var credentialMode: String
    public var category: String
    public var registeredAt: Date

    public init(
        id: String,
        name: String,
        remoteAppAlias: String,
        server: String,
        port: Int,
        rdpPath: String? = nil,
        webUrl: String? = nil,
        credentialTarget: String,
        credentialMode: String,
        category: String,
        registeredAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.remoteAppAlias = remoteAppAlias
        self.server = server
        self.port = port
        self.rdpPath = rdpPath
        self.webUrl = webUrl
        self.credentialTarget = credentialTarget
        self.credentialMode = credentialMode
        self.category = category
        self.registeredAt = registeredAt
    }
}

/// apps.json dosyasinin tamami.
public struct AppRegistryDocument: Codable, Equatable, Sendable {
    public var version: String
    public var updatedAt: Date
    public var apps: [RegisteredApp]

    public init(
        version: String = "1.0",
        updatedAt: Date = Date(),
        apps: [RegisteredApp] = []
    ) {
        self.version = version
        self.updatedAt = updatedAt
        self.apps = apps
    }
}

// MARK: - Server Probe (probe.json semasi)

/// ServerProbe REST endpoint'inden donen JSON'in root'u.
/// PowerShell ServerProbe.ps1 ile ayni sema (components haritasi + recommendations).
public struct ProbeResult: Codable, Equatable, Sendable {
    public var server: String
    public var components: [String: ProbeComponent]
    public var webEndpoint: WebEndpoint?
    public var existingRemoteApps: [RemoteAppInfo]
    public var recommendations: [String]
    public var generatedAt: Date

    public init(
        server: String,
        components: [String: ProbeComponent],
        webEndpoint: WebEndpoint? = nil,
        existingRemoteApps: [RemoteAppInfo] = [],
        recommendations: [String] = [],
        generatedAt: Date = Date()
    ) {
        self.server = server
        self.components = components
        self.webEndpoint = webEndpoint
        self.existingRemoteApps = existingRemoteApps
        self.recommendations = recommendations
        self.generatedAt = generatedAt
    }

    /// Bilesen durumunu "ok" olanlar icin true doner.
    public func isComponentOK(_ name: String) -> Bool {
        components[name]?.status == .ok
    }
}

public struct ProbeComponent: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable {
        case ok, warning, error, unknown
        public var symbol: String {
            switch self {
            case .ok: return "[OK]"
            case .warning: return "[WARN]"
            case .error: return "[ERR]"
            case .unknown: return "[?]"
            }
        }
    }

    public var status: Status
    public var value: String
    public var details: [String]

    public init(status: Status, value: String = "", details: [String] = []) {
        self.status = status
        self.value = value
        self.details = details
    }
}

public struct WebEndpoint: Codable, Equatable, Sendable {
    public var rdWebAvailable: Bool
    public var guacamoleAvailable: Bool
    public var rdWebUrl: String?
    public var guacamoleUrl: String?

    public init(
        rdWebAvailable: Bool = false,
        guacamoleAvailable: Bool = false,
        rdWebUrl: String? = nil,
        guacamoleUrl: String? = nil
    ) {
        self.rdWebAvailable = rdWebAvailable
        self.guacamoleAvailable = guacamoleAvailable
        self.rdWebUrl = rdWebUrl
        self.guacamoleUrl = guacamoleUrl
    }
}

public struct RemoteAppInfo: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var alias: String
    public var iconPath: String?

    public init(id: String, name: String, alias: String, iconPath: String? = nil) {
        self.id = id
        self.name = name
        self.alias = alias
        self.iconPath = iconPath
    }
}

// MARK: - Keychain Target

/// KeychainService icin standardize edilmis target adi.
/// PowerShell Credential.ps1 ile ayni format: `RdpVirtualBoxApp:<server>:<appId>`
public enum KeychainTarget {
    public static let namespace = "RdpVirtualBoxApp"

    public static func make(server: String, appId: String) -> String {
        let trimmed = server.trimmingCharacters(in: .whitespaces)
        return "\(namespace):\(trimmed):\(appId)"
    }

    public static func parse(_ target: String) -> (server: String, appId: String)? {
        let parts = target.split(separator: ":", maxSplits: 2).map(String.init)
        guard parts.count == 3, parts[0] == namespace else { return nil }
        return (parts[1], parts[2])
    }
}