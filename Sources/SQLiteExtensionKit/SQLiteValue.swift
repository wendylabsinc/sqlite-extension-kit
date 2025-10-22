import CSQLite
import Foundation

/// Represents a SQLite value type.
///
/// SQLite values can be one of five types: integer, real, text, blob, or null.
///
/// ## Topics
/// ### Value Types
/// - ``ValueType``
///
/// ### Accessing Values
/// - ``intValue``
/// - ``doubleValue``
/// - ``textValue``
/// - ``blobValue``
/// - ``isNull``
public struct SQLiteValue: @unchecked Sendable {
    /// The underlying SQLite value pointer.
    let pointer: OpaquePointer

    /// Creates a SQLite value wrapper.
    ///
    /// - Parameter pointer: The underlying `sqlite3_value` pointer.
    init(_ pointer: OpaquePointer) {
        self.pointer = pointer
    }

    /// The type of the SQLite value.
    ///
    /// ## Example
    /// ```swift
    /// let value: SQLiteValue = ...
    /// switch value.type {
    /// case .integer:
    ///     print("Integer: \(value.intValue)")
    /// case .real:
    ///     print("Real: \(value.doubleValue)")
    /// case .text:
    ///     print("Text: \(value.textValue)")
    /// case .blob:
    ///     print("Blob with \(value.blobValue.count) bytes")
    /// case .null:
    ///     print("NULL value")
    /// }
    /// ```
    public var type: ValueType {
        ValueType(rawValue: sqlite3_value_type(pointer)) ?? .null
    }

    /// Returns `true` if the value is NULL.
    public var isNull: Bool {
        type == .null
    }

    /// Returns the value as an integer.
    ///
    /// If the value is not an integer, SQLite will attempt to convert it.
    public var intValue: Int64 {
        sqlite3_value_int64(pointer)
    }

    /// Returns the value as a double.
    ///
    /// If the value is not a real number, SQLite will attempt to convert it.
    public var doubleValue: Double {
        sqlite3_value_double(pointer)
    }

    /// Returns the value as text.
    ///
    /// Returns an empty string if the value is NULL or cannot be converted to text.
    public var textValue: String {
        guard let cString = sqlite3_value_text(pointer) else {
            return ""
        }
        return String(cString: cString)
    }

    /// Returns the value as a blob (binary data).
    ///
    /// Returns empty data if the value is NULL or cannot be converted to a blob.
    public var blobValue: Data {
        let bytes = sqlite3_value_blob(pointer)
        let count = Int(sqlite3_value_bytes(pointer))

        guard count > 0, let bytes = bytes else {
            return Data()
        }

        return Data(bytes: bytes, count: count)
    }

    /// The size of the value in bytes.
    public var bytes: Int {
        Int(sqlite3_value_bytes(pointer))
    }
}

extension SQLiteValue {
    /// Represents the type of a SQLite value.
    public enum ValueType: Int32, Sendable {
        /// Integer value (64-bit signed integer).
        case integer = 1  // SQLITE_INTEGER

        /// Floating-point value (64-bit IEEE floating point).
        case real = 2     // SQLITE_FLOAT

        /// Text value (UTF-8 string).
        case text = 3     // SQLITE_TEXT

        /// Binary large object.
        case blob = 4     // SQLITE_BLOB

        /// NULL value.
        case null = 5     // SQLITE_NULL
    }
}
