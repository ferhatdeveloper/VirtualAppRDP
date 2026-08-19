import SwiftUI
import RdpVirtualBoxAppCore

// =====================================================================
//  Step1ServerInfo.swift
//  Rdp Virtual Box App - macOS Native Client - Adim 1
//
//  Sunucu IP, port, kullanici adi ve parola formu. "Sunucuyu Tara"
//  butonu ile asenkron ServerProbeService.probe() cagirilir ve sonuclar
//  state.probe icine yazilir. Validation ServerInfo.validate() ile yapilir.
// =====================================================================

struct Step1ServerInfo: View {
    @ObservedObject var store: WizardStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(store.strings.step1Title)
                .font(.title2).bold()

            Form {
                TextField(store.strings.serverIpLabel, text: $store.state.server.ip)
                    .textContentType(.URL)
                    .disableAutocorrection(true)

                Stepper(value: $store.state.server.port, in: 1...65535) {
                    HStack {
                        Text(store.strings.portLabel)
                        Spacer()
                        Text(String(store.state.server.port))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                TextField(store.strings.usernameLabel, text: $store.state.server.username)
                    .textContentType(.username)
                    .disableAutocorrection(true)

                SecureField(store.strings.passwordLabel, text: $store.state.server.password)
                    .textContentType(.password)
            }
            .formStyle(.grouped)

            HStack {
                Button {
                    Task { await store.runProbe() }
                } label: {
                    HStack(spacing: 6) {
                        if store.isProbing {
                            ProgressView().controlSize(.small)
                        }
                        Text(store.strings.probeButton)
                    }
                }
                .disabled(store.state.server.ip.isEmpty || store.isProbing)

                if let err = store.probeError {
                    Text(err)
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }
        }
        .padding(20)
    }
}