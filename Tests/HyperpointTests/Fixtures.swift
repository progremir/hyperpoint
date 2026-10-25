import HyperpointKit

let mx = DeviceMatch.device(vendor: .logitech, product: ProductID(rawValue: 0xB023))
let mouse24G = DeviceMatch.device(vendor: VendorID(rawValue: 0x1EA7), product: ProductID(rawValue: 0x0002))
let magicKeyboard = DeviceMatch.device(vendor: VendorID(rawValue: 0x004C), product: ProductID(rawValue: 0x0321))

extension Config {
    static let example = Config(
        version: empty.version, hyper: empty.hyper,
        devices: [
            DevicePreset.mxMaster3.profile(for: mx, name: "MX Master 3"),
            DevicePreset.mouse24G.profile(for: mouse24G, name: "2.4G Mouse"),
            DevicePreset.keyboard.profile(for: .builtIn, name: "Built-in Keyboard"),
            DevicePreset.keyboard.profile(for: magicKeyboard, name: "Magic Keyboard"),
        ],
        ignored: [])
}
