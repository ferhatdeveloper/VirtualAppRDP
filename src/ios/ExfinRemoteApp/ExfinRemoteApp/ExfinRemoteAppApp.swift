import SwiftUI

@main
struct ExfinRemoteAppApp: App {
    var body: some Scene {
        WindowGroup {
            WizardView()
                .preferredColorScheme(.dark)
        }
    }
}
