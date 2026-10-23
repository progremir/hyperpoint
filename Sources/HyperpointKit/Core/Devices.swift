struct UsagePair: Hashable, Sendable {
    var page: Int
    var usage: Int

    static let keyboard = UsagePair(page: 0x01, usage: 0x06)
    static let mouse = UsagePair(page: 0x01, usage: 0x02)
    static let hidppPage = 0xFF43
}

struct HIDProperties: Equatable, Sendable {
    var vendor: VendorID
    var product: ProductID
    var builtIn: Bool
    var transport: String?
    var locationID: UInt32?
    var name: String?
    var primaryUsagePage: Int
    var primaryUsage: Int
    /// Every top-level collection. The MX Master 3 reports keyboard as its primary usage and also has mouse and
    /// HID++ collections (measured).
    var usagePairs: [UsagePair]

    static let keys = [
        "VendorID", "ProductID", "Built-In", "Transport", "LocationID", "Product", "PrimaryUsagePage", "PrimaryUsage",
        "DeviceUsagePairs",
    ]

    static let logitech = VendorID(rawValue: 0x046D)

    /// The built-in keyboard has no VendorID or ProductID at all (measured).
    init(bag: [String: Any]) {
        func number(_ key: String) -> Int { (bag[key] as? Int) ?? 0 }
        vendor = VendorID(rawValue: UInt16(truncatingIfNeeded: number("VendorID")))
        product = ProductID(rawValue: UInt16(truncatingIfNeeded: number("ProductID")))
        builtIn = number("Built-In") == 1
        transport = bag["Transport"] as? String
        locationID = (bag["LocationID"] as? Int).map { UInt32(truncatingIfNeeded: $0) }
        name = bag["Product"] as? String
        primaryUsagePage = number("PrimaryUsagePage")
        primaryUsage = number("PrimaryUsage")
        let pairs = (bag["DeviceUsagePairs"] as? [[String: Any]] ?? []).compactMap { pair in
            (pair["DeviceUsagePage"] as? Int).flatMap { page in (pair["DeviceUsage"] as? Int).map { UsagePair(page: page, usage: $0) } }
        }
        usagePairs = pairs.isEmpty ? [UsagePair(page: primaryUsagePage, usage: primaryUsage)] : pairs
    }

    var speaksHIDPP: Bool { vendor == Self.logitech && usagePairs.contains { $0.page == UsagePair.hidppPage } }

    /// A keyboard that is not also an external mouse. The built-in keyboard shares its device with the trackpad, so
    /// built-in devices always count.
    var hostsHyper: Bool { usagePairs.contains(.keyboard) && (builtIn || !usagePairs.contains(.mouse)) }
}

struct DeviceKey: Hashable, Sendable {
    var vendor: VendorID
    var product: ProductID
    var builtIn: Bool
    var locationID: UInt32?
    var transport: String?

    init(_ properties: HIDProperties) {
        vendor = properties.vendor
        product = properties.product
        builtIn = properties.builtIn
        locationID = properties.locationID
        transport = properties.transport
    }
}

struct DeviceInstanceID: Hashable, Sendable, CustomStringConvertible {
    let rawValue: UInt64
    var description: String { "#\(rawValue)" }
}

struct SenderID: Hashable, Sendable {
    let rawValue: UInt64
}

struct PresentDevice: Equatable, Sendable {
    var id: DeviceInstanceID
    var key: DeviceKey
    var properties: HIDProperties
    var eventServices: [SenderID]
    var hidpp: HIDPPCapabilities?

    var name: String { properties.name ?? "Unknown device" }
}

/// Groups the IOHIDDevice interfaces of one physical device into a `PresentDevice`. Interfaces are named by their
/// IORegistry entry ids, so this is `DeviceHub`'s bookkeeping without the IOKit calls.
struct DeviceRoster {
    enum Change: Equatable {
        case appeared(PresentDevice)
        case disappeared(PresentDevice)
    }

    private struct Entry {
        var device: PresentDevice
        var interfaces: Set<UInt64>
    }

    private var entries: [DeviceKey: Entry] = [:]
    private var keyOfInterface: [UInt64: DeviceKey] = [:]
    private var nextID: UInt64 = 1

    var devices: [PresentDevice] { entries.values.map(\.device).sorted { $0.id.rawValue < $1.id.rawValue } }

    func tracks(interface: UInt64) -> Bool { keyOfInterface[interface] != nil }

    mutating func interfaceAppeared(_ interface: UInt64, properties: HIDProperties, services: [SenderID]) -> Change? {
        guard keyOfInterface[interface] == nil else { return nil }
        let key = DeviceKey(properties)
        keyOfInterface[interface] = key
        if var entry = entries[key] {
            entry.interfaces.insert(interface)
            entry.device.eventServices += services
            entries[key] = entry
            return nil
        }
        let device = PresentDevice(
            id: DeviceInstanceID(rawValue: nextID), key: key, properties: properties, eventServices: services)
        nextID += 1
        entries[key] = Entry(device: device, interfaces: [interface])
        return .appeared(device)
    }

    mutating func interfaceRemoved(_ interface: UInt64) -> Change? {
        guard let key = keyOfInterface.removeValue(forKey: interface), var entry = entries[key] else { return nil }
        entry.interfaces.remove(interface)
        guard entry.interfaces.isEmpty else {
            entries[key] = entry
            return nil
        }
        entries[key] = nil
        return .disappeared(entry.device)
    }
}

extension DeviceMatch {
    func matches(_ properties: HIDProperties) -> Bool {
        switch self {
        case .builtIn: properties.builtIn
        case .device(let vendor, let product):
            !properties.builtIn && properties.vendor == vendor && properties.product == product
        }
    }

    init(identifying properties: HIDProperties) {
        self = properties.builtIn ? .builtIn : .device(vendor: properties.vendor, product: properties.product)
    }

    var hidutilKeyboardMatching: String {
        let keyboard = "\"PrimaryUsagePage\":1,\"PrimaryUsage\":6"
        switch self {
        case .builtIn:
            return "{\"Built-In\":1,\(keyboard)}"
        case .device(let vendor, let product):
            let hex = { (value: UInt16) in "0x" + String(value, radix: 16, uppercase: true) }
            return "{\"VendorID\":\(hex(vendor.rawValue)),\"ProductID\":\(hex(product.rawValue)),\(keyboard)}"
        }
    }
}

extension Config {
    func profile(for properties: HIDProperties) -> DeviceProfile? {
        guard !ignored.contains(where: { $0.matches(properties) }) else { return nil }
        return devices.first { $0.match.matches(properties) }
    }
}
