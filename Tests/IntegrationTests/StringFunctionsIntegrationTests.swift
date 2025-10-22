import Testing
import Foundation
import SQLiteExtensionKit
@testable import ExampleExtensions
import CSQLite

/// Integration tests for string manipulation extension functions.
@Suite("String Functions Integration Tests")
struct StringFunctionsIntegrationTests {
    /// Helper to create a test database with string functions registered
    func createDatabase() throws -> OpaquePointer? {
        var db: OpaquePointer?
        guard sqlite3_open(":memory:", &db) == SQLITE_OK, let db = db else {
            return nil
        }

        let database = SQLiteDatabase(db)
        try StringFunctionsExtension.register(with: database)

        return db
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

    /// Tests the reverse function
    @Test("Reverse function")
    func testReverse() throws {
        let db = try #require(try createDatabase())
        defer { sqlite3_close(db) }

        let result1 = executeScalarText(db, "SELECT reverse('hello')")
        #expect(result1 == "olleh")

        let result2 = executeScalarText(db, "SELECT reverse('racecar')")
        #expect(result2 == "racecar")

        let result3 = executeScalarText(db, "SELECT reverse('')")
        #expect(result3 == "")
    }

    /// Tests the ROT13 function
    @Test("ROT13 function")
    func testRot13() throws {
        let db = try #require(try createDatabase())
        defer { sqlite3_close(db) }

        let result1 = executeScalarText(db, "SELECT rot13('hello')")
        #expect(result1 == "uryyb")

        let result2 = executeScalarText(db, "SELECT rot13('HELLO')")
        #expect(result2 == "URYYB")

        // Double ROT13 should return original
        let result3 = executeScalarText(db, "SELECT rot13(rot13('test'))")
        #expect(result3 == "test")

        // Numbers and special chars should be unchanged
        let result4 = executeScalarText(db, "SELECT rot13('hello123!@#')")
        #expect(result4 == "uryyb123!@#")
    }

    /// Tests the trim_all function
    @Test("Trim all whitespace function")
    func testTrimAll() throws {
        let db = try #require(try createDatabase())
        defer { sqlite3_close(db) }

        let result1 = executeScalarText(db, "SELECT trim_all('  hello  ')")
        #expect(result1 == "hello")

        let result2 = executeScalarText(db, "SELECT trim_all('h e l l o')")
        #expect(result2 == "hello")

        let result3 = executeScalarText(db, "SELECT trim_all('hello')")
        #expect(result3 == "hello")
    }

    /// Tests the word_count function
    @Test("Word count function")
    func testWordCount() throws {
        let db = try #require(try createDatabase())
        defer { sqlite3_close(db) }

        let result1 = executeScalarInt(db, "SELECT word_count('hello world')")
        #expect(result1 == 2)

        let result2 = executeScalarInt(db, "SELECT word_count('one two three four')")
        #expect(result2 == 4)

        let result3 = executeScalarInt(db, "SELECT word_count('')")
        #expect(result3 == 0)

        let result4 = executeScalarInt(db, "SELECT word_count('  multiple   spaces  ')")
        #expect(result4 == 2)
    }

    /// Tests string functions with NULL values
    @Test("String functions with NULL")
    func testStringFunctionsWithNull() throws {
        let db = try #require(try createDatabase())
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?

        // reverse(NULL) should return empty string
        sqlite3_prepare_v2(db, "SELECT reverse(NULL)", -1, &stmt, nil)
        sqlite3_step(stmt)
        let result1 = String(cString: sqlite3_column_text(stmt, 0))
        sqlite3_finalize(stmt)
        #expect(result1 == "")

        // word_count(NULL) should return 0
        let result2 = executeScalarInt(db, "SELECT word_count(NULL)")
        #expect(result2 == 0)
    }

    /// Tests string functions with real table data
    @Test("String functions with table data")
    func testStringFunctionsWithTable() throws {
        let db = try #require(try createDatabase())
        defer { sqlite3_close(db) }

        // Create and populate test table
        let sql = """
        CREATE TABLE messages (id INTEGER, text TEXT);
        INSERT INTO messages VALUES
            (1, 'hello world'),
            (2, 'Swift is great'),
            (3, 'SQLite extensions');
        """
        sqlite3_exec(db, sql, nil, nil, nil)

        // Test reverse on table data
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, "SELECT reverse(text) FROM messages WHERE id = 1", -1, &stmt, nil)
        sqlite3_step(stmt)
        let result = String(cString: sqlite3_column_text(stmt, 0))
        sqlite3_finalize(stmt)
        #expect(result == "dlrow olleh")

        // Test word_count aggregation
        let totalWords = executeScalarInt(db, "SELECT SUM(word_count(text)) FROM messages")
        // "hello world" = 2, "Swift is great" = 3, "SQLite extensions" = 2, total = 7
        #expect(totalWords == 7)
    }
}
