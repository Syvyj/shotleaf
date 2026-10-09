// swift-tools-version: 6.1
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
    dependencies: [
        // On-device model (ADR-0006). The FoundationModels bridge needs the
        // macOS 27 SDK, so that trait is off.
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", .upToNextMinor(from: "3.32.3"), traits: []),
        .package(url: "https://github.com/ml-explore/mlx-swift", .upToNextMinor(from: "0.32.3")),
        .package(url: "https://github.com/huggingface/swift-huggingface", from: "0.9.0"),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.3.0"),
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
        // The built-in model: Gemma 4 E2B on MLX. Heavy dependencies stay here.
        .target(
            name: "EmbeddedKit",
            dependencies: [
                "Core",
                .product(name: "MLXVLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
                .product(name: "Tokenizers", package: "swift-transformers"),
            ]
        ),

        // App composition layer (the only module that knows everything). The
        // .xcodeproj app target links this; `swift build` also compiles it so
        // App Shell logic is verified headlessly.
        .target(
            name: "AppFeature",
            dependencies: [
                "Core", "InferenceKit", "ContextKit", "CaptureKit",
                "PerceptionKit", "ActionKit", "SettingsKit", "EmbeddedKit",
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
        .testTarget(name: "AppFeatureTests", dependencies: ["AppFeature", "PerceptionKit"]),
        .testTarget(name: "PerceptionKitTests", dependencies: ["Core", "PerceptionKit", "CaptureKit"]),
    ]
)
