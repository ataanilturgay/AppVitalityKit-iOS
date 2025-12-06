import Foundation

public struct AnyEncodable: Encodable {
    private let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case let number as NSNumber:
            try encode(number: number, into: &container)
        case let string as String:
            try container.encode(string)
        case let bool as Bool:
            try container.encode(bool)
        case let array as [Any]:
            var unkeyed = encoder.unkeyedContainer()
            for element in array {
                let encodable = AnyEncodable(element)
                try unkeyed.encode(encodable)
            }
        case let dict as [String: Any]:
            var keyed = encoder.container(keyedBy: DynamicCodingKey.self)
            for (key, value) in dict {
                let codingKey = DynamicCodingKey(stringValue: key)
                try keyed.encode(AnyEncodable(value), forKey: codingKey)
            }
        case is NSNull:
            try container.encodeNil()
        default:
            let context = EncodingError.Context(codingPath: container.codingPath,
                                                debugDescription: "Unsupported value \(value)")
            throw EncodingError.invalidValue(value, context)
        }
    }

    private func encode(number: NSNumber, into container: inout SingleValueEncodingContainer) throws {
        if CFGetTypeID(number) == CFBooleanGetTypeID() {
            try container.encode(number.boolValue)
            return
        }
        
        switch CFNumberGetType(number as CFNumber) {
        case .charType:
            try container.encode(number.boolValue)
        case .sInt8Type, .sInt16Type, .sInt32Type, .sInt64Type, .shortType, .longType, .longLongType, .cfIndexType, .nsIntegerType:
            try container.encode(number.intValue)
        case .floatType, .float32Type, .float64Type, .doubleType, .cgFloatType:
            try container.encode(number.doubleValue)
        @unknown default:
            try container.encode(number.doubleValue)
        }
    }

    private struct DynamicCodingKey: CodingKey {
        let stringValue: String
        init(stringValue: String) { self.stringValue = stringValue }
        var intValue: Int? { nil }
        init?(intValue: Int) { return nil }
    }
}

// MARK: - ExpressibleByLiteral Support
// This allows users to pass values directly without wrapping in AnyEncodable(.init(...))

extension AnyEncodable: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self.value = value
    }
}

extension AnyEncodable: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) {
        self.value = value
    }
}

extension AnyEncodable: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.value = value
    }
}

extension AnyEncodable: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) {
        self.value = value
    }
}

extension AnyEncodable: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, Any)...) {
        let dict = Dictionary(uniqueKeysWithValues: elements)
        self.value = dict
    }
}

extension AnyEncodable: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: Any...) {
        self.value = elements
    }
}
