// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LinuxDockerApp",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "LinuxDockerApp", targets: ["LinuxDockerApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.8.0"),
        .package(path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "LinuxDockerApp",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "SQLiteExtensionKit", package: "sqlite-extension-kit"),
                .product(name: "ExampleExtensions", package: "sqlite-extension-kit")
            ],
            path: ".",
            exclude: ["Package.resolved", ".logs"],
            sources: ["main.swift"]
        )
    ]
)
