import Foundation

final class ProbeClient {
    let host: String
    let port: Int
    let useHttps: Bool
    let token: String?

    var baseURL: String {
        let scheme = useHttps ? "https" : "http"
        return "\(scheme)://\(host):\(port)"
    }

    init(host: String, port: Int, useHttps: Bool, token: String?) {
        self.host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        self.port = port
        self.useHttps = useHttps
        self.token = token?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func health() async throws -> HealthInfo {
        let json = try await getJSON("/health")
        return HealthInfo(
            status: json["status"] as? String ?? "",
            version: json["version"] as? String ?? "",
            hostname: json["hostname"] as? String ?? "",
            port: (json["port"] as? NSNumber)?.intValue ?? 0,
            rdpPort: (json["rdpPort"] as? NSNumber)?.intValue ?? 0
        )
    }

    func apps() async throws -> [RemoteAppInfo] {
        let json = try await getJSON("/api/apps")
        let arr = json["apps"] as? [[String: Any]] ?? []
        return arr.compactMap { o in
            let alias = (o["alias"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (o["id"] as? String ?? "")
            guard !alias.isEmpty else { return nil }
            return RemoteAppInfo(
                id: (o["id"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? alias,
                alias: alias,
                name: (o["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? alias,
                path: o["path"] as? String ?? ""
            )
        }
    }

    func customers() async throws -> [CustomerInfo] {
        let json = try await getJSON("/api/portal")
        let arr = json["customers"] as? [[String: Any]] ?? []
        return arr.compactMap { o in
            guard let id = o["id"] as? String, !id.isEmpty else { return nil }
            return CustomerInfo(id: id, name: (o["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? id)
        }
    }

    func rdpIndex(customerId: String?) async throws -> [RdpFileInfo] {
        var path = "/rdp"
        if let customerId, !customerId.isEmpty {
            path += "?customer=\(enc(customerId))"
        }
        let json = try await getJSON(path)
        let arr = json["files"] as? [[String: Any]] ?? []
        return arr.map { o in
            RdpFileInfo(
                alias: o["alias"] as? String ?? "",
                name: o["name"] as? String ?? "",
                kind: o["kind"] as? String ?? "",
                label: o["label"] as? String ?? "",
                host: o["host"] as? String ?? "",
                port: (o["port"] as? NSNumber)?.intValue ?? 0,
                fileName: o["fileName"] as? String ?? "",
                url: o["url"] as? String ?? ""
            )
        }
    }

    func iconPNG(alias: String) async -> Data? {
        guard !alias.isEmpty else { return nil }
        do {
            let json = try await getJSON("/api/icon?alias=\(enc(alias))")
            guard let b64 = json["png"] as? String, !b64.isEmpty else { return nil }
            return Data(base64Encoded: b64)
        } catch {
            return nil
        }
    }

    func downloadRdp(relativeURL: String, clientId: String?) async throws -> String {
        var path = relativeURL.hasPrefix("/") ? relativeURL : "/\(relativeURL)"
        if let clientId, !clientId.isEmpty {
            path += path.contains("?") ? "&" : "?"
            path += "client=\(enc(clientId))"
        }
        let (data, status) = try await request(path: path, method: "GET", jsonBody: nil)
        if status == 403 { throw ProbeError.http(403, "") }
        guard (200..<300).contains(status) else {
            throw ProbeError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if text.isEmpty { throw ProbeError.message("Sunucu boş .rdp döndürdü.") }
        return text
    }

    func registerClient(machineId: String, hostname: String, username: String, apps: [RemoteAppInfo]) async throws {
        let payload: [String: Any] = [
            "machineId": machineId,
            "hostname": hostname,
            "username": username,
            "apps": apps.map { ["id": $0.id, "name": $0.name, "alias": $0.alias] }
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let (data, status) = try await request(path: "/api/clients", method: "POST", jsonBody: body)
        guard (200..<300).contains(status) else {
            throw ProbeError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
    }

    private func getJSON(_ path: String) async throws -> [String: Any] {
        let (data, status) = try await request(path: path, method: "GET", jsonBody: nil)
        guard (200..<300).contains(status) else {
            throw ProbeError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProbeError.message("Sunucu JSON döndürmedi.")
        }
        return obj
    }

    private func request(path: String, method: String, jsonBody: Data?) async throws -> (Data, Int) {
        guard let url = URL(string: baseURL + path) else { throw ProbeError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("EXFIN-RemoteAPP-iOS/1.1.5", forHTTPHeaderField: "User-Agent")
        req.setValue("application/json, application/x-rdp, */*", forHTTPHeaderField: "Accept")
        if let token, !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let jsonBody {
            req.httpBody = jsonBody
            req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? -1
        return (data, status)
    }

    private func enc(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
    }
}
