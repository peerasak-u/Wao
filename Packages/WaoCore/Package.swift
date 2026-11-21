// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "WaoCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "WaoCore", targets: ["WaoCore"]),
        .library(name: "WaoInference", targets: ["WaoInference"]),
    ],
    targets: [
        .target(name: "WaoCore"),
        // Built by tools/fetch_onnxruntime.sh; only the app links it, never the keyboard.
        .binaryTarget(name: "onnxruntime", path: "Vendor/onnxruntime.xcframework"),
        .target(
            name: "WaoInference",
            dependencies: ["WaoCore", "onnxruntime"],
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedLibrary("z", .when(platforms: [.iOS])),
                .linkedLibrary("sqlite3", .when(platforms: [.iOS])),
                .linkedFramework("CoreML", .when(platforms: [.iOS])),
            ]
        ),
        .testTarget(
            name: "WaoCoreTests",
            dependencies: ["WaoCore", "WaoInference"],
            exclude: ["Fixtures"]
        ),
    ]
)
