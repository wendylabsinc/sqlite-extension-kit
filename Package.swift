// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

#if swift(>=6.0)
let strictConcurrencySettings: [SwiftSetting] = []
#else
let strictConcurrencySettings: [SwiftSetting] = [
    .enableUpcomingFeature("StrictConcurrency")
]
#endif

let commonSwiftSettings: [SwiftSetting] = strictConcurrencySettings + [
    .enableExperimentalFeature("AccessLevelOnImport")
]

let cursorSwiftSettings: [SwiftSetting] = strictConcurrencySettings

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
        .executable(
            name: "LinuxDockerDemo",
            targets: ["LinuxDockerDemo"]
        ),
    ],
    dependencies: [],
    targets: [
        // The main SQLiteExtensionKit target
        .target(
            name: "SQLiteExtensionKit",
            dependencies: ["CSQLite"],
            swiftSettings: commonSwiftSettings
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
            swiftSettings: cursorSwiftSettings
        ),
        .executableTarget(
            name: "LinuxDockerDemo",
            dependencies: ["SQLiteExtensionKit", "ExampleExtensions"],
            path: "Examples/LinuxDockerApp",
            swiftSettings: cursorSwiftSettings
        ),

        // Unit tests
        .testTarget(
            name: "SQLiteExtensionKitTests",
            dependencies: ["SQLiteExtensionKit"],
            swiftSettings: cursorSwiftSettings
        ),

        // Integration tests
        .testTarget(
            name: "IntegrationTests",
            dependencies: ["SQLiteExtensionKit", "ExampleExtensions"],
            swiftSettings: cursorSwiftSettings
        ),
    ],
    swiftLanguageModes: [.v6]
)
