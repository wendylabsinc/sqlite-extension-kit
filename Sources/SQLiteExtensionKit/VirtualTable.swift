import CSQLite
import Foundation

/// A protocol for implementing SQLite virtual tables.
///
/// Virtual tables allow you to create table-like interfaces to arbitrary data sources.
///
/// ## Topics
/// ### Required Methods
/// - ``schema``
/// - ``bestIndex(_:)``
/// - ``open()``
///
/// ### Optional Methods
/// - ``disconnect()``
/// - ``update(_:)``
public protocol VirtualTableModule: Sendable {
    /// The associated cursor type for iterating over rows.
    associatedtype Cursor: VirtualTableCursor

    /// The SQL schema for this virtual table.
    ///
    /// ## Example
    /// ```swift
    /// static var schema: String {
    ///     "CREATE TABLE x(key TEXT, value TEXT)"
    /// }
    /// ```
    static var schema: String { get }

    /// Called when a new instance of the virtual table is created.
    ///
    /// - Parameter arguments: Arguments passed to CREATE VIRTUAL TABLE.
    /// - Returns: A new instance of the virtual table.
    /// - Throws: Any error during initialization.
    static func create(arguments: [String]) throws -> Self

    /// Called when connecting to an existing virtual table.
    ///
    /// - Parameter arguments: Arguments passed when connecting.
    /// - Returns: A new instance of the virtual table.
    /// - Throws: Any error during connection.
    static func connect(arguments: [String]) throws -> Self

    /// Determines the best way to execute a query.
    ///
    /// SQLite calls this to determine the most efficient way to access the virtual table.
    ///
    /// - Parameter indexInfo: Information about the query constraints.
    /// - Returns: Index information for query optimization.
    func bestIndex(_ indexInfo: IndexInfo) -> IndexInfo

    /// Opens a new cursor for iterating over table rows.
    ///
    /// - Returns: A new cursor instance.
    /// - Throws: Any error during cursor creation.
    func open() throws -> Cursor

    /// Called when the last connection to the table is closed.
    func disconnect()

    /// Handles insert, update, and delete operations for writable virtual tables.
    ///
    /// Implement this method to support mutation via SQL statements.
    ///
    /// - Parameter operation: The requested operation and associated values.
    /// - Returns: The outcome of the operation.
    /// - Throws: Any error encountered during processing.
    mutating func update(_ operation: VirtualTableUpdateOperation) throws -> VirtualTableUpdateOutcome
}

extension VirtualTableModule {
    /// Default implementation that uses `create` for connect.
    public static func connect(arguments: [String]) throws -> Self {
        try create(arguments: arguments)
    }

    /// Default implementation with no special action.
    public func disconnect() {}

    /// Default implementation that reports the table as read-only.
    public mutating func update(_ operation: VirtualTableUpdateOperation) throws -> VirtualTableUpdateOutcome {
        _ = operation
        return .readOnly
    }
}

/// A cursor for iterating over virtual table rows.
public protocol VirtualTableCursor: Sendable {
    /// Filters the cursor based on query constraints.
    ///
    /// - Parameters:
    ///   - indexNumber: The index number from `bestIndex`.
    ///   - indexString: The index string from `bestIndex`.
    ///   - values: Values for the query constraints.
    /// - Throws: Any error during filtering.
    mutating func filter(indexNumber: Int, indexString: String?, values: [SQLiteValue]) throws

    /// Advances the cursor to the next row.
    ///
    /// - Throws: Any error during advancement.
    mutating func next() throws

    /// Returns whether the cursor has reached the end.
    var eof: Bool { get }

    /// Returns the value for a specific column.
    ///
    /// - Parameter index: The column index.
    /// - Returns: The column value.
    /// - Throws: Any error retrieving the value.
    func column(at index: Int) throws -> ColumnValue

    /// Returns the current row ID.
    var rowid: Int64 { get }
}

/// Operations that SQLite can request via `xUpdate` on a virtual table.
public enum VirtualTableUpdateOperation: Sendable {
    /// Insert a new row into the virtual table.
    ///
    /// - Parameters:
    ///   - rowid: The requested row identifier, if provided by SQLite.
    ///   - values: Column values for the new row in schema order.
    case insert(rowid: Int64?, values: [SQLiteValue])

    /// Update an existing row in the virtual table.
    ///
    /// - Parameters:
    ///   - originalRowid: The current row identifier.
    ///   - newRowid: The requested replacement row identifier, if any.
    ///   - values: Column values for the updated row in schema order.
    case update(originalRowid: Int64, newRowid: Int64?, values: [SQLiteValue])

    /// Delete the row identified by `rowid`.
    ///
    /// - Parameter rowid: The row identifier being deleted.
    case delete(rowid: Int64)
}

/// The outcome of handling a `VirtualTableUpdateOperation`.
public enum VirtualTableUpdateOutcome: Sendable {
    /// The operation was processed successfully.
    ///
    /// - Parameter rowid: The row identifier that SQLite should use after the operation.
    case handled(rowid: Int64?)

    /// The table does not support writes and should be treated as read-only.
    case readOnly
}

/// Represents a column value in a virtual table.
public enum ColumnValue: Sendable {
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob(Data)
    case null

    /// Sets this value as the result in a SQLite context.
    func setResult(in context: SQLiteContext) {
        switch self {
        case .integer(let value):
            context.result(value)
        case .real(let value):
            context.result(value)
        case .text(let value):
            context.result(value)
        case .blob(let value):
            context.result(value)
        case .null:
            context.resultNull()
        }
    }
}

/// Information about query constraints and ordering for virtual table optimization.
public struct IndexInfo: Sendable {
    /// Constraints on the query.
    public let constraints: [Constraint]

    /// Ordering requirements.
    public let orderBy: [OrderBy]

    /// The estimated cost of this index.
    public var estimatedCost: Double

    /// The estimated number of rows.
    public var estimatedRows: Int64

    /// An integer identifying this index.
    public var indexNumber: Int

    /// A string identifying this index.
    public var indexString: String?

    /// Whether the output is already ordered.
    public var orderByConsumed: Bool

    /// Constraint usage information.
    public var constraintUsage: [ConstraintUsage]

    public init(
        constraints: [Constraint] = [],
        orderBy: [OrderBy] = [],
        estimatedCost: Double = 1000000.0,
        estimatedRows: Int64 = 1000000,
        indexNumber: Int = 0,
        indexString: String? = nil,
        orderByConsumed: Bool = false,
        constraintUsage: [ConstraintUsage] = []
    ) {
        self.constraints = constraints
        self.orderBy = orderBy
        self.estimatedCost = estimatedCost
        self.estimatedRows = estimatedRows
        self.indexNumber = indexNumber
        self.indexString = indexString
        self.orderByConsumed = orderByConsumed
        self.constraintUsage = constraintUsage
    }

    /// A constraint on a column.
    public struct Constraint: Sendable {
        /// The column index.
        public let column: Int

        /// The constraint operator.
        public let op: Operator

        /// Whether the constraint is usable.
        public let usable: Bool

        public init(column: Int, op: Operator, usable: Bool) {
            self.column = column
            self.op = op
            self.usable = usable
        }

        /// Constraint operators.
        public enum Operator: Int32, Sendable {
            case eq = 2
            case gt = 4
            case le = 8
            case lt = 16
            case ge = 32
            case match = 64
            case like = 65
            case glob = 66
            case regexp = 67
            case ne = 68
            case isNot = 69
            case isNotNull = 70
            case isNull = 71
            case `is` = 72
            case limit = 73
            case offset = 74
        }
    }

    /// Ordering requirement.
    public struct OrderBy: Sendable {
        /// The column index.
        public let column: Int

        /// Whether to sort descending.
        public let desc: Bool

        public init(column: Int, desc: Bool) {
            self.column = column
            self.desc = desc
        }
    }

    /// Information about how a constraint is used.
    public struct ConstraintUsage: Sendable {
        /// The argument index for this constraint.
        public var argvIndex: Int

        /// Whether to omit the double-check of this constraint.
        public var omit: Bool

        public init(argvIndex: Int = 0, omit: Bool = false) {
            self.argvIndex = argvIndex
            self.omit = omit
        }
    }
}
