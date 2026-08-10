import Foundation

/// A minimal, **order-preserving** JSON value used to build request bodies and
/// the Gemini `responseSchema`. Preserving object key order keeps the emitted
/// JSON readable and makes tests deterministic (plain dictionaries would
/// reorder keys).
public indirect enum JSONValue: Encodable, Equatable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case object([Pair])
    case array([JSONValue])
    case null

    public struct Pair: Equatable, Sendable {
        public let key: String
        public let value: JSONValue
        public init(_ key: String, _ value: JSONValue) {
            self.key = key
            self.value = value
        }
    }

    private struct DynamicKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(_ s: String) { stringValue = s }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .string(let s):
            var c = encoder.singleValueContainer(); try c.encode(s)
        case .int(let i):
            var c = encoder.singleValueContainer(); try c.encode(i)
        case .double(let d):
            var c = encoder.singleValueContainer(); try c.encode(d)
        case .bool(let b):
            var c = encoder.singleValueContainer(); try c.encode(b)
        case .null:
            var c = encoder.singleValueContainer(); try c.encodeNil()
        case .array(let arr):
            var c = encoder.unkeyedContainer()
            for v in arr { try c.encode(v) }
        case .object(let pairs):
            var c = encoder.container(keyedBy: DynamicKey.self)
            for p in pairs { try c.encode(p.value, forKey: DynamicKey(p.key)) }
        }
    }

    /// Serialize to compact UTF-8 JSON data.
    public func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }
}

// MARK: - Ergonomic builders

public extension JSONValue {
    static func obj(_ pairs: [(String, JSONValue)]) -> JSONValue {
        .object(pairs.map { Pair($0.0, $0.1) })
    }
    static func str(_ s: String) -> JSONValue { .string(s) }
    static func arr(_ values: [JSONValue]) -> JSONValue { .array(values) }
    static func strings(_ values: [String]) -> JSONValue { .array(values.map(JSONValue.string)) }
}
