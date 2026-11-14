import Core
import Foundation

/// JSON conventions shared with the server: snake_case keys (`pair_id` ↔ `pairID`),
/// ISO 8601 timestamps with or without fractional seconds.
public enum BackendJSON {
    struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int?
        init(_ string: String) { stringValue = string }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) {
            stringValue = String(intValue)
            self.intValue = intValue
        }
    }

    /// `pair_id` → `pairID`, `expires_at` → `expiresAt`, `id` → `id`.
    public static func camelCase(_ key: String) -> String {
        let parts = key.split(separator: "_")
        guard parts.count > 1 else { return key }
        var result = String(parts[0])
        for part in parts.dropFirst() {
            result += part == "id" ? "ID" : part.prefix(1).uppercased() + part.dropFirst()
        }
        return result
    }

    /// `pairID` → `pair_id`, `expiresAt` → `expires_at`.
    public static func snakeCase(_ key: String) -> String {
        var result = ""
        var previousUpper = false
        for character in key {
            if character.isUppercase {
                if !previousUpper, !result.isEmpty { result.append("_") }
                result.append(contentsOf: character.lowercased())
                previousUpper = true
            } else {
                result.append(character)
                previousUpper = false
            }
        }
        return result
    }

    public static func parseDate(_ string: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string.replacingOccurrences(of: " ", with: "T"))
    }

    public static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .custom { path in AnyKey(camelCase(path[path.count - 1].stringValue)) }
        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            guard let date = parseDate(raw) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad timestamp \(raw)"))
            }
            return date
        }
        return decoder
    }

    public static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .custom { path in AnyKey(snakeCase(path[path.count - 1].stringValue)) }
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    /// Reads the pair secret whatever text encoding the server used (hex, base64 or raw text).
    public static func secretData(_ text: String) -> Data {
        let hex = Array(text)
        if hex.count.isMultiple(of: 2), hex.count >= 32, hex.allSatisfy(\.isHexDigit) {
            var data = Data()
            var index = 0
            while index < hex.count {
                data.append(UInt8(String(hex[index...index + 1]), radix: 16) ?? 0)
                index += 2
            }
            return data
        }
        if let data = Data(base64Encoded: text), data.count >= 16 { return data }
        return Data(text.utf8)
    }
}

/// A loosely typed JSON value for Edge Function request bodies.
public enum JSONValue: Encodable, Equatable, Sendable {
    case string(String)
    case int(Int)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .null: try container.encodeNil()
        case .array(let v): try container.encode(v)
        case .object(let v): try container.encode(v)
        }
    }

    /// Re-encodes any Encodable model (with snake_case keys) as a JSON value.
    public static func from(_ value: some Encodable) -> JSONValue {
        guard let data = try? BackendJSON.encoder.encode(value),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return .null }
        return convert(object)
    }

    private static func convert(_ object: Any) -> JSONValue {
        switch object {
        case let v as String: .string(v)
        case let v as NSNumber where CFGetTypeID(v) == CFBooleanGetTypeID(): .bool(v.boolValue)
        case let v as NSNumber: .int(v.intValue)
        case let v as [Any]: .array(v.map(convert))
        case let v as [String: Any]: .object(v.mapValues(convert))
        default: .null
        }
    }
}

/// The `{ok, data}` / `{ok:false, error:{code, message}}` envelope every Edge Function returns.
struct FunctionEnvelope<T: Decodable>: Decodable {
    struct Failure: Decodable {
        var code: String
        var message: String?
    }

    var ok: Bool
    var data: T?
    var error: Failure?

    static func unwrap(_ data: Data) throws -> T {
        let envelope: FunctionEnvelope<T>
        do {
            envelope = try BackendJSON.decoder.decode(FunctionEnvelope<T>.self, from: data)
        } catch {
            throw BackendError(.unknown, message: "Unreadable server response")
        }
        if envelope.ok, let value = envelope.data { return value }
        if envelope.ok, let empty = Empty() as? T { return empty }
        throw BackendError(rawCode: envelope.error?.code ?? "unknown", message: envelope.error?.message ?? "")
    }
}

/// For functions whose `data` is empty or irrelevant.
struct Empty: Decodable {
    init() {}
    init(from decoder: Decoder) throws {}
}
