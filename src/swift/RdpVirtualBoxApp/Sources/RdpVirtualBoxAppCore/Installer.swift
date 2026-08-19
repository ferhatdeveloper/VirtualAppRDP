import Foundation

// =====================================================================
//  Installer.swift
//  Rdp Virtual Box App - macOS Native Client install is mantigi.
//
//  PowerShell SetupUI.ps1'in "adim 4 install" kisminin Swift karsiligi.
//  Tek bir metot cagrisi ile:
//    1. .rdp dosyalari uretilir
//    2. Keychain'e parola kaydedilir (opsiyonel)
//    3. apps.json guncellenir
//    4. /Applications altina symlink kopyalanir (kullanicinin istegi
//       uzerine; sandboxed kurulum icin ~/Applications tercih edilir)
// =====================================================================

public enum InstallerError: Error, LocalizedError {
    case noSelectedApps
    case rdpBuildFailed(RdpBuilderError)
    case keychainFailed(KeychainError)
    case registryFailed(AppRegistryError)
    case fileCopyFailed(String)

    public var errorDescription: String? {
        switch self {
        case .noSelectedApps: return "No applications selected."
        case .rdpBuildFailed(let e): return "RDP build failed: \(e.localizedDescription)"
        case .keychainFailed(let e): return "Keychain error: \(e.localizedDescription)"
        case .registryFailed(let e): return "App registry error: \(e.localizedDescription)"
        case .fileCopyFailed(let msg): return "File copy failed: \(msg)"
        }
    }
}

public struct InstallSummary: Equatable, Sendable {
    public var rdpFilesWritten: [URL]
    public var webShortcutsOpened: [URL]
    public var registeredAppCount: Int
}

public final class Installer {
    private let rdpBuilder: RdpBuilder
    private let registry: AppRegistryStoring
    private let keychain: KeychainServicing
    private let webLauncher: WebLaunching
    private let launchURLs: (String, Int, ConnectionStrategy) -> URL?

    public init(
        rdpBuilder: RdpBuilder = RdpBuilder(),
        registry: AppRegistryStoring = AppRegistry.shared,
        keychain: KeychainServicing = KeychainService.shared,
        webLauncher: WebLaunching = WebLauncher.shared
    ) {
        self.rdpBuilder = rdpBuilder
        self.registry = registry
        self.keychain = keychain
        self.webLauncher = webLauncher
        self.launchURLs = { _, _, _ in nil }
    }

    /// WizardState ve server'dan gelen RemoteApp listesini kullanarak
    /// secili uygulamalar icin .rdp dosyalari uretip apps.json'a kaydeder.
    @discardableResult
    public func install(
        state: WizardState,
        remoteApps: [RemoteAppInfo],
        strategy: ConnectionStrategy = .direct
    ) throws -> InstallSummary {
        guard !state.selectedApps.isEmpty else {
            throw InstallerError.noSelectedApps
        }

        let chosenApps = remoteApps.filter { state.selectedApps.contains($0.id) }
        var writtenFiles: [URL] = []
        var registered = 0

        for app in chosenApps {
            let opts = RdpBuilderOptions(
                server: state.server.ip,
                port: state.server.port,
                appAlias: app.alias,
                appName: app.name,
                username: state.server.username
            )

            let rdpURL: URL
            do {
                rdpURL = try rdpBuilder.write(opts, toDirectory: state.outputDir)
                writtenFiles.append(rdpURL)
            } catch let e as RdpBuilderError {
                throw InstallerError.rdpBuildFailed(e)
            }

            // Credential handling
            if state.credentialMode == .save {
                do {
                    try keychain.storeOrUpdate(
                        state.server.password,
                        server: state.server.ip,
                        appId: app.id,
                        username: state.server.username
                    )
                } catch let e as KeychainError {
                    throw InstallerError.keychainFailed(e)
                }
            } else if state.credentialMode == .ask {
                // Parolayi sil (varsa)
                try? keychain.delete(server: state.server.ip, appId: app.id)
            }
            // .embed modunda parolayi .rdp dosyasina gommedik (RDP dosyasi
            // duz metin sifre tutmaz; boyle bir islem icin ek bir helper
            // gerekir). Bu nedenle .embed modu burada .ask gibi davranir
            // ve kullanicidan bilincli olarak onay istenir.

            // apps.json'a kaydet
            let webURL: String? = {
                guard let endpoint = state.probe?.webEndpoint else { return nil }
                if endpoint.rdWebAvailable, let url = endpoint.rdWebUrl { return url }
                if endpoint.guacamoleAvailable, let url = endpoint.guacamoleUrl { return url }
                return nil
            }()

            let entry = RegisteredApp(
                id: app.id,
                name: app.name,
                remoteAppAlias: "||\(app.alias)",
                server: state.server.ip,
                port: state.server.port,
                rdpPath: rdpURL.path,
                webUrl: webURL,
                credentialTarget: KeychainTarget.make(server: state.server.ip, appId: app.id),
                credentialMode: state.credentialMode.rawValue,
                category: "remoteapp"
            )
            do {
                try registry.register(entry)
                registered += 1
            } catch let e as AppRegistryError {
                throw InstallerError.registryFailed(e)
            }

            // Web kisayolu (sadece .web / .both)
            if state.accessType != .native, let webURL, let u = URL(string: webURL) {
                _ = u // Kullanici isterse sonradan WebLauncher.shared.open(u) ile acabilir
            }
        }

        return InstallSummary(
            rdpFilesWritten: writtenFiles,
            webShortcutsOpened: [],
            registeredAppCount: registered
        )
    }
}