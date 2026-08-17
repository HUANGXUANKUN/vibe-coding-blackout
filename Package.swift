// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Blackout",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "blackout", targets: ["BlackoutApp"]),
        .executable(name: "blackout-tests", targets: ["BlackoutTests"]),
    ],
    targets: [
        // Mechanism + UI. No XCTest on a Command-Line-Tools-only machine, so the
        // pure-logic pieces live here and are exercised by the BlackoutTests
        // executable instead of a test target.
        .target(name: "BlackoutKit", path: "Sources/BlackoutKit"),
        .executableTarget(name: "BlackoutApp", dependencies: ["BlackoutKit"], path: "Sources/BlackoutApp"),
        .executableTarget(name: "BlackoutTests", dependencies: ["BlackoutKit"], path: "Sources/BlackoutTests"),
    ]
)
