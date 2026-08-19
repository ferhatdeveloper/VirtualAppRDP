// swift-tools-version: 5.9
// =====================================================================
//  Package.swift
//  Rdp Virtual Box App - macOS Native Client (SwiftUI)
//
//  Swift Package Manager manifesti. swift build / swift test komutlari
//  ile komut satiri uzerinden derlenebilir; CI runner (macos-latest)
//  tarafindan kullanilir. Xcodegen veya Xcode projesi olusturmadan da
//  .app bundle uretilebilir (bkz. build/make-dmg.sh).
//
//  Build : swift build -c release --package-path src/swift/RdpVirtualBoxApp
//  Run   : swift run RdpVirtualBoxApp
//  Test  : swift test --package-path src/swift/RdpVirtualBoxApp
// =====================================================================

import PackageDescription

let package = Package(
    name: "RdpVirtualBoxApp",
    defaultLocalization: "tr",
    platforms: [
        .macOS(.v13) // Ventura; SwiftUI Form .grouped ve modern API'ler icin
    ],
    products: [
        .executable(
            name: "RdpVirtualBoxApp",
            targets: ["RdpVirtualBoxApp"]
        ),
        .library(
            name: "RdpVirtualBoxAppCore",
            targets: ["RdpVirtualBoxAppCore"]
        )
    ],
    targets: [
        .executableTarget(
            name: "RdpVirtualBoxApp",
            dependencies: ["RdpVirtualBoxAppCore"],
            path: "Sources/RdpVirtualBoxApp",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .enableUpcomingFeature("BareSlashRegexLiterals")
            ]
        ),
        .target(
            name: "RdpVirtualBoxAppCore",
            path: "Sources/RdpVirtualBoxAppCore"
        ),
        .testTarget(
            name: "RdpVirtualBoxAppTests",
            dependencies: ["RdpVirtualBoxAppCore"],
            path: "Tests/RdpVirtualBoxAppTests",
            resources: [
                .process("Fixtures")
            ]
        )
    ]
)