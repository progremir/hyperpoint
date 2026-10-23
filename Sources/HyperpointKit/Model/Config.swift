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

    /// Files written before hold to scroll name right-button pan, which decoding converts to a rule.
    private enum LegacyScrollingKeys: String, CodingKey { case rightButtonPan }
    private struct RightButtonPan: Decodable { var momentum: Bool }

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

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        match = try container.decode(DeviceMatch.self, forKey: .match)
        name = try container.decode(String.self, forKey: .name)
        rules = try container.decodeIfPresent([Rule].self, forKey: .rules)
        gestures = try container.decodeIfPresent(GestureSettings.self, forKey: .gestures)
        scrolling = try container.decodeIfPresent(ScrollSettings.self, forKey: .scrolling)
        hyper = try container.decodeIfPresent(Bool.self, forKey: .hyper)
        guard container.contains(.scrolling),
            let pan = try container.nestedContainer(keyedBy: LegacyScrollingKeys.self, forKey: .scrolling)
                .decodeIfPresent(RightButtonPan.self, forKey: .rightButtonPan)
        else { return }
        let rule = Rule(control: .button(1), trigger: .holdMove(nil), action: .scroll)
        if !(rules ?? []).contains(where: { $0.control == rule.control && $0.trigger == rule.trigger }) {
            rules = (rules ?? []) + [rule]
        }
        if scrolling?.holdToScroll == nil {
            scrolling?.holdToScroll = HoldToScroll(speed: 1, direction: .grab, momentum: pan.momentum)
        }
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
    /// A plain mouse button, numbered as CGEvent numbers them: 1 is the right button, 2 the middle, 3 back and
    /// 4 forward. The left button, 0, cannot have rules.
    case button(Int)

    public static let buttonRange: ClosedRange<Int> = 1...31
}

public enum Trigger: Hashable, Sendable {
    case click
    case hold
    /// Hold and move one way, or with no direction, hold and move any way.
    case holdMove(Direction?)
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
    /// While the button is held, moving the mouse scrolls the page instead of moving the pointer.
    case scroll
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

    public static let `default` = GestureSettings(fire: .pastDistance, distance: 120)
    /// The distances the parser accepts.
    public static let distanceRange: ClosedRange<Int> = 20...2000

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
    public var holdToScroll: HoldToScroll?
    public var clickThrough: ClickThrough?

    public init(
        smooth: SmoothScroll? = nil, hiResWheel: Bool? = nil, holdToScroll: HoldToScroll? = nil,
        clickThrough: ClickThrough? = nil
    ) {
        self.smooth = smooth
        self.hiResWheel = hiResWheel
        self.holdToScroll = holdToScroll
        self.clickThrough = clickThrough
    }
}

/// Smooth scrolling for the main wheel. Each wheel step glides the page by the distance the speed curve gives it.
public struct SmoothScroll: Codable, Equatable, Sendable {
    /// How long a step's glide lasts after it reaches full speed, in tenths of a second.
    public var duration: Double
    /// A step's glide slows as (1 - t / duration) ^ brake. At 1 it slows evenly, and higher values brake hard first
    /// and coast into a soft stop.
    public var brake: Double
    /// Milliseconds a step's glide takes to rise from rest to full speed, without changing how far it goes.
    public var easeIn: Double
    /// How fast the page scrolls for how fast the wheel spins.
    public var curve: SpeedCurve

    private enum CodingKeys: String, CodingKey { case duration, brake, easeIn, curve }
    /// Files written before the curve still parse, and these keys convert to an equivalent curve.
    private enum LegacyKeys: String, CodingKey { case speed, startBoost, acceleration }

    public static let defaultEaseIn = 60.0

    public static let `default` = SmoothScroll(duration: 4, brake: 2, easeIn: defaultEaseIn, curve: .default)

    /// The values the parser accepts.
    public static let durationRange: ClosedRange<Double> = 1...20
    public static let brakeRange: ClosedRange<Double> = 0.5...10
    public static let easeInRange: ClosedRange<Double> = 0...300

    public init(duration: Double, brake: Double, easeIn: Double, curve: SpeedCurve) {
        self.duration = duration
        self.brake = brake
        self.easeIn = easeIn
        self.curve = curve
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        duration = try container.decode(Double.self, forKey: .duration)
        brake = try container.decode(Double.self, forKey: .brake)
        easeIn = try container.decodeIfPresent(Double.self, forKey: .easeIn) ?? Self.defaultEaseIn
        let legacy = try decoder.container(keyedBy: LegacyKeys.self)
        if let curve = try container.decodeIfPresent(SpeedCurve.self, forKey: .curve) {
            self.curve = curve
        } else if legacy.allKeys.isEmpty {
            curve = .default
        } else {
            let acceleration: SpeedCurve.LegacyAcceleration?
            if let on = try? legacy.decode(Bool.self, forKey: .acceleration) {
                acceleration = on ? .default : nil
            } else {
                acceleration = try legacy.decodeIfPresent(SpeedCurve.LegacyAcceleration.self, forKey: .acceleration)
            }
            curve = SpeedCurve(
                speed: try legacy.decodeIfPresent(Double.self, forKey: .speed) ?? 40,
                startBoost: try legacy.decodeIfPresent(Double.self, forKey: .startBoost) ?? 2,
                acceleration: acceleration, glide: duration / 10)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(duration, forKey: .duration)
        try container.encode(brake, forKey: .brake)
        try container.encode(easeIn, forKey: .easeIn)
        try container.encode(curve, forKey: .curve)
    }
}

/// How the page moves for a button whose rule is hold and move → scroll.
public struct HoldToScroll: Codable, Equatable, Sendable {
    /// How far the page moves for how far the mouse moves. At 1 the page follows the hand.
    public var speed: Double
    public var direction: HoldScrollDirection
    /// On release the page keeps the hand's last speed and glides to a stop, like a trackpad.
    public var momentum: Bool

    public static let `default` = HoldToScroll(speed: 1, direction: .grab, momentum: true)
    /// The speeds the parser accepts.
    public static let speedRange: ClosedRange<Double> = 0.25...4

    public init(speed: Double, direction: HoldScrollDirection, momentum: Bool) {
        self.speed = speed
        self.direction = direction
        self.momentum = momentum
    }
}

public enum HoldScrollDirection: String, Codable, CaseIterable, Sendable {
    /// The page moves with the hand, like dragging it on a trackpad.
    case grab
    /// Moving the hand down scrolls down, the way the wheel does.
    case wheel
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
                    smooth: .default,
                    hiResWheel: true,
                    holdToScroll: .default,
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
