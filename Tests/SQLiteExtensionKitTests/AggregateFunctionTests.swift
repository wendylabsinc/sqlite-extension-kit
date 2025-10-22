import Testing
import Foundation
@testable import SQLiteExtensionKit
import CSQLite

/// Tests for aggregate function registration and execution.
@Suite("Aggregate Function Tests")
struct AggregateFunctionTests {
    /// Helper to create a test database connection with sample data
    func createDatabaseWithData() throws -> OpaquePointer? {
        var db: OpaquePointer?
        guard sqlite3_open(":memory:", &db) == SQLITE_OK else {
            return nil
        }

        // Create sample table
        let createTable = """
        CREATE TABLE numbers (value INTEGER);
        INSERT INTO numbers VALUES (1), (2), (3), (4), (5);
        """

        guard sqlite3_exec(db, createTable, nil, nil, nil) == SQLITE_OK else {
            sqlite3_close(db)
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

    /// Tests basic aggregate function (product)
    @Test("Product aggregate function")
    func testProductAggregate() throws {
        let db = try #require(try createDatabaseWithData())
        defer { sqlite3_close(db) }

        let database = SQLiteDatabase(db)

        try database.createAggregateFunction(
            name: "product",
            step: { context, args in
                guard let first = args.first else { return }

                let value = first.intValue
                let aggCtx = sqlite3_aggregate_context(context.pointer, 16)
                let statePtr = aggCtx!.assumingMemoryBound(to: (product: Int64, count: Int64).self)

                if statePtr.pointee.count == 0 {
                    statePtr.pointee.product = value
                } else {
                    statePtr.pointee.product *= value
                }
                statePtr.pointee.count += 1
            },
            final: { context in
                let aggCtx = sqlite3_aggregate_context(context.pointer, 16)
                let statePtr = aggCtx!.assumingMemoryBound(to: (product: Int64, count: Int64).self)

                if statePtr.pointee.count == 0 {
                    context.resultNull()
                } else {
                    context.result(statePtr.pointee.product)
                }
            }
        )

        // 1 * 2 * 3 * 4 * 5 = 120
        let result = executeScalarInt(db, "SELECT product(value) FROM numbers")
        #expect(result == 120)
    }

    /// Tests aggregate with no rows
    @Test("Aggregate with empty table")
    func testAggregateEmptyTable() throws {
        var db: OpaquePointer?
        sqlite3_open(":memory:", &db)
        defer { sqlite3_close(db) }
        guard let db = db else { return }

        let database = SQLiteDatabase(db)

        // Create empty table
        sqlite3_exec(db, "CREATE TABLE empty (value INTEGER)", nil, nil, nil)

        try database.createAggregateFunction(
            name: "my_sum",
            step: { context, args in
                guard let first = args.first else { return }

                let value = first.intValue
                let aggCtx = sqlite3_aggregate_context(context.pointer, 16)
                let statePtr = aggCtx!.assumingMemoryBound(to: (sum: Int64, count: Int64).self)
                statePtr.pointee.sum += value
                statePtr.pointee.count += 1
            },
            final: { context in
                let aggCtx = sqlite3_aggregate_context(context.pointer, 16)
                let statePtr = aggCtx!.assumingMemoryBound(to: (sum: Int64, count: Int64).self)

                if statePtr.pointee.count == 0 {
                    context.resultNull()
                } else {
                    context.result(statePtr.pointee.sum)
                }
            }
        )

        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, "SELECT my_sum(value) FROM empty", -1, &stmt, nil)
        sqlite3_step(stmt)

        let type = sqlite3_column_type(stmt, 0)
        sqlite3_finalize(stmt)

        #expect(type == SQLITE_NULL)
    }

    /// Tests aggregate with complex state (average)
    @Test("Average aggregate with complex state")
    func testAverageAggregate() throws {
        let db = try #require(try createDatabaseWithData())
        defer { sqlite3_close(db) }

        let database = SQLiteDatabase(db)

        try database.createAggregateFunction(
            name: "my_avg",
            step: { context, args in
                guard let first = args.first else { return }

                let value = first.doubleValue
                let aggCtx = sqlite3_aggregate_context(context.pointer, 16)
                let statePtr = aggCtx!.assumingMemoryBound(to: (sum: Double, count: Int64).self)

                statePtr.pointee.sum += value
                statePtr.pointee.count += 1
            },
            final: { context in
                let aggCtx = sqlite3_aggregate_context(context.pointer, 16)
                let statePtr = aggCtx!.assumingMemoryBound(to: (sum: Double, count: Int64).self)

                if statePtr.pointee.count == 0 {
                    context.resultNull()
                } else {
                    let average = statePtr.pointee.sum / Double(statePtr.pointee.count)
                    context.result(average)
                }
            }
        )

        // (1 + 2 + 3 + 4 + 5) / 5 = 3.0
        let result = executeScalarDouble(db, "SELECT my_avg(value) FROM numbers")
        #expect(result != nil)
        #expect(abs(result! - 3.0) < 0.001)
    }

    /// Tests aggregate with GROUP BY
    @Test("Aggregate with GROUP BY")
    func testAggregateGroupBy() throws {
        var db: OpaquePointer?
        sqlite3_open(":memory:", &db)
        defer { sqlite3_close(db) }
        guard let db = db else { return }

        let database = SQLiteDatabase(db)

        // Create table with groups
        let createTable = """
        CREATE TABLE items (category TEXT, value INTEGER);
        INSERT INTO items VALUES ('A', 10), ('A', 20), ('B', 30), ('B', 40);
        """
        sqlite3_exec(db, createTable, nil, nil, nil)

        try database.createAggregateFunction(
            name: "sum_group",
            step: { context, args in
                guard let first = args.first else { return }

                let value = first.intValue
                let aggCtx = sqlite3_aggregate_context(context.pointer, 8)
                let currentPtr = aggCtx!.assumingMemoryBound(to: Int64.self)
                currentPtr.pointee += value
            },
            final: { context in
                let aggCtx = sqlite3_aggregate_context(context.pointer, 8)
                let resultPtr = aggCtx!.assumingMemoryBound(to: Int64.self)
                context.result(resultPtr.pointee)
            }
        )

        var stmt: OpaquePointer?
        let sql = "SELECT category, sum_group(value) FROM items GROUP BY category ORDER BY category"
        sqlite3_prepare_v2(db, sql, -1, &stmt, nil)

        // First row: A, 30
        #expect(sqlite3_step(stmt) == SQLITE_ROW)
        let cat1 = String(cString: sqlite3_column_text(stmt, 0))
        let sum1 = sqlite3_column_int64(stmt, 1)
        #expect(cat1 == "A")
        #expect(sum1 == 30)

        // Second row: B, 70
        #expect(sqlite3_step(stmt) == SQLITE_ROW)
        let cat2 = String(cString: sqlite3_column_text(stmt, 0))
        let sum2 = sqlite3_column_int64(stmt, 1)
        #expect(cat2 == "B")
        #expect(sum2 == 70)

        sqlite3_finalize(stmt)
    }

    /// Tests aggregate counting rows
    @Test("Count aggregate function")
    func testCountAggregate() throws {
        let db = try #require(try createDatabaseWithData())
        defer { sqlite3_close(db) }

        let database = SQLiteDatabase(db)

        try database.createAggregateFunction(
            name: "my_count",
            step: { context, args in
                let aggCtx = sqlite3_aggregate_context(context.pointer, 8)
                let countPtr = aggCtx!.assumingMemoryBound(to: Int64.self)
                countPtr.pointee += 1
            },
            final: { context in
                let aggCtx = sqlite3_aggregate_context(context.pointer, 8)
                let countPtr = aggCtx!.assumingMemoryBound(to: Int64.self)
                context.result(countPtr.pointee)
            }
        )

        let result = executeScalarInt(db, "SELECT my_count(value) FROM numbers")
        #expect(result == 5)
    }
}
