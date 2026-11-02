// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Drift",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Drift", targets: ["Drift"])],
    targets: [
        .target(name: "DriftCore"),
        .executableTarget(name: "Drift", dependencies: ["DriftCore"], resources: [.copy("Resources")]),
        .testTarget(name: "DriftCoreTests", dependencies: ["DriftCore"])
    ],
    swiftLanguageModes: [.v5]
)
