import SQLiteExtensionKit
import Foundation

/// Advanced extension demonstrating collations, JSON functions, and complex data types.
///
/// This extension showcases more sophisticated SQLite extension features:
/// - Custom collation sequences for sorting
/// - JSON manipulation functions
/// - Array operations
/// - Regular expressions
///
/// ## Usage in SQL
/// ```sql
/// -- Case-insensitive natural sort
/// SELECT * FROM files ORDER BY name COLLATE natural_sort;
///
/// -- JSON extraction
/// SELECT json_extract('{"name":"Alice","age":30}', '$.name');
///
/// -- Array operations
/// SELECT array_contains('[1,2,3,4]', 3);  -- Returns 1 (true)
///
/// -- Regular expressions
/// SELECT regexp_match('test@example.com', '.*@.*\\.com');  -- Returns 1
/// ```
public struct AdvancedFunctionsExtension: SQLiteExtensionModule {
    public static let name = "advanced_functions"

    public static func register(with db: SQLiteDatabase) throws {
        // JSON extraction function
        try db.createScalarFunction(name: "json_extract_simple", argumentCount: 2, deterministic: true) { context, args in
            guard args.count == 2 else {
                context.resultError("json_extract_simple() requires 2 arguments")
                return
            }

            let jsonString = args[0].textValue
            let path = args[1].textValue

            guard let data = jsonString.data(using: .utf8) else {
                context.resultNull()
                return
            }

            do {
                let json = try JSONSerialization.jsonObject(with: data)

                // Simple path extraction (supports $.key or $.key.subkey)
                let keys = path.dropFirst(2).split(separator: ".").map(String.init)

                var current: Any = json
                for key in keys {
                    if let dict = current as? [String: Any] {
                        guard let value = dict[key] else {
                            context.resultNull()
                            return
                        }
                        current = value
                    } else if let array = current as? [Any], let index = Int(key) {
                        guard index < array.count else {
                            context.resultNull()
                            return
                        }
                        current = array[index]
                    } else {
                        context.resultNull()
                        return
                    }
                }

                // Convert result to appropriate type
                if let string = current as? String {
                    context.result(string)
                } else if let number = current as? Int {
                    context.result(Int64(number))
                } else if let number = current as? Double {
                    context.result(number)
                } else if let bool = current as? Bool {
                    context.result(Int64(bool ? 1 : 0))
                } else {
                    // For complex types, return as JSON string
                    let resultData = try JSONSerialization.data(withJSONObject: current)
                    context.result(String(data: resultData, encoding: .utf8) ?? "")
                }
            } catch {
                context.resultError("Invalid JSON: \(error.localizedDescription)")
            }
        }

        // JSON array contains
        try db.createScalarFunction(name: "json_array_contains", argumentCount: 2, deterministic: true) { context, args in
            guard args.count == 2 else {
                context.resultError("json_array_contains() requires 2 arguments")
                return
            }

            let jsonString = args[0].textValue
            let searchValue = args[1].textValue

            guard let data = jsonString.data(using: .utf8) else {
                context.result(Int64(0))
                return
            }

            do {
                guard let array = try JSONSerialization.jsonObject(with: data) as? [Any] else {
                    context.result(Int64(0))
                    return
                }

                let contains = array.contains { element in
                    if let str = element as? String {
                        return str == searchValue
                    } else if let num = element as? Int {
                        return String(num) == searchValue
                    } else if let num = element as? Double {
                        return String(num) == searchValue
                    }
                    return false
                }

                context.result(Int64(contains ? 1 : 0))
            } catch {
                context.result(Int64(0))
            }
        }

        // Regular expression matching
        try db.createScalarFunction(name: "regexp_match", argumentCount: 2, deterministic: true) { context, args in
            guard args.count == 2 else {
                context.resultError("regexp_match() requires 2 arguments")
                return
            }

            let text = args[0].textValue
            let pattern = args[1].textValue

            do {
                let regex = try NSRegularExpression(pattern: pattern)
                let range = NSRange(text.startIndex..., in: text)
                let matches = regex.firstMatch(in: text, range: range) != nil
                context.result(Int64(matches ? 1 : 0))
            } catch {
                context.resultError("Invalid regex pattern: \(error.localizedDescription)")
            }
        }

        // Regular expression replace
        try db.createScalarFunction(name: "regexp_replace", argumentCount: 3, deterministic: true) { context, args in
            guard args.count == 3 else {
                context.resultError("regexp_replace() requires 3 arguments")
                return
            }

            let text = args[0].textValue
            let pattern = args[1].textValue
            let replacement = args[2].textValue

            do {
                let regex = try NSRegularExpression(pattern: pattern)
                let range = NSRange(text.startIndex..., in: text)
                let result = regex.stringByReplacingMatches(
                    in: text,
                    range: range,
                    withTemplate: replacement
                )
                context.result(result)
            } catch {
                context.resultError("Invalid regex pattern: \(error.localizedDescription)")
            }
        }

        // Levenshtein distance (edit distance)
        try db.createScalarFunction(name: "levenshtein", argumentCount: 2, deterministic: true) { context, args in
            guard args.count == 2 else {
                context.resultError("levenshtein() requires 2 arguments")
                return
            }

            let s1 = args[0].textValue
            let s2 = args[1].textValue

            let distance = calculateLevenshtein(s1, s2)
            context.result(Int64(distance))
        }

        // UUID generation
        try db.createScalarFunction(name: "uuid", argumentCount: 0, deterministic: false) { context, _ in
            context.result(UUID().uuidString)
        }

        // Timestamp in various formats
        try db.createScalarFunction(name: "unix_timestamp", argumentCount: 0, deterministic: false) { context, _ in
            context.result(Int64(Date().timeIntervalSince1970))
        }

        try db.createScalarFunction(name: "iso8601_timestamp", argumentCount: 0, deterministic: false) { context, _ in
            let formatter = ISO8601DateFormatter()
            context.result(formatter.string(from: Date()))
        }

        // URL encoding/decoding
        try db.createScalarFunction(name: "url_encode", argumentCount: 1, deterministic: true) { context, args in
            guard let first = args.first else {
                context.resultNull()
                return
            }

            let text = first.textValue
            let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
            context.result(encoded)
        }

        try db.createScalarFunction(name: "url_decode", argumentCount: 1, deterministic: true) { context, args in
            guard let first = args.first else {
                context.resultNull()
                return
            }

            let text = first.textValue
            let decoded = text.removingPercentEncoding ?? text
            context.result(decoded)
        }
    }
}

// MARK: - Helper Functions

/// Calculates Levenshtein distance between two strings
private func calculateLevenshtein(_ s1: String, _ s2: String) -> Int {
    let s1Array = Array(s1)
    let s2Array = Array(s2)

    var matrix = Array(repeating: Array(repeating: 0, count: s2Array.count + 1), count: s1Array.count + 1)

    for i in 0...s1Array.count {
        matrix[i][0] = i
    }

    for j in 0...s2Array.count {
        matrix[0][j] = j
    }

    for i in 1...s1Array.count {
        for j in 1...s2Array.count {
            let cost = s1Array[i - 1] == s2Array[j - 1] ? 0 : 1
            matrix[i][j] = min(
                matrix[i - 1][j] + 1,      // deletion
                matrix[i][j - 1] + 1,      // insertion
                matrix[i - 1][j - 1] + cost // substitution
            )
        }
    }

    return matrix[s1Array.count][s2Array.count]
}

/// Entry point for the advanced functions extension.
@_cdecl("sqlite3_advancedfunctions_init")
public func sqlite3_advancedfunctions_init(
    db: OpaquePointer?,
    pzErrMsg: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?,
    pApi: UnsafePointer<sqlite3_api_routines>?
) -> Int32 {
    return AdvancedFunctionsExtension.entryPoint(db: db, pzErrMsg: pzErrMsg, pApi: pApi)
}
