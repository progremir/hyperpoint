struct Carrier: Hashable, Sendable {
    let usage: HIDUsage
    let keyCode: KeyCode

    private init(usage: UInt16, keyCode: UInt16) {
        self.usage = HIDUsage(rawValue: usage)
        self.keyCode = KeyCode(rawValue: keyCode)
    }

    static let f13 = Carrier(usage: 0x68, keyCode: 105)
    static let f14 = Carrier(usage: 0x69, keyCode: 107)
    static let f15 = Carrier(usage: 0x6A, keyCode: 113)
    static let f16 = Carrier(usage: 0x6B, keyCode: 106)
    static let f17 = Carrier(usage: 0x6C, keyCode: 64)
    static let f18 = Carrier(usage: 0x6D, keyCode: 79)
    static let f19 = Carrier(usage: 0x6E, keyCode: 80)
    static let f20 = Carrier(usage: 0x6F, keyCode: 90)

    // F21 to F24 have HID usages but no macOS virtual key code, so the tap could never see them.
    static let pool: [Carrier] = [f13, f14, f15, f16, f17, f18, f19, f20]

    static let hyper = f18
}

enum CarrierMeaning: Equatable, Sendable {
    case holdModifiers(Modifiers)
}

enum KeyTarget: Equatable, Sendable {
    case carrier(Carrier, CarrierMeaning)
}

struct KeyRoute: Equatable, Sendable {
    var source: HIDUsage
    var target: KeyTarget

    static func hyper(from key: HIDUsage) -> KeyRoute {
        KeyRoute(source: key, target: .carrier(.hyper, .holdModifiers(.hyper)))
    }

    var destination: HIDUsage {
        switch target {
        case .carrier(let carrier, _): carrier.usage
        }
    }
}

struct KeyMapSetup: Equatable, Sendable {
    var routes: [KeyRoute]

    static let neutral = KeyMapSetup(routes: [])

    struct Pair: Hashable, Sendable {
        var source: UInt64
        var destination: UInt64
    }

    var pairs: Set<Pair> {
        Set(routes.map { Pair(source: Self.hidutilValue($0.source), destination: Self.hidutilValue($0.destination)) })
    }

    var userKeyMappingJSON: String {
        let entries = routes.map {
            "{\"HIDKeyboardModifierMappingSrc\":\(Self.hex(Self.hidutilValue($0.source))),"
                + "\"HIDKeyboardModifierMappingDst\":\(Self.hex(Self.hidutilValue($0.destination)))}"
        }
        return "{\"UserKeyMapping\":[\(entries.joined(separator: ","))]}"
    }

    var carriesHyper: Bool { routes.contains { $0.destination == Carrier.hyper.usage } }

    static func pendingWrite(desired: KeyMapSetup, written: KeyMapSetup?) -> KeyMapSetup? {
        desired.routes.isEmpty && (written?.routes.isEmpty ?? true) ? nil : desired
    }

    static func hyperpointLeftover(in pairs: Set<Pair>) -> KeyMapSetup? {
        let routes = pairs.compactMap { pair in
            Carrier.pool.first { hidutilValue($0.usage) == pair.destination }.map { carrier in
                KeyRoute(
                    source: HIDUsage(rawValue: UInt16(truncatingIfNeeded: pair.source)),
                    target: .carrier(carrier, .holdModifiers([])))
            }
        }
        return routes.isEmpty ? nil : KeyMapSetup(routes: routes)
    }

    private static let keyboardUsagePageHighWord: UInt64 = 0x07 << 32

    private static func hidutilValue(_ usage: HIDUsage) -> UInt64 { keyboardUsagePageHighWord | UInt64(usage.rawValue) }

    private static func hex(_ value: UInt64) -> String { "0x" + String(value, radix: 16, uppercase: true) }
}
