# SQLiteExtensionKit

[![Swift Package Index](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fwendylabsinc%2Fsqlite-extension-kit%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/wendylabsinc/sqlite-extension-kit)
[![Platforms](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fwendylabsinc%2Fsqlite-extension-kit%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/wendylabsinc/sqlite-extension-kit)
[![Documentation](https://swiftpackageindex.com/wendylabsinc/sqlite-extension-kit/badge.svg)](https://swiftpackageindex.com/wendylabsinc/sqlite-extension-kit/documentation)

A modern, Swift-ergonomic package for building SQLite loadable extensions with full support for Apple platforms, macOS, and Linux.

[![iOS](https://img.shields.io/badge/iOS-18.0+-blue.svg)](https://developer.apple.com/ios/)
[![macOS](https://img.shields.io/badge/macOS-15.0+-blue.svg)](https://developer.apple.com/macos/)
[![tvOS](https://img.shields.io/badge/tvOS-18.0+-blue.svg)](https://developer.apple.com/tvos/)
[![watchOS](https://img.shields.io/badge/watchOS-11.0+-blue.svg)](https://developer.apple.com/watchos/)
[![Linux](https://img.shields.io/badge/Linux-Ubuntu%20|%20Debian-orange.svg)](https://www.linux.org/)
[![Swift](https://img.shields.io/badge/Swift-6.0+-orange.svg)](https://swift.org)

**Deployment Guides Available**: Comprehensive guides for Android (JNI wrapper approach) and Windows (DLL compilation) integration are available in the [DocC documentation](#documentation). Generate locally with `swift package generate-documentation` or view online (when published).

## Features

- **Type-safe API**: Swift-native types with comprehensive error handling
- **Easy Extension Creation**: Protocol-based design for creating loadable extensions
- **Scalar Functions**: Register custom functions that return single values
- **Aggregate Functions**: Implement custom aggregations with stateful processing
- **Comprehensive Documentation**: Full DocC documentation with examples
- **Thoroughly Tested**: Unit and integration tests covering all functionality
- **Cross-platform**: Works on macOS, iOS, and Linux

## Requirements

- Swift 6.0 or later
- SQLite 3.x
- Platforms: macOS 15+, iOS 18+, tvOS 18+, watchOS 11+, Linux

## Installation

### Swift Package Manager

Add SQLiteExtensionKit to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/wendylabsinc/sqlite-extension-kit", from: "0.0.3")
]
```

## Quick Start

### Creating a Simple Extension

```swift
import SQLiteExtensionKit

public struct MyExtension: SQLiteExtensionModule {
    public static let name = "my_extension"

    public static func register(with db: SQLiteDatabase) throws {
        // Register a scalar function
        try db.createScalarFunction(name: "double") { context, args in
            guard let first = args.first else {
                context.resultNull()
                return
            }
            context.result(first.intValue * 2)
        }
    }
}

// Export the entry point
@_cdecl("sqlite3_myextension_init")
public func sqlite3_myextension_init(
    db: OpaquePointer?,
    pzErrMsg: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?,
    pApi: UnsafePointer<sqlite3_api_routines>?
) -> Int32 {
    return MyExtension.entryPoint(db: db, pzErrMsg: pzErrMsg, pApi: pApi)
}
```

If you need to customise the entry point manually, call
`initializeExtensionIfNeeded(pApi)` before interacting with any SQLite APIs to ensure the
extension table is initialised.

### Building Your Extension

```bash
# Build the extension as a dynamic library
swift build -c release

# The extension will be built as a .dylib (macOS) or .so (Linux)
```

### Using Your Extension in SQLite

```sql
-- Load the extension
.load .build/release/libMyExtension.dylib

-- Use the function
SELECT double(21);  -- Returns 42
```

## Examples

### String Manipulation Functions

```swift
try db.createScalarFunction(name: "reverse", argumentCount: 1, deterministic: true) { context, args in
    guard let first = args.first else {
        context.resultNull()
        return
    }

    let text = first.textValue
    context.result(String(text.reversed()))
}
```

Usage:
```sql
SELECT reverse('hello');  -- Returns 'olleh'
```

### Mathematical Functions

```swift
try db.createScalarFunction(name: "power", argumentCount: 2, deterministic: true) { context, args in
    guard args.count == 2 else {
        context.resultError("power() requires exactly 2 arguments")
        return
    }

    let base = args[0].doubleValue
    let exponent = args[1].doubleValue
    context.result(pow(base, exponent))
}
```

Usage:
```sql
SELECT power(2, 8);  -- Returns 256.0
```

### Aggregate Functions

```swift
try db.createAggregateFunction(
    name: "product",
    argumentCount: 1,
    step: { context, args in
        guard let first = args.first else { return }

        let value = first.doubleValue
        context.withAggregateValue(initialValue: (product: 1.0, count: Int64(0))) { state in
            if state.count == 0 {
                state.product = value
            } else {
                state.product *= value
            }
            state.count += 1
        }
    },
    final: { context in
        if !context.withExistingAggregateValue((product: Double, count: Int64).self, clearOnExit: true, { state in
            if state.count == 0 {
                context.resultNull()
            } else {
                context.result(state.product)
            }
        }) {
            context.resultNull()
        }
    }
)
```

Usage:
```sql
SELECT product(value) FROM numbers;
```

The helpers `withAggregateValue(initialValue:)` and `withExistingAggregateValue(_:clearOnExit:_:)`
store copyable state safely and release it when you are done. For complex reference types, fall back
to ``aggregateState(create:)`` / ``existingAggregateState(_:)`` — see the window-function examples in
`Sources/ExampleExtensions/WindowFunctions.swift`.

### Virtual Tables

Register a Swift virtual table module and expose it to SQLite:

```swift
try db.registerVirtualTableModule(name: "keyvalue", module: KeyValueVirtualTable.self)
sqlite3_exec(db.pointer, "CREATE VIRTUAL TABLE kv USING keyvalue", nil, nil, nil)
```

The sample `KeyValueVirtualTable` demonstrates how to implement the required protocols; the C glue
is handled internally by SQLiteExtensionKit.

Write-enabled modules can override `update(_:)` to handle inserts, updates, and deletes:

```swift
mutating func update(_ operation: VirtualTableUpdateOperation) throws -> VirtualTableUpdateOutcome {
    switch operation {
    case let .insert(rowid, values):
        storage.insert(values, preferredRowID: rowid)
        return .handled(rowid: storage.lastInsertedRowID)
    case let .update(originalRowid, newRowid, values):
        storage.replace(rowID: originalRowid, with: values, preferredRowID: newRowid)
        return .handled(rowid: newRowid ?? originalRowid)
    case let .delete(rowid):
        storage.remove(rowID: rowid)
        return .handled(rowid: nil)
    }
}
```

Once the module is registered, ordinary SQL writes delegate back to Swift so you can manage
persistence explicitly:

```sql
INSERT INTO kv(key, value) VALUES ('city', 'Paris');
UPDATE kv SET value = 'Berlin' WHERE key = 'city';
DELETE FROM kv WHERE key = 'city';
```

## Working with Different Value Types

SQLiteExtensionKit provides type-safe access to SQLite values:

```swift
try db.createScalarFunction(name: "type_demo") { context, args in
    guard let value = args.first else {
        context.resultNull()
        return
    }

    switch value.type {
    case .integer:
        context.result("Integer: \(value.intValue)")
    case .real:
        context.result("Real: \(value.doubleValue)")
    case .text:
        context.result("Text: \(value.textValue)")
    case .blob:
        context.result("Blob with \(value.bytes) bytes")
    case .null:
        context.result("NULL value")
    }
}
```

## API Reference

### Core Types

- **`SQLiteValue`**: Represents a SQLite value (integer, real, text, blob, or null)
- **`SQLiteContext`**: The execution context for returning results from functions
- **`SQLiteDatabase`**: Wrapper for registering extensions with a database
- **`SQLiteExtensionModule`**: Protocol for defining extension modules

### Function Types

- **`ScalarFunction`**: Functions that return a single value
- **`AggregateStepFunction`**: Step function for aggregates
- **`AggregateFinalFunction`**: Finalize function for aggregates

### Error Handling

- **`SQLiteExtensionError`**: Errors that can occur during extension operations

## Example Extensions

The package includes several example extensions demonstrating various capabilities:

### StringFunctionsExtension
- `reverse(text)`: Reverse a string
- `rot13(text)`: ROT13 encoding
- `trim_all(text)`: Remove all whitespace
- `word_count(text)`: Count words in text

### MathFunctionsExtension
- `power(x, y)`: x raised to the power of y
- `factorial(n)`: Calculate factorial
- `fibonacci(n)`: Calculate nth Fibonacci number
- `product(x)`: Aggregate product
- `std_dev(x)`: Standard deviation aggregate

### DataFunctionsExtension
- `hex_encode(blob)`: Encode as hexadecimal
- `hex_decode(text)`: Decode hexadecimal
- `base64_encode(blob)`: Encode as base64
- `base64_decode(text)`: Decode base64

Platform-specific helpers:
- `sha256(data)`: SHA-256 hash (macOS/iOS only)
- `reverse_bytes(blob)`: Reverse byte order

## Linux Docker Demo

Want to see the extension loading on a Linux system that relies on the distro-provided SQLite?
Use the Docker example:

```bash
docker build -f Examples/LinuxDocker/Dockerfile -t sqlite-extension-kit-demo .
docker run --rm sqlite-extension-kit-demo
```

The container installs the system `libsqlite3`, runs the test suite, builds the `ExampleExtensions`
product in release mode, and executes the `LinuxDockerDemo` helper. The demo links against the
system library, registers the Swift string extension entry point, and executes a handful of SQL
queries to show the results.

Want to exercise the same example directly on macOS? Use the helper script, which runs the
standalone GRDB-backed executable and verifies the expected output:

```bash
Scripts/run-linuxdockerapp.sh
```

See the [GRDB integration guide](Sources/SQLiteExtensionKit/Documentation.docc/Articles/GRDBIntegration.md)
for a deeper walkthrough of how the example registers SQLiteExtensionKit within GRDB and how you can
apply the pattern in your own projects.

### AdvancedFunctionsExtension
- JSON extraction and manipulation
- Regular expression matching and replacement
- String similarity (Levenshtein distance)
- UUID generation, timestamps
- URL encoding/decoding

See the **Advanced Examples** article in the [DocC documentation](#documentation) for detailed examples.

### WindowFunctionsExtension
- Aggregate-based window-like functions
- Moving averages, percentiles, median
- String aggregation
- Running totals

See the **Advanced Examples** article in the [DocC documentation](#documentation) for detailed examples.

### Virtual Table Architecture
- Protocol-based virtual table design
- Example key-value store implementation
- Reference architecture for custom data sources

See the **Advanced Examples** article in the [DocC documentation](#documentation) for detailed examples.

## Building and Testing

```bash
# Build the package (zero warnings)
swift build

# Run all tests (54 tests in 8 suites)
swift test

# Build in release mode
swift build -c release

# Run specific tests
swift test --filter StringFunctionsTests
```

### Code Quality

- **Zero Swift compiler warnings** in strict Swift 6 concurrency mode
- **52 passing tests** with comprehensive coverage
- **Full DocC documentation** with examples
- **Thread-safe** with `@unchecked Sendable` where appropriate
- **Memory-safe** aggregate context usage patterns

## Documentation

Generate documentation using DocC:

```bash
swift package generate-documentation
```

The documentation includes comprehensive platform-specific deployment guides:
- **Android Integration**: JNI wrapper approach, Room integration, Gradle configuration
- **iOS Integration**: Static library approach, framework embedding
- **Windows Deployment**: DLL compilation, .NET integration, IIS deployment
- **Linux Deployment**: Shared object files, systemd services

## Platform-Specific Notes

### macOS/iOS
- Extensions are built as `.dylib` files
- CryptoKit is available for cryptographic functions

### Linux
- Extensions are built as `.so` files
- Ensure SQLite development headers are installed: `apt-get install libsqlite3-dev`

## Best Practices

1. **Use Deterministic Functions**: Mark functions as deterministic when they always return the same result for the same inputs
2. **Handle NULL Values**: Always check for NULL values in your functions
3. **Error Handling**: Use `context.resultError()` to report errors to SQLite
4. **Type Safety**: Use the appropriate type accessors (`.intValue`, `.textValue`, etc.)
5. **Memory Management**: Aggregate functions should properly manage their context memory

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is available under the MIT License.

## Acknowledgments

Built with Swift 6.0 for modern, safe, and ergonomic SQLite extension development.
