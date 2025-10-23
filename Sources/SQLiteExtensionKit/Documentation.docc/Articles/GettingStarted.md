# Getting Started with SQLiteExtensionKit

Learn how to build your first SQLite extension with Swift.

## Overview

SQLiteExtensionKit makes it easy to extend SQLite with custom functions written in Swift. This guide walks you through creating a simple extension, building it, and loading it into SQLite.

## Installation

### Swift Package Manager

Add SQLiteExtensionKit to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/wendylabsinc/sqlite-extension-kit", from: "0.0.1")
]
```

### Requirements

- Swift 6.0 or later
- SQLite 3.x
- Supported platforms: macOS 13+, iOS 16+, Linux

## Your First Extension

### 1. Create the Extension Module

Create a new Swift file for your extension:

```swift
import SQLiteExtensionKit

public struct MyExtension: SQLiteExtensionModule {
    public static let name = "my_extension"

    public static func register(with db: SQLiteDatabase) throws {
        // Register a simple doubling function
        try db.createScalarFunction(name: "double") { context, args in
            guard let first = args.first else {
                context.resultNull()
                return
            }
            context.result(first.intValue * 2)
        }
    }
}
```

### 2. Export the Entry Point

SQLite requires a C-compatible entry point with a specific naming convention:

```swift
@_cdecl("sqlite3_myextension_init")
public func sqlite3_myextension_init(
    db: OpaquePointer?,
    pzErrMsg: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?,
    pApi: OpaquePointer?
) -> Int32 {
    return MyExtension.entryPoint(db: db, pzErrMsg: pzErrMsg, pApi: pApi)
}
```

**Naming Convention**: The function must be named `sqlite3_<extension_name>_init` where `<extension_name>` matches your library name (lowercased).

### 3. Configure Your Package

Update your `Package.swift` to build a dynamic library:

```swift
let package = Package(
    name: "MyExtension",
    products: [
        .library(
            name: "MyExtension",
            type: .dynamic,
            targets: ["MyExtension"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/yourusername/SQLiteExtensionKit", from: "0.0.1")
    ],
    targets: [
        .target(
            name: "MyExtension",
            dependencies: ["SQLiteExtensionKit"]
        )
    ]
)
```

### 4. Build the Extension

```bash
# Build in release mode for production
swift build -c release

# The extension will be at:
# macOS: .build/release/libMyExtension.dylib
# Linux: .build/release/libMyExtension.so
```

### 5. Load and Use the Extension

#### In SQLite CLI

```sql
-- Load the extension
.load .build/release/libMyExtension.dylib

-- Use your function
SELECT double(21);  -- Returns 42
```

#### In Code

```swift
import CSQLite

var db: OpaquePointer?
sqlite3_open(":memory:", &db)

// Enable extension loading
sqlite3_enable_load_extension(db, 1)

// Load the extension
let path = ".build/release/libMyExtension.dylib"
var errMsg: UnsafeMutablePointer<CChar>?
let result = sqlite3_load_extension(db, path, nil, &errMsg)

if result != SQLITE_OK {
    print("Error loading extension: \(String(cString: errMsg!))")
    sqlite3_free(errMsg)
}

// Use the function
var stmt: OpaquePointer?
sqlite3_prepare_v2(db, "SELECT double(21)", -1, &stmt, nil)
sqlite3_step(stmt)
let result = sqlite3_column_int64(stmt, 0)  // 42
```

## Understanding Value Types

SQLiteExtensionKit provides type-safe access to SQLite values:

```swift
try db.createScalarFunction(name: "type_aware") { context, args in
    guard let value = args.first else {
        context.resultNull()
        return
    }

    switch value.type {
    case .integer:
        context.result(value.intValue * 2)
    case .real:
        context.result(value.doubleValue * 2.0)
    case .text:
        context.result(value.textValue.uppercased())
    case .blob:
        context.result(Data(value.blobValue.reversed()))
    case .null:
        context.resultNull()
    }
}
```

## Error Handling

Report errors to SQLite using the context:

```swift
try db.createScalarFunction(name: "safe_divide") { context, args in
    guard args.count == 2 else {
        context.resultError("safe_divide() requires 2 arguments")
        return
    }

    let divisor = args[1].doubleValue
    if divisor == 0 {
        context.resultError("Division by zero")
        return
    }

    context.result(args[0].doubleValue / divisor)
}
```

## Next Steps

- Learn about <doc:CreatingYourFirstExtension> in detail
- Explore deployment options in <doc:DeploymentGuide>
- See platform-specific integration for <doc:iOSIntegration> or <doc:LinuxDeployment>
