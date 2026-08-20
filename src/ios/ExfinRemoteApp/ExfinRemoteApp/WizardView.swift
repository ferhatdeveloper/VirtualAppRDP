import SwiftUI
import UIKit

struct WizardView: View {
    @StateObject private var store = WizardStore()

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                header
                ScrollView {
                    Group {
                        switch store.step {
                        case 1: StepServer(store: store)
                        case 2: StepProbe(store: store)
                        case 3: StepApps(store: store)
                        default: StepConnect(store: store)
                        }
                    }
                    .padding(20)
                }
                navBar
            }
            .background(Color(red: 0.043, green: 0.071, blue: 0.125))
            .navigationBarHidden(true)
            .sheet(item: Binding(
                get: { store.shareURL.map { IdentifiedURL(url: $0) } },
                set: { store.shareURL = $0?.url }
            )) { item in
                ShareSheet(items: [item.url])
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("EXFIN RemoteAPP")
                .font(.title2.bold())
            Text("iOS istemci · RemoteApp")
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(Array(["Sunucu", "Tarama", "Uygulama", "Bağlan"].enumerated()), id: \.offset) { i, label in
                    VStack(spacing: 6) {
                        Capsule()
                            .fill(i < store.step ? Color(red: 0.23, green: 0.62, blue: 1) : Color.white.opacity(0.15))
                            .frame(height: 4)
                        Text(label)
                            .font(.caption2)
                            .foregroundStyle(i + 1 == store.step ? Color(red: 0.23, green: 0.62, blue: 1) : .secondary)
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.07, green: 0.10, blue: 0.17))
    }

    private var navBar: some View {
        HStack(spacing: 8) {
            if store.step > 1 {
                Button("Geri") { store.goBack() }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
            }
            if store.step < 4 {
                Button("İleri") { store.goNext() }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
    }
}

private struct IdentifiedURL: Identifiable {
    var url: URL
    var id: String { url.absoluteString }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct StepServer: View {
    @ObservedObject var store: WizardStore
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Adım 1 · Sunucu").font(.title3.bold())
            Text("Probe API adresini girin. Varsayılan HTTP 8444’tür.")
                .foregroundStyle(.secondary)
            TextField("Sunucu IP / DNS", text: $store.host)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.url)
            TextField("Probe port", text: $store.port)
                .keyboardType(.numberPad)
            TextField("Windows kullanıcı adı", text: $store.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField("Bearer token (isteğe bağlı)", text: $store.token)
            Toggle("HTTPS kullan", isOn: $store.useHttps)
        }
        .textFieldStyle(.roundedBorder)
    }
}

private struct StepProbe: View {
    @ObservedObject var store: WizardStore
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Adım 2 · Sunucu taraması").font(.title3.bold())
            Text("Probe API’den sağlık, uygulamalar ve .rdp hedefleri alınır.")
                .foregroundStyle(.secondary)
            Button {
                Task { await store.probe() }
            } label: {
                if store.probing {
                    ProgressView().tint(.black)
                } else {
                    Text("Sunucuyu tara")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.probing || store.host.isEmpty)
            .frame(maxWidth: .infinity)

            if let err = store.probeError {
                StatusText(text: err, error: true)
            }
            if let h = store.health {
                InfoRow(label: "Sunucu", value: h.hostname.isEmpty ? store.host : h.hostname)
                InfoRow(label: "Sürüm", value: h.version.isEmpty ? "—" : h.version)
                InfoRow(label: "Durum", value: h.status.isEmpty ? "ok" : h.status)
                InfoRow(label: "RDP dinleme", value: h.rdpPort > 0 ? "\(h.rdpPort)" : "—")
                InfoRow(label: "Uygulama sayısı", value: "\(store.apps.count)")
            }
            if !store.customers.isEmpty {
                Text("Müşteri").bold()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(store.customers) { c in
                            Button(c.name) { store.customerId = c.id }
                                .buttonStyle(.bordered)
                                .tint(store.customerId == c.id ? .blue : .gray)
                        }
                    }
                }
            }
        }
    }
}

private struct StepApps: View {
    @ObservedObject var store: WizardStore

    private var kinds: [RdpFileInfo] {
        store.rdpFiles.filter { $0.alias.caseInsensitiveCompare(store.selectedAlias) == .orderedSame }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Adım 3 · RemoteApp seçimi").font(.title3.bold())
            if store.apps.isEmpty {
                StatusText(text: "Henüz uygulama yok. Önce sunucuyu tarayın.", error: false)
            }
            ForEach(store.apps) { app in
                let selected = app.alias.caseInsensitiveCompare(store.selectedAlias) == .orderedSame
                Button {
                    store.selectedAlias = app.alias
                } label: {
                    HStack(spacing: 12) {
                        if let img = store.icons[app.alias] {
                            Image(uiImage: img).resizable().frame(width: 36, height: 36)
                        } else {
                            Image(systemName: "desktopcomputer")
                        }
                        VStack(alignment: .leading) {
                            Text(app.name).bold().foregroundStyle(.primary)
                            Text(app.alias).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                    }
                    .padding(12)
                    .background(selected ? Color(red: 0.12, green: 0.23, blue: 0.37) : Color(red: 0.07, green: 0.10, blue: 0.17))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            Text("Bağlantı yolu").bold()
            if kinds.isEmpty {
                StatusText(text: "Bu uygulama için .rdp hedefi yok. Sunucuyu yeniden tarayın.", error: false)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(kinds) { file in
                            Button(file.label.isEmpty ? file.kind.uppercased() : file.label) {
                                store.kind = file.kind.lowercased()
                            }
                            .buttonStyle(.bordered)
                            .tint(store.kind.caseInsensitiveCompare(file.kind) == .orderedSame ? .blue : .gray)
                        }
                    }
                }
                if let chosen = kinds.first(where: { $0.kind.caseInsensitiveCompare(store.kind) == .orderedSame }) {
                    InfoRow(label: "Hedef", value: "\(chosen.host):\(chosen.port)")
                }
            }
        }
    }
}

private struct StepConnect: View {
    @ObservedObject var store: WizardStore
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Adım 4 · Bağlan").font(.title3.bold())
            Text("Cihaz kaydedilir, .rdp indirilir ve Microsoft Remote Desktop ile paylaşılır. Windows parolası RDP istemcisinde sorulur.")
                .foregroundStyle(.secondary)
            InfoRow(label: "Cihaz", value: store.deviceName)
            InfoRow(label: "Uygulama", value: store.apps.first { $0.alias.caseInsensitiveCompare(store.selectedAlias) == .orderedSame }?.name ?? "—")
            InfoRow(label: "Yol", value: store.kind.uppercased())
            if !store.rdClientInstalled {
                StatusText(text: "Microsoft Remote Desktop yüklü değil. App Store’dan ücretsiz kurun.", error: true)
                Button("Remote Desktop’ı yükle") { RdpOpener.openStore() }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
            }
            Button {
                Task { await store.registerAndConnect() }
            } label: {
                if store.connecting { ProgressView().tint(.black) } else { Text("Kaydet ve bağlan") }
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.connecting || store.selectedAlias.isEmpty)
            .frame(maxWidth: .infinity)
            Button("Web portalını aç") { store.openPortal() }
                .buttonStyle(.bordered)
                .disabled(store.host.isEmpty)
                .frame(maxWidth: .infinity)
            if let msg = store.connectMessage {
                let err = msg.contains("onay") || msg.hasPrefix("HTTP") || msg.contains("başarısız") || msg.contains("gerekir")
                StatusText(text: msg, error: err)
            }
        }
    }
}

private struct InfoRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary).frame(width: 140, alignment: .leading)
            Text(value).bold()
            Spacer()
        }
        .padding(12)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct StatusText: View {
    let text: String
    let error: Bool
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: error ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
            Text(text)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(error ? Color.red.opacity(0.2) : Color.green.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
