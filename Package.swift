// swift-tools-version:5.9
// This package compiles only the platform-independent core (StageDeck/Core) so it can be
// built and tested on Linux / CI without Xcode. The iPad app itself is StageDeck.xcodeproj,
// which compiles the very same Core sources directly into the app target.
import PackageDescription

let package = Package(
    name: "StageDeckCore",
    products: [
        .library(name: "StageDeckCore", targets: ["StageDeckCore"]),
    ],
    targets: [
        .target(
            name: "StageDeckCore",
            path: "StageDeck/Core",
            swiftSettings: [.unsafeFlags(["-swift-version", "5"])]
        ),
        .testTarget(
            name: "StageDeckCoreTests",
            dependencies: ["StageDeckCore"],
            path: "Tests/StageDeckCoreTests",
            swiftSettings: [.unsafeFlags(["-swift-version", "5"])]
        ),
    ]
)
