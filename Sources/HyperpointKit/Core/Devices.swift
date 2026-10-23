/// The IOKit properties of one HID interface that Hyperpoint reads, parsed once at the `DeviceHub` boundary.
struct HIDProperties: Equatable, Sendable {
    var vendor: VendorID
    var product: ProductID
    var builtIn: Bool
    var transport: String?
    var locationID: UInt32?
    var name: String?
    var primaryUsagePage: Int
    var primaryUsage: Int

    static let keys = [
        "VendorID", "ProductID", "Built-In", "Transport", "LocationID", "Product", "PrimaryUsagePage", "PrimaryUsage",
    ]

    /// A missing number reads as 0. The built-in keyboard has no VendorID or ProductID at all (measured).
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
    }
}

/// What makes two interfaces parts of one physical device.
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

/// One appearance of a device. A reconnect is a new instance.
struct DeviceInstanceID: Hashable, Sendable, CustomStringConvertible {
    let rawValue: UInt64
    var description: String { "#\(rawValue)" }
}

/// The registry id of a HID event service, which is what `IOHIDEventGetSenderID` reports for its events.
struct SenderID: Hashable, Sendable {
    let rawValue: UInt64
}

/// A connected device, grouped from its IOHIDDevice interfaces.
struct PresentDevice: Equatable, Sendable {
    var id: DeviceInstanceID
    var key: DeviceKey
    var properties: HIDProperties
    var eventServices: [SenderID]

    var name: String { properties.name ?? "Unknown device" }
}

extension DeviceMatch {
    /// The authority on which profile a device has. IOHIDManager ignores `Built-In` (measured), so its matching
    /// is only a prefilter.
    func matches(_ properties: HIDProperties) -> Bool {
        switch self {
        case .builtIn: properties.builtIn
        case .device(let vendor, let product):
            !properties.builtIn && properties.vendor == vendor && properties.product == product
        }
    }

    /// The match that names this device, which also selects its keyboard service for `hidutil`.
    init(identifying properties: HIDProperties) {
        self = properties.builtIn ? .builtIn : .device(vendor: properties.vendor, product: properties.product)
    }

    /// `hidutil --matching` for the device's keyboard service, which selects exactly one service for each of the
    /// built-in and Magic keyboards (measured).
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
    /// The profile for a device, or nil when it has none or the user ignored it.
    func profile(for properties: HIDProperties) -> DeviceProfile? {
        guard !ignored.contains(where: { $0.matches(properties) }) else { return nil }
        return devices.first { $0.match.matches(properties) }
    }
}
