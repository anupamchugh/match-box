// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MatchInbox",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "MatchInboxCore", targets: ["MatchInboxCore"]),
        .executable(name: "match-inbox", targets: ["match-inbox"]),
        .executable(name: "MatchInboxApp", targets: ["MatchInboxApp"]),
    ],
    targets: [
        .target(name: "MatchInboxCore"),
        .target(name: "MatchInboxFoundationModels", dependencies: ["MatchInboxCore"]),
        .target(name: "MatchInboxSwiftData", dependencies: ["MatchInboxCore"]),
        .target(name: "MatchInboxCLI", dependencies: ["MatchInboxCore", "MatchInboxFoundationModels", "MatchInboxSwiftData"]),
        .executableTarget(name: "match-inbox", dependencies: ["MatchInboxCLI"]),
        .executableTarget(
            name: "MatchInboxApp",
            dependencies: ["MatchInboxCore", "MatchInboxSwiftData", "MatchInboxFoundationModels"],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "MatchInboxCoreTests", dependencies: ["MatchInboxCore"]),
        .testTarget(name: "MatchInboxCLITests", dependencies: ["MatchInboxCLI", "MatchInboxCore", "MatchInboxSwiftData"]),
        .testTarget(name: "MatchInboxFoundationModelsTests", dependencies: ["MatchInboxFoundationModels"]),
        .testTarget(name: "MatchInboxSwiftDataTests", dependencies: ["MatchInboxSwiftData"]),
    ]
)
