import Testing
import Foundation
import SQLiteExtensionKit
@testable import ExampleExtensions
import CSQLite

/// Integration tests for data/binary manipulation extension functions.
@Suite("Data Functions Integration Tests")
struct DataFunctionsIntegrationTests {
    /// Helper to create a test database with data functions registered
    func createDatabase() throws -> OpaquePointer? {
        var db: OpaquePointer?
        guard sqlite3_open(":memory:", &db) == SQLITE_OK, let db = db else {
            return nil
        }

        let database = SQLiteDatabase(db)
        try DataFunctionsExtension.register(with: database)

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

    /// Helper to execute SQL and get blob result
    func executeScalarBlob(_ db: OpaquePointer, _ sql: String) -> Data? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_step(stmt) == SQLITE_ROW else {
            return nil
        }

        guard let bytes = sqlite3_column_blob(stmt, 0) else {
            return nil
        }

        let count = Int(sqlite3_column_bytes(stmt, 0))
        return Data(bytes: bytes, count: count)
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

    /// Tests hex encoding
    @Test("Hex encode function")
    func testHexEncode() throws {
        let db = try #require(try createDatabase())
        defer { sqlite3_close(db) }

        let result1 = executeScalarText(db, "SELECT hex_encode(x'DEADBEEF')")
        #expect(result1 == "DEADBEEF")

        let result2 = executeScalarText(db, "SELECT hex_encode(x'48656C6C6F')")  // "Hello"
        #expect(result2 == "48656C6C6F")

        let result3 = executeScalarText(db, "SELECT hex_encode(x'')")
        #expect(result3 == "")
    }

    /// Tests hex decoding
    @Test("Hex decode function")
    func testHexDecode() throws {
        let db = try #require(try createDatabase())
        defer { sqlite3_close(db) }

        let result1 = executeScalarBlob(db, "SELECT hex_decode('DEADBEEF')")
        #expect(result1 == Data([0xDE, 0xAD, 0xBE, 0xEF]))

        let result2 = executeScalarBlob(db, "SELECT hex_decode('48656C6C6F')")
        #expect(result2 == Data([0x48, 0x65, 0x6C, 0x6C, 0x6F]))

        // Test case insensitivity
        let result3 = executeScalarBlob(db, "SELECT hex_decode('deadbeef')")
        #expect(result3 == Data([0xDE, 0xAD, 0xBE, 0xEF]))
    }

    /// Tests hex encode/decode round-trip
    @Test("Hex encode/decode round-trip")
    func testHexRoundTrip() throws {
        let db = try #require(try createDatabase())
        defer { sqlite3_close(db) }

        let result = executeScalarBlob(db, "SELECT hex_decode(hex_encode(x'CAFEBABE'))")
        #expect(result == Data([0xCA, 0xFE, 0xBA, 0xBE]))
    }

    /// Tests base64 encoding
    @Test("Base64 encode function")
    func testBase64Encode() throws {
        let db = try #require(try createDatabase())
        defer { sqlite3_close(db) }

        let result1 = executeScalarText(db, "SELECT base64_encode('Hello')")
        #expect(result1 == "SGVsbG8=")

        let result2 = executeScalarText(db, "SELECT base64_encode('Hello, World!')")
        #expect(result2 == "SGVsbG8sIFdvcmxkIQ==")

        let result3 = executeScalarText(db, "SELECT base64_encode('')")
        #expect(result3 == "")
    }

    /// Tests base64 decoding
    @Test("Base64 decode function")
    func testBase64Decode() throws {
        let db = try #require(try createDatabase())
        defer { sqlite3_close(db) }

        let result1 = executeScalarText(db, "SELECT base64_decode('SGVsbG8=')")
        #expect(result1 == "Hello")

        let result2 = executeScalarText(db, "SELECT base64_decode('SGVsbG8sIFdvcmxkIQ==')")
        #expect(result2 == "Hello, World!")
    }

    /// Tests base64 round-trip
    @Test("Base64 encode/decode round-trip")
    func testBase64RoundTrip() throws {
        let db = try #require(try createDatabase())
        defer { sqlite3_close(db) }

        let result = executeScalarText(db, "SELECT base64_decode(base64_encode('Swift is awesome!'))")
        #expect(result == "Swift is awesome!")
    }

    /// Tests byte count function
    @Test("Byte count function")
    func testByteCount() throws {
        let db = try #require(try createDatabase())
        defer { sqlite3_close(db) }

        let result1 = executeScalarInt(db, "SELECT byte_count('Hello')")
        #expect(result1 == 5)

        let result2 = executeScalarInt(db, "SELECT byte_count(x'DEADBEEF')")
        #expect(result2 == 4)

        let result3 = executeScalarInt(db, "SELECT byte_count('')")
        #expect(result3 == 0)
    }

    #if canImport(CryptoKit)
    /// Tests SHA-256 hashing
    @Test("SHA-256 hash function")
    func testSHA256() throws {
        let db = try #require(try createDatabase())
        defer { sqlite3_close(db) }

        // Test known hash
        let result1 = executeScalarText(db, "SELECT sha256('hello')")
        #expect(result1 == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")

        // Empty string hash
        let result2 = executeScalarText(db, "SELECT sha256('')")
        #expect(result2 == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")

        // Same input should always produce same hash (deterministic)
        let result3a = executeScalarText(db, "SELECT sha256('test')")
        let result3b = executeScalarText(db, "SELECT sha256('test')")
        #expect(result3a == result3b)
    }
    #endif

    /// Tests reverse bytes function
    @Test("Reverse bytes function")
    func testReverseBytes() throws {
        let db = try #require(try createDatabase())
        defer { sqlite3_close(db) }

        let result1 = executeScalarBlob(db, "SELECT reverse_bytes(x'DEADBEEF')")
        #expect(result1 == Data([0xEF, 0xBE, 0xAD, 0xDE]))

        let result2 = executeScalarBlob(db, "SELECT reverse_bytes(x'010203')")
        #expect(result2 == Data([0x03, 0x02, 0x01]))

        // Reversing twice should give original
        let result3 = executeScalarBlob(db, "SELECT reverse_bytes(reverse_bytes(x'CAFEBABE'))")
        #expect(result3 == Data([0xCA, 0xFE, 0xBA, 0xBE]))
    }

    /// Tests data functions with table data
    @Test("Data functions with table data")
    func testDataFunctionsWithTable() throws {
        let db = try #require(try createDatabase())
        defer { sqlite3_close(db) }

        let sql = """
        CREATE TABLE secrets (id INTEGER, data BLOB);
        INSERT INTO secrets VALUES (1, x'DEADBEEF'), (2, x'CAFEBABE');
        """
        sqlite3_exec(db, sql, nil, nil, nil)

        // Test hex_encode on table data
        let result1 = executeScalarText(db, "SELECT hex_encode(data) FROM secrets WHERE id = 1")
        #expect(result1 == "DEADBEEF")

        // Test byte_count aggregation
        let totalBytes = executeScalarInt(db, "SELECT SUM(byte_count(data)) FROM secrets")
        #expect(totalBytes == 8)  // 4 + 4
    }

    /// Tests error handling
    @Test("Data functions error handling")
    func testErrorHandling() throws {
        let db = try #require(try createDatabase())
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?

        // Invalid hex string (odd length)
        sqlite3_prepare_v2(db, "SELECT hex_decode('ABC')", -1, &stmt, nil)
        let errorCode1 = sqlite3_step(stmt)
        sqlite3_finalize(stmt)
        #expect(errorCode1 == SQLITE_ERROR)

        // Invalid hex characters
        sqlite3_prepare_v2(db, "SELECT hex_decode('GGGG')", -1, &stmt, nil)
        let errorCode2 = sqlite3_step(stmt)
        sqlite3_finalize(stmt)
        #expect(errorCode2 == SQLITE_ERROR)

        // Invalid base64
        sqlite3_prepare_v2(db, "SELECT base64_decode('!!!invalid!!!')", -1, &stmt, nil)
        let errorCode3 = sqlite3_step(stmt)
        sqlite3_finalize(stmt)
        #expect(errorCode3 == SQLITE_ERROR)
    }
}
