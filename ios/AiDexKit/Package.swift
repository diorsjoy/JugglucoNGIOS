// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AiDexKit",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "AiDexKit", targets: ["AiDexKit"]),
    ],
    targets: [
        .target(name: "AiDexKit"),
        .executableTarget(name: "AiDexKitSelfCheck", dependencies: ["AiDexKit"]),
        // Real CoreBluetooth scan/connect against a physical AiDex sensor.
        // Run: swift run AiDexLiveScan <serial-number>
        .executableTarget(name: "AiDexLiveScan", dependencies: ["AiDexKit"]),
    ]
)
