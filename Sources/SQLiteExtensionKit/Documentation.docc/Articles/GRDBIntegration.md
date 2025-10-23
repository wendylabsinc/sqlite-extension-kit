# Integrating With GRDB

Learn how to load SQLiteExtensionKit modules inside [GRDB](https://github.com/groue/GRDB.swift)
applications and validate the behaviour using the bundled Docker-focused sample.

## Overview

SQLiteExtensionKit exposes pure-Swift APIs for registering scalar functions, aggregates, and
virtual tables with SQLite. When you are already using GRDB for query execution, you can reuse the
same extension modules by registering them during database configuration. The `LinuxDockerApp`
executable (shipped in this repository) demonstrates the minimal glue required: it initialises a
`DatabaseQueue`, registers the sample string functions, and executes a few queries through GRDB.

If you want to see the pattern end to end, run the helper script in the repository root:

```bash
Scripts/run-linuxdockerapp.sh
```

The script:

- Builds the standalone `Examples/LinuxDockerApp` package (which depends on GRDB 7.8.0).
- Executes the program and captures the output in `Examples/LinuxDockerApp/.logs/`.
- Verifies that the expected `reverse`, `word_count`, and `trim_all` function results are present.

## Registering Extensions During GRDB Configuration

The key is to hook registration into GRDB’s configuration callback. The sample uses
`Configuration.prepareDatabase` to obtain the raw SQLite connection and pass it to
`SQLiteDatabase`, which in turn exposes the high-level registration APIs from SQLiteExtensionKit:

```swift
import ExampleExtensions
import GRDB
import SQLiteExtensionKit

var configuration = Configuration()
configuration.prepareDatabase { db in
    guard let connection = db.sqliteConnection else {
        fatalError("Missing sqlite3 handle")
    }

    let database = SQLiteDatabase(connection)
    try StringFunctionsExtension.register(with: database)
}

let queue = try DatabaseQueue(configuration: configuration)
```

Once configured, you can execute queries through GRDB’s typed APIs and take advantage of the Swift
extensions:

```swift
let reversed: String = try queue.read { db in
    try String.fetchOne(db, sql: "SELECT reverse('docker demo')") ?? ""
}
```

The same approach works for aggregate functions, virtual tables, and any additional extension
modules you build.

## Adapting the Pattern to Your Project

1. Add SQLiteExtensionKit and (optionally) ExampleExtensions as dependencies alongside GRDB.
2. Register the modules you need inside your GRDB configuration callback
   (`Configuration.prepareDatabase`, `DatabasePool.Configuration`, etc.).
3. Exercise the functions through GRDB’s fetching APIs (`fetchOne`, `fetchAll`, `Row`, Query
   Interface) just like any other SQL feature.

Tip: if you bundle the loadable extension as a dynamic library, you can use the same Swift modules
from GRDB on Apple platforms and dynamic loading on Linux, keeping business logic consistent.
