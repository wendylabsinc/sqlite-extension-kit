# iOS Integration

Integrate SQLite extensions into iOS applications using static libraries.

## Overview

On iOS, you cannot load dynamic libraries at runtime due to App Store security restrictions. Instead, you must compile your extensions as static libraries and link them directly with SQLite into your application.

## Why Static Libraries on iOS

iOS applications cannot use SQLite's `load_extension()` API because:

1. App sandboxing prevents dynamic library loading
2. Code signing requirements restrict runtime code loading
3. App Store guidelines prohibit downloadable code execution

**Solution**: Compile extensions as static libraries and register them at app startup.

## Building a Static Library for iOS

### Step 1: Configure Package for Static Linking

Update your `Package.swift` to support static library builds:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MyExtension",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "MyExtension",
            type: .static,  // Changed to static
            targets: ["MyExtension"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/yourusername/SQLiteExtensionKit", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "MyExtension",
            dependencies: ["SQLiteExtensionKit"]
        )
    ]
)
```

### Step 2: Create a Registration Function

Instead of using `@_cdecl` for dynamic loading, create a Swift-callable registration function:

```swift
import SQLiteExtensionKit
import CSQLite

public struct MyExtension: SQLiteExtensionModule {
    public static let name = "my_extension"

    public static func register(with db: SQLiteDatabase) throws {
        try db.createScalarFunction(name: "my_func") { context, args in
            // Implementation
            context.result("Hello from iOS!")
        }
    }
}

/// Call this function at app startup to register the extension
public func registerMyExtension(with db: OpaquePointer) throws {
    let database = SQLiteDatabase(db)
    try MyExtension.register(with: database)
}
```

### Step 3: Build for iOS Architectures

Build for both simulator and device:

```bash
# Build for iOS Simulator (arm64)
swift build -c release \
  --triple arm64-apple-ios16.0-simulator

# Build for iOS Device (arm64)
swift build -c release \
  --triple arm64-apple-ios16.0

# Build universal binary (if needed)
lipo -create \
  .build/arm64-apple-ios16.0-simulator/release/libMyExtension.a \
  .build/arm64-apple-ios16.0/release/libMyExtension.a \
  -output libMyExtension-universal.a
```

### Step 4: Integrate into iOS Project

#### Using Swift Package Manager in Xcode

1. In Xcode, go to **File > Add Packages...**
2. Add your extension package
3. Select your target and add the package as a dependency

#### Using CocoaPods

Create a `MyExtension.podspec`:

```ruby
Pod::Spec.new do |s|
  s.name             = 'MyExtension'
  s.version          = '1.0.0'
  s.summary          = 'SQLite extension for iOS'
  s.homepage         = 'https://github.com/yourusername/MyExtension'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Your Name' => 'email@example.com' }
  s.source           = { :git => 'https://github.com/yourusername/MyExtension.git', :tag => s.version.to_s }

  s.ios.deployment_target = '16.0'
  s.swift_version = '6.0'

  s.source_files = 'Sources/MyExtension/**/*.swift'
  s.dependency 'SQLiteExtensionKit'

  s.libraries = 'sqlite3'
end
```

### Step 5: Register at App Startup

In your iOS app, register the extension when opening the database:

```swift
import UIKit
import SQLite3
import MyExtension

class DatabaseManager {
    private var db: OpaquePointer?

    func openDatabase() throws {
        let path = try FileManager.default
            .url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("app.db")
            .path

        guard sqlite3_open(path, &db) == SQLITE_OK else {
            throw DatabaseError.cannotOpen
        }

        // Register the extension immediately after opening
        try registerMyExtension(with: db!)

        // Now you can use the extension functions
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, "SELECT my_func()", -1, &stmt, nil)
        sqlite3_step(stmt)
        let result = String(cString: sqlite3_column_text(stmt, 0))
        print("Extension result: \(result)")
        sqlite3_finalize(stmt)
    }
}
```

## Using with GRDB or SQLite.swift

### GRDB Integration

```swift
import GRDB
import MyExtension

let dbQueue = try DatabaseQueue(path: "/path/to/database.db")

try dbQueue.write { db in
    // Register extension with GRDB's database connection
    try registerMyExtension(with: db.sqliteConnection)

    // Use the extension
    let result = try String.fetchOne(db, sql: "SELECT my_func()")
    print(result)
}
```

### SQLite.swift Integration

```swift
import SQLite
import MyExtension

let db = try Connection("/path/to/database.db")

// Get the raw sqlite3 pointer
let handle = db.handle
try registerMyExtension(with: handle)

// Use the extension
let result = try db.scalar("SELECT my_func()") as! String
```

## Linking with Embedded SQLite

If you're embedding a custom SQLite build in your iOS app:

### Step 1: Build SQLite as a Framework

```bash
# Download SQLite amalgamation
curl -O https://www.sqlite.org/2024/sqlite-amalgamation-3450000.zip
unzip sqlite-amalgamation-3450000.zip

# Create Xcode framework project with sqlite3.c and sqlite3.h
# Or use existing SQLite framework
```

### Step 2: Link Your Extension

In your Xcode project:

1. Add `libMyExtension.a` to your target
2. Link against your SQLite framework
3. Ensure both are linked in the same binary

### Step 3: Verify Linking

```bash
# Check that symbols are present
nm libMyExtension.a | grep "my_func"

# Verify no duplicate symbols with SQLite
nm -gU YourApp | grep sqlite3
```

## Testing on iOS

Create unit tests that verify extension functionality:

```swift
import XCTest
import SQLite3
@testable import MyExtension

class MyExtensionTests: XCTestCase {
    var db: OpaquePointer?

    override func setUp() {
        super.setUp()
        sqlite3_open(":memory:", &db)
        try? registerMyExtension(with: db!)
    }

    override func tearDown() {
        sqlite3_close(db)
        super.tearDown()
    }

    func testMyFunction() throws {
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, "SELECT my_func()", -1, &stmt, nil)
        sqlite3_step(stmt)

        let result = String(cString: sqlite3_column_text(stmt, 0))
        XCTAssertEqual(result, "Hello from iOS!")

        sqlite3_finalize(stmt)
    }
}
```

## Common Issues

### Symbol Conflicts

If you get duplicate symbol errors:

```
duplicate symbol '_sqlite3_open' in:
    libMyExtension.a
    libsqlite3.dylib
```

**Solution**: Ensure you're not linking both the system SQLite and your extension's SQLite symbols. Use `-force_load` selectively:

```bash
# In Xcode build settings
OTHER_LDFLAGS = -force_load $(BUILD_DIR)/libMyExtension.a
```

### Extension Not Found

If functions return "no such function" errors:

1. Verify registration is called before using functions
2. Check that registration completed without errors
3. Ensure the database connection is the same instance

### Memory Issues

If you encounter crashes:

1. Ensure database outlives all extension usage
2. Don't capture database pointer in closures
3. Use proper memory management for aggregate context

## Performance Considerations

Static linking has performance benefits:

- **Faster startup**: No runtime loading overhead
- **Better optimization**: Linker can inline across boundaries
- **Smaller binary**: Dead code elimination works better

## App Store Submission

Ensure compliance when submitting:

1. Include all required architectures (arm64 for devices)
2. Remove simulator architectures from release builds
3. Properly sign all embedded libraries
4. Document third-party code usage

## Next Steps

- See <doc:AndroidIntegration> for similar static library approach on Android
- Learn about <doc:DeploymentGuide> for other platforms
- Explore <doc:AdvancedFunctions> for complex extension features
