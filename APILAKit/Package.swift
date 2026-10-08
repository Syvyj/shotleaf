// swift-tools-version: 6.0
import PackageDescription

// APILA — macOS AI Productivity Suite.
// Single package, many targets: the compiler enforces module boundaries
// (a target sees only what it declares in `dependencies`) without the
// ceremony of N separate packages. The macOS app itself lives in APILA.xcodeproj
// as a thin target that links this package's `AppFeature` product — that gives
// us a signable .app bundle for TCC permissions while keeping all logic here.
// See ARCHITECTURE_DECISIONS.md.
let package = Package(
    name: "APILA",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "inference-demo", targets: ["InferenceDemo"]),
        .library(name: "Core", targets: ["Core"]),
        .library(name: "InferenceKit", targets: ["InferenceKit"]),
        .library(name: "ContextKit", targets: ["ContextKit"]),
        .library(name: "CaptureKit", targets: ["CaptureKit"]),
        .library(name: "PerceptionKit", targets: ["PerceptionKit"]),
        .library(name: "ActionKit", targets: ["ActionKit"]),
        .library(name: "SettingsKit", targets: ["SettingsKit"]),
        .library(name: "AppFeature", targets: ["AppFeature"]),
    ],
    targets: [
        // Foundation-only contracts and domain types. Depends on nothing.
        .target(name: "Core"),

        // Feature modules — each depends ONLY on Core, never on each other.
        .target(name: "InferenceKit", dependencies: ["Core"]),
        .target(name: "ContextKit", dependencies: ["Core"]),
        .target(name: "CaptureKit", dependencies: ["Core"]),
        .target(name: "PerceptionKit", dependencies: ["Core"]),
        .target(name: "ActionKit", dependencies: ["Core"]),
        .target(name: "SettingsKit", dependencies: ["Core"]),

        // App composition layer (the only module that knows everything). The
        // .xcodeproj app target links this; `swift build` also compiles it so
        // App Shell logic is verified headlessly.
        .target(
            name: "AppFeature",
            dependencies: [
                "Core", "InferenceKit", "ContextKit",
                "PerceptionKit", "ActionKit", "SettingsKit",
            ]
        ),

        // Network-free runnable proof of the InferenceKit path.
        .executableTarget(
            name: "InferenceDemo",
            dependencies: ["Core", "InferenceKit", "ActionKit"]
        ),

        .testTarget(name: "CoreTests", dependencies: ["Core", "SettingsKit"]),
        .testTarget(name: "InferenceKitTests", dependencies: ["Core", "InferenceKit", "ActionKit"]),
        .testTarget(name: "ContextKitTests", dependencies: ["Core", "ContextKit"]),
    ]
)
