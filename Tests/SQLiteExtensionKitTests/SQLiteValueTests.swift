import Testing
import Foundation
@testable import SQLiteExtensionKit
import CSQLite

/// Tests for SQLiteValue type handling.
@Suite("SQLiteValue Tests")
struct SQLiteValueTests {
    /// Helper to create a test database connection
    func createDatabase() -> OpaquePointer? {
        var db: OpaquePointer?
        let result = sqlite3_open(":memory:", &db)
        guard result == SQLITE_OK else {
            return nil
        }
        return db
    }

    /// Tests integer value handling
    @Test("Integer value handling")
    func testIntegerValue() throws {
        let db = try #require(createDatabase())
        defer { sqlite3_close(db) }

        let database = SQLiteDatabase(db)
        try database.createScalarFunction(name: "test_int") { context, args in
            // Test that we can read integer values correctly
            guard let first = args.first else {
                context.resultNull()
                return
            }
            #expect(first.type == .integer)
            #expect(first.intValue == 42)
            #expect(first.isNull == false)
            context.result(first.intValue * 2)
        }

        var stmt: OpaquePointer?
        let sql = "SELECT test_int(42)"
        sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        sqlite3_step(stmt)

        let result = sqlite3_column_int64(stmt, 0)
        sqlite3_finalize(stmt)

        #expect(result == 84)
    }

    /// Tests double value handling
    @Test("Double value handling")
    func testDoubleValue() throws {
        let db = try #require(createDatabase())
        defer { sqlite3_close(db) }

        let database = SQLiteDatabase(db)
        try database.createScalarFunction(name: "test_double") { context, args in
            guard let first = args.first else {
                context.resultNull()
                return
            }
            #expect(first.type == .real)
            #expect(abs(first.doubleValue - 3.14159) < 0.00001)
            context.result(first.doubleValue * 2.0)
        }

        var stmt: OpaquePointer?
        let sql = "SELECT test_double(3.14159)"
        sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        sqlite3_step(stmt)

        let result = sqlite3_column_double(stmt, 0)
        sqlite3_finalize(stmt)

        #expect(abs(result - 6.28318) < 0.00001)
    }

    /// Tests text value handling
    @Test("Text value handling")
    func testTextValue() throws {
        let db = try #require(createDatabase())
        defer { sqlite3_close(db) }

        let database = SQLiteDatabase(db)
        try database.createScalarFunction(name: "test_text") { context, args in
            guard let first = args.first else {
                context.result("")
                return
            }
            #expect(first.type == .text)
            #expect(first.textValue == "Hello, World!")
            context.result(first.textValue.uppercased())
        }

        var stmt: OpaquePointer?
        let sql = "SELECT test_text('Hello, World!')"
        sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        sqlite3_step(stmt)

        let resultPtr = sqlite3_column_text(stmt, 0)
        let result = String(cString: resultPtr!)
        sqlite3_finalize(stmt)

        #expect(result == "HELLO, WORLD!")
    }

    /// Tests NULL value handling
    @Test("NULL value handling")
    func testNullValue() throws {
        let db = try #require(createDatabase())
        defer { sqlite3_close(db) }

        let database = SQLiteDatabase(db)
        try database.createScalarFunction(name: "test_null") { context, args in
            guard let first = args.first else {
                context.resultNull()
                return
            }
            #expect(first.type == .null)
            #expect(first.isNull == true)
            if first.isNull {
                context.resultNull()
            } else {
                context.result(Int64(1))
            }
        }

        var stmt: OpaquePointer?
        let sql = "SELECT test_null(NULL)"
        sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        sqlite3_step(stmt)

        let type = sqlite3_column_type(stmt, 0)
        sqlite3_finalize(stmt)

        #expect(type == SQLITE_NULL)
    }

    /// Tests blob value handling
    @Test("Blob value handling")
    func testBlobValue() throws {
        let db = try #require(createDatabase())
        defer { sqlite3_close(db) }

        let database = SQLiteDatabase(db)
        try database.createScalarFunction(name: "test_blob") { context, args in
            guard let first = args.first else {
                context.result(Data())
                return
            }
            #expect(first.type == .blob)
            #expect(first.blobValue == Data([0xDE, 0xAD, 0xBE, 0xEF]))
            context.result(Data(first.blobValue.reversed()))
        }

        var stmt: OpaquePointer?
        let sql = "SELECT test_blob(x'DEADBEEF')"
        sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        sqlite3_step(stmt)

        let blobPtr = sqlite3_column_blob(stmt, 0)
        let blobSize = sqlite3_column_bytes(stmt, 0)
        let result = Data(bytes: blobPtr!, count: Int(blobSize))
        sqlite3_finalize(stmt)

        #expect(result == Data([0xEF, 0xBE, 0xAD, 0xDE]))
    }
}
