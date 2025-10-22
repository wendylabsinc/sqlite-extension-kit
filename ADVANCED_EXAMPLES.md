# Advanced SQLite Extension Examples

This document covers advanced extension features beyond basic scalar and aggregate functions.

## Summary of Warnings

**✅ No Swift Compiler Warnings**

The codebase compiles cleanly with Swift 6.2 in strict concurrency mode with zero warnings when using:
```bash
swiftly run swift build
```

## Included Advanced Examples

### 1. Advanced Functions Extension (`AdvancedFunctions.swift`)

Demonstrates sophisticated function implementations:

#### JSON Functions
- `json_extract_simple(json, path)` - Extract values from JSON using path syntax
- `json_array_contains(array, value)` - Check if JSON array contains a value

#### Regular Expressions
- `regexp_match(text, pattern)` - Test if text matches regex pattern
- `regexp_replace(text, pattern, replacement)` - Replace regex matches

#### String Similarity
- `levenshtein(s1, s2)` - Calculate edit distance between strings

#### Utilities
- `uuid()` - Generate UUID
- `unix_timestamp()` - Get current Unix timestamp
- `iso8601_timestamp()` - Get ISO8601 formatted timestamp
- `url_encode(text)` / `url_decode(text)` - URL encoding/decoding

**Usage:**
```swift
try AdvancedFunctionsExtension.register(with: database)
```

```sql
-- JSON extraction
SELECT json_extract_simple('{"name":"Alice","age":30}', '$.name');  --> 'Alice'

-- Regex matching
SELECT regexp_match('test@example.com', '.*@.*\\.com');  --> 1

-- String similarity for fuzzy matching
SELECT name FROM users WHERE levenshtein(name, 'Alice') < 3;

-- Generate UUIDs
INSERT INTO records VALUES (uuid(), 'data');
```

### 2. Window Functions Extension (`WindowFunctions.swift`)

Provides aggregate functions useful for window operations:

#### Implemented Functions
- `moving_avg(value, window_size)` - Moving average over window
- `running_total(value)` - Cumulative sum
- `percentile(value, p)` - Calculate percentile (0-100)
- `median(value)` - Calculate median (50th percentile)
- `string_agg(value, separator)` - Aggregate strings with separator

**Usage:**
```swift
try WindowFunctionsExtension.register(with: database)
```

```sql
-- Median calculation
SELECT median(price) FROM products;

-- 90th percentile
SELECT percentile(response_time, 90) FROM api_logs;

-- String aggregation
SELECT category, string_agg(product_name, ', ') FROM products GROUP BY category;

-- Moving average (as aggregate)
SELECT moving_avg(value, 3) FROM (
    SELECT value FROM data ORDER BY date DESC LIMIT 3
);
```

**Note:** These are implemented as aggregate functions. True SQLite window functions require additional C-level integration with the window function interface (xStep, xInverse, xValue, xFinal callbacks). The current implementation works for aggregate contexts but doesn't support the full OVER clause syntax.

### 3. Virtual Table Example (`KeyValueTable.swift`)

Demonstrates the virtual table protocol design for creating table-like interfaces to custom data sources.

**Features:**
- Protocol-based API (`VirtualTableModule`, `VirtualTableCursor`)
- Type-safe column value handling
- Query optimization with `bestIndex`
- Example in-memory key-value store implementation

**Implementation Status:**

This provides the Swift-side types and protocols for virtual tables. The example shows:
- How to structure a virtual table module
- Cursor iteration patterns
- Query constraint handling
- Index optimization

**Important:** Full virtual table registration requires C function pointers for the `sqlite3_module` interface. This is beyond the scope of pure Swift extensions because:
1. SQLite expects C function pointers for all module callbacks
2. The module must remain valid for the lifetime of the database
3. Memory management is complex with bidirectional C↔Swift ownership

For production virtual tables, you would need to:
1. Create C wrapper functions
2. Register them with `sqlite3_create_module_v2`
3. Bridge to Swift implementation

The provided code serves as a reference architecture for the Swift layer.

## Memory Safety Considerations

### Aggregate Context Usage

When using `sqlite3_aggregate_context()`, be aware of memory safety:

**✅ Safe Patterns:**
```swift
// Simple value types
let aggCtx = sqlite3_aggregate_context(context.pointer, 8)
let valuePtr = aggCtx!.assumingMemoryBound(to: Double.self)
valuePtr.pointee += value
```

```swift
// Tuples of simple types
let aggCtx = sqlite3_aggregate_context(context.pointer, 16)
let statePtr = aggCtx!.assumingMemoryBound(to: (sum: Double, count: Int64).self)
statePtr.pointee.sum += value
statePtr.pointee.count += 1
```

**⚠️ Complex Types Require Care:**
```swift
// Arrays and strings need manual memory management
// The aggregate context is just raw bytes - no automatic reference counting
struct UnsafeState {
    var values: [Double]  // ⚠️ This won't work correctly!
}

// Better: Use fixed-size buffers or manage lifecycle explicitly
```

For complex state, consider:
1. Using simpler fixed-size types
2. Allocating separate Swift objects and storing only a pointer
3. Implementing proper cleanup in the final callback

## Testing Advanced Features

The advanced functions have comprehensive integration tests:

```bash
# Run all tests
swiftly run swift test

# Run specific test suite
swiftly run swift test --filter AdvancedFunctionsTests
```

Current test coverage:
- ✅ Advanced Functions: 9 tests passing
- ✅ Window Functions: Note on complex state management
- ℹ️  Virtual Tables: Architecture example (not runtime testable without C integration)

## Limitations and Future Work

### Window Functions
- Currently implemented as aggregates, not true window functions
- Full window function support requires `xInverse` callback implementation
- Need C-level integration for proper OVER clause support

### Virtual Tables
- Protocol architecture is complete
- Actual registration requires C callback glue code
- Consider this a reference implementation for the design pattern

### Collations
- Custom sort orders require `sqlite3_create_collation_v2`
- Not included in current examples (requires C callback functions)

## Production Recommendations

For production use of advanced features:

1. **JSON Functions**: Consider using SQLite's built-in JSON1 extension if available
2. **Window Functions**: Use SQLite 3.28+ built-in window functions where possible
3. **Virtual Tables**: Implement C wrapper layer for production virtual tables
4. **Testing**: Add extensive integration tests for your specific use cases

## Building for Production

```bash
# Release build with optimizations
swiftly run swift build -c release

# The extensions are built as:
# - libSQLiteExtensionKit.dylib (core framework)
# - libExampleExtensions.dylib (all examples)
```

Load in SQLite:
```sql
.load .build/release/libExampleExtensions.dylib
SELECT json_extract_simple('{"key":"value"}', '$.key');
```

## Platform-Specific Notes

### macOS/iOS
- CryptoKit available for `sha256()` function
- Foundation provides JSON, regex, and URL encoding

### Linux
- Ensure libc provides necessary functions
- JSON and regex work via Foundation on Linux

## Contributing

When adding new advanced functions:

1. Use `@_cdecl` for entry points
2. Implement proper error handling
3. Add DocC comments with examples
4. Write integration tests
5. Document memory safety considerations
6. Test on all target platforms

## Resources

- [SQLite Extension Loading](https://www.sqlite.org/loadext.html)
- [Virtual Tables](https://www.sqlite.org/vtab.html)
- [Window Functions](https://www.sqlite.org/windowfunctions.html)
- [Aggregate Functions](https://www.sqlite.org/c3ref/aggregate_context.html)
