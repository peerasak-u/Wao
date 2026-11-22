// swift-tools-version:5.10
import PackageDescription

// Beam search is plain Swift array work: unoptimized, a 9 s clip took 5.9 s to decode instead of 0.75 s.
let optimizedInDebug: [SwiftSetting] = [.unsafeFlags(["-O"], .when(configuration: .debug))]

let package = Package(
    name: "WaoCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "WaoCore", targets: ["WaoCore"]),
        .library(name: "WaoTyping", targets: ["WaoTyping"]),
        .library(name: "WaoInference", targets: ["WaoInference"]),
        .executable(name: "wao-transcribe", targets: ["wao-transcribe"]),
        .executable(name: "wao-typing-eval", targets: ["wao-typing-eval"]),
    ],
    targets: [
        .target(name: "WaoCore", resources: [.process("Resources")], swiftSettings: optimizedInDebug),
        // Keyboard-only, so the app does not ship the typing model and emoji data a second time.
        .target(name: "WaoTyping", resources: [.process("Resources")], swiftSettings: optimizedInDebug),
        // Built by tools/fetch_onnxruntime.sh; only the app links it, never the keyboard.
        .binaryTarget(name: "onnxruntime", path: "Vendor/onnxruntime.xcframework"),
        .target(
            name: "WaoInference",
            dependencies: ["WaoCore", "onnxruntime"],
            resources: [.process("Resources")],
            swiftSettings: optimizedInDebug,
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedLibrary("z", .when(platforms: [.iOS])),
                .linkedLibrary("sqlite3", .when(platforms: [.iOS])),
                .linkedFramework("CoreML", .when(platforms: [.iOS])),
            ]
        ),
        .executableTarget(name: "wao-transcribe", dependencies: ["WaoCore", "WaoInference"]),
        .executableTarget(name: "wao-typing-eval", dependencies: ["WaoTyping"]),
        .testTarget(
            name: "WaoCoreTests",
            dependencies: ["WaoCore", "WaoTyping", "WaoInference", "wao-typing-eval"],
            exclude: ["Fixtures"]
        ),
    ]
)
