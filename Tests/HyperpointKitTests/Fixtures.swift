@testable import HyperpointKit

enum Bags {
    static let builtInKeyboard: [String: any Sendable] = [
        "Built-In": 1, "Transport": "FIFO", "LocationID": 111, "Product": "Apple Internal Keyboard / Trackpad",
        "PrimaryUsagePage": 1, "PrimaryUsage": 6,
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
    ]
    static let karabinerVirtualKeyboard: [String: any Sendable] = [
        "VendorID": 0x5AC, "ProductID": 0x24F, "LocationID": 0, "Product": "Karabiner DriverKit VirtualHIDKeyboard 1.8.0",
        "PrimaryUsagePage": 1, "PrimaryUsage": 6,
    ]
}

func present(_ id: UInt64, _ bag: [String: any Sendable]) -> PresentDevice {
    let properties = HIDProperties(bag: bag)
    return PresentDevice(
        id: DeviceInstanceID(rawValue: id), key: DeviceKey(properties), properties: properties, eventServices: [])
}

let thisMac = [
    present(1, Bags.builtInKeyboard), present(2, Bags.magicKeyboard), present(3, Bags.mxMaster3),
    present(4, Bags.karabinerVirtualKeyboard),
]

let capsLock = HIDUsage(name: "capsLock")!
