import Testing
import Foundation
import SQLiteExtensionKit
@testable import ExampleExtensions
import CSQLite

/// Integration tests for advanced extension functions.
@Suite("Advanced Functions Integration Tests")
struct AdvancedFunctionsIntegrationTests {
    /// Helper to create a test database with advanced functions registered
    func createDatabase() throws -> OpaquePointer? {
        var db: OpaquePointer?
        guard sqlite3_open(":memory:", &db) == SQLITE_OK, let db = db else {
            return nil
        }

        let database = SQLiteDatabase(db)
        try AdvancedFunctionsExtension.register(with: database)

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

    /// Tests JSON extraction
    @Test("JSON extract function")
    func testJSONExtract() throws {
        let db = try #require(try createDatabase())
        defer { sqlite3_close(db) }

        let json = #"{"name":"Alice","age":30,"address":{"city":"NYC"}}"#

        let result1 = executeScalarText(db, "SELECT json_extract_simple('\(json)', '$.name')")
        #expect(result1 == "Alice")

        let result2 = executeScalarInt(db, "SELECT json_extract_simple('\(json)', '$.age')")
        #expect(result2 == 30)

        let result3 = executeScalarText(db, "SELECT json_extract_simple('\(json)', '$.address.city')")
        #expect(result3 == "NYC")
    }

    /// Tests JSON array contains
    @Test("JSON array contains function")
    func testJSONArrayContains() throws {
        let db = try #require(try createDatabase())
        defer { sqlite3_close(db) }

        let result1 = executeScalarInt(db, "SELECT json_array_contains('[1,2,3,4]', '3')")
        #expect(result1 == 1)

        let result2 = executeScalarInt(db, "SELECT json_array_contains('[1,2,3,4]', '5')")
        #expect(result2 == 0)

        let result3 = executeScalarInt(db, "SELECT json_array_contains('[\"a\",\"b\",\"c\"]', 'b')")
        #expect(result3 == 1)
    }

    /// Tests regular expression matching
    @Test("Regular expression match")
    func testRegexMatch() throws {
        let db = try #require(try createDatabase())
        defer { sqlite3_close(db) }

        let result1 = executeScalarInt(db, "SELECT regexp_match('test@example.com', '.*@.*\\.com')")
        #expect(result1 == 1)

        let result2 = executeScalarInt(db, "SELECT regexp_match('invalid-email', '.*@.*\\.com')")
        #expect(result2 == 0)

        let result3 = executeScalarInt(db, "SELECT regexp_match('123-456-7890', '^[0-9]{3}-[0-9]{3}-[0-9]{4}$')")
        #expect(result3 == 1)
    }

    /// Tests regular expression replace
    @Test("Regular expression replace")
    func testRegexReplace() throws {
        let db = try #require(try createDatabase())
        defer { sqlite3_close(db) }

        let result1 = executeScalarText(db, "SELECT regexp_replace('hello world', 'world', 'Swift')")
        #expect(result1 == "hello Swift")

        let result2 = executeScalarText(db, "SELECT regexp_replace('123-456-7890', '[^0-9]', '')")
        #expect(result2 == "1234567890")
    }

    /// Tests Levenshtein distance
    @Test("Levenshtein distance")
    func testLevenshtein() throws {
        let db = try #require(try createDatabase())
        defer { sqlite3_close(db) }

        let result1 = executeScalarInt(db, "SELECT levenshtein('kitten', 'sitting')")
        #expect(result1 == 3)

        let result2 = executeScalarInt(db, "SELECT levenshtein('hello', 'hello')")
        #expect(result2 == 0)

        let result3 = executeScalarInt(db, "SELECT levenshtein('abc', 'xyz')")
        #expect(result3 == 3)
    }

    /// Tests UUID generation
    @Test("UUID generation")
    func testUUID() throws {
        let db = try #require(try createDatabase())
        defer { sqlite3_close(db) }

        let result = executeScalarText(db, "SELECT uuid()")
        #expect(result != nil)
        #expect(result!.count == 36) // Standard UUID format
        #expect(result!.contains("-"))
    }

    /// Tests timestamp functions
    @Test("Timestamp functions")
    func testTimestamps() throws {
        let db = try #require(try createDatabase())
        defer { sqlite3_close(db) }

        let unixTime = executeScalarInt(db, "SELECT unix_timestamp()")
        #expect(unixTime != nil)
        #expect(unixTime! > 0)

        let iso8601 = executeScalarText(db, "SELECT iso8601_timestamp()")
        #expect(iso8601 != nil)
        #expect(iso8601!.contains("T"))
    }

    /// Tests URL encoding/decoding
    @Test("URL encoding and decoding")
    func testURLEncoding() throws {
        let db = try #require(try createDatabase())
        defer { sqlite3_close(db) }

        let result1 = executeScalarText(db, "SELECT url_encode('hello world')")
        #expect(result1 == "hello%20world")

        let result2 = executeScalarText(db, "SELECT url_decode('hello%20world')")
        #expect(result2 == "hello world")

        // Round-trip test
        let result3 = executeScalarText(db, "SELECT url_decode(url_encode('test with spaces & symbols!'))")
        #expect(result3 == "test with spaces & symbols!")
    }
}
