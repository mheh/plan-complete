import Foundation

public enum JSONValue: Sendable, Hashable, Codable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Int.self) { self = .int(value) }
        else if let value = try? container.decode(Double.self) { self = .double(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    public subscript(key: String) -> JSONValue? {
        if case .object(let object) = self { return object[key] }
        return nil
    }

    public var stringValue: String? { if case .string(let v) = self { return v }; return nil }
    public var boolValue: Bool? { if case .bool(let v) = self { return v }; return nil }
    public var arrayValue: [JSONValue]? { if case .array(let v) = self { return v }; return nil }
    public var objectValue: [String: JSONValue]? { if case .object(let v) = self { return v }; return nil }
    public var intValue: Int? {
        switch self {
        case .int(let v): return v
        case .double(let v): return Int(exactly: v)
        default: return nil
        }
    }
    public var doubleValue: Double? {
        switch self {
        case .int(let v): return Double(v)
        case .double(let v): return v
        default: return nil
        }
    }

    public static func decode(_ data: Data) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: data)
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes, .sortedKeys]
        return try encoder.encode(self)
    }

    /// One line, with a space after each `:` and `,`.
    public func encoded(spaced: Bool) throws -> Data {
        guard spaced else { return try encoded() }
        switch self {
        case .object(let fields):
            let parts = try fields.keys.sorted().map { key in
                "\(String(decoding: try JSONValue.string(key).encoded(), as: UTF8.self)): "
                    + String(decoding: try fields[key, default: .null].encoded(spaced: true), as: UTF8.self)
            }
            return Data((parts.isEmpty ? "{}" : "{ \(parts.joined(separator: ", ")) }").utf8)
        case .array(let items):
            let parts = try items.map { String(decoding: try $0.encoded(spaced: true), as: UTF8.self) }
            return Data("[\(parts.joined(separator: ", "))]".utf8)
        default:
            return try encoded()
        }
    }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByBooleanLiteral,
    ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral, ExpressibleByNilLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
    public init(integerLiteral value: Int) { self = .int(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
    public init(nilLiteral: ()) { self = .null }
}

extension JSONValue {
    public func removing(_ key: String) -> JSONValue {
        guard case .object(var object) = self else { return self }
        object[key] = nil
        return .object(object)
    }
}

extension JSONValue {
    /// Objects merge key by key, at every depth; any other value of `other` replaces. `null` changes nothing.
    public func merging(_ other: JSONValue) -> JSONValue {
        guard case .object(var fields) = self, case .object(let overrides) = other else {
            return other == .null ? self : other
        }
        for (key, value) in overrides {
            fields[key] = fields[key]?.merging(value) ?? (value == .null ? nil : value)
        }
        return .object(fields)
    }
}
