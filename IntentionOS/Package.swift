// swift-tools-version:5.6
import PackageDescription

let package = Package(
    name: "IntentionOS",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(name: "IntentionOS", targets: ["IntentionOS"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "IntentionOS",
            dependencies: [],
            path: "Sources"
        )
    ]
)
