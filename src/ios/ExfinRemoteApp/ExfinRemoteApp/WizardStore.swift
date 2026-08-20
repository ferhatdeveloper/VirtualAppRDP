import Foundation
import SwiftUI
import UIKit

@MainActor
final class WizardStore: ObservableObject {
    @Published var step = 1
    @Published var host = UserDefaults.standard.string(forKey: "host") ?? ""
    @Published var port = UserDefaults.standard.string(forKey: "port") ?? "8444"
    @Published var useHttps = UserDefaults.standard.bool(forKey: "https")
    @Published var username = UserDefaults.standard.string(forKey: "username") ?? ""
    @Published var token = UserDefaults.standard.string(forKey: "token") ?? ""
    @Published var customerId = UserDefaults.standard.string(forKey: "customerId") ?? ""
    @Published var kind = UserDefaults.standard.string(forKey: "kind") ?? "lan"
    @Published var selectedAlias = ""

    @Published var probing = false
    @Published var connecting = false
    @Published var probeError: String?
    @Published var connectMessage: String?

    @Published var health: HealthInfo?
    @Published var apps: [RemoteAppInfo] = []
    @Published var customers: [CustomerInfo] = []
    @Published var rdpFiles: [RdpFileInfo] = []
    @Published var icons: [String: UIImage] = [:]
    @Published var shareURL: URL?

    var machineId: String {
        UIDevice.current.identifierForVendor?.uuidString ?? "ios-unknown"
    }

    var deviceName: String { UIDevice.current.name }

    var rdClientInstalled: Bool { RdpOpener.isRdClientInstalled }

    func persist() {
        let ud = UserDefaults.standard
        ud.set(host, forKey: "host")
        ud.set(port, forKey: "port")
        ud.set(useHttps, forKey: "https")
        ud.set(username, forKey: "username")
        ud.set(token, forKey: "token")
        ud.set(customerId, forKey: "customerId")
        ud.set(kind, forKey: "kind")
    }

    func goNext() {
        persist()
        if step == 1 && health == nil && !probing { Task { await probe() } }
        step = min(4, step + 1)
        probeError = nil
        connectMessage = nil
    }

    func goBack() {
        step = max(1, step - 1)
        probeError = nil
        connectMessage = nil
    }

    private func client() throws -> ProbeClient {
        let p = Int(port) ?? 8444
        if host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ProbeError.message("Sunucu adresi gerekli.")
        }
        return ProbeClient(host: host, port: min(max(p, 1), 65535), useHttps: useHttps, token: token.isEmpty ? nil : token)
    }

    func probe() async {
        persist()
        probing = true
        probeError = nil
        defer { probing = false }
        do {
            let api = try client()
            let h = try await api.health()
            let list = try await api.apps()
            let cust = (try? await api.customers()) ?? []
            let cid = customerId.isEmpty ? (cust.first?.id ?? "") : customerId
            let files = try await api.rdpIndex(customerId: cid.isEmpty ? nil : cid)
            var nextIcons: [String: UIImage] = [:]
            for app in list {
                if let data = await api.iconPNG(alias: app.alias), let img = UIImage(data: data) {
                    nextIcons[app.alias] = img
                }
            }
            health = h
            apps = list
            customers = cust
            rdpFiles = files
            customerId = cid
            if selectedAlias.isEmpty { selectedAlias = list.first?.alias ?? "" }
            let kinds = files.filter { $0.alias.caseInsensitiveCompare(selectedAlias) == .orderedSame }.map { $0.kind.lowercased() }
            if !kinds.contains(kind.lowercased()), let first = kinds.first { kind = first }
            icons = nextIcons
        } catch {
            probeError = error.localizedDescription
        }
    }

    func registerAndConnect() async {
        persist()
        connecting = true
        connectMessage = nil
        defer { connecting = false }
        do {
            guard let app = apps.first(where: { $0.alias.caseInsensitiveCompare(selectedAlias) == .orderedSame }) else {
                throw ProbeError.message("Bir uygulama seçin.")
            }
            guard let file = rdpFiles.first(where: {
                $0.alias.caseInsensitiveCompare(selectedAlias) == .orderedSame &&
                $0.kind.caseInsensitiveCompare(kind) == .orderedSame
            }) else {
                throw ProbeError.message("Bu uygulama için \(kind.uppercased()) .rdp kaydı yok.")
            }
            let user = username.isEmpty ? "ios" : username
            let clientKey = (machineId + "|" + user).lowercased()
            let api = try client()
            _ = try? await api.registerClient(machineId: machineId, hostname: deviceName, username: user, apps: [app])
            let content = try await api.downloadRdp(relativeURL: file.url, clientId: clientKey)
            let url = try RdpOpener.saveRdp(fileName: file.fileName.isEmpty ? "\(app.alias).rdp" : file.fileName, content: content)
            shareURL = url
            RdpOpener.open(fileURL: url)
            connectMessage = "RDP dosyası hazır: \(file.fileName.isEmpty ? app.name : file.fileName)"
        } catch {
            connectMessage = error.localizedDescription
        }
    }

    func openPortal() {
        persist()
        let scheme = useHttps ? "https" : "http"
        let p = Int(port) ?? 8444
        RdpOpener.openPortal("\(scheme)://\(host.trimmingCharacters(in: .whitespacesAndNewlines)):\(p)/download")
    }
}
