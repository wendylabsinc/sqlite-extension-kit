// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SQLiteExtensionKit",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
        .tvOS(.v18),
        .watchOS(.v11)
    ],
    products: [
        // The main library for building SQLite extensions
        .library(
            name: "SQLiteExtensionKit",
            type: .dynamic,
            targets: ["SQLiteExtensionKit"]
        ),
        // Example extensions as executables
        .library(
            name: "ExampleExtensions",
            type: .dynamic,
            targets: ["ExampleExtensions"]
        ),
    ],
    dependencies: [],
    targets: [
        // The main SQLiteExtensionKit target
        .target(
            name: "SQLiteExtensionKit",
            dependencies: ["CSQLite"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .enableExperimentalFeature("AccessLevelOnImport")
            ]
        ),

        // C wrapper for SQLite
        .target(
            name: "CSQLite",
            dependencies: [],
            publicHeadersPath: "include"
        ),

        // Example extensions demonstrating usage
        .target(
            name: "ExampleExtensions",
            dependencies: ["SQLiteExtensionKit"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),

        // Unit tests
        .testTarget(
            name: "SQLiteExtensionKitTests",
            dependencies: ["SQLiteExtensionKit"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),

        // Integration tests
        .testTarget(
            name: "IntegrationTests",
            dependencies: ["SQLiteExtensionKit", "ExampleExtensions"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
