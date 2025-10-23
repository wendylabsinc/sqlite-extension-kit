import CSQLite
import Foundation

// MARK: - Type Erasure Helpers

protocol AnyVirtualTableModuleAdapter: AnyObject {
    var schema: String { get }
    func create(arguments: [String]) throws -> AnyVirtualTableInstanceAdapter
    func connect(arguments: [String]) throws -> AnyVirtualTableInstanceAdapter
}

protocol AnyVirtualTableInstanceAdapter: AnyObject {
    func bestIndex(info: inout IndexInfo)
    func disconnect()
    func open() throws -> AnyVirtualTableCursorAdapter
}

protocol AnyVirtualTableCursorAdapter: AnyObject {
    func filter(indexNumber: Int, indexString: String?, values: [SQLiteValue]) throws
    func next() throws
    func eof() -> Bool
    func column(at index: Int) throws -> ColumnValue
    func rowid() throws -> Int64
}

final class VirtualTableModuleAdapter<Module: VirtualTableModule>: AnyVirtualTableModuleAdapter {
    var schema: String {
        Module.schema
    }
    func create(arguments: [String]) throws -> AnyVirtualTableInstanceAdapter {
        let module = try Module.create(arguments: arguments)
        return VirtualTableInstanceAdapter(module: module)
    }

    func connect(arguments: [String]) throws -> AnyVirtualTableInstanceAdapter {
        let module = try Module.connect(arguments: arguments)
        return VirtualTableInstanceAdapter(module: module)
    }
}

final class VirtualTableInstanceAdapter<Module: VirtualTableModule>: AnyVirtualTableInstanceAdapter {
    private var module: Module

    init(module: Module) {
        self.module = module
    }

    func bestIndex(info: inout IndexInfo) {
        info = module.bestIndex(info)
    }

    func disconnect() {
        module.disconnect()
    }

    func open() throws -> AnyVirtualTableCursorAdapter {
        let cursor = try module.open()
        return VirtualTableCursorAdapter(cursor: cursor)
    }
}

final class VirtualTableCursorAdapter<Cursor: VirtualTableCursor>: AnyVirtualTableCursorAdapter {
    private var cursor: Cursor

    init(cursor: Cursor) {
        self.cursor = cursor
    }

    func filter(indexNumber: Int, indexString: String?, values: [SQLiteValue]) throws {
        try cursor.filter(
            indexNumber: indexNumber,
            indexString: indexString,
            values: values
        )
    }

    func next() throws {
        try cursor.next()
    }

    func eof() -> Bool {
        cursor.eof
    }

    func column(at index: Int) throws -> ColumnValue {
        try cursor.column(at: index)
    }

    func rowid() throws -> Int64 {
        cursor.rowid
    }
}

// MARK: - Descriptor & Registry

final class VirtualTableModuleDescriptor: @unchecked Sendable {
    let name: String
    let adapter: AnyVirtualTableModuleAdapter

    init(name: String, adapter: AnyVirtualTableModuleAdapter) {
        self.name = name
        self.adapter = adapter
    }
}

// MARK: - SQLite Callback Helpers

private func strings(from argc: Int32, argv: UnsafePointer<UnsafePointer<CChar>?>?) -> [String] {
    guard argc > 0, let argv = argv else {
        return []
    }

    return (0..<Int(argc)).compactMap { index in
        guard let pointer = argv[index] else { return nil }
        return String(cString: pointer)
    }
}

private func values(from argc: Int32, argv: UnsafeMutablePointer<OpaquePointer?>?) -> [SQLiteValue] {
    guard argc > 0, let argv = argv else {
        return []
    }

    var result: [SQLiteValue] = []
    result.reserveCapacity(Int(argc))

    for index in 0..<Int(argc) {
        if let valuePointer = argv[index] {
            result.append(SQLiteValue(valuePointer))
        }
    }

    return result
}

private func allocateVirtualTable() -> UnsafeMutablePointer<SQLiteVirtualTable>? {
    let size = sqlite3_uint64(MemoryLayout<SQLiteVirtualTable>.stride)
    guard let raw = sqlite3_malloc64(size) else {
        return nil
    }
    raw.initializeMemory(as: UInt8.self, repeating: 0, count: Int(size))
    let pointer = raw.bindMemory(to: SQLiteVirtualTable.self, capacity: 1)
    pointer.pointee.swiftTable = nil
    pointer.pointee.moduleContext = nil
    return pointer
}

private func allocateCursor() -> UnsafeMutablePointer<SQLiteVirtualCursor>? {
    let size = sqlite3_uint64(MemoryLayout<SQLiteVirtualCursor>.stride)
    guard let raw = sqlite3_malloc64(size) else {
        return nil
    }
    raw.initializeMemory(as: UInt8.self, repeating: 0, count: Int(size))
    let pointer = raw.bindMemory(to: SQLiteVirtualCursor.self, capacity: 1)
    pointer.pointee.swiftCursor = nil
    pointer.pointee.table = nil
    return pointer
}

private func releaseVirtualTable(_ pointer: UnsafeMutablePointer<SQLiteVirtualTable>?) {
    guard let pointer = pointer else { return }

    if let swiftPointer = pointer.pointee.swiftTable {
        let object = Unmanaged<AnyObject>
            .fromOpaque(swiftPointer)
            .takeRetainedValue()
        _ = object as? AnyVirtualTableInstanceAdapter
    }

    sqlite3_free(pointer)
}

private func releaseCursor(_ pointer: UnsafeMutablePointer<SQLiteVirtualCursor>?) {
    guard let pointer = pointer else { return }

    if let swiftPointer = pointer.pointee.swiftCursor {
        let object = Unmanaged<AnyObject>
            .fromOpaque(swiftPointer)
            .takeRetainedValue()
        _ = object as? AnyVirtualTableCursorAdapter
    }

    sqlite3_free(pointer)
}

private func retainInstancePointer(
    for instance: AnyVirtualTableInstanceAdapter
) -> UnsafeMutableRawPointer {
    Unmanaged.passRetained(instance as AnyObject).toOpaque()
}

private func takeInstanceUnretained(
    _ pointer: UnsafeMutableRawPointer
) -> AnyVirtualTableInstanceAdapter? {
    Unmanaged<AnyObject>
        .fromOpaque(pointer)
        .takeUnretainedValue() as? AnyVirtualTableInstanceAdapter
}

private func takeInstanceRetained(
    _ pointer: UnsafeMutableRawPointer
) -> AnyVirtualTableInstanceAdapter? {
    Unmanaged<AnyObject>
        .fromOpaque(pointer)
        .takeRetainedValue() as? AnyVirtualTableInstanceAdapter
}

private func retainCursorPointer(
    for cursor: AnyVirtualTableCursorAdapter
) -> UnsafeMutableRawPointer {
    Unmanaged.passRetained(cursor as AnyObject).toOpaque()
}

private func takeCursorUnretained(
    _ pointer: UnsafeMutableRawPointer
) -> AnyVirtualTableCursorAdapter? {
    Unmanaged<AnyObject>
        .fromOpaque(pointer)
        .takeUnretainedValue() as? AnyVirtualTableCursorAdapter
}

private func takeCursorRetained(
    _ pointer: UnsafeMutableRawPointer
) -> AnyVirtualTableCursorAdapter? {
    Unmanaged<AnyObject>
        .fromOpaque(pointer)
        .takeRetainedValue() as? AnyVirtualTableCursorAdapter
}

private func assignVirtualTableError(
    _ vtab: UnsafeMutablePointer<SQLiteVirtualTable>?,
    message: String
) {
    guard let base = vtab?.withMemoryRebound(to: sqlite3_vtab.self, capacity: 1, { $0 }) else {
        return
    }
    SQLiteExtensionKit_VirtualTableSetError(base, message)
}

// MARK: - Index Info Conversion

private func swiftIndexInfo(from pointer: UnsafeMutablePointer<sqlite3_index_info>) -> IndexInfo {
    let info = pointer.pointee

    var constraints: [IndexInfo.Constraint] = []
    if let constraintPointer = info.aConstraint {
        constraints.reserveCapacity(Int(info.nConstraint))
        for idx in 0..<Int(info.nConstraint) {
            let constraint = constraintPointer[idx]
            let opValue = Int32(constraint.op)
            let op = IndexInfo.Constraint.Operator(rawValue: opValue) ?? .eq
            constraints.append(
                .init(
                    column: Int(constraint.iColumn),
                    op: op,
                    usable: constraint.usable != 0
                )
            )
        }
    }

    var orderBy: [IndexInfo.OrderBy] = []
    if let orderPointer = info.aOrderBy {
        orderBy.reserveCapacity(Int(info.nOrderBy))
        for idx in 0..<Int(info.nOrderBy) {
            let order = orderPointer[idx]
            orderBy.append(
                .init(
                    column: Int(order.iColumn),
                    desc: order.desc != 0
                )
            )
        }
    }

    var constraintUsage: [IndexInfo.ConstraintUsage] = []
    if let usagePointer = info.aConstraintUsage {
        constraintUsage.reserveCapacity(Int(info.nConstraint))
        for idx in 0..<Int(info.nConstraint) {
            let usage = usagePointer[idx]
            constraintUsage.append(
                .init(
                    argvIndex: Int(usage.argvIndex),
                    omit: usage.omit != 0
                )
            )
        }
    }

    return IndexInfo(
        constraints: constraints,
        orderBy: orderBy,
        estimatedCost: info.estimatedCost,
        estimatedRows: info.estimatedRows,
        indexNumber: Int(info.idxNum),
        indexString: info.idxStr.flatMap { String(cString: $0) },
        orderByConsumed: info.orderByConsumed != 0,
        constraintUsage: constraintUsage
    )
}

private func apply(
    indexInfo: IndexInfo,
    to pointer: UnsafeMutablePointer<sqlite3_index_info>
) {
    pointer.pointee.idxNum = Int32(indexInfo.indexNumber)

    if pointer.pointee.idxStr != nil, pointer.pointee.needToFreeIdxStr != 0 {
        sqlite3_free(pointer.pointee.idxStr)
    }

    if let indexString = indexInfo.indexString {
        let bytes = indexString.utf8CString
        if let raw = sqlite3_malloc64(sqlite3_uint64(bytes.count)) {
            let buffer = raw.assumingMemoryBound(to: CChar.self)
            bytes.withUnsafeBufferPointer { source in
                guard let baseAddress = source.baseAddress else { return }
                buffer.initialize(from: baseAddress, count: source.count)
            }
            pointer.pointee.idxStr = buffer
            pointer.pointee.needToFreeIdxStr = 1
        } else {
            pointer.pointee.idxStr = nil
            pointer.pointee.needToFreeIdxStr = 0
        }
    } else {
        pointer.pointee.idxStr = nil
        pointer.pointee.needToFreeIdxStr = 0
    }

    pointer.pointee.orderByConsumed = indexInfo.orderByConsumed ? 1 : 0
    pointer.pointee.estimatedCost = indexInfo.estimatedCost
    pointer.pointee.estimatedRows = indexInfo.estimatedRows

    if let usagePointer = pointer.pointee.aConstraintUsage {
        let limit = min(Int(pointer.pointee.nConstraint), indexInfo.constraintUsage.count)
        for index in 0..<limit {
            let usage = indexInfo.constraintUsage[index]
            usagePointer[index].argvIndex = Int32(usage.argvIndex)
            usagePointer[index].omit = UInt8(usage.omit ? 1 : 0)
        }
    }
}

// MARK: - SQLite Callbacks (Swift)

@_cdecl("SQLiteExtensionKit_VirtualTableCreate")
func SQLiteExtensionKit_VirtualTableCreate(
    _ context: UnsafeMutableRawPointer?,
    _ db: OpaquePointer?,
    _ argc: Int32,
    _ argv: UnsafePointer<UnsafePointer<CChar>?>?,
    _ outTable: UnsafeMutablePointer<UnsafeMutablePointer<SQLiteVirtualTable>?>?,
    _ pzErr: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?,
    _ isCreate: Int32
) -> Int32 {
    guard let context else {
        return SQLITE_MISUSE
    }

    let descriptor = Unmanaged<VirtualTableModuleDescriptor>
        .fromOpaque(context)
        .takeUnretainedValue()

    let arguments = strings(from: argc, argv: argv)

    do {
        let instance: AnyVirtualTableInstanceAdapter

        if isCreate != 0 {
            instance = try descriptor.adapter.create(arguments: arguments)
        } else {
            instance = try descriptor.adapter.connect(arguments: arguments)
        }

        guard let tablePointer = allocateVirtualTable() else {
            return SQLITE_NOMEM
        }

        tablePointer.pointee.swiftTable = retainInstancePointer(for: instance)
        tablePointer.pointee.moduleContext = context

        if let db {
            let result = descriptor.adapter.schema.withCString { schema in
                sqlite3_declare_vtab(db, schema)
            }

            if result != SQLITE_OK {
                releaseVirtualTable(tablePointer)
                if let pzErr, pzErr.pointee == nil {
                    let message = String(cString: sqlite3_errmsg(db))
                    assignError(message, to: pzErr)
                }
                return result
            }
        }

        outTable?.pointee = tablePointer
        return SQLITE_OK
    } catch {
        if let pzErr, pzErr.pointee == nil {
            let message = "Virtual table \(descriptor.name) failed: \(error)"
            assignError(message, to: pzErr)
        }
        return SQLITE_ERROR
    }
}

@_cdecl("SQLiteExtensionKit_VirtualTableBestIndex")
func SQLiteExtensionKit_VirtualTableBestIndex(
    _ tablePointer: UnsafeMutablePointer<SQLiteVirtualTable>?,
    _ indexInfoPointer: UnsafeMutablePointer<sqlite3_index_info>?
) -> Int32 {
    guard
        let tablePointer,
        let swiftPointer = tablePointer.pointee.swiftTable,
        let indexInfoPointer
    else {
        return SQLITE_ERROR
    }

    guard let instance = takeInstanceUnretained(swiftPointer) else {
        return SQLITE_ERROR
    }

    var swiftInfo = swiftIndexInfo(from: indexInfoPointer)
    instance.bestIndex(info: &swiftInfo)
    apply(indexInfo: swiftInfo, to: indexInfoPointer)
    return SQLITE_OK
}

@_cdecl("SQLiteExtensionKit_VirtualTableDisconnect")
func SQLiteExtensionKit_VirtualTableDisconnect(
    _ tablePointer: UnsafeMutablePointer<SQLiteVirtualTable>?
) -> Int32 {
    guard let tablePointer else {
        return SQLITE_ERROR
    }

    if let swiftPointer = tablePointer.pointee.swiftTable,
       let instance = takeInstanceRetained(swiftPointer) {
        instance.disconnect()
    }

    tablePointer.pointee.swiftTable = nil
    tablePointer.pointee.moduleContext = nil
    releaseVirtualTable(tablePointer)
    return SQLITE_OK
}

@_cdecl("SQLiteExtensionKit_VirtualTableDestroy")
func SQLiteExtensionKit_VirtualTableDestroy(
    _ tablePointer: UnsafeMutablePointer<SQLiteVirtualTable>?
) -> Int32 {
    SQLiteExtensionKit_VirtualTableDisconnect(tablePointer)
}

@_cdecl("SQLiteExtensionKit_VirtualTableOpen")
func SQLiteExtensionKit_VirtualTableOpen(
    _ tablePointer: UnsafeMutablePointer<SQLiteVirtualTable>?,
    _ outCursor: UnsafeMutablePointer<UnsafeMutablePointer<SQLiteVirtualCursor>?>?
) -> Int32 {
    guard
        let tablePointer,
        let swiftPointer = tablePointer.pointee.swiftTable
    else {
        return SQLITE_ERROR
    }

    guard let instance = takeInstanceUnretained(swiftPointer) else {
        return SQLITE_ERROR
    }

    do {
        let cursor = try instance.open()
        guard let cursorPointer = allocateCursor() else {
            return SQLITE_NOMEM
        }

        cursorPointer.pointee.table = tablePointer
        cursorPointer.pointee.swiftCursor = retainCursorPointer(for: cursor)

        outCursor?.pointee = cursorPointer
        return SQLITE_OK
    } catch {
        assignVirtualTableError(tablePointer, message: "Open failed: \(error)")
        return SQLITE_ERROR
    }
}

@_cdecl("SQLiteExtensionKit_VirtualTableClose")
func SQLiteExtensionKit_VirtualTableClose(
    _ cursorPointer: UnsafeMutablePointer<SQLiteVirtualCursor>?
) -> Int32 {
    guard let cursorPointer else {
        return SQLITE_ERROR
    }

    if let swiftPointer = cursorPointer.pointee.swiftCursor,
       let cursor = takeCursorRetained(swiftPointer) {
        _ = cursor
    }

    cursorPointer.pointee.swiftCursor = nil
    cursorPointer.pointee.table = nil
    releaseCursor(cursorPointer)
    return SQLITE_OK
}

@_cdecl("SQLiteExtensionKit_VirtualTableFilter")
func SQLiteExtensionKit_VirtualTableFilter(
    _ cursorPointer: UnsafeMutablePointer<SQLiteVirtualCursor>?,
    _ idxNum: Int32,
    _ idxStr: UnsafePointer<CChar>?,
    _ argv: UnsafeMutablePointer<OpaquePointer?>?,
    _ argc: Int32
) -> Int32 {
    guard
        let cursorPointer,
        let swiftPointer = cursorPointer.pointee.swiftCursor
    else {
        return SQLITE_ERROR
    }

    guard let cursor = takeCursorUnretained(swiftPointer) else {
        return SQLITE_ERROR
    }

    let arguments = values(from: argc, argv: argv)
    let indexString = idxStr.flatMap { String(cString: $0) }

    do {
        try cursor.filter(
            indexNumber: Int(idxNum),
            indexString: indexString,
            values: arguments
        )
        return SQLITE_OK
    } catch {
        assignVirtualTableError(cursorPointer.pointee.table, message: "Filter failed: \(error)")
        return SQLITE_ERROR
    }
}

@_cdecl("SQLiteExtensionKit_VirtualTableNext")
func SQLiteExtensionKit_VirtualTableNext(
    _ cursorPointer: UnsafeMutablePointer<SQLiteVirtualCursor>?
) -> Int32 {
    guard
        let cursorPointer,
        let swiftPointer = cursorPointer.pointee.swiftCursor
    else {
        return SQLITE_ERROR
    }

    guard let cursor = takeCursorUnretained(swiftPointer) else {
        return SQLITE_ERROR
    }

    do {
        try cursor.next()
        return SQLITE_OK
    } catch {
        assignVirtualTableError(cursorPointer.pointee.table, message: "Next failed: \(error)")
        return SQLITE_ERROR
    }
}

@_cdecl("SQLiteExtensionKit_VirtualTableEof")
func SQLiteExtensionKit_VirtualTableEof(
    _ cursorPointer: UnsafeMutablePointer<SQLiteVirtualCursor>?
) -> Int32 {
    guard
        let cursorPointer,
        let swiftPointer = cursorPointer.pointee.swiftCursor
    else {
        return 1
    }

    guard let cursor = takeCursorUnretained(swiftPointer) else {
        return 1
    }

    return cursor.eof() ? 1 : 0
}

@_cdecl("SQLiteExtensionKit_VirtualTableColumn")
func SQLiteExtensionKit_VirtualTableColumn(
    _ cursorPointer: UnsafeMutablePointer<SQLiteVirtualCursor>?,
    _ contextPointer: OpaquePointer?,
    _ column: Int32
) -> Int32 {
    guard
        let cursorPointer,
        let swiftPointer = cursorPointer.pointee.swiftCursor,
        let contextPointer
    else {
        return SQLITE_ERROR
    }

    guard let cursor = takeCursorUnretained(swiftPointer) else {
        return SQLITE_ERROR
    }

    do {
        let value = try cursor.column(at: Int(column))
        let context = SQLiteContext(contextPointer)
        value.setResult(in: context)
        return SQLITE_OK
    } catch {
        assignVirtualTableError(cursorPointer.pointee.table, message: "Column failed: \(error)")
        return SQLITE_ERROR
    }
}

@_cdecl("SQLiteExtensionKit_VirtualTableRowid")
func SQLiteExtensionKit_VirtualTableRowid(
    _ cursorPointer: UnsafeMutablePointer<SQLiteVirtualCursor>?,
    _ rowidPointer: UnsafeMutablePointer<Int64>?
) -> Int32 {
    guard
        let cursorPointer,
        let swiftPointer = cursorPointer.pointee.swiftCursor,
        let rowidPointer
    else {
        return SQLITE_ERROR
    }

    guard let cursor = takeCursorUnretained(swiftPointer) else {
        return SQLITE_ERROR
    }

    do {
        rowidPointer.pointee = try cursor.rowid()
        return SQLITE_OK
    } catch {
        assignVirtualTableError(cursorPointer.pointee.table, message: "Rowid failed: \(error)")
        return SQLITE_ERROR
    }
}

// MARK: - Error Assignment Helper

private func assignError(
    _ message: String,
    to pzErr: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
) {
    guard let pzErr else { return }
    let bytes = message.utf8CString
    guard let raw = sqlite3_malloc64(sqlite3_uint64(bytes.count)) else {
        return
    }

    let buffer = raw.assumingMemoryBound(to: CChar.self)
    bytes.withUnsafeBufferPointer { pointer in
        guard let baseAddress = pointer.baseAddress else { return }
        buffer.initialize(from: baseAddress, count: pointer.count)
    }
    pzErr.pointee = buffer
}
