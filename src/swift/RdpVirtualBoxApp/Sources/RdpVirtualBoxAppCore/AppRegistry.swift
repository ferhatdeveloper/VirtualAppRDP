import Foundation

// =====================================================================
//  AppRegistry.swift
//  Rdp Virtual Box App - macOS Native Client uygulama kayit yoneticisi.
//
//  PowerShell'deki AppRegistry.ps1'in Swift karsiligi. apps.json dosyasi
//  ~/Library/Application Support/RdpVirtualBoxApp/apps.json altinda
//  tutulur. Atomik yazma (tmp -> move) ile yarim dosya riski onlenir.
//
//  Schema JSON, Windows istemcisiyle bire bir uyumludur.
// =====================================================================

public enum AppRegistryError: Error, LocalizedError {
    case notFound(id: String)
    case encodingFailed

    public var errorDescription: String? {
        switch self {
        case .notFound(let id): return "App not registered: \(id)"
        case .encodingFailed: return "Failed to encode apps.json."
        }
    }
}

public protocol AppRegistryStoring {
    func load() throws -> AppRegistryDocument
    func save(_ document: AppRegistryDocument) throws
    func register(_ app: RegisteredApp) throws
    func unregister(id: String) throws
    func find(id: String) throws -> RegisteredApp?
    func all() throws -> [RegisteredApp]
}

public final class AppRegistry: AppRegistryStoring {
    public static let shared = AppRegistry()

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL? = nil) {
        if let provided = fileURL {
            self.fileURL = provided
        } else {
            let supportDir = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first!
                .appendingPathComponent("RdpVirtualBoxApp", isDirectory: true)
            self.fileURL = supportDir.appendingPathComponent("apps.json")
        }

        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec
    }

    // MARK: - Public API

    public func load() throws -> AppRegistryDocument {
        let fm = FileManager.default
        if !fm.fileExists(atPath: fileURL.path) {
            try ensureDirectory()
            let empty = AppRegistryDocument()
            try persist(empty)
            return empty
        }
        let data = try Data(contentsOf: fileURL)
        if data.isEmpty {
            return AppRegistryDocument()
        }
        return try decoder.decode(AppRegistryDocument.self, from: data)
    }

    public func save(_ document: AppRegistryDocument) throws {
        var doc = document
        doc.updatedAt = Date()
        try persist(doc)
    }

    public func register(_ app: RegisteredApp) throws {
        var doc = try load()
        if let idx = doc.apps.firstIndex(where: { $0.id == app.id }) {
            doc.apps[idx] = app
        } else {
            doc.apps.append(app)
        }
        try save(doc)
    }

    public func unregister(id: String) throws {
        var doc = try load()
        let before = doc.apps.count
        doc.apps.removeAll { $0.id == id }
        guard doc.apps.count != before else {
            throw AppRegistryError.notFound(id: id)
        }
        try save(doc)
    }

    public func find(id: String) throws -> RegisteredApp? {
        try load().apps.first { $0.id == id }
    }

    public func all() throws -> [RegisteredApp] {
        try load().apps
    }

    // MARK: - Atomic write

    private func persist(_ doc: AppRegistryDocument) throws {
        try ensureDirectory()
        let data: Data
        do {
            data = try encoder.encode(doc)
        } catch {
            throw AppRegistryError.encodingFailed
        }
        let tmp = fileURL.appendingPathExtension("tmp")
        try data.write(to: tmp, options: [.atomic])
        if FileManager.default.fileExists(atPath: fileURL.path) {
            _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: tmp)
        } else {
            try FileManager.default.moveItem(at: tmp, to: fileURL)
        }
    }

    private func ensureDirectory() throws {
        let dir = fileURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    // MARK: - Helpers

    public var registryFileURL: URL { fileURL }

    public func appsJSONPath() -> String { fileURL.path }
}