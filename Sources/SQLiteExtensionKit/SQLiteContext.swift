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

    // MARK: - Aggregate State Helpers

    /// Returns an aggregate state object, creating it if necessary.
    ///
    /// - Parameter create: Closure that produces the initial state when none exists.
    /// - Returns: The aggregate state instance.
    public func aggregateState<T: AnyObject>(create: () -> T) -> T {
        guard let storage = aggregateStateStorage(allocate: true) else {
            return create()
        }

        if let existing = storage.pointee.pointer {
            return Unmanaged<T>.fromOpaque(existing).takeUnretainedValue()
        }

        let state = create()
        storage.pointee.pointer = Unmanaged.passRetained(state).toOpaque()
        return state
    }

    /// Returns the existing aggregate state if one has been created.
    ///
    /// - Parameter type: The expected type of the state object.
    /// - Returns: The existing state or `nil` if none has been created.
    public func existingAggregateState<T: AnyObject>(_ type: T.Type) -> T? {
        guard let storage = aggregateStateStorage(allocate: false),
              let pointer = storage.pointee.pointer else {
            return nil
        }

        return Unmanaged<T>.fromOpaque(pointer).takeUnretainedValue()
    }

    /// Releases and clears an aggregate state object.
    ///
    /// - Parameter type: The type of the state object to clear.
    public func clearAggregateState<T: AnyObject>(_ type: T.Type) {
        guard let storage = aggregateStateStorage(allocate: false),
              let pointer = storage.pointee.pointer else {
            return
        }

        Unmanaged<T>.fromOpaque(pointer).release()
        storage.pointee.pointer = nil
    }

    /// Accesses a copyable aggregate state value, creating it if needed.
    ///
    /// - Parameters:
    ///   - initialValue: The initial value to assign when the state is first created.
    ///   - clearOnExit: Whether to clear the stored state after the closure finishes.
    ///   - body: Closure that mutates the state in-place.
    public func withAggregateValue<State>(
        initialValue: @autoclosure () -> State,
        clearOnExit: Bool = false,
        _ body: (inout State) throws -> Void
    ) rethrows {
        let box: AggregateValueBox<State> = aggregateState {
            AggregateValueBox(value: initialValue())
        }

        defer {
            if clearOnExit {
                clearAggregateState(AggregateValueBox<State>.self)
            }
        }

        try body(&box.value)
    }

    /// Executes the closure with an existing aggregate value if one has been created.
    ///
    /// - Parameters:
    ///   - type: The value type stored in the aggregate state.
    ///   - clearOnExit: Whether to clear the stored state after the closure finishes.
    ///   - body: Closure that receives the current value for mutation.
    /// - Returns: `true` if a state existed and the closure ran, otherwise `false`.
    @discardableResult
    public func withExistingAggregateValue<State>(
        _ type: State.Type = State.self,
        clearOnExit: Bool = false,
        _ body: (inout State) throws -> Void
    ) rethrows -> Bool {
        guard let box = existingAggregateState(AggregateValueBox<State>.self) else {
            return false
        }

        defer {
            if clearOnExit {
                clearAggregateState(AggregateValueBox<State>.self)
            }
        }

        try body(&box.value)
        return true
    }

    /// Retrieves and clears the aggregate value if it exists.
    ///
    /// - Parameter type: The value type stored in the aggregate state.
    /// - Returns: The stored value, or `nil` if none exists.
    public func takeAggregateValue<State>(_ type: State.Type = State.self) -> State? {
        guard let box = existingAggregateState(AggregateValueBox<State>.self) else {
            return nil
        }

        defer {
            clearAggregateState(AggregateValueBox<State>.self)
        }

        return box.value
    }

    private func aggregateStateStorage(
        allocate: Bool
    ) -> UnsafeMutablePointer<AggregateStateHolder>? {
        if let raw = sqlite3_aggregate_context(pointer, 0) {
            return raw.bindMemory(to: AggregateStateHolder.self, capacity: 1)
        }

        guard allocate,
              let raw = sqlite3_aggregate_context(
                  pointer,
                  Int32(MemoryLayout<AggregateStateHolder>.stride)
              ) else {
            return nil
        }

        let storage = raw.bindMemory(to: AggregateStateHolder.self, capacity: 1)
        storage.initialize(to: AggregateStateHolder(pointer: nil))
        return storage
    }

    private struct AggregateStateHolder {
        var pointer: UnsafeMutableRawPointer?
    }

    private final class AggregateValueBox<State>: @unchecked Sendable {
        var value: State

        init(value: State) {
            self.value = value
        }
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
