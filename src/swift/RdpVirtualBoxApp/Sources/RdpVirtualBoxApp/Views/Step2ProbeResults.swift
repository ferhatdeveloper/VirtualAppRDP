import SwiftUI
import RdpVirtualBoxAppCore

// =====================================================================
//  Step2ProbeResults.swift
//  Rdp Virtual Box App - macOS Native Client - Adim 2
//
//  Probe sonuclarini tablo halinde gosterir: Bileşen, Durum, Değer.
//  Bilesen statusu ok ise yesil, warning ise sari, error ise kirmizi
//  renkte sembol gosterilir. Recommendations listesi ayri bolumde.
// =====================================================================

struct Step2ProbeResults: View {
    @ObservedObject var store: WizardStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(store.strings.step2Title)
                .font(.title2).bold()

            if let probe = store.state.probe {
                componentTable(for: probe)
                if !probe.recommendations.isEmpty {
                    recommendationsView(for: probe)
                }
            } else {
                Text(store.strings.probeProgress)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(20)
    }

    private func componentTable(for probe: ProbeResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(store.strings.componentHeader).bold().frame(maxWidth: .infinity, alignment: .leading)
                Text(store.strings.statusHeader).bold().frame(width: 110, alignment: .leading)
                Text(store.strings.valueHeader).bold().frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()

            ForEach(probe.components.sorted(by: { $0.key < $1.key }), id: \.key) { entry in
                HStack {
                    Text(entry.key).frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 6) {
                        Circle()
                            .fill(color(for: entry.value.status))
                            .frame(width: 10, height: 10)
                        Text(statusLabel(for: entry.value.status))
                            .frame(width: 90, alignment: .leading)
                    }
                    .frame(width: 110, alignment: .leading)
                    Text(entry.value.value)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func recommendationsView(for probe: ProbeResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(store.strings.recommendations).bold()
            ForEach(Array(probe.recommendations.enumerated()), id: \.offset) { _, rec in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "lightbulb").foregroundStyle(.yellow)
                    Text(rec)
                }
            }
        }
        .padding(.top, 12)
    }

    private func color(for status: ProbeComponent.Status) -> Color {
        switch status {
        case .ok: return .green
        case .warning: return .yellow
        case .error: return .red
        case .unknown: return .gray
        }
    }

    private func statusLabel(for status: ProbeComponent.Status) -> String {
        switch status {
        case .ok: return store.strings.statusOk
        case .warning: return store.strings.statusWarn
        case .error: return store.strings.statusError
        case .unknown: return "?"
        }
    }
}