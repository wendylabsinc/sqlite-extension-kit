import CSQLite
import Foundation

/// Represents the execution context for a SQLite function.
///
/// Use this type to return results from your custom SQLite functions and to access
/// function metadata and auxiliary data.
///
/// ## Topics
/// ### Returning Results
/// - ``result(_:)-9ca21``
/// - ``result(_:)-8x7td``
/// - ``result(_:)-3bt8o``
/// - ``result(_:)-5yh2z``
/// - ``resultNull()``
/// - ``resultError(_:)``
///
/// ### Accessing Metadata
/// - ``database``
public struct SQLiteContext: @unchecked Sendable {
    /// The underlying SQLite context pointer.
    public let pointer: OpaquePointer

    /// Creates a SQLite context wrapper.
    ///
    /// - Parameter pointer: The underlying `sqlite3_context` pointer.
    init(_ pointer: OpaquePointer) {
        self.pointer = pointer
    }

    /// The database connection associated with this context.
    public var database: OpaquePointer {
        sqlite3_context_db_handle(pointer)
    }

    // MARK: - Result Methods

    /// Sets the result to an integer value.
    ///
    /// ## Example
    /// ```swift
    /// func doubleValue(context: SQLiteContext, args: [SQLiteValue]) throws {
    ///     let value = args[0].intValue
    ///     context.result(value * 2)
    /// }
    /// ```
    ///
    /// - Parameter value: The integer result to return.
    public func result(_ value: Int64) {
        sqlite3_result_int64(pointer, value)
    }

    /// Sets the result to a double value.
    ///
    /// ## Example
    /// ```swift
    /// func squareRoot(context: SQLiteContext, args: [SQLiteValue]) throws {
    ///     let value = args[0].doubleValue
    ///     context.result(sqrt(value))
    /// }
    /// ```
    ///
    /// - Parameter value: The double result to return.
    public func result(_ value: Double) {
        sqlite3_result_double(pointer, value)
    }

    /// Sets the result to a text value.
    ///
    /// ## Example
    /// ```swift
    /// func uppercase(context: SQLiteContext, args: [SQLiteValue]) throws {
    ///     let text = args[0].textValue
    ///     context.result(text.uppercased())
    /// }
    /// ```
    ///
    /// - Parameter value: The text result to return.
    public func result(_ value: String) {
        value.withCString { cString in
            let length = Int32(value.utf8.count)
            sqlite3_result_text(pointer, cString, length, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
    }

    /// Sets the result to a blob (binary data) value.
    ///
    /// ## Example
    /// ```swift
    /// func reverseBlob(context: SQLiteContext, args: [SQLiteValue]) throws {
    ///     let data = args[0].blobValue
    ///     context.result(Data(data.reversed()))
    /// }
    /// ```
    ///
    /// - Parameter value: The blob data result to return.
    public func result(_ value: Data) {
        value.withUnsafeBytes { bytes in
            sqlite3_result_blob(
                pointer,
                bytes.baseAddress,
                Int32(value.count),
                unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            )
        }
    }

    /// Sets the result to NULL.
    ///
    /// ## Example
    /// ```swift
    /// func conditionalValue(context: SQLiteContext, args: [SQLiteValue]) throws {
    ///     if args[0].isNull {
    ///         context.resultNull()
    ///     } else {
    ///         context.result(args[0].intValue)
    ///     }
    /// }
    /// ```
    public func resultNull() {
        sqlite3_result_null(pointer)
    }

    /// Sets the result to an error with the given message.
    ///
    /// ## Example
    /// ```swift
    /// func divide(context: SQLiteContext, args: [SQLiteValue]) throws {
    ///     let divisor = args[1].doubleValue
    ///     if divisor == 0 {
    ///         context.resultError("Division by zero")
    ///         return
    ///     }
    ///     context.result(args[0].doubleValue / divisor)
    /// }
    /// ```
    ///
    /// - Parameter message: The error message to return.
    public func resultError(_ message: String) {
        message.withCString { cString in
            sqlite3_result_error(pointer, cString, -1)
        }
    }

    /// Sets the result to an error code.
    ///
    /// - Parameter code: The SQLite error code to return.
    public func resultErrorCode(_ code: Int32) {
        sqlite3_result_error_code(pointer, code)
    }
}
