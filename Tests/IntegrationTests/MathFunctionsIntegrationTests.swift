import Testing
import Foundation
import SQLiteExtensionKit
@testable import ExampleExtensions
import CSQLite

/// Integration tests for mathematical extension functions.
@Suite("Math Functions Integration Tests")
struct MathFunctionsIntegrationTests {
    /// Helper to create a test database with math functions registered
    func createDatabase() throws -> OpaquePointer? {
        var db: OpaquePointer?
        guard sqlite3_open(":memory:", &db) == SQLITE_OK, let db = db else {
            return nil
        }

        let database = SQLiteDatabase(db)
        try MathFunctionsExtension.register(with: database)

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

    /// Helper to execute SQL and get double result
    func executeScalarDouble(_ db: OpaquePointer, _ sql: String) -> Double? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_step(stmt) == SQLITE_ROW else {
            return nil
        }

        return sqlite3_column_double(stmt, 0)
    }

    /// Tests the power function
    @Test("Power function")
    func testPower() throws {
        let db = try #require(try createDatabase())
        defer { sqlite3_close(db) }

        let result1 = executeScalarDouble(db, "SELECT power(2, 8)")
        #expect(result1 != nil)
        #expect(abs(result1! - 256.0) < 0.001)

        let result2 = executeScalarDouble(db, "SELECT power(10, 3)")
        #expect(result2 != nil)
        #expect(abs(result2! - 1000.0) < 0.001)

        let result3 = executeScalarDouble(db, "SELECT power(5, 0)")
        #expect(result3 != nil)
        #expect(abs(result3! - 1.0) < 0.001)

        let result4 = executeScalarDouble(db, "SELECT power(2, -1)")
        #expect(result4 != nil)
        #expect(abs(result4! - 0.5) < 0.001)
    }

    /// Tests the factorial function
    @Test("Factorial function")
    func testFactorial() throws {
        let db = try #require(try createDatabase())
        defer { sqlite3_close(db) }

        let result1 = executeScalarInt(db, "SELECT factorial(0)")
        #expect(result1 == 1)

        let result2 = executeScalarInt(db, "SELECT factorial(1)")
        #expect(result2 == 1)

        let result3 = executeScalarInt(db, "SELECT factorial(5)")
        #expect(result3 == 120)

        let result4 = executeScalarInt(db, "SELECT factorial(10)")
        #expect(result4 == 3628800)
    }

    /// Tests factorial error handling
    @Test("Factorial error cases")
    func testFactorialErrors() throws {
        let db = try #require(try createDatabase())
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?

        // Negative numbers should error
        sqlite3_prepare_v2(db, "SELECT factorial(-1)", -1, &stmt, nil)
        let errorCode = sqlite3_step(stmt)
        sqlite3_finalize(stmt)
        #expect(errorCode == SQLITE_ERROR)
    }

    /// Tests the fibonacci function
    @Test("Fibonacci function")
    func testFibonacci() throws {
        let db = try #require(try createDatabase())
        defer { sqlite3_close(db) }

        let result1 = executeScalarInt(db, "SELECT fibonacci(0)")
        #expect(result1 == 0)

        let result2 = executeScalarInt(db, "SELECT fibonacci(1)")
        #expect(result2 == 1)

        let result3 = executeScalarInt(db, "SELECT fibonacci(10)")
        #expect(result3 == 55)

        let result4 = executeScalarInt(db, "SELECT fibonacci(15)")
        #expect(result4 == 610)

        // Verify fibonacci sequence: F(n) = F(n-1) + F(n-2)
        let f10 = executeScalarInt(db, "SELECT fibonacci(10)")!
        let f11 = executeScalarInt(db, "SELECT fibonacci(11)")!
        let f12 = executeScalarInt(db, "SELECT fibonacci(12)")!
        #expect(f12 == f10 + f11)
    }

    /// Tests the product aggregate function
    @Test("Product aggregate function")
    func testProductAggregate() throws {
        let db = try #require(try createDatabase())
        defer { sqlite3_close(db) }

        // Create test table
        let sql = """
        CREATE TABLE numbers (value REAL);
        INSERT INTO numbers VALUES (2.0), (3.0), (4.0);
        """
        sqlite3_exec(db, sql, nil, nil, nil)

        let result = executeScalarDouble(db, "SELECT product(value) FROM numbers")
        #expect(result != nil)
        #expect(abs(result! - 24.0) < 0.001)  // 2 * 3 * 4 = 24
    }

    /// Tests product with single value
    @Test("Product with single value")
    func testProductSingle() throws {
        let db = try #require(try createDatabase())
        defer { sqlite3_close(db) }

        let sql = """
        CREATE TABLE numbers (value REAL);
        INSERT INTO numbers VALUES (42.0);
        """
        sqlite3_exec(db, sql, nil, nil, nil)

        let result = executeScalarDouble(db, "SELECT product(value) FROM numbers")
        #expect(result != nil)
        #expect(abs(result! - 42.0) < 0.001)
    }

    /// Tests product with empty table
    @Test("Product with empty table")
    func testProductEmpty() throws {
        let db = try #require(try createDatabase())
        defer { sqlite3_close(db) }

        sqlite3_exec(db, "CREATE TABLE numbers (value REAL)", nil, nil, nil)

        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, "SELECT product(value) FROM numbers", -1, &stmt, nil)
        sqlite3_step(stmt)
        let type = sqlite3_column_type(stmt, 0)
        sqlite3_finalize(stmt)

        #expect(type == SQLITE_NULL)
    }

    /// Tests standard deviation aggregate
    @Test("Standard deviation aggregate")
    func testStandardDeviation() throws {
        let db = try #require(try createDatabase())
        defer { sqlite3_close(db) }

        // Test with known values: [2, 4, 4, 4, 5, 5, 7, 9]
        // Mean = 5, Variance = 4, StdDev = 2
        let sql = """
        CREATE TABLE data (value REAL);
        INSERT INTO data VALUES (2), (4), (4), (4), (5), (5), (7), (9);
        """
        sqlite3_exec(db, sql, nil, nil, nil)

        let result = executeScalarDouble(db, "SELECT std_dev(value) FROM data")
        #expect(result != nil)
        #expect(abs(result! - 2.0) < 0.001)
    }

    /// Tests standard deviation with single value
    @Test("Standard deviation with single value")
    func testStdDevSingle() throws {
        let db = try #require(try createDatabase())
        defer { sqlite3_close(db) }

        let sql = """
        CREATE TABLE data (value REAL);
        INSERT INTO data VALUES (5.0);
        """
        sqlite3_exec(db, sql, nil, nil, nil)

        let result = executeScalarDouble(db, "SELECT std_dev(value) FROM data")
        #expect(result != nil)
        #expect(abs(result!) < 0.001)  // Should be 0
    }

    /// Tests mathematical functions with table data
    @Test("Math functions with complex queries")
    func testMathFunctionsWithQueries() throws {
        let db = try #require(try createDatabase())
        defer { sqlite3_close(db) }

        let sql = """
        CREATE TABLE items (id INTEGER, quantity INTEGER);
        INSERT INTO items VALUES (1, 2), (2, 3), (3, 4);
        """
        sqlite3_exec(db, sql, nil, nil, nil)

        // Use power to calculate squares
        let sumOfSquares = executeScalarDouble(db, "SELECT SUM(power(quantity, 2)) FROM items")
        #expect(sumOfSquares != nil)
        #expect(abs(sumOfSquares! - 29.0) < 0.001)  // 4 + 9 + 16 = 29

        // Combine multiple functions
        let result = executeScalarDouble(db, "SELECT product(power(quantity, 2)) FROM items")
        #expect(result != nil)
        #expect(abs(result! - 576.0) < 0.001)  // 4 * 9 * 16 = 576
    }
}
