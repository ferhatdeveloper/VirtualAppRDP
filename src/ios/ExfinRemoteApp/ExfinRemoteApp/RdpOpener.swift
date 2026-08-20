import Foundation
import UIKit

enum RdpOpener {
    static let rdClientStore = URL(string: "https://apps.apple.com/app/microsoft-remote-desktop/id714464092")!

    static var isRdClientInstalled: Bool {
        UIApplication.shared.canOpenURL(URL(string: "rdp://")!)
    }

    static func saveRdp(fileName: String, content: String) throws -> URL {
        let safe = fileName.replacingOccurrences(of: "[^A-Za-z0-9._-]", with: "_", options: .regularExpression)
        let name = safe.isEmpty ? "app.rdp" : safe
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let text = content.replacingOccurrences(of: "\n", with: "\r\n")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static func open(fileURL: URL) {
        DispatchQueue.main.async {
            if UIApplication.shared.canOpenURL(fileURL) {
                UIApplication.shared.open(fileURL, options: [:], completionHandler: nil)
            }
        }
    }

    static func openStore() {
        UIApplication.shared.open(rdClientStore, options: [:], completionHandler: nil)
    }

    static func openPortal(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
}
