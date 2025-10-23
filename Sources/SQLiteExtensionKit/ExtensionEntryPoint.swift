import CSQLite
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// A protocol that defines a SQLite extension module.
///
/// Implement this protocol to create a loadable SQLite extension.
///
/// ## Example
/// ```swift
/// public struct MyExtension: SQLiteExtensionModule {
///     public static let name = "my_extension"
///
///     public static func register(with db: SQLiteDatabase) throws {
///         try db.createScalarFunction(name: "my_func") { context, args in
///             context.result("Hello from my extension!")
///         }
///     }
/// }
///
/// @_cdecl("sqlite3_myextension_init")
/// public func sqlite3_myextension_init(
///     db: OpaquePointer?,
///     pzErrMsg: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?,
///     pApi: UnsafePointer<sqlite3_api_routines>?
/// ) -> Int32 {
///     return MyExtension.entryPoint(db: db, pzErrMsg: pzErrMsg, pApi: pApi)
/// }
/// ```
public protocol SQLiteExtensionModule: Sendable {
    /// The name of the extension module.
    static var name: String { get }

    /// Register the extension's functions and features with the database.
    ///
    /// - Parameter db: The database to register with.
    /// - Throws: Any error that occurs during registration.
    static func register(with db: SQLiteDatabase) throws
}

extension SQLiteExtensionModule {
    /// The standard entry point implementation for a loadable extension.
    ///
    /// Use this method in your `@_cdecl` entry point function.
    ///
    /// ## Example
    /// ```swift
    /// @_cdecl("sqlite3_myext_init")
    /// public func sqlite3_myext_init(
    ///     db: OpaquePointer?,
    ///     pzErrMsg: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?,
    ///     pApi: UnsafePointer<sqlite3_api_routines>?
    /// ) -> Int32 {
    ///     return MyExtension.entryPoint(db: db, pzErrMsg: pzErrMsg, pApi: pApi)
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - db: The SQLite database connection pointer.
    ///   - pzErrMsg: A pointer to store error messages.
    ///   - pApi: The SQLite API routines pointer (opaque, not used directly in Swift).
    /// - Returns: SQLITE_OK on success, or an error code on failure.
    public static func entryPoint(
        db: OpaquePointer?,
        pzErrMsg: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?,
        pApi: UnsafePointer<sqlite3_api_routines>?
    ) -> Int32 {
        if let pApi = pApi {
            SQLiteExtensionKitInitialize(pApi)
        }

        guard let db = db else {
            return SQLITE_ERROR
        }

        // Initialize the SQLite extension API
        // This is required for all loadable extensions
        // Note: SQLite requires extensions to initialize the global API table via
        // SQLITE_EXTENSION_INIT2. The call to `SQLiteExtensionKitInitialize` above
        // bridges that requirement for Swift.

        do {
            let database = SQLiteDatabase(db)
            try Self.register(with: database)
            return SQLITE_OK
        } catch let error as SQLiteExtensionError {
            assignErrorMessage("Extension '\(Self.name)' failed: \(error)", to: pzErrMsg)

            switch error {
            case .functionRegistrationFailed(_, let code):
                return code
            case .sqliteError(let code):
                return code
            default:
                return SQLITE_ERROR
            }
        } catch {
            assignErrorMessage("Extension '\(Self.name)' failed: \(error)", to: pzErrMsg)
            return SQLITE_ERROR
        }
    }
}

/// Creates a standard SQLite extension entry point.
///
/// This is a convenience function that creates the entry point for a loadable extension.
///
/// ## Example
/// ```swift
/// @_cdecl("sqlite3_myext_init")
/// public func sqlite3_myext_init(
///     db: OpaquePointer?,
///     pzErrMsg: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?,
///     pApi: UnsafePointer<sqlite3_api_routines>?
/// ) -> Int32 {
///     return createExtensionEntryPoint(name: "myext", db: db, pzErrMsg: pzErrMsg, pApi: pApi) { db in
///         try db.createScalarFunction(name: "hello") { context, _ in
///             context.result("Hello, World!")
///         }
///     }
/// }
/// ```
///
/// - Parameters:
///   - name: The name of the extension.
///   - db: The SQLite database connection pointer.
///   - pzErrMsg: A pointer to store error messages.
///   - pApi: The SQLite API routines pointer (opaque, not used directly in Swift).
///   - register: A closure that registers the extension's functions.
/// - Returns: SQLITE_OK on success, or an error code on failure.
public func createExtensionEntryPoint(
    name: String,
    db: OpaquePointer?,
    pzErrMsg: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?,
    pApi: UnsafePointer<sqlite3_api_routines>?,
    register: (SQLiteDatabase) throws -> Void
) -> Int32 {
    if let pApi = pApi {
        SQLiteExtensionKitInitialize(pApi)
    }

    guard let db = db else {
        return SQLITE_ERROR
    }

    do {
        let database = SQLiteDatabase(db)
        try register(database)
        return SQLITE_OK
    } catch let error as SQLiteExtensionError {
        assignErrorMessage("Extension '\(name)' failed: \(error)", to: pzErrMsg)

        switch error {
        case .functionRegistrationFailed(_, let code):
            return code
        case .sqliteError(let code):
            return code
        default:
            return SQLITE_ERROR
        }
    } catch {
        assignErrorMessage("Extension '\(name)' failed: \(error)", to: pzErrMsg)
        return SQLITE_ERROR
    }
}

private func assignErrorMessage(
    _ message: String,
    to pzErrMsg: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
) {
    guard let pzErrMsg = pzErrMsg else { return }

    let bytes = message.utf8CString
    let allocationSize = sqlite3_uint64(bytes.count)
    guard let raw = sqlite3_malloc64(allocationSize) else {
        return
    }

    let buffer = raw.assumingMemoryBound(to: CChar.self)
    bytes.withUnsafeBufferPointer { pointer in
        guard let baseAddress = pointer.baseAddress else { return }
        buffer.initialize(from: baseAddress, count: pointer.count)
    }

    pzErrMsg.pointee = buffer
}
