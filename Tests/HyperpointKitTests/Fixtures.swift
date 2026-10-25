@testable import HyperpointKit

enum Bags {
    static let builtInKeyboard: [String: any Sendable] = [
        "Built-In": 1, "Transport": "FIFO", "LocationID": 111, "Product": "Apple Internal Keyboard / Trackpad",
        "PrimaryUsagePage": 1, "PrimaryUsage": 6,
        "DeviceUsagePairs": [
            ["DeviceUsagePage": 1, "DeviceUsage": 6], ["DeviceUsagePage": 12, "DeviceUsage": 1],
            ["DeviceUsagePage": 0xFF00, "DeviceUsage": 6],
        ],
    ]
    /// `hidutil list` shows the same keyboard as vendor 0x0, product 0x0.
    static let builtInKeyboardAsListed: [String: any Sendable] = builtInKeyboard.merging(["VendorID": 0, "ProductID": 0]) { $1 }
    static let magicKeyboard: [String: any Sendable] = [
        "VendorID": 0x4C, "ProductID": 0x321, "Built-In": 0, "Transport": "Bluetooth", "LocationID": 2_064_679_845,
        "Product": "Эмир’s Magic Keyboard", "PrimaryUsagePage": 1, "PrimaryUsage": 6,
    ]
    static let mxMaster3: [String: any Sendable] = [
        "VendorID": 1133, "ProductID": 45091, "Transport": "Bluetooth Low Energy", "LocationID": 745_701_390,
        "Product": "MX Master 3", "PrimaryUsagePage": 1, "PrimaryUsage": 6,
        "DeviceUsagePairs": [
            ["DeviceUsagePage": 1, "DeviceUsage": 6], ["DeviceUsagePage": 1, "DeviceUsage": 2],
            ["DeviceUsagePage": 1, "DeviceUsage": 1], ["DeviceUsagePage": 0xFF43, "DeviceUsage": 0x202],
        ],
    ]
    static let karabinerVirtualKeyboard: [String: any Sendable] = [
        "VendorID": 0x5AC, "ProductID": 0x24F, "LocationID": 0, "Product": "Karabiner DriverKit VirtualHIDKeyboard 1.8.0",
        "PrimaryUsagePage": 1, "PrimaryUsage": 6,
    ]
}

func present(_ id: UInt64, _ bag: [String: any Sendable], services: [UInt64] = []) -> PresentDevice {
    let properties = HIDProperties(bag: bag)
    return PresentDevice(
        id: DeviceInstanceID(rawValue: id), key: DeviceKey(properties), properties: properties,
        eventServices: services.map(SenderID.init))
}

let thisMac = [
    present(1, Bags.builtInKeyboard), present(2, Bags.magicKeyboard), present(3, Bags.mxMaster3),
    present(4, Bags.karabinerVirtualKeyboard),
]

let capsLock = HIDUsage(name: "capsLock")!

let measuredMXCapabilities = HIDPPCapabilities(
    controls: [
        (0x50, false, false), (0x51, false, false), (0x52, true, true), (0x53, true, true), (0x56, true, true),
        (0xC3, true, true), (0xC4, true, true), (0xD7, true, true),
    ].map { HIDPPCapabilities.Control(cid: CID(rawValue: $0.0), divertable: $0.1, rawXY: $0.2) },
    thumbWheel: true)

func discovered(_ device: PresentDevice, _ capabilities: HIDPPCapabilities = measuredMXCapabilities) -> PresentDevice {
    var device = device
    device.hidpp = capabilities
    return device
}

extension Config {
    static let example = Config(
        version: empty.version, hyper: empty.hyper,
        devices: [
            DevicePreset.mxMaster3.profile(
                for: .device(vendor: .logitech, product: ProductID(rawValue: 0xB023)), name: "MX Master 3"),
            DevicePreset.mouse24G.profile(
                for: .device(vendor: VendorID(rawValue: 0x1EA7), product: ProductID(rawValue: 0x0002)), name: "2.4G Mouse"),
            DevicePreset.keyboard.profile(for: .builtIn, name: "Built-in Keyboard"),
            DevicePreset.keyboard.profile(
                for: .device(vendor: VendorID(rawValue: 0x004C), product: ProductID(rawValue: 0x0321)), name: "Magic Keyboard"),
        ],
        ignored: [])
}
