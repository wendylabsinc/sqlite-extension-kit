import SQLiteExtensionKit
import Foundation

/// Example extension demonstrating mathematical functions.
///
/// This extension provides mathematical functions including:
/// - Scalar functions: `power(x, y)`, `factorial(n)`, `fibonacci(n)`
/// - Aggregate functions: `product(x)`, `std_dev(x)`
///
/// ## Usage in SQL
/// ```sql
/// -- Scalar functions
/// SELECT power(2, 8);              -- Returns 256.0
/// SELECT factorial(5);             -- Returns 120
/// SELECT fibonacci(10);            -- Returns 55
///
/// -- Aggregate functions
/// SELECT product(value) FROM numbers;
/// SELECT std_dev(price) FROM products;
/// ```
public struct MathFunctionsExtension: SQLiteExtensionModule {
    public static let name = "math_functions"

    public static func register(with db: SQLiteDatabase) throws {
        // Power function: power(x, y) = x^y
        try db.createScalarFunction(name: "power", argumentCount: 2, deterministic: true) { context, args in
            guard args.count == 2 else {
                context.resultError("power() requires exactly 2 arguments")
                return
            }

            let base = args[0].doubleValue
            let exponent = args[1].doubleValue
            let result = pow(base, exponent)

            context.result(result)
        }

        // Factorial function
        try db.createScalarFunction(name: "factorial", argumentCount: 1, deterministic: true) { context, args in
            guard let first = args.first else {
                context.resultNull()
                return
            }

            let n = first.intValue
            if n < 0 {
                context.resultError("factorial() requires non-negative integer")
                return
            }

            if n > 20 {
                context.resultError("factorial() overflow for n > 20")
                return
            }

            if n <= 1 {
                context.result(Int64(1))
                return
            }

            var result: Int64 = 1
            for i in 2...n {
                result *= i
            }

            context.result(result)
        }

        // Fibonacci function
        try db.createScalarFunction(name: "fibonacci", argumentCount: 1, deterministic: true) { context, args in
            guard let first = args.first else {
                context.resultNull()
                return
            }

            let n = first.intValue
            if n < 0 {
                context.resultError("fibonacci() requires non-negative integer")
                return
            }

            if n <= 1 {
                context.result(n)
                return
            }

            var a: Int64 = 0
            var b: Int64 = 1

            for _ in 2...n {
                let temp = a + b
                a = b
                b = temp
            }

            context.result(b)
        }

        // Product aggregate: multiplies all values together
        try db.createAggregateFunction(
            name: "product",
            argumentCount: 1,
            step: { context, args in
                guard let first = args.first else { return }

                let value = first.doubleValue
                context.withAggregateValue(initialValue: (product: 1.0, count: Int64(0))) { state in
                    if state.count == 0 {
                        state.product = value
                    } else {
                        state.product *= value
                    }
                    state.count += 1
                }
            },
            final: { context in
                guard context.withExistingAggregateValue((product: Double, count: Int64).self, clearOnExit: true, { state in
                    if state.count == 0 {
                        context.resultNull()
                    } else {
                        context.result(state.product)
                    }
                }) else {
                    context.resultNull()
                    return
                }
            }
        )

        // Standard deviation aggregate
        try db.createAggregateFunction(
            name: "std_dev",
            argumentCount: 1,
            step: { context, args in
                guard let first = args.first else { return }

                let value = first.doubleValue

                context.withAggregateValue(initialValue: (count: Int64(0), sum: 0.0, sumSquares: 0.0)) { state in
                    state.count += 1
                    state.sum += value
                    state.sumSquares += value * value
                }
            },
            final: { context in
                guard context.withExistingAggregateValue((count: Int64, sum: Double, sumSquares: Double).self, clearOnExit: true, { state in
                    let count = state.count
                    if count == 0 {
                        context.resultNull()
                        return
                    }

                    let mean = state.sum / Double(count)
                    let variance = (state.sumSquares / Double(count)) - (mean * mean)
                    let stdDev = sqrt(max(0, variance))  // max to handle floating point errors

                    context.result(stdDev)
                }) else {
                    context.resultNull()
                    return
                }
            }
        )
    }
}

/// Entry point for the math functions extension.
@_cdecl("sqlite3_mathfunctions_init")
public func sqlite3_mathfunctions_init(
    db: OpaquePointer?,
    pzErrMsg: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?,
    pApi: UnsafePointer<sqlite3_api_routines>?
) -> Int32 {
    return MathFunctionsExtension.entryPoint(db: db, pzErrMsg: pzErrMsg, pApi: pApi)
}
