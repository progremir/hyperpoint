/// A 16-bit id written as a hex string, such as "0x046D".
public protocol HexCoded: Hashable, Sendable, Codable {
    var rawValue: UInt16 { get }
    init(rawValue: UInt16)
    static var digits: Int { get }
}

extension HexCoded {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard text.hasPrefix("0x") || text.hasPrefix("0X"), let value = UInt16(text.dropFirst(2), radix: 16) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "\"\(text)\" is not a hex id such as \"0x046D\"")
        }
        self.init(rawValue: value)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        let hex = String(rawValue, radix: 16, uppercase: true)
        try container.encode("0x" + String(repeating: "0", count: max(0, Self.digits - hex.count)) + hex)
    }
}

extension HIDUsage: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let name = try container.decode(String.self)
        guard let usage = HIDUsage(name: name) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "unknown key \"\(name)\"")
        }
        self = usage
    }

    public func encode(to encoder: any Encoder) throws {
        guard let name else {
            throw EncodingError.invalidValue(self, .init(codingPath: encoder.codingPath, debugDescription: "unnamed key"))
        }
        var container = encoder.singleValueContainer()
        try container.encode(name)
    }
}

extension DeviceMatch: Codable {
    enum CodingKeys: String, CodingKey { case vendor, product, builtIn }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let builtIn = try container.decodeIfPresent(Bool.self, forKey: .builtIn) {
            guard builtIn, !container.contains(.vendor), !container.contains(.product) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .builtIn, in: container,
                    debugDescription: "write {\"builtIn\": true} alone, or a vendor and product instead")
            }
            self = .builtIn
        } else {
            self = .device(
                vendor: try container.decode(VendorID.self, forKey: .vendor),
                product: try container.decode(ProductID.self, forKey: .product))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .builtIn:
            try container.encode(true, forKey: .builtIn)
        case .device(let vendor, let product):
            try container.encode(vendor, forKey: .vendor)
            try container.encode(product, forKey: .product)
        }
    }
}

extension Control: Codable {
    enum CodingKeys: String, CodingKey { case hidpp, key, button }

    public init(from decoder: any Decoder) throws {
        if let name = try? decoder.singleValueContainer().decode(String.self) {
            guard name == "thumbWheel" else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: decoder.codingPath, debugDescription: "unknown control \"\(name)\""))
            }
            self = .thumbWheel
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard container.allKeys.count == 1, let key = container.allKeys.first else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "a control is \"thumbWheel\" or one of {\"hidpp\"}, {\"key\"}, {\"button\"}"))
        }
        switch key {
        case .hidpp: self = .hidpp(try container.decode(CID.self, forKey: .hidpp))
        case .key: self = .key(try container.decode(HIDUsage.self, forKey: .key))
        case .button: self = .button(try container.decode(Int.self, forKey: .button))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .thumbWheel:
            var container = encoder.singleValueContainer()
            try container.encode("thumbWheel")
        case .hidpp(let cid):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(cid, forKey: .hidpp)
        case .key(let usage):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(usage, forKey: .key)
        case .button(let number):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(number, forKey: .button)
        }
    }
}

extension Trigger: Codable {
    static let byName: [String: Trigger] = {
        var names: [String: Trigger] = ["click": .click, "hold": .hold, "scroll": .scroll]
        for direction in Direction.allCases { names["holdMove" + direction.rawValue] = .holdMove(direction) }
        return names
    }()

    public var name: String {
        switch self {
        case .click: "click"
        case .hold: "hold"
        case .holdMove(let direction): "holdMove" + direction.rawValue
        case .scroll: "scroll"
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let name = try container.decode(String.self)
        guard let trigger = Self.byName[name] else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "unknown trigger \"\(name)\"")
        }
        self = trigger
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(name)
    }
}

extension Action: Codable {
    enum CodingKeys: String, CodingKey { case shortcut, modifier }

    public init(from decoder: any Decoder) throws {
        if let name = try? decoder.singleValueContainer().decode(String.self) {
            if name == "reverse" {
                self = .reverse
            } else if let system = SystemAction.allCases.first(where: { $0.name == name }) {
                self = .system(system)
            } else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: decoder.codingPath, debugDescription: "unknown action \"\(name)\""))
            }
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard container.allKeys.count == 1, let key = container.allKeys.first else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "an action is a name such as \"missionControl\", or {\"shortcut\"} or {\"modifier\"}"))
        }
        switch key {
        case .shortcut: self = .shortcut(try container.decode(Chord.self, forKey: .shortcut))
        case .modifier: self = .modifier(try container.decode(HeldModifier.self, forKey: .modifier))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .reverse:
            var container = encoder.singleValueContainer()
            try container.encode("reverse")
        case .system(let action):
            var container = encoder.singleValueContainer()
            try container.encode(action.name)
        case .shortcut(let chord):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(chord, forKey: .shortcut)
        case .modifier(let modifier):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(modifier, forKey: .modifier)
        }
    }
}

extension Chord: Codable {
    static let modifierNamesInWrittenOrder: [(Modifiers, [String])] = [
        (.control, ["ctrl", "control"]),
        (.option, ["opt", "option", "alt"]),
        (.shift, ["shift"]),
        (.command, ["cmd", "command"]),
    ]

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        var tokens = text.split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        guard let keyName = tokens.popLast(), let key = KeyCode(name: keyName) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "\"\(text)\" does not end in a key name such as \"s\" or \"4\"")
        }
        var modifiers: Modifiers = []
        for token in tokens {
            guard let (modifier, _) = Self.modifierNamesInWrittenOrder.first(where: { $0.1.contains(token.lowercased()) }) else {
                throw DecodingError.dataCorruptedError(
                    in: container, debugDescription: "unknown modifier \"\(token)\" in \"\(text)\"")
            }
            modifiers.insert(modifier)
        }
        self.init(key: key, modifiers: modifiers)
    }

    public func encode(to encoder: any Encoder) throws {
        guard let keyName = key.name else {
            throw EncodingError.invalidValue(self, .init(codingPath: encoder.codingPath, debugDescription: "unnamed key"))
        }
        let names = Self.modifierNamesInWrittenOrder.filter { modifiers.contains($0.0) }.map { $0.1[0] }
        var container = encoder.singleValueContainer()
        try container.encode((names + [keyName]).joined(separator: "+"))
    }
}
