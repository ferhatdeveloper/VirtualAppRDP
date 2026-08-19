import Foundation
import Security

// =====================================================================
//  KeychainService.swift
//  Rdp Virtual Box App - macOS Native Client kimlik saklama katmani.
//
//  Windows Credential Manager'in (advapi32.dll CredMan API) macOS
//  karsiligi: Keychain Services. SecItem* API ile generic password
//  tipinde credential kaydeder. Target formati PowerShell ile ayni:
//      RdpVirtualBoxApp:<serverIp>:<appId>
//
//  Testlerde `SecItemAdd` gercek Keychain'e yazmamak icin service
//  injection desenine izin verilir (bkz. RdpVirtualBoxAppTests).
// =====================================================================

public enum KeychainError: Error, LocalizedError, Equatable {
    case unhandledError(status: OSStatus)
    case itemNotFound
    case invalidData

    public var errorDescription: String? {
        switch self {
        case .unhandledError(let status):
            if let message = SecCopyErrorMessageString(status, nil) as String? {
                return "Keychain error: \(message) (\(status))"
            }
            return "Keychain error: OSStatus \(status)"
        case .itemNotFound: return "Item not found in Keychain."
        case .invalidData: return "Keychain returned invalid data."
        }
    }
}

public protocol KeychainServicing {
    func storePassword(_ password: String, target: String, username: String) throws
    func loadPassword(target: String) throws -> String?
    func deletePassword(target: String) throws
    func listTargets() throws -> [String]
}

extension KeychainServicing {
    public func storeOrUpdate(_ password: String, server: String, appId: String, username: String) throws {
        let target = KeychainTarget.make(server: server, appId: appId)
        try storePassword(password, target: target, username: username)
    }

    public func load(server: String, appId: String) throws -> String? {
        try loadPassword(target: KeychainTarget.make(server: server, appId: appId))
    }

    public func delete(server: String, appId: String) throws {
        try deletePassword(target: KeychainTarget.make(server: server, appId: appId))
    }
}

public final class KeychainService: KeychainServicing {
    public static let shared = KeychainService()

    private let service: String

    public init(service: String = KeychainTarget.namespace) {
        self.service = service
    }

    // MARK: - Public API

    public func storePassword(_ password: String, target: String, username: String) throws {
        guard let data = password.data(using: .utf8) else { throw KeychainError.invalidData }

        // Once ayni target varsa sil ki duplicate -25299 (errSecDuplicateItem) almayalim.
        try? deletePassword(target: target)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: target,
            kSecAttrLabel as String: "Rdp Virtual Box App - \(username)",
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unhandledError(status: status) }
    }

    public func loadPassword(target: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: target,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.unhandledError(status: status) }
        guard let data = item as? Data, let s = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }
        return s
    }

    public func deletePassword(target: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: target
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecItemNotFound { return }
        guard status == errSecSuccess else { throw KeychainError.unhandledError(status: status) }
    }

    public func listTargets() throws -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        var items: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &items)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess else { throw KeychainError.unhandledError(status: status) }
        guard let array = items as? [[String: Any]] else { return [] }
        return array.compactMap { $0[kSecAttrAccount as String] as? String }
    }

    // MARK: - Helpers

    public func storeOrUpdate(_ password: String, server: String, appId: String, username: String) throws {
        let target = KeychainTarget.make(server: server, appId: appId)
        try storePassword(password, target: target, username: username)
    }

    public func load(server: String, appId: String) throws -> String? {
        try loadPassword(target: KeychainTarget.make(server: server, appId: appId))
    }

    public func delete(server: String, appId: String) throws {
        try deletePassword(target: KeychainTarget.make(server: server, appId: appId))
    }
}