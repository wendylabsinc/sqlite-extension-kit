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
