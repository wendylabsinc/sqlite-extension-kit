# SQLiteExtensionKit

A modern, Swift-ergonomic package for building SQLite loadable extensions with full support for Apple platforms, macOS, and Linux.

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
- Platforms: macOS 13+, iOS 16+, Linux

## Installation

### Swift Package Manager

Add SQLiteExtensionKit to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/yourusername/SQLiteExtensionKit", from: "1.0.0")
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

### Building Your Extension

```bash
# Build the extension as a dynamic library
swiftly run swift build -c release

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
        let aggCtx = sqlite3_aggregate_context(context.pointer, 8)
        let currentPtr = aggCtx!.assumingMemoryBound(to: Double.self)

        if sqlite3_aggregate_count(context.pointer) == 1 {
            currentPtr.pointee = value
        } else {
            currentPtr.pointee *= value
        }
    },
    final: { context in
        let aggCtx = sqlite3_aggregate_context(context.pointer, 8)
        let resultPtr = aggCtx!.assumingMemoryBound(to: Double.self)

        if sqlite3_aggregate_count(context.pointer) == 0 {
            context.resultNull()
        } else {
            context.result(resultPtr.pointee)
        }
    }
)
```

Usage:
```sql
SELECT product(value) FROM numbers;
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
- `sha256(data)`: SHA-256 hash (macOS/iOS only)
- `reverse_bytes(blob)`: Reverse byte order

### AdvancedFunctionsExtension (See [ADVANCED_EXAMPLES.md](ADVANCED_EXAMPLES.md))
- JSON extraction and manipulation
- Regular expression matching and replacement
- String similarity (Levenshtein distance)
- UUID generation, timestamps
- URL encoding/decoding

### WindowFunctionsExtension (See [ADVANCED_EXAMPLES.md](ADVANCED_EXAMPLES.md))
- Aggregate-based window-like functions
- Moving averages, percentiles, median
- String aggregation
- Running totals

### Virtual Table Architecture (See [ADVANCED_EXAMPLES.md](ADVANCED_EXAMPLES.md))
- Protocol-based virtual table design
- Example key-value store implementation
- Reference architecture for custom data sources

## Building and Testing

```bash
# Build the package (zero warnings)
swiftly run swift build

# Run all tests (52 tests in 7 suites)
swiftly run swift test

# Build in release mode
swiftly run swift build -c release

# Run specific tests
swiftly run swift test --filter StringFunctionsTests
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
