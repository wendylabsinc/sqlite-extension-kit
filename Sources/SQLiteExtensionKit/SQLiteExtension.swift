import CSQLite
import Foundation

/// Errors that can occur when working with SQLite extensions.
public enum SQLiteExtensionError: Error, Sendable {
    /// Failed to register a function with the given name.
    case functionRegistrationFailed(name: String, code: Int32)

    /// Invalid argument count for a function.
    case invalidArgumentCount

    /// Generic SQLite error with an error code.
    case sqliteError(code: Int32)
}

/// A type that represents a SQLite scalar function.
///
/// Scalar functions take zero or more arguments and return a single value.
///
/// ## Example
/// ```swift
/// let upperFunc: ScalarFunction = { context, args in
///     guard let first = args.first else {
///         context.resultNull()
///         return
///     }
///     context.result(first.textValue.uppercased())
/// }
/// ```
public typealias ScalarFunction = @Sendable (SQLiteContext, [SQLiteValue]) throws -> Void

/// A type that represents the step function for a SQLite aggregate.
///
/// The step function is called once for each row in the aggregation.
public typealias AggregateStepFunction = @Sendable (SQLiteContext, [SQLiteValue]) throws -> Void

/// A type that represents the finalize function for a SQLite aggregate.
///
/// The finalize function is called once at the end of the aggregation to compute the final result.
public typealias AggregateFinalFunction = @Sendable (SQLiteContext) throws -> Void

/// Represents a SQLite database connection for registering extensions.
public struct SQLiteDatabase: @unchecked Sendable {
    /// The underlying database connection pointer.
    public let pointer: OpaquePointer

    /// Creates a SQLite database wrapper.
    ///
    /// - Parameter pointer: The underlying `sqlite3` database pointer.
    public init(_ pointer: OpaquePointer) {
        self.pointer = pointer
    }

    /// Registers a scalar function with the database.
    ///
    /// Scalar functions take zero or more arguments and return a single value.
    ///
    /// ## Example
    /// ```swift
    /// try db.createScalarFunction(name: "reverse_string") { context, args in
    ///     guard let first = args.first else {
    ///         context.resultNull()
    ///         return
    ///     }
    ///     context.result(String(first.textValue.reversed()))
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - name: The name of the function as it will be used in SQL.
    ///   - argumentCount: The number of arguments the function accepts. Use -1 for variable arguments.
    ///   - deterministic: Whether the function always returns the same result for the same inputs.
    ///   - function: The function implementation.
    /// - Throws: ``SQLiteExtensionError`` if registration fails.
    public func createScalarFunction(
        name: String,
        argumentCount: Int32 = -1,
        deterministic: Bool = false,
        function: @escaping ScalarFunction
    ) throws {
        let box = FunctionBox(function: function)
        let userData = Unmanaged.passRetained(box).toOpaque()

        var flags = SQLITE_UTF8
        if deterministic {
            flags |= SQLITE_DETERMINISTIC
        }

        let result = sqlite3_create_function_v2(
            pointer,
            name,
            argumentCount,
            flags,
            userData,
            { contextPtr, argc, argv in
                guard let contextPtr = contextPtr,
                      let argv = argv else {
                    return
                }

                let context = SQLiteContext(contextPtr)
                let userData = sqlite3_user_data(contextPtr)
                let box = Unmanaged<FunctionBox>.fromOpaque(userData!).takeUnretainedValue()

                var args: [SQLiteValue] = []
                for i in 0..<Int(argc) {
                    args.append(SQLiteValue(argv[i]!))
                }

                do {
                    try box.function(context, args)
                } catch {
                    context.resultError("Function error: \(error)")
                }
            },
            nil,
            nil,
            { userData in
                guard let userData = userData else { return }
                Unmanaged<FunctionBox>.fromOpaque(userData).release()
            }
        )

        if result != SQLITE_OK {
            throw SQLiteExtensionError.functionRegistrationFailed(name: name, code: result)
        }
    }

    /// Registers an aggregate function with the database.
    ///
    /// Aggregate functions process multiple rows and return a single result.
    ///
    /// ## Example
    /// ```swift
    /// try db.createAggregateFunction(
    ///     name: "sum_squares",
    ///     step: { context, args in
    ///         // Accumulate sum of squares
    ///         let value = args[0].doubleValue
    ///         let current = context.getAggregateContext(Double.self) ?? 0.0
    ///         context.setAggregateContext(current + value * value)
    ///     },
    ///     final: { context in
    ///         let sum = context.getAggregateContext(Double.self) ?? 0.0
    ///         context.result(sum)
    ///     }
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - name: The name of the aggregate function.
    ///   - argumentCount: The number of arguments the function accepts.
    ///   - step: The step function called for each row.
    ///   - final: The finalize function called to compute the result.
    /// - Throws: ``SQLiteExtensionError`` if registration fails.
    public func createAggregateFunction(
        name: String,
        argumentCount: Int32 = -1,
        step: @escaping AggregateStepFunction,
        final: @escaping AggregateFinalFunction
    ) throws {
        let box = AggregateFunctionBox(step: step, final: final)
        let userData = Unmanaged.passRetained(box).toOpaque()

        let result = sqlite3_create_function_v2(
            pointer,
            name,
            argumentCount,
            SQLITE_UTF8,
            userData,
            nil,
            { contextPtr, argc, argv in
                guard let contextPtr = contextPtr,
                      let argv = argv else {
                    return
                }

                let context = SQLiteContext(contextPtr)
                let userData = sqlite3_user_data(contextPtr)
                let box = Unmanaged<AggregateFunctionBox>.fromOpaque(userData!).takeUnretainedValue()

                var args: [SQLiteValue] = []
                for i in 0..<Int(argc) {
                    args.append(SQLiteValue(argv[i]!))
                }

                do {
                    try box.step(context, args)
                } catch {
                    context.resultError("Aggregate step error: \(error)")
                }
            },
            { contextPtr in
                guard let contextPtr = contextPtr else { return }

                let context = SQLiteContext(contextPtr)
                let userData = sqlite3_user_data(contextPtr)
                let box = Unmanaged<AggregateFunctionBox>.fromOpaque(userData!).takeUnretainedValue()

                do {
                    try box.final(context)
                } catch {
                    context.resultError("Aggregate final error: \(error)")
                }
            },
            { userData in
                guard let userData = userData else { return }
                Unmanaged<AggregateFunctionBox>.fromOpaque(userData).release()
            }
        )

        if result != SQLITE_OK {
            throw SQLiteExtensionError.functionRegistrationFailed(name: name, code: result)
        }
    }
}

// MARK: - Internal Support Types

/// Box to hold scalar function closures
final class FunctionBox: @unchecked Sendable {
    let function: ScalarFunction

    init(function: @escaping ScalarFunction) {
        self.function = function
    }
}

/// Box to hold aggregate function closures
final class AggregateFunctionBox: @unchecked Sendable {
    let step: AggregateStepFunction
    let final: AggregateFinalFunction

    init(step: @escaping AggregateStepFunction, final: @escaping AggregateFinalFunction) {
        self.step = step
        self.final = final
    }
}
