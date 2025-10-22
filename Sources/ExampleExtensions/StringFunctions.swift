import SQLiteExtensionKit
import Foundation

/// Example extension demonstrating string manipulation functions.
///
/// This extension provides several utility functions for working with strings in SQLite:
/// - `reverse(text)`: Reverses a string
/// - `rot13(text)`: Applies ROT13 encoding
/// - `trim_all(text)`: Removes all whitespace from a string
///
/// ## Usage in SQL
/// ```sql
/// SELECT reverse('hello');        -- Returns 'olleh'
/// SELECT rot13('hello');          -- Returns 'uryyb'
/// SELECT trim_all('  hello  ');   -- Returns 'hello'
/// ```
public struct StringFunctionsExtension: SQLiteExtensionModule {
    public static let name = "string_functions"

    public static func register(with db: SQLiteDatabase) throws {
        // Reverse a string
        try db.createScalarFunction(name: "reverse", argumentCount: 1, deterministic: true) { context, args in
            guard let first = args.first else {
                context.resultNull()
                return
            }

            let text = first.textValue
            context.result(String(text.reversed()))
        }

        // ROT13 encoding
        try db.createScalarFunction(name: "rot13", argumentCount: 1, deterministic: true) { context, args in
            guard let first = args.first else {
                context.resultNull()
                return
            }

            let text = first.textValue
            let result = text.map { char -> Character in
                switch char {
                case "a"..."m", "A"..."M":
                    return Character(UnicodeScalar(char.unicodeScalars.first!.value + 13)!)
                case "n"..."z", "N"..."Z":
                    return Character(UnicodeScalar(char.unicodeScalars.first!.value - 13)!)
                default:
                    return char
                }
            }
            context.result(String(result))
        }

        // Remove all whitespace
        try db.createScalarFunction(name: "trim_all", argumentCount: 1, deterministic: true) { context, args in
            guard let first = args.first else {
                context.resultNull()
                return
            }

            let text = first.textValue
            let result = text.filter { !$0.isWhitespace }
            context.result(result)
        }

        // Word count function
        try db.createScalarFunction(name: "word_count", argumentCount: 1, deterministic: true) { context, args in
            guard let first = args.first else {
                context.resultNull()
                return
            }

            let text = first.textValue
            let words = text.components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
            context.result(Int64(words.count))
        }
    }
}

/// Entry point for the string functions extension.
///
/// Load this extension in SQLite with:
/// ```sql
/// .load libExampleExtensions
/// ```
@_cdecl("sqlite3_stringfunctions_init")
public func sqlite3_stringfunctions_init(
    db: OpaquePointer?,
    pzErrMsg: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?,
    pApi: OpaquePointer?
) -> Int32 {
    return StringFunctionsExtension.entryPoint(db: db, pzErrMsg: pzErrMsg, pApi: pApi)
}
