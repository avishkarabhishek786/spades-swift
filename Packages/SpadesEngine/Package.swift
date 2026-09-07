// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SpadesEngine",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SpadesEngine", targets: ["SpadesEngine"])
    ],
    targets: [
        .target(
            name: "SpadesEngine",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "SpadesEngineTests",
            dependencies: ["SpadesEngine"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
