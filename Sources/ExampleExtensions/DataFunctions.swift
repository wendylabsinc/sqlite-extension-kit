import SQLiteExtensionKit
import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

/// Example extension demonstrating binary data manipulation functions.
///
/// This extension provides functions for working with BLOBs and binary data:
/// - `hex_encode(blob)`: Encodes binary data as hexadecimal
/// - `hex_decode(text)`: Decodes hexadecimal to binary data
/// - `base64_encode(blob)`: Encodes binary data as base64
/// - `base64_decode(text)`: Decodes base64 to binary data
/// - `sha256(data)`: Computes SHA-256 hash (when CryptoKit is available)
///
/// ## Usage in SQL
/// ```sql
/// SELECT hex_encode(x'DEADBEEF');          -- Returns 'DEADBEEF'
/// SELECT hex_decode('48656c6c6f');         -- Returns x'48656c6c6f' (Hello)
/// SELECT base64_encode('Hello');           -- Returns 'SGVsbG8='
/// SELECT base64_decode('SGVsbG8=');        -- Returns 'Hello'
/// SELECT sha256('Hello, World!');          -- Returns hash as hex string
/// ```
public struct DataFunctionsExtension: SQLiteExtensionModule {
    public static let name = "data_functions"

    public static func register(with db: SQLiteDatabase) throws {
        // Hex encode
        try db.createScalarFunction(name: "hex_encode", argumentCount: 1, deterministic: true) { context, args in
            guard let first = args.first else {
                context.resultNull()
                return
            }

            let data = first.blobValue
            let hexString = data.map { String(format: "%02X", $0) }.joined()
            context.result(hexString)
        }

        // Hex decode
        try db.createScalarFunction(name: "hex_decode", argumentCount: 1, deterministic: true) { context, args in
            guard let first = args.first else {
                context.resultNull()
                return
            }

            let hexString = first.textValue.replacingOccurrences(of: " ", with: "")

            guard hexString.count % 2 == 0 else {
                context.resultError("hex_decode() requires even-length hex string")
                return
            }

            var data = Data()
            var index = hexString.startIndex

            while index < hexString.endIndex {
                let nextIndex = hexString.index(index, offsetBy: 2)
                let byteString = hexString[index..<nextIndex]

                guard let byte = UInt8(byteString, radix: 16) else {
                    context.resultError("hex_decode() invalid hex string")
                    return
                }

                data.append(byte)
                index = nextIndex
            }

            context.result(data)
        }

        // Base64 encode
        try db.createScalarFunction(name: "base64_encode", argumentCount: 1, deterministic: true) { context, args in
            guard let first = args.first else {
                context.resultNull()
                return
            }

            let data: Data
            if first.type == .blob {
                data = first.blobValue
            } else {
                data = first.textValue.data(using: .utf8) ?? Data()
            }

            let base64 = data.base64EncodedString()
            context.result(base64)
        }

        // Base64 decode
        try db.createScalarFunction(name: "base64_decode", argumentCount: 1, deterministic: true) { context, args in
            guard let first = args.first else {
                context.resultNull()
                return
            }

            let base64String = first.textValue

            guard let data = Data(base64Encoded: base64String) else {
                context.resultError("base64_decode() invalid base64 string")
                return
            }

            // Try to decode as UTF-8 string, otherwise return as blob
            if let string = String(data: data, encoding: .utf8) {
                context.result(string)
            } else {
                context.result(data)
            }
        }

        // Byte count
        try db.createScalarFunction(name: "byte_count", argumentCount: 1, deterministic: true) { context, args in
            guard let first = args.first else {
                context.resultNull()
                return
            }

            let count = first.bytes
            context.result(Int64(count))
        }

        #if canImport(CryptoKit)
        // SHA-256 hash
        try db.createScalarFunction(name: "sha256", argumentCount: 1, deterministic: true) { context, args in
            guard let first = args.first else {
                context.resultNull()
                return
            }

            let data: Data
            if first.type == .blob {
                data = first.blobValue
            } else {
                data = first.textValue.data(using: .utf8) ?? Data()
            }

            let hash = SHA256.hash(data: data)
            let hashString = hash.map { String(format: "%02x", $0) }.joined()
            context.result(hashString)
        }
        #endif

        // Reverse bytes
        try db.createScalarFunction(name: "reverse_bytes", argumentCount: 1, deterministic: true) { context, args in
            guard let first = args.first else {
                context.resultNull()
                return
            }

            let data = first.blobValue
            context.result(Data(data.reversed()))
        }
    }
}

/// Entry point for the data functions extension.
@_cdecl("sqlite3_datafunctions_init")
public func sqlite3_datafunctions_init(
    db: OpaquePointer?,
    pzErrMsg: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?,
    pApi: OpaquePointer?
) -> Int32 {
    return DataFunctionsExtension.entryPoint(db: db, pzErrMsg: pzErrMsg, pApi: pApi)
}
