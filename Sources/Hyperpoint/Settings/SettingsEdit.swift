import Foundation
import HyperpointKit

/// A rule's identity in its profile. The parser rejects two rules with the same control and trigger.
struct RuleKey: Hashable, Sendable {
    var control: Control
    var trigger: Trigger

    init(_ rule: Rule) {
        control = rule.control
        trigger = rule.trigger
    }
}

/// Every change the settings window makes to the config, as data. An edit names its profile by match and its rule
/// by `RuleKey`, both unique in a valid file, so applying it to a file that changed since the window drew it still
/// lands where the user meant, or does nothing.
enum SettingsEdit: Equatable, Sendable {
    case hyperKey(HIDUsage)
    /// Creates the profile when the keyboard has none.
    case hyperOn(DeviceMatch, name: String, Bool)
    case rename(DeviceMatch, String)
    /// Creates the profile when the device has none.
    case addRule(DeviceMatch, name: String, Rule)
    case replaceRule(DeviceMatch, RuleKey, Rule)
    case removeRule(DeviceMatch, RuleKey)
    case gestureFire(DeviceMatch, GestureFire)
    case gestureDistance(DeviceMatch, Int)
    /// Nil turns smooth scrolling off.
    case smooth(DeviceMatch, SmoothScroll?)
    /// Nil turns acceleration off.
    case acceleration(DeviceMatch, Acceleration?)
    case smoothKnob(DeviceMatch, SmoothKnob, Double)

    func applied(to config: Config) -> Config {
        var config = config
        switch self {
        case .hyperKey(let key):
            config.hyper.key = key
        case .hyperOn(let match, let name, let on):
            if !config.editProfile(match, { $0.hyper = on }), on {
                config.devices.append(DeviceProfile(match: match, name: name, hyper: true))
            }
        case .rename(let match, let name):
            let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { break }
            config.editProfile(match) { $0.name = name }
        case .addRule(let match, let name, let rule):
            if !config.editProfile(match, { $0.rules = ($0.rules ?? []) + [rule] }) {
                config.devices.append(DeviceProfile(match: match, name: name, rules: [rule]))
            }
        case .replaceRule(let match, let key, let rule):
            config.editProfile(match) { profile in
                guard let index = profile.rules?.firstIndex(where: { RuleKey($0) == key }) else { return }
                profile.rules?[index] = rule
            }
        case .removeRule(let match, let key):
            config.editProfile(match) { $0.rules?.removeAll { RuleKey($0) == key } }
        case .gestureFire(let match, let fire):
            config.editProfile(match) { $0.gestures = GestureSettings(fire: fire, distance: ($0.gestures ?? .default).distance) }
        case .gestureDistance(let match, let distance):
            config.editProfile(match) { $0.gestures = GestureSettings(fire: ($0.gestures ?? .default).fire, distance: distance) }
        case .smooth(let match, let smooth):
            config.editProfile(match) { profile in
                guard smooth != nil || profile.scrolling != nil else { return }
                var scrolling = profile.scrolling ?? ScrollSettings()
                scrolling.smooth = smooth
                profile.scrolling = scrolling
            }
        case .acceleration(let match, let acceleration):
            config.editProfile(match) { $0.scrolling?.smooth?.acceleration = acceleration }
        case .smoothKnob(let match, let knob, let value):
            config.editProfile(match) { profile in
                guard let smooth = profile.scrolling?.smooth else { return }
                profile.scrolling?.smooth = knob.setting(value, in: smooth)
            }
        }
        return config
    }

    /// For the log, in the file's own key names.
    var logDescription: String {
        switch self {
        case .hyperKey(let key): "hyper.key = \(key.name ?? "?")"
        case .hyperOn(let match, _, let on): "\(Self.profile(match)).hyper = \(on)"
        case .rename(let match, let name): "\(Self.profile(match)).name = \(Self.json(name))"
        case .addRule(let match, _, let rule): "\(Self.profile(match)).rules += \(Self.json(rule))"
        case .replaceRule(let match, let key, let rule):
            "\(Self.profile(match)).rules[\(Self.json(key.control)) \(key.trigger.name)] = \(Self.json(rule))"
        case .removeRule(let match, let key):
            "\(Self.profile(match)).rules -= \(Self.json(key.control)) \(key.trigger.name)"
        case .gestureFire(let match, let fire): "\(Self.profile(match)).gestures.fire = \(fire.rawValue)"
        case .gestureDistance(let match, let distance): "\(Self.profile(match)).gestures.distance = \(distance)"
        case .smooth(let match, let smooth):
            "\(Self.profile(match)).scrolling.smooth = \(smooth.map(Self.json) ?? "none")"
        case .acceleration(let match, let acceleration):
            "\(Self.profile(match)).scrolling.smooth.acceleration = \(acceleration.map(Self.json) ?? "false")"
        case .smoothKnob(let match, let knob, let value):
            "\(Self.profile(match)).scrolling.smooth.\(knob.key) = \(value.formatted(.number.locale(Locale(identifier: "en_US_POSIX")).grouping(.never)))"
        }
    }

    private static func profile(_ match: DeviceMatch) -> String { "devices[\(json(match))]" }

    private static func json(_ value: some Encodable) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(value)).map { String(decoding: $0, as: UTF8.self) } ?? "?"
    }
}

extension Config {
    /// Changes the profile for `match` and says whether there was one.
    @discardableResult
    fileprivate mutating func editProfile(_ match: DeviceMatch, _ change: (inout DeviceProfile) -> Void) -> Bool {
        guard let index = devices.firstIndex(where: { $0.match == match }) else { return false }
        change(&devices[index])
        return true
    }
}
