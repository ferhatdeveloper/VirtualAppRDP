import SwiftUI
import RdpVirtualBoxAppCore

// =====================================================================
//  WizardView.swift
//  Rdp Virtual Box App - macOS Native Client 4 adimlik sihirbaz kabugu.
//
//  PowerShell SetupUI.ps1'deki tek-form sihirbaz deseninin SwiftUI
//  karsiligidir. NavigationStack icinde 4 step view gosterilir; state
//  ObservableObject olan WizardStore uzerinden paylasilir.
// =====================================================================

@MainActor
final class WizardStore: ObservableObject {
    @Published var state: WizardState
    @Published var currentStep: Int = 1
    @Published var isProbing: Bool = false
    @Published var isInstalling: Bool = false
    @Published var probeError: String?
    @Published var installError: String?
    @Published var installDone: Bool = false
    @Published var lastSummary: InstallSummary?

    let probeService: ServerProbeQuerying
    let installer: Installer

    init(
        initialState: WizardState = WizardState(),
        probeService: ServerProbeQuerying = ServerProbeService.shared,
        installer: Installer = Installer()
    ) {
        self.state = initialState
        self.probeService = probeService
        self.installer = installer
    }

    var strings: UiStrings { UiStrings(language: state.language) }

    // MARK: - Step navigation

    func goNext() {
        guard currentStep < 4 else { return }
        currentStep += 1
    }

    func goBack() {
        guard currentStep > 1 else { return }
        currentStep -= 1
    }

    // MARK: - Probe

    func runProbe() async {
        isProbing = true
        probeError = nil
        defer { isProbing = false }

        do {
            let result = try await probeService.probe(
                server: state.server.ip,
                port: 8443
            )
            state.probe = result
        } catch {
            probeError = error.localizedDescription
        }
    }

    // MARK: - Install

    func runInstall() async {
        isInstalling = true
        installError = nil
        installDone = false
        defer { isInstalling = false }

        guard let probe = state.probe else {
            installError = strings.probeFailed.replacingOccurrences(of: "{0}", with: "Probe not run yet.")
            return
        }
        do {
            let summary = try installer.install(state: state, remoteApps: probe.existingRemoteApps)
            lastSummary = summary
            installDone = true
        } catch {
            installError = error.localizedDescription
        }
    }
}

struct WizardView: View {
    @StateObject private var store = WizardStore()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                headerBar
                Divider()
                stepContainer
                Divider()
                footerBar
            }
            .background(Color(NSColor.windowBackgroundColor))
        }
    }

    private var headerBar: some View {
        HStack {
            Image(systemName: "display.arrowtriangle.4.outward")
                .imageScale(.large)
                .foregroundStyle(Color.accentColor)
            Text(store.strings.formTitle)
                .font(.system(size: 16, weight: .semibold))
            Spacer()
            Picker("", selection: $store.state.language) {
                ForEach(UILanguage.allCases, id: \.self) { lang in
                    Text(lang.displayName).tag(lang)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 110)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var stepContainer: some View {
        switch store.currentStep {
        case 1:
            Step1ServerInfo(store: store)
        case 2:
            Step2ProbeResults(store: store)
        case 3:
            Step3AppSelection(store: store)
        case 4:
            Step4Review(store: store)
        default:
            EmptyView()
        }
    }

    private var footerBar: some View {
        HStack(spacing: 12) {
            // Step indicator
            Text(store.strings.stepLabelFormat
                .replacingOccurrences(of: "{0}", with: String(store.currentStep))
                .replacingOccurrences(of: "{1}", with: currentStepTitle())
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)

            Spacer()

            if store.currentStep > 1 {
                Button(store.strings.backButton) { store.goBack() }
                    .keyboardShortcut(.cancelAction)
            }

            if store.currentStep < 4 {
                Button(store.strings.nextButton) { store.goNext() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canProceed())
            } else {
                Button(store.strings.installButton) {
                    Task { await store.runInstall() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canProceed() || store.isInstalling)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func currentStepTitle() -> String {
        switch store.currentStep {
        case 1: return store.strings.step1Title
        case 2: return store.strings.step2Title
        case 3: return store.strings.step3Title
        case 4: return store.strings.step4Title
        default: return ""
        }
    }

    private func canProceed() -> Bool {
        switch store.currentStep {
        case 1:
            return !store.state.server.ip.isEmpty
                && !store.state.server.username.isEmpty
                && !store.state.server.password.isEmpty
                && !store.isProbing
        case 2:
            return store.state.probe != nil
        case 3:
            return !store.state.selectedApps.isEmpty
        case 4:
            return !store.isInstalling
        default:
            return false
        }
    }
}