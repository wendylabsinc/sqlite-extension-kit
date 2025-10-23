import Testing
import CSQLite
@testable import SQLiteExtensionKit

@Suite("Virtual Table Tests")
struct VirtualTableTests {
    @Test("Register and query virtual table")
    func testVirtualTableQuery() throws {
        var db: OpaquePointer?
        #expect(sqlite3_open(":memory:", &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        guard let db else { return }

        let database = SQLiteDatabase(db)
        try database.registerVirtualTableModule(
            name: "numbers",
            module: NumbersVirtualTable.self
        )

        #expect(sqlite3_exec(db, "CREATE VIRTUAL TABLE temp_numbers USING numbers", nil, nil, nil) == SQLITE_OK)

        var stmt: OpaquePointer?
        #expect(sqlite3_prepare_v2(db, "SELECT value FROM temp_numbers ORDER BY value", -1, &stmt, nil) == SQLITE_OK)
        defer { sqlite3_finalize(stmt) }

        var collected: [Int64] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            collected.append(sqlite3_column_int64(stmt, 0))
        }

        #expect(collected == [1, 2, 3])
    }
}

// MARK: - Test Module

struct NumbersVirtualTable: VirtualTableModule {
    struct NumbersCursor: VirtualTableCursor {
        private var index: Int = 0
        private var values: [Int64] = []

        mutating func filter(
            indexNumber: Int,
            indexString: String?,
            values: [SQLiteValue]
        ) throws {
            self.values = [1, 2, 3]
            index = 0
        }

        mutating func next() throws {
            index += 1
        }

        var eof: Bool {
            index >= values.count
        }

        func column(at index: Int) throws -> ColumnValue {
            guard self.index < values.count else {
                return .null
            }
            return .integer(values[self.index])
        }

        var rowid: Int64 {
            guard index < values.count else { return 0 }
            return values[index]
        }
    }

    static var schema: String {
        "CREATE TABLE x(value INTEGER NOT NULL)"
    }

    static func create(arguments: [String]) throws -> NumbersVirtualTable {
        NumbersVirtualTable()
    }

    func bestIndex(_ indexInfo: IndexInfo) -> IndexInfo {
        indexInfo
    }

    func open() throws -> NumbersCursor {
        NumbersCursor()
    }
}

@Test("Virtual table supports inserts, updates, and deletes")
func testVirtualTableWrites() throws {
    var db: OpaquePointer?
    #expect(sqlite3_open(":memory:", &db) == SQLITE_OK)
    defer { sqlite3_close(db) }
    guard let db else { return }

    let database = SQLiteDatabase(db)
    try database.registerVirtualTableModule(
        name: "keyvalue",
        module: KeyValueVirtualTable.self
    )

    #expect(sqlite3_exec(db, "CREATE VIRTUAL TABLE kv USING keyvalue", nil, nil, nil) == SQLITE_OK)

    #expect(sqlite3_exec(db, "INSERT INTO kv(key, value) VALUES('one', '1')", nil, nil, nil) == SQLITE_OK)
    #expect(sqlite3_exec(db, "INSERT INTO kv(rowid, key, value) VALUES(10, 'two', '2')", nil, nil, nil) == SQLITE_OK)
    #expect(sqlite3_exec(db, "UPDATE kv SET value='one updated' WHERE key='one'", nil, nil, nil) == SQLITE_OK)
    #expect(sqlite3_exec(db, "DELETE FROM kv WHERE key='two'", nil, nil, nil) == SQLITE_OK)

    var stmt: OpaquePointer?
    #expect(sqlite3_prepare_v2(db, "SELECT rowid, key, value FROM kv ORDER BY rowid", -1, &stmt, nil) == SQLITE_OK)
    defer { sqlite3_finalize(stmt) }

    var rows: [(Int64, String, String)] = []
    while sqlite3_step(stmt) == SQLITE_ROW {
        let rowid = sqlite3_column_int64(stmt, 0)
        let key = sqlite3_column_text(stmt, 1).map { pointer -> String in
            pointer.withMemoryRebound(to: CChar.self, capacity: 0) { rebound in
                String(cString: rebound)
            }
        } ?? ""
        let value = sqlite3_column_text(stmt, 2).map { pointer -> String in
            pointer.withMemoryRebound(to: CChar.self, capacity: 0) { rebound in
                String(cString: rebound)
            }
        } ?? ""
        rows.append((rowid, key, value))
    }

    #expect(rows.count == 1)
    #expect(rows.first?.0 ?? 0 > 0)
    #expect(rows.first?.1 == "one")
    #expect(rows.first?.2 == "one updated")
}

// MARK: - Writable Test Module

struct KeyValueVirtualTable: VirtualTableModule {
    final class Storage: @unchecked Sendable {
        struct Entry {
            var rowid: Int64
            var key: String
            var value: String
        }

        private var entriesByRowID: [Int64: Entry] = [:]
        private var rowIDByKey: [String: Int64] = [:]
        private var nextIdentifier: Int64 = 1

        func snapshot() -> [Entry] {
            entriesByRowID.values.sorted { $0.rowid < $1.rowid }
        }

        func nextRowID() -> Int64 {
            let value = nextIdentifier
            nextIdentifier += 1
            return value
        }

        func assign(rowid: Int64, key: String, value: String) {
            entriesByRowID[rowid] = Entry(rowid: rowid, key: key, value: value)
            rowIDByKey[key] = rowid
            if rowid >= nextIdentifier {
                nextIdentifier = rowid + 1
            }
        }

        func remove(rowid: Int64) {
            guard let entry = entriesByRowID.removeValue(forKey: rowid) else {
                return
            }
            if let mappedRowID = rowIDByKey[entry.key], mappedRowID == rowid {
                rowIDByKey.removeValue(forKey: entry.key)
            }
        }

        func entry(forRowID rowid: Int64) -> Entry? {
            entriesByRowID[rowid]
        }

        func rowID(forKey key: String) -> Int64? {
            rowIDByKey[key]
        }
    }

    struct KeyValueCursor: VirtualTableCursor {
        private let storage: Storage
        private var rows: [Storage.Entry] = []
        private var index: Int = 0

        init(storage: Storage) {
            self.storage = storage
        }

        mutating func filter(
            indexNumber: Int,
            indexString: String?,
            values: [SQLiteValue]
        ) throws {
            _ = (indexNumber, indexString, values)
            rows = storage.snapshot()
            index = 0
        }

        mutating func next() throws {
            index += 1
        }

        var eof: Bool {
            index >= rows.count
        }

        func column(at columnIndex: Int) throws -> ColumnValue {
            guard index < rows.count else { return .null }
            let entry = rows[index]
            switch columnIndex {
            case 0:
                return .text(entry.key)
            case 1:
                return .text(entry.value)
            default:
                return .null
            }
        }

        var rowid: Int64 {
            guard index < rows.count else { return 0 }
            return rows[index].rowid
        }
    }

    enum UpdateError: Error {
        case invalidColumnCount
        case missingRow(Int64)
        case duplicateKey(String)
    }

    static var schema: String {
        "CREATE TABLE x(key TEXT PRIMARY KEY, value TEXT)"
    }

    private var storage: Storage

    init(storage: Storage) {
        self.storage = storage
    }

    static func create(arguments: [String]) throws -> KeyValueVirtualTable {
        _ = arguments
        return KeyValueVirtualTable(storage: Storage())
    }

    static func connect(arguments: [String]) throws -> KeyValueVirtualTable {
        try create(arguments: arguments)
    }

    func bestIndex(_ indexInfo: IndexInfo) -> IndexInfo {
        indexInfo
    }

    func open() throws -> KeyValueCursor {
        KeyValueCursor(storage: storage)
    }

    mutating func update(_ operation: VirtualTableUpdateOperation) throws -> VirtualTableUpdateOutcome {
        switch operation {
        case let .insert(rowid, values):
            guard values.count >= 2 else {
                throw UpdateError.invalidColumnCount
            }
            let key = values[0].textValue
            let value = values[1].textValue

            if let existingRowID = storage.rowID(forKey: key) {
                storage.assign(rowid: existingRowID, key: key, value: value)
                return .handled(rowid: existingRowID)
            }

            let assignedRowID = rowid ?? storage.nextRowID()
            storage.assign(rowid: assignedRowID, key: key, value: value)
            return .handled(rowid: assignedRowID)

        case let .update(originalRowid, newRowid, values):
            guard values.count >= 2 else {
                throw UpdateError.invalidColumnCount
            }

            guard storage.entry(forRowID: originalRowid) != nil else {
                throw UpdateError.missingRow(originalRowid)
            }

            let key = values[0].textValue
            let value = values[1].textValue

            if let existingRowID = storage.rowID(forKey: key),
               existingRowID != originalRowid {
                throw UpdateError.duplicateKey(key)
            }

            storage.remove(rowid: originalRowid)
            let assignedRowID = newRowid ?? originalRowid
            storage.assign(rowid: assignedRowID, key: key, value: value)
            return .handled(rowid: assignedRowID)

        case let .delete(rowid):
            storage.remove(rowid: rowid)
            return .handled(rowid: nil)
        }
    }
}
