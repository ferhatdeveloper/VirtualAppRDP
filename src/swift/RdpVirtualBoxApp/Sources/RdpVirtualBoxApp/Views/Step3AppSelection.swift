import SwiftUI
import RdpVirtualBoxAppCore

// =====================================================================
//  Step3AppSelection.swift
//  Rdp Virtual Box App - macOS Native Client - Adim 3
//
//  Sunucudan gelen RemoteApp listesinden kurulacak uygulamalari
//  secmek icin List; erisim tipi (Native/Web/Both) ve kimlik
//  bilgisi modu (Ask/Save/Embed) icin Picker.
// =====================================================================

struct Step3AppSelection: View {
    @ObservedObject var store: WizardStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(store.strings.step3Title)
                .font(.title2).bold()

            if let probe = store.state.probe, !probe.existingRemoteApps.isEmpty {
                Text(store.strings.chooseApps)
                    .font(.callout)

                List(probe.existingRemoteApps) { app in
                    HStack {
                        Toggle(isOn: bindingForApp(app.id)) {
                            VStack(alignment: .leading) {
                                Text(app.name).bold()
                                Text(app.alias).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
                .frame(minHeight: 180)
            } else {
                Text("Sunucuda RemoteApp bulunamadı.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Form {
                Picker(store.strings.accessTypeLabel, selection: $store.state.accessType) {
                    ForEach(AccessType.allCases, id: \.self) { type in
                        Text(store.strings.accessTypeName(type)).tag(type)
                    }
                }

                Picker(store.strings.credentialLabel, selection: $store.state.credentialMode) {
                    ForEach(CredentialMode.allCases, id: \.self) { mode in
                        Text(store.strings.credentialName(mode)).tag(mode)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .padding(20)
    }

    private func bindingForApp(_ id: String) -> Binding<Bool> {
        Binding(
            get: { store.state.selectedApps.contains(id) },
            set: { isOn in
                if isOn {
                    store.state.selectedApps.insert(id)
                } else {
                    store.state.selectedApps.remove(id)
                }
            }
        )
    }
}