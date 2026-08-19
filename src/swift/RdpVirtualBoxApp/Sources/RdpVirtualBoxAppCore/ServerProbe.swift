import Foundation

// =====================================================================
//  ServerProbe.swift
//  Rdp Virtual Box App - macOS Native Client sunucu tarama katmani.
//
//  Windows istemcisi WinRM (5985/5986) uzerinden ServerProbe.ps1 ile
//  tarama yapar. macOS'ta WinRM yoktur; bunun yerine sunucuda barinan
//  REST/HTTPS endpoint'ine (ProbeApi.ps1 veya ASP.NET Core minimal API)
//  HTTP istegi atar. JSON semasi mevcut PowerShell semasi ile aynidir
//  (probe.json -> ProbeResult).
//
//  Standart URL formati: https://<server>:8443/probe/api/probe
//  Auth: opsiyonel Bearer (client secret).
// =====================================================================

public enum ServerProbeError: Error, LocalizedError {
    case invalidURL
    case http(status: Int, body: String)
    case decoding(Error)
    case transport(Error)

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "Probe URL is invalid."
        case .http(let status, let body):
            return "Server probe HTTP \(status): \(body.prefix(200))"
        case .decoding(let err):
            return "Failed to decode probe response: \(err.localizedDescription)"
        case .transport(let err):
            return "Network error: \(err.localizedDescription)"
        }
    }
}

public protocol ServerProbeQuerying {
    func probe(server: String, port: Int, path: String, token: String?) async throws -> ProbeResult
}

extension ServerProbeQuerying {
    public func probe(server: String, port: Int = 8443, path: String = "/probe/api/probe", token: String? = nil) async throws -> ProbeResult {
        try await probe(server: server, port: port, path: path, token: token)
    }
}

public final class ServerProbeService: ServerProbeQuerying {
    public static let shared = ServerProbeService()

    private let session: URLSession
    private let decoder: JSONDecoder

    public init(session: URLSession? = nil) {
        if let s = session {
            self.session = s
        } else {
            let cfg = URLSessionConfiguration.ephemeral
            cfg.timeoutIntervalForRequest = 30
            cfg.timeoutIntervalForResource = 60
            self.session = URLSession(configuration: cfg)
        }

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec
    }

    public func probe(
        server: String,
        port: Int = 8443,
        path: String = "/probe/api/probe",
        token: String? = nil
    ) async throws -> ProbeResult {
        var components = URLComponents()
        components.scheme = "https"
        components.host = server
        components.port = port
        components.path = path
        guard let url = components.url else { throw ServerProbeError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ServerProbeError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw ServerProbeError.http(status: -1, body: "No HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ServerProbeError.http(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }

        do {
            return try decoder.decode(ProbeResult.self, from: data)
        } catch {
            throw ServerProbeError.decoding(error)
        }
    }
}