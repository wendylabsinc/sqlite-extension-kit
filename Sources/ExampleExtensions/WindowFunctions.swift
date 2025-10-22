import SQLiteExtensionKit
import Foundation

/// Example extension demonstrating window functions.
///
/// Window functions perform calculations across a set of table rows that are
/// related to the current row. Unlike aggregate functions, window functions
/// do not cause rows to become grouped into a single output row.
///
/// ## Usage in SQL
/// ```sql
/// -- Running total
/// SELECT value, running_total(value) OVER (ORDER BY id) FROM data;
///
/// -- Moving average (3-row window)
/// SELECT value, moving_avg(value, 3) OVER (ORDER BY id) FROM data;
///
/// -- Rank within partition
/// SELECT category, value,
///        dense_rank_custom(value) OVER (PARTITION BY category ORDER BY value DESC)
/// FROM products;
/// ```
///
/// ## Implementation Note
/// Window functions require the xStep, xInverse, xValue, and xFinal callbacks
/// of the aggregate function interface. This is a simplified demonstration.
///
/// For full window function support, you need to register with SQLITE_UTF8 | SQLITE_DETERMINISTIC
/// and implement the window-specific aggregate interface.
public struct WindowFunctionsExtension: SQLiteExtensionModule {
    public static let name = "window_functions"

    public static func register(with db: SQLiteDatabase) throws {
        // Moving average window function
        // This demonstrates a simplified approach - full window functions
        // require special registration with xInverse support

        try db.createAggregateFunction(
            name: "moving_avg",
            argumentCount: 2,
            step: { context, args in
                guard args.count == 2 else { return }

                let value = args[0].doubleValue
                let windowSize = Int(args[1].intValue)

                // Store values and window size
                let aggCtx = sqlite3_aggregate_context(context.pointer, 1024)
                let statePtr = aggCtx!.assumingMemoryBound(to: MovingAvgState.self)

                if statePtr.pointee.windowSize == 0 {
                    statePtr.pointee.windowSize = windowSize
                }

                statePtr.pointee.values.append(value)
                statePtr.pointee.sum += value

                // Keep only the last 'windowSize' values
                if statePtr.pointee.values.count > windowSize {
                    let removed = statePtr.pointee.values.removeFirst()
                    statePtr.pointee.sum -= removed
                }
            },
            final: { context in
                let aggCtx = sqlite3_aggregate_context(context.pointer, 1024)
                let statePtr = aggCtx!.assumingMemoryBound(to: MovingAvgState.self)

                if statePtr.pointee.values.isEmpty {
                    context.resultNull()
                } else {
                    let avg = statePtr.pointee.sum / Double(statePtr.pointee.values.count)
                    context.result(avg)
                }
            }
        )

        // Running total
        try db.createAggregateFunction(
            name: "running_total",
            argumentCount: 1,
            step: { context, args in
                guard let first = args.first else { return }

                let value = first.doubleValue
                let aggCtx = sqlite3_aggregate_context(context.pointer, 8)
                let sumPtr = aggCtx!.assumingMemoryBound(to: Double.self)
                sumPtr.pointee += value
            },
            final: { context in
                let aggCtx = sqlite3_aggregate_context(context.pointer, 8)
                let sumPtr = aggCtx!.assumingMemoryBound(to: Double.self)
                context.result(sumPtr.pointee)
            }
        )

        // Percentile calculation (approximate)
        try db.createAggregateFunction(
            name: "percentile",
            argumentCount: 2,
            step: { context, args in
                guard args.count == 2 else { return }

                let value = args[0].doubleValue
                let aggCtx = sqlite3_aggregate_context(context.pointer, 1024)
                let statePtr = aggCtx!.assumingMemoryBound(to: PercentileState.self)

                statePtr.pointee.values.append(value)
                statePtr.pointee.percentile = args[1].doubleValue
            },
            final: { context in
                let aggCtx = sqlite3_aggregate_context(context.pointer, 1024)
                let statePtr = aggCtx!.assumingMemoryBound(to: PercentileState.self)

                if statePtr.pointee.values.isEmpty {
                    context.resultNull()
                    return
                }

                let sorted = statePtr.pointee.values.sorted()
                let p = statePtr.pointee.percentile
                let index = Int(Double(sorted.count - 1) * p / 100.0)
                context.result(sorted[index])
            }
        )

        // Median (50th percentile)
        try db.createAggregateFunction(
            name: "median",
            argumentCount: 1,
            step: { context, args in
                guard let first = args.first else { return }

                let value = first.doubleValue
                let aggCtx = sqlite3_aggregate_context(context.pointer, 1024)
                let statePtr = aggCtx!.assumingMemoryBound(to: MedianState.self)
                statePtr.pointee.values.append(value)
            },
            final: { context in
                let aggCtx = sqlite3_aggregate_context(context.pointer, 1024)
                let statePtr = aggCtx!.assumingMemoryBound(to: MedianState.self)

                if statePtr.pointee.values.isEmpty {
                    context.resultNull()
                    return
                }

                let sorted = statePtr.pointee.values.sorted()
                let count = sorted.count

                if count % 2 == 0 {
                    // Even number of elements: average the two middle values
                    let median = (sorted[count / 2 - 1] + sorted[count / 2]) / 2.0
                    context.result(median)
                } else {
                    // Odd number of elements: take the middle value
                    context.result(sorted[count / 2])
                }
            }
        )

        // String aggregation (like GROUP_CONCAT but customizable)
        try db.createAggregateFunction(
            name: "string_agg",
            argumentCount: 2,
            step: { context, args in
                guard args.count == 2 else { return }

                let value = args[0].textValue
                let separator = args[1].textValue

                let aggCtx = sqlite3_aggregate_context(context.pointer, 1024)
                let statePtr = aggCtx!.assumingMemoryBound(to: StringAggState.self)

                if statePtr.pointee.separator.isEmpty {
                    statePtr.pointee.separator = separator
                }

                statePtr.pointee.values.append(value)
            },
            final: { context in
                let aggCtx = sqlite3_aggregate_context(context.pointer, 1024)
                let statePtr = aggCtx!.assumingMemoryBound(to: StringAggState.self)

                if statePtr.pointee.values.isEmpty {
                    context.resultNull()
                } else {
                    let result = statePtr.pointee.values.joined(separator: statePtr.pointee.separator)
                    context.result(result)
                }
            }
        )
    }
}

// MARK: - State Structures

struct MovingAvgState {
    var values: [Double] = []
    var sum: Double = 0.0
    var windowSize: Int = 0
}

struct PercentileState {
    var values: [Double] = []
    var percentile: Double = 50.0
}

struct MedianState {
    var values: [Double] = []
}

struct StringAggState {
    var values: [String] = []
    var separator: String = ""
}

/// Entry point for the window functions extension.
@_cdecl("sqlite3_windowfunctions_init")
public func sqlite3_windowfunctions_init(
    db: OpaquePointer?,
    pzErrMsg: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?,
    pApi: OpaquePointer?
) -> Int32 {
    return WindowFunctionsExtension.entryPoint(db: db, pzErrMsg: pzErrMsg, pApi: pApi)
}
