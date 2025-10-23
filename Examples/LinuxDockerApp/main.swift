import Foundation
import ExampleExtensions
import GRDB
import SQLiteExtensionKit

struct DockerGRDBDemo {
    private let queue: DatabaseQueue

    init() throws {
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            guard let connection = db.sqliteConnection else {
                throw DemoError.missingSQLiteHandle
            }

            let database = SQLiteDatabase(connection)
            try StringFunctionsExtension.register(with: database)
        }

        queue = try DatabaseQueue(configuration: configuration)
    }

    func run() throws {
        let reversed: String = try queue.read { db in
            try String.fetchOne(db, sql: "SELECT reverse('docker demo')") ?? ""
        }

        let wordCount: Int = try queue.read { db in
            try Int.fetchOne(db, sql: "SELECT word_count('using sqlite extension kit in docker')") ?? 0
        }

        let trimmed: String = try queue.read { db in
            try String.fetchOne(db, sql: "SELECT trim_all(' swift  on  linux ')") ?? ""
        }

        print("reversed: \(reversed)")
        print("word_count: \(wordCount)")
        print("trimmed: \(trimmed)")
    }
}

enum DemoError: Error {
    case missingSQLiteHandle
}

do {
    let demo = try DockerGRDBDemo()
    try demo.run()
} catch {
    if let data = "Demo failed: \(error)\n".data(using: .utf8) {
        FileHandle.standardError.write(data)
    }
    exit(1)
}
