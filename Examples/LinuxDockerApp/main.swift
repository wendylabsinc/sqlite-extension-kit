import CSQLite
import Foundation
import SQLiteExtensionKit
import ExampleExtensions

func runDemo() throws {
    var dbPointer: OpaquePointer?
    guard sqlite3_open(":memory:", &dbPointer) == SQLITE_OK, let db = dbPointer else {
        throw DemoError.openFailed
    }
    defer { sqlite3_close(db) }

    let registrationResult = StringFunctionsExtension.entryPoint(
        db: db,
        pzErrMsg: nil,
        pApi: nil
    )

    guard registrationResult == SQLITE_OK else {
        throw DemoError.registrationFailed(code: registrationResult)
    }

    let queries: [(String, String)] = [
        ("SELECT reverse('docker demo')", "reversed"),
        ("SELECT word_count('using sqlite extension kit in docker')", "word_count"),
        ("SELECT trim_all(' swift  on  linux ')", "trimmed")
    ]

    for (sql, label) in queries {
        try run(query: sql, label: label, db: db)
    }
}

func run(query: String, label: String, db: OpaquePointer) throws {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK, let stmt = statement else {
        throw DemoError.prepareFailed(query: query)
    }
    defer { sqlite3_finalize(stmt) }

    guard sqlite3_step(stmt) == SQLITE_ROW else {
        throw DemoError.executionFailed(query: query)
    }

    if let textPointer = sqlite3_column_text(stmt, 0) {
        let value = String(cString: textPointer)
        print("\(label): \(value)")
    } else {
        print("\(label): NULL")
    }
}

enum DemoError: Error {
    case openFailed
    case registrationFailed(code: Int32)
    case prepareFailed(query: String)
    case executionFailed(query: String)
}

do {
    try runDemo()
} catch {
    if let data = "Demo failed: \(error)\n".data(using: .utf8) {
        FileHandle.standardError.write(data)
    }
    exit(1)
}
