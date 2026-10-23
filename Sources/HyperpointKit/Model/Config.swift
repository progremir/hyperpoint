/// The parsed `~/.config/hyperpoint/config.json`. `ConfigCodec.decode` is the only way in.
public struct Config: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var hyper: HyperSettings
    public var devices: [DeviceProfile]
    public var ignored: [DeviceMatch]

    public init(version: Int, hyper: HyperSettings, devices: [DeviceProfile], ignored: [DeviceMatch]) {
        self.version = version
        self.hyper = hyper
        self.devices = devices
        self.ignored = ignored
    }
}

public struct HyperSettings: Codable, Equatable, Sendable {
    /// The key that becomes hyper on every keyboard whose profile has `"hyper": true`.
    public var key: HIDUsage
    public var onTap: HyperTap

    public init(key: HIDUsage, onTap: HyperTap) {
        self.key = key
        self.onTap = onTap
    }
}

public enum HyperTap: String, Codable, Sendable {
    case nothing
}

/// One device entry. Every optional section that is absent means "leave the device as macOS has it".
public struct DeviceProfile: Codable, Equatable, Sendable {
    public var match: DeviceMatch
    public var name: String
    public var rules: [Rule]?
    public var gestures: GestureSettings?
    public var scrolling: ScrollSettings?
    public var hyper: Bool?

    public init(
        match: DeviceMatch, name: String, rules: [Rule]? = nil, gestures: GestureSettings? = nil,
        scrolling: ScrollSettings? = nil, hyper: Bool? = nil
    ) {
        self.match = match
        self.name = name
        self.rules = rules
        self.gestures = gestures
        self.scrolling = scrolling
        self.hyper = hyper
    }
}

public enum DeviceMatch: Hashable, Sendable {
    case device(vendor: VendorID, product: ProductID)
    case builtIn
}

public struct VendorID: HexCoded {
    public let rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }
    public static let digits = 4
}

public struct ProductID: HexCoded {
    public let rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }
    public static let digits = 4
}

/// A HID++ control id, such as 0xC3 for the MX Master 3 gesture button.
public struct CID: HexCoded {
    public let rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }
    public static let digits = 2
}

public struct Rule: Codable, Equatable, Sendable {
    public var control: Control
    public var trigger: Trigger
    public var action: Action

    public init(control: Control, trigger: Trigger, action: Action) {
        self.control = control
        self.trigger = trigger
        self.action = action
    }

    enum CodingKeys: String, CodingKey {
        case control
        case trigger = "when"
        case action = "do"
    }
}

public enum Control: Hashable, Sendable {
    case hidpp(CID)
    case thumbWheel
    /// A key that a mouse sends from its keyboard interface.
    case key(HIDUsage)
    case button(Int)
}

public enum Trigger: Hashable, Sendable {
    case click
    case hold
    case holdMove(Direction)
    case scroll
}

public enum Direction: String, CaseIterable, Sendable {
    case up = "Up", down = "Down", left = "Left", right = "Right"
}

public enum Action: Hashable, Sendable {
    case system(SystemAction)
    case shortcut(Chord)
    case modifier(HeldModifier)
    case reverse
}

/// The raw value is the CGS symbolic hotkey id, so this enum is the id table.
public enum SystemAction: Int, CaseIterable, Sendable {
    case missionControl = 32
    case appExpose = 33
    case spaceLeft = 79
    case spaceRight = 81

    public var name: String { "\(self)" }
}

/// A key with modifiers, written "shift+cmd+4" in the file.
public struct Chord: Hashable, Sendable {
    public var key: KeyCode
    public var modifiers: Modifiers

    public init(key: KeyCode, modifiers: Modifiers) {
        self.key = key
        self.modifiers = modifiers
    }
}

public struct GestureSettings: Codable, Equatable, Sendable {
    public var fire: GestureFire
    /// Net movement, in sensor counts, that turns a hold into a swipe.
    public var distance: Int

    public init(fire: GestureFire, distance: Int) {
        self.fire = fire
        self.distance = distance
    }
}

public enum GestureFire: String, Codable, Sendable {
    case pastDistance
    case onRelease
}

public struct ScrollSettings: Codable, Equatable, Sendable {
    public var smooth: SmoothScroll?
    public var hiResWheel: Bool?
    public var rightButtonPan: RightButtonPan?
    public var clickThrough: ClickThrough?

    public init(
        smooth: SmoothScroll? = nil, hiResWheel: Bool? = nil, rightButtonPan: RightButtonPan? = nil,
        clickThrough: ClickThrough? = nil
    ) {
        self.smooth = smooth
        self.hiResWheel = hiResWheel
        self.rightButtonPan = rightButtonPan
        self.clickThrough = clickThrough
    }
}

public struct SmoothScroll: Codable, Equatable, Sendable {
    public var duration: Double
    public var brake: Double
    public var acceleration: Bool

    public init(duration: Double, brake: Double, acceleration: Bool) {
        self.duration = duration
        self.brake = brake
        self.acceleration = acceleration
    }
}

public struct RightButtonPan: Codable, Equatable, Sendable {
    public var momentum: Bool
    public init(momentum: Bool) { self.momentum = momentum }
}

public struct ClickThrough: Codable, Equatable, Sendable {
    public var left: Bool
    public var right: Bool

    public init(left: Bool, right: Bool) {
        self.left = left
        self.right = right
    }
}

extension Config {
    /// Reproduces the BetterMouse and Karabiner setup this app replaces. docs/architecture.md shows it as the
    /// default file, and a test keeps the two equal.
    public static let `default` = Config(
        version: currentVersion,
        hyper: HyperSettings(key: HIDUsage(name: "capsLock")!, onTap: .nothing),
        devices: [
            DeviceProfile(
                match: .device(vendor: VendorID(rawValue: 0x046D), product: ProductID(rawValue: 0xB023)),
                name: "MX Master 3",
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
                ],
                gestures: GestureSettings(fire: .pastDistance, distance: 120),
                scrolling: ScrollSettings(
                    smooth: SmoothScroll(duration: 4, brake: 2, acceleration: true),
                    hiResWheel: true,
                    rightButtonPan: RightButtonPan(momentum: true),
                    clickThrough: ClickThrough(left: true, right: true)
                )
            ),
            DeviceProfile(
                match: .device(vendor: VendorID(rawValue: 0x1EA7), product: ProductID(rawValue: 0x0002)),
                name: "2.4G Mouse",
                rules: [
                    Rule(control: .key(HIDUsage(name: "escape")!), trigger: .hold, action: .modifier(.rightOption)),
                    Rule(
                        control: .key(HIDUsage(name: "return")!), trigger: .click,
                        action: .shortcut(Chord(key: KeyCode(name: "s")!, modifiers: [.option, .shift]))
                    ),
                ]
            ),
            DeviceProfile(match: .builtIn, name: "Built-in Keyboard", hyper: true),
            DeviceProfile(
                match: .device(vendor: VendorID(rawValue: 0x004C), product: ProductID(rawValue: 0x0321)),
                name: "Magic Keyboard", hyper: true
            ),
        ],
        ignored: []
    )
}
