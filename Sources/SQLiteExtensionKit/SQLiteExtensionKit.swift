/// # SQLiteExtensionKit
///
/// A Swift package for building SQLite loadable extensions with a modern, type-safe API.
///
/// ## Overview
///
/// SQLiteExtensionKit provides a Swift-ergonomic interface for creating SQLite extensions
/// that can be loaded dynamically into SQLite databases. It supports:
///
/// - Scalar functions (functions that return a single value)
/// - Aggregate functions (functions that operate on groups of rows)
/// - Type-safe value handling
/// - Comprehensive error handling
///
/// ## Creating a Simple Extension
///
/// To create a loadable extension, implement the ``SQLiteExtensionModule`` protocol:
///
/// ```swift
/// import SQLiteExtensionKit
///
/// public struct MyExtension: SQLiteExtensionModule {
///     public static let name = "my_extension"
///
///     public static func register(with db: SQLiteDatabase) throws {
///         // Register a scalar function
///         try db.createScalarFunction(name: "double") { context, args in
///             guard let first = args.first else {
///                 context.resultNull()
///                 return
///             }
///             context.result(first.intValue * 2)
///         }
///     }
/// }
///
/// // Export the entry point
/// @_cdecl("sqlite3_myextension_init")
/// public func sqlite3_myextension_init(
///     db: OpaquePointer?,
///     pzErrMsg: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?,
///     pApi: UnsafePointer<sqlite3_api_routines>?
/// ) -> Int32 {
///     return MyExtension.entryPoint(db: db, pzErrMsg: pzErrMsg, pApi: pApi)
/// }
/// ```
///
/// ## Topics
///
/// ### Creating Extensions
/// - ``SQLiteExtensionModule``
/// - ``createExtensionEntryPoint(name:db:pzErrMsg:pApi:register:)``
///
/// ### Working with Databases
/// - ``SQLiteDatabase``
///
/// ### Function Types
/// - ``ScalarFunction``
/// - ``AggregateStepFunction``
/// - ``AggregateFinalFunction``
///
/// ### Working with Values
/// - ``SQLiteValue``
/// - ``SQLiteContext``
///
/// ### Error Handling
/// - ``SQLiteExtensionError``

@_exported import CSQLite
