/// A starting profile, written into the file once when the user sets a device up. Nothing in the file says which
/// preset a profile came from, so changing a preset never changes a profile already saved.
public enum DevicePreset: CaseIterable, Sendable {
    case mxMaster3
    case mouse24G
    case keyboard

    enum Fit: Equatable {
        case exact(DeviceMatch)
        case kind(DeviceKind)
    }

    var fit: Fit {
        switch self {
        case .mxMaster3: .exact(.device(vendor: .logitech, product: ProductID(rawValue: 0xB023)))
        case .mouse24G: .exact(.device(vendor: VendorID(rawValue: 0x1EA7), product: ProductID(rawValue: 0x0002)))
        case .keyboard: .kind(.keyboard)
        }
    }

    public func profile(for match: DeviceMatch, name: String) -> DeviceProfile {
        switch self {
        case .mxMaster3:
            DeviceProfile(
                match: match, name: name,
                rules: [
                    Rule(control: .hidpp(CID(rawValue: 0xC3)), trigger: .click, action: .system(.missionControl)),
                    Rule(control: .hidpp(CID(rawValue: 0xC3)), trigger: .holdMove(.down), action: .system(.appExpose)),
                    Rule(control: .hidpp(CID(rawValue: 0xC3)), trigger: .holdMove(.left), action: .system(.spaceLeft)),
                    Rule(control: .hidpp(CID(rawValue: 0xC3)), trigger: .holdMove(.right), action: .system(.spaceRight)),
                    Rule(
                        control: .hidpp(CID(rawValue: 0xC4)), trigger: .click,
                        action: .shortcut(Chord(key: KeyCode(name: "4")!, modifiers: [.shift, .command]))
                    ),
                    Rule(control: .thumbWheel, trigger: .scroll, action: .reverse),
                    Rule(control: .button(1), trigger: .holdMove(nil), action: .scroll),
                ],
                gestures: GestureSettings(fire: .pastDistance, distance: 120),
                scrolling: ScrollSettings(
                    smooth: .default,
                    hiResWheel: true,
                    holdToScroll: .default,
                    clickThrough: ClickThrough(left: true, right: true)
                )
            )
        case .mouse24G:
            DeviceProfile(
                match: match, name: name,
                rules: [
                    Rule(control: .key(HIDUsage(name: "escape")!), trigger: .hold, action: .modifier(.rightOption)),
                    Rule(
                        control: .key(HIDUsage(name: "return")!), trigger: .click,
                        action: .shortcut(Chord(key: KeyCode(name: "s")!, modifiers: [.option, .shift]))
                    ),
                ]
            )
        case .keyboard:
            DeviceProfile(match: match, name: name, hyper: true)
        }
    }

    public func isForAnotherModel(than match: DeviceMatch) -> Bool {
        switch fit {
        case .exact(let model): model != match
        case .kind: false
        }
    }

    /// The presets for a device, best first. A preset made for this exact device comes first whatever its kind, since
    /// the 2.4G mouse may show up as a keyboard. Then the presets for its kind.
    public static func offered(for match: DeviceMatch, kind: DeviceKind) -> [DevicePreset] {
        allCases.filter { $0.fit == .exact(match) } + allCases.filter { $0.fit == .kind(kind) }
    }
}
