import SwiftUI
import RdpVirtualBoxAppCore

// =====================================================================
//  App.swift
//  Rdp Virtual Box App - macOS Native Client giris noktasi.
//
//  @main ile SwiftUI uygulamasini baslatir. Yapilandirma:
//    - 720 x 540 ana pencere boyutu
//    - Tek pencere (Settings olmadan)
//    - Komut grubu: About, Quit
//  Wizard tek bir NavigationStack ile akar; Step view'lari
//  Sources/RdpVirtualBoxApp/Views/ altindadir.
// =====================================================================

@main
struct RdpVirtualBoxApp: App {
    var body: some Scene {
        WindowGroup {
            WizardView()
                .frame(minWidth: 720, minHeight: 540)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("Hakkında") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/ferhatdeveloper/VirtualAppRDP")!)
                }
            }
        }
    }
}