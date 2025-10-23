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
                let windowSize = max(1, Int(args[1].intValue))

                // Store values and running sum in a reference type to ensure proper initialisation.
                let state: MovingAvgState = context.aggregateState { MovingAvgState() }

                if state.windowSize == 0 {
                    state.windowSize = windowSize
                }

                state.values.append(value)
                state.sum += value

                // Keep only the last 'windowSize' values
                if state.values.count > state.windowSize {
                    let removed = state.values.removeFirst()
                    state.sum -= removed
                }
            },
            final: { context in
                guard let state: MovingAvgState = context.existingAggregateState(MovingAvgState.self) else {
                    context.resultNull()
                    return
                }

                defer { context.clearAggregateState(MovingAvgState.self) }

                if state.values.isEmpty {
                    context.resultNull()
                    return
                }

                let avg = state.sum / Double(state.values.count)
                context.result(avg)
            }
        )

        // Running total
        try db.createAggregateFunction(
            name: "running_total",
            argumentCount: 1,
            step: { context, args in
                guard let first = args.first else { return }

                let value = first.doubleValue
                context.withAggregateValue(initialValue: 0.0) { sum in
                    sum += value
                }
            },
            final: { context in
                if !context.withExistingAggregateValue(Double.self, clearOnExit: true, { sum in
                    context.result(sum)
                }) {
                    context.result(0.0)
                }
            }
        )

        // Percentile calculation (approximate)
        try db.createAggregateFunction(
            name: "percentile",
            argumentCount: 2,
            step: { context, args in
                guard args.count == 2 else { return }

                let value = args[0].doubleValue
                let state: PercentileState = context.aggregateState { PercentileState() }

                state.values.append(value)
                state.percentile = args[1].doubleValue
            },
            final: { context in
                guard let state: PercentileState = context.existingAggregateState(PercentileState.self) else {
                    context.resultNull()
                    return
                }

                defer { context.clearAggregateState(PercentileState.self) }

                if state.values.isEmpty {
                    context.resultNull()
                    return
                }

                let sorted = state.values.sorted()
                let percentileValue = state.percentile
                let index = Int(Double(sorted.count - 1) * percentileValue / 100.0)
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
                let state: MedianState = context.aggregateState { MedianState() }
                state.values.append(value)
            },
            final: { context in
                guard let state: MedianState = context.existingAggregateState(MedianState.self) else {
                    context.resultNull()
                    return
                }

                defer { context.clearAggregateState(MedianState.self) }

                if state.values.isEmpty {
                    context.resultNull()
                    return
                }

                let sorted = state.values.sorted()
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

                let state: StringAggState = context.aggregateState { StringAggState() }

                if state.separator.isEmpty {
                    state.separator = separator
                }

                state.values.append(value)
            },
            final: { context in
                guard let state: StringAggState = context.existingAggregateState(StringAggState.self) else {
                    context.resultNull()
                    return
                }

                defer { context.clearAggregateState(StringAggState.self) }

                if state.values.isEmpty {
                    context.resultNull()
                    return
                }

                let result = state.values.joined(separator: state.separator)
                context.result(result)
            }
        )
    }
}

// MARK: - State Structures

final class MovingAvgState: @unchecked Sendable {
    var values: [Double] = []
    var sum: Double = 0.0
    var windowSize: Int = 0
}

final class PercentileState: @unchecked Sendable {
    var values: [Double] = []
    var percentile: Double = 50.0
}

final class MedianState: @unchecked Sendable {
    var values: [Double] = []
}

final class StringAggState: @unchecked Sendable {
    var values: [String] = []
    var separator: String = ""
}

/// Entry point for the window functions extension.
@_cdecl("sqlite3_windowfunctions_init")
public func sqlite3_windowfunctions_init(
    db: OpaquePointer?,
    pzErrMsg: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?,
    pApi: UnsafePointer<sqlite3_api_routines>?
) -> Int32 {
    return WindowFunctionsExtension.entryPoint(db: db, pzErrMsg: pzErrMsg, pApi: pApi)
}
