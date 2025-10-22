import Testing
import Foundation
@testable import SQLiteExtensionKit
import CSQLite

/// Tests for scalar function registration and execution.
@Suite("Scalar Function Tests")
struct ScalarFunctionTests {
    /// Helper to create a test database connection
    func createDatabase() -> OpaquePointer? {
        var db: OpaquePointer?
        let result = sqlite3_open(":memory:", &db)
        guard result == SQLITE_OK else {
            return nil
        }
        return db
    }

    /// Helper to execute SQL and get integer result
    func executeScalarInt(_ db: OpaquePointer, _ sql: String) -> Int64? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_step(stmt) == SQLITE_ROW else {
            return nil
        }

        return sqlite3_column_int64(stmt, 0)
    }

    /// Helper to execute SQL and get text result
    func executeScalarText(_ db: OpaquePointer, _ sql: String) -> String? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_step(stmt) == SQLITE_ROW else {
            return nil
        }

        guard let cString = sqlite3_column_text(stmt, 0) else {
            return nil
        }

        return String(cString: cString)
    }

    /// Tests basic scalar function registration
    @Test("Register and execute scalar function")
    func testScalarFunction() throws {
        let db = try #require(createDatabase())
        defer { sqlite3_close(db) }

        let database = SQLiteDatabase(db)

        // Register a simple doubling function
        try database.createScalarFunction(name: "double") { context, args in
            guard let first = args.first else {
                context.resultNull()
                return
            }
            context.result(first.intValue * 2)
        }

        let result = executeScalarInt(db, "SELECT double(21)")
        #expect(result == 42)
    }

    /// Tests deterministic flag
    @Test("Deterministic scalar function")
    func testDeterministicFunction() throws {
        let db = try #require(createDatabase())
        defer { sqlite3_close(db) }

        let database = SQLiteDatabase(db)

        try database.createScalarFunction(name: "add_one", deterministic: true) { context, args in
            guard let first = args.first else {
                context.resultNull()
                return
            }
            context.result(first.intValue + 1)
        }

        let result = executeScalarInt(db, "SELECT add_one(41)")
        #expect(result == 42)
    }

    /// Tests function with multiple arguments
    @Test("Multi-argument scalar function")
    func testMultiArgumentFunction() throws {
        let db = try #require(createDatabase())
        defer { sqlite3_close(db) }

        let database = SQLiteDatabase(db)

        try database.createScalarFunction(name: "add_numbers") { context, args in
            guard args.count >= 2 else {
                context.resultError("add_numbers() requires at least 2 arguments")
                return
            }
            context.result(args[0].intValue + args[1].intValue)
        }

        // Test the function directly
        var stmt: OpaquePointer?
        let sql = "SELECT add_numbers(20, 22)"
        let prepareResult = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        #expect(prepareResult == SQLITE_OK)

        if prepareResult == SQLITE_OK {
            let stepResult = sqlite3_step(stmt)
            #expect(stepResult == SQLITE_ROW)

            if stepResult == SQLITE_ROW {
                let result = sqlite3_column_int64(stmt, 0)
                #expect(result == 42)
            }
        }
        sqlite3_finalize(stmt)
    }

    /// Tests function returning text
    @Test("Text-returning scalar function")
    func testTextFunction() throws {
        let db = try #require(createDatabase())
        defer { sqlite3_close(db) }

        let database = SQLiteDatabase(db)

        try database.createScalarFunction(name: "greet") { context, args in
            guard let first = args.first else {
                context.result("Hello, World!")
                return
            }
            context.result("Hello, \(first.textValue)!")
        }

        let result1 = executeScalarText(db, "SELECT greet()")
        #expect(result1 == "Hello, World!")

        let result2 = executeScalarText(db, "SELECT greet('Alice')")
        #expect(result2 == "Hello, Alice!")
    }

    /// Tests function with error handling
    @Test("Function error handling")
    func testFunctionError() throws {
        let db = try #require(createDatabase())
        defer { sqlite3_close(db) }

        let database = SQLiteDatabase(db)

        try database.createScalarFunction(name: "safe_divide") { context, args in
            guard args.count == 2 else {
                context.resultError("safe_divide() requires 2 arguments")
                return
            }

            let divisor = args[1].doubleValue
            if divisor == 0 {
                context.resultError("Division by zero")
                return
            }

            context.result(args[0].doubleValue / divisor)
        }

        // Test normal division
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, "SELECT safe_divide(10.0, 2.0)", -1, &stmt, nil)
        #expect(sqlite3_step(stmt) == SQLITE_ROW)
        let result = sqlite3_column_double(stmt, 0)
        sqlite3_finalize(stmt)
        #expect(abs(result - 5.0) < 0.001)

        // Test division by zero
        sqlite3_prepare_v2(db, "SELECT safe_divide(10.0, 0.0)", -1, &stmt, nil)
        let errorCode = sqlite3_step(stmt)
        sqlite3_finalize(stmt)
        #expect(errorCode == SQLITE_ERROR)
    }

    /// Tests variable argument count
    @Test("Variable argument count function")
    func testVariableArguments() throws {
        let db = try #require(createDatabase())
        defer { sqlite3_close(db) }

        let database = SQLiteDatabase(db)

        // Sum all arguments
        try database.createScalarFunction(name: "sum_all", argumentCount: -1) { context, args in
            let sum = args.reduce(Int64(0)) { $0 + $1.intValue }
            context.result(sum)
        }

        let result1 = executeScalarInt(db, "SELECT sum_all(1)")
        #expect(result1 == 1)

        let result2 = executeScalarInt(db, "SELECT sum_all(1, 2, 3)")
        #expect(result2 == 6)

        let result3 = executeScalarInt(db, "SELECT sum_all(10, 20, 30, 40)")
        #expect(result3 == 100)
    }

    /// Tests NULL handling
    @Test("NULL value handling in functions")
    func testNullHandling() throws {
        let db = try #require(createDatabase())
        defer { sqlite3_close(db) }

        let database = SQLiteDatabase(db)

        try database.createScalarFunction(name: "is_null_func") { context, args in
            if args.first?.isNull ?? true {
                context.result(Int64(1))
            } else {
                context.result(Int64(0))
            }
        }

        let result1 = executeScalarInt(db, "SELECT is_null_func(NULL)")
        #expect(result1 == 1)

        let result2 = executeScalarInt(db, "SELECT is_null_func(42)")
        #expect(result2 == 0)
    }
}
