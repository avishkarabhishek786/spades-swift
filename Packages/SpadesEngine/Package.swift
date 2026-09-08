// swift-tools-version: 6.0
import PackageDescription

// Two library targets, and deliberately no dependency between them.
//
// Spades rules must not be able to reach for stake tiers, and stake arithmetic
// must not be able to reach for `Trick`. A file split inside one module relies
// on discipline; a target split is enforced by the compiler for free. The app
// composes them: it maps an engine result into a `MatchOutcome` and hands that
// to the economy.
let package = Package(
    name: "SpadesEngine",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SpadesEngine", targets: ["SpadesEngine"]),
        .library(name: "SpadesEconomy", targets: ["SpadesEconomy"]),
    ],
    targets: [
        .target(
            name: "SpadesEngine",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "SpadesEconomy",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "SpadesEngineTests",
            dependencies: ["SpadesEngine"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "SpadesEconomyTests",
            dependencies: ["SpadesEconomy"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
