// swift-tools-version: 6.1
import PackageDescription

// Shotleaf — screenshots, text from screenshots, clipboard history and snippets for macOS.
// © 2026 Oleksii Ziuzin (Syvyj). Licensed under GPL-3.0-or-later, see LICENSE.
// Single package, many targets: the compiler enforces module boundaries
// (a target sees only what it declares in `dependencies`) without the
// ceremony of N separate packages. The macOS app itself lives in Shotleaf.xcodeproj
// as a thin target that links this package's `AppFeature` product — that gives
// us a signable .app bundle for TCC permissions while keeping all logic here.
// See ARCHITECTURE_DECISIONS.md.
let package = Package(
    name: "Shotleaf",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "Core", targets: ["Core"]),
        .library(name: "CaptureKit", targets: ["CaptureKit"]),
        .library(name: "PerceptionKit", targets: ["PerceptionKit"]),
        .library(name: "SettingsKit", targets: ["SettingsKit"]),
        .library(name: "AppFeature", targets: ["AppFeature"]),
    ],
    targets: [
        // Foundation-only contracts and domain types. Depends on nothing.
        .target(name: "Core"),

        // Feature modules — each depends ONLY on Core, never on each other.
        .target(name: "CaptureKit", dependencies: ["Core"]),
        .target(name: "PerceptionKit", dependencies: ["Core"]),
        .target(name: "SettingsKit", dependencies: ["Core"]),
        // App composition layer (the only module that knows everything). The
        // .xcodeproj app target links this; `swift build` also compiles it so
        // App Shell logic is verified headlessly.
        .target(
            name: "AppFeature",
            dependencies: [
                "Core", "CaptureKit", "PerceptionKit", "SettingsKit",
            ]
        ),

        .testTarget(name: "CoreTests", dependencies: ["Core", "SettingsKit"]),
        .testTarget(name: "AppFeatureTests", dependencies: ["AppFeature", "CaptureKit", "PerceptionKit"]),
        .testTarget(name: "PerceptionKitTests", dependencies: ["Core", "PerceptionKit", "CaptureKit"]),
    ]
)
