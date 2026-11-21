// swift-tools-version:5.10
import PackageDescription

// Beam search is plain Swift array work: unoptimized, a 9 s clip took 5.9 s to decode instead of 0.75 s.
let optimizedInDebug: [SwiftSetting] = [.unsafeFlags(["-O"], .when(configuration: .debug))]

let package = Package(
    name: "WaoCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "WaoCore", targets: ["WaoCore"]),
        .library(name: "WaoInference", targets: ["WaoInference"]),
        .executable(name: "wao-transcribe", targets: ["wao-transcribe"]),
    ],
    targets: [
        .target(name: "WaoCore", resources: [.process("Resources")], swiftSettings: optimizedInDebug),
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
        .testTarget(
            name: "WaoCoreTests",
            dependencies: ["WaoCore", "WaoInference"],
            exclude: ["Fixtures"]
        ),
    ]
)
