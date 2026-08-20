import Foundation

struct HealthInfo: Equatable {
    var status: String
    var version: String
    var hostname: String
    var port: Int
    var rdpPort: Int
}

struct RemoteAppInfo: Identifiable, Equatable {
    var id: String
    var alias: String
    var name: String
    var path: String
}

struct CustomerInfo: Identifiable, Equatable {
    var id: String
    var name: String
}

struct RdpFileInfo: Identifiable, Equatable {
    var id: String { "\(alias)-\(kind)-\(url)" }
    var alias: String
    var name: String
    var kind: String
    var label: String
    var host: String
    var port: Int
    var fileName: String
    var url: String
}

enum ProbeError: LocalizedError {
    case invalidURL
    case http(Int, String)
    case message(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Sunucu adresi geçersiz."
        case .http(let code, let body):
            if code == 403 { return "Bu cihaz henüz onaylanmadı. Yöneticinin panelde İstemciler sekmesinden izin vermesi gerekir." }
            let snippet = body.trimmingCharacters(in: .whitespacesAndNewlines).prefix(180)
            return snippet.isEmpty ? "HTTP \(code)" : "HTTP \(code): \(snippet)"
        case .message(let text): return text
        }
    }
}
