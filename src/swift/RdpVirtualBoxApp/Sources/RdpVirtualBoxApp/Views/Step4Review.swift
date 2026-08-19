import SwiftUI
import RdpVirtualBoxAppCore

// =====================================================================
//  Step4Review.swift
//  Rdp Virtual Box App - macOS Native Client - Adim 4
//
//  Yapilan tum secimlerin ozetini gosterir ve "Kurulumu Baslat"
//  butonuyla Installer.install() tetiklenir. Kurulum bitince
//  sonuc mesaji ve uretilen dosyalarin listesi gosterilir.
// =====================================================================

struct Step4Review: View {
    @ObservedObject var store: WizardStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(store.strings.step4Title)
                .font(.title2).bold()

            summarySection

            if store.isInstalling {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(store.strings.installingLabel)
                }
            }

            if let err = store.installError {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }

            if store.installDone, let summary = store.lastSummary {
                Label(store.strings.installDone, systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)

                if !summary.rdpFilesWritten.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Üretilen .rdp dosyaları:").bold()
                        ForEach(summary.rdpFilesWritten, id: \.self) { url in
                            Text(url.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }

            Spacer()
        }
        .padding(20)
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(store.strings.summaryLabel).font(.headline)

            Group {
                row("Sunucu", store.state.server.ip)
                row("Port", String(store.state.server.port))
                row("Kullanıcı", store.state.server.username)
                row("Erişim Tipi", store.strings.accessTypeName(store.state.accessType))
                row("Kimlik", store.strings.credentialName(store.state.credentialMode))
                row("Seçili Uygulama", "\(store.state.selectedApps.count) adet")
                row("Çıktı Klasörü", store.state.outputDir)
            }
            .font(.callout)
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(.secondary).frame(width: 130, alignment: .leading)
            Text(value).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}