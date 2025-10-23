import SQLiteExtensionKit
import Foundation
import Synchronization

/// Example virtual table implementation: In-memory key-value store.
///
/// This demonstrates how to create a virtual table in SQLite using Swift.
/// The table stores key-value pairs in memory.
///
/// ## Usage in SQL
/// ```sql
/// -- Create the virtual table
/// CREATE VIRTUAL TABLE kv USING keyvalue;
///
/// -- Insert values
/// INSERT INTO kv VALUES ('name', 'Alice');
/// INSERT INTO kv VALUES ('age', '30');
///
/// -- Query values
/// SELECT * FROM kv WHERE key = 'name';
/// SELECT value FROM kv WHERE key = 'age';
/// ```
///
/// ## Implementation Note
/// This is a simplified example. Full virtual table support requires:
/// - Implementing the complete sqlite3_module interface
/// - Proper memory management with C callbacks
/// - Transaction support
/// - Update/delete operations
///
/// For production use, consider using the full C API for virtual tables
/// as they require complex callback management beyond this Swift wrapper.
public struct KeyValueVirtualTable: VirtualTableModule {
    /// Storage for key-value pairs
    private let storage: Storage

    /// Shared storage class
    final class Storage: Sendable {
        private let data = Mutex<[String: String]>([:])

        func set(_ key: String, _ value: String) {
            data.withLock {
                $0[key] = value
            }
        }

        func get(_ key: String) -> String? {
            data.withLock {
                $0[key]
            }
        }

        func all() -> [(String, String)] {
            data.withLock {
                Array($0)
            }
        }

        func remove(_ key: String) {
            data.withLock {
                _ = $0.removeValue(forKey: key)
            }
        }
    }

    public static var schema: String {
        "CREATE TABLE x(key TEXT PRIMARY KEY, value TEXT)"
    }

    public static func create(arguments: [String]) throws -> KeyValueVirtualTable {
        KeyValueVirtualTable(storage: Storage())
    }

    private init(storage: Storage) {
        self.storage = storage
    }

    public func bestIndex(_ indexInfo: IndexInfo) -> IndexInfo {
        // Check if we have a constraint on the key column
        var newInfo = indexInfo
        var argvIndex = 1

        for constraint in indexInfo.constraints {
            if constraint.usable && constraint.column == 0 && constraint.op == .eq {
                // We can use the equality constraint on the key column
                var usage = IndexInfo.ConstraintUsage()
                usage.argvIndex = argvIndex
                usage.omit = true
                newInfo.constraintUsage.append(usage)
                argvIndex += 1

                // Much cheaper when we can look up by key
                newInfo.estimatedCost = 1.0
                newInfo.estimatedRows = 1
                newInfo.indexNumber = 1
                return newInfo
            }
        }

        // Full table scan
        newInfo.estimatedCost = Double(storage.all().count)
        newInfo.estimatedRows = Int64(storage.all().count)
        newInfo.indexNumber = 0
        return newInfo
    }

    public func open() throws -> KeyValueCursor {
        KeyValueCursor(storage: storage)
    }

    /// Cursor for iterating over key-value pairs
    public struct KeyValueCursor: VirtualTableCursor {
        private let storage: Storage
        private var currentIndex: Int = 0
        private var rows: [(String, String)] = []
        private var currentRowId: Int64 = 0

        init(storage: Storage) {
            self.storage = storage
        }

        public mutating func filter(
            indexNumber: Int,
            indexString: String?,
            values: [SQLiteValue]
        ) throws {
            if indexNumber == 1 && !values.isEmpty {
                // Lookup by key
                let key = values[0].textValue
                if let value = storage.get(key) {
                    rows = [(key, value)]
                } else {
                    rows = []
                }
            } else {
                // Full scan
                rows = storage.all()
            }
            currentIndex = 0
            currentRowId = 0
        }

        public mutating func next() throws {
            currentIndex += 1
            currentRowId += 1
        }

        public var eof: Bool {
            currentIndex >= rows.count
        }

        public func column(at index: Int) throws -> ColumnValue {
            guard currentIndex < rows.count else {
                return .null
            }

            let row = rows[currentIndex]
            switch index {
            case 0:
                return .text(row.0) // key
            case 1:
                return .text(row.1) // value
            default:
                return .null
            }
        }

        public var rowid: Int64 {
            currentRowId
        }
    }
}

/// Extension that exposes the KeyValue virtual table.
public struct KeyValueTableExtension: SQLiteExtensionModule {
    public static let name = "keyvalue_table"

    public static func register(with db: SQLiteDatabase) throws {
        try db.registerVirtualTableModule(name: "keyvalue", module: KeyValueVirtualTable.self)
    }
}

/// Entry point for the key-value virtual table extension.
@_cdecl("sqlite3_keyvalue_init")
public func sqlite3_keyvalue_init(
    db: OpaquePointer?,
    pzErrMsg: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?,
    pApi: UnsafePointer<sqlite3_api_routines>?
) -> Int32 {
    return KeyValueTableExtension.entryPoint(db: db, pzErrMsg: pzErrMsg, pApi: pApi)
}
