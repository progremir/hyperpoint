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
    case addDevice(DeviceMatch, name: String, ProfileSource)
    case hyperOn(DeviceMatch, Bool)
    case rename(DeviceMatch, String)
    case kind(DeviceMatch, DeviceKind)
    case addRule(DeviceMatch, Rule)
    case replaceRule(DeviceMatch, RuleKey, Rule)
    case removeRule(DeviceMatch, RuleKey)
    case gestureFire(DeviceMatch, GestureFire)
    case gestureDistance(DeviceMatch, Int)
    /// Nil turns smooth scrolling off.
    case smooth(DeviceMatch, SmoothScroll?)
    case smoothKnob(DeviceMatch, SmoothKnob, Double)
    case curve(DeviceMatch, SpeedCurve)
    case holdToScroll(DeviceMatch, HoldToScroll)
    /// Removes the profile. A connected device then shows as new.
    case forget(DeviceMatch)
    /// Only a device without a profile can be ignored, since the parser rejects a match in both.
    case ignore(DeviceMatch, Bool)

    func applied(to config: Config) -> Config {
        var config = config
        switch self {
        case .hyperKey(let key):
            config.hyper.key = key
        case .addDevice(let match, let name, let source):
            let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !config.ignored.contains(match), !config.devices.contains(where: { $0.match == match })
            else { break }
            let profile: DeviceProfile? =
                switch source {
                case .preset(let preset): preset.isForAnotherModel(than: match) ? nil : preset.profile(for: match, name: name)
                case .copy(let other):
                    config.devices.first { $0.match == other }.map { profile in
                        var copy = profile
                        copy.match = match
                        copy.name = name
                        return copy
                    }
                case .blank: DeviceProfile(match: match, name: name)
                }
            if let profile { config.devices.append(profile) }
        case .hyperOn(let match, let on):
            config.editProfile(match) { $0.hyper = on }
        case .rename(let match, let name):
            let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { break }
            config.editProfile(match) { $0.name = name }
        case .kind(let match, let kind):
            config.editProfile(match) { $0.kind = kind }
        case .addRule(let match, let rule):
            config.editProfile(match) { $0.rules = ($0.rules ?? []) + [rule] }
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
        case .smoothKnob(let match, let knob, let value):
            config.editProfile(match) { profile in
                guard let smooth = profile.scrolling?.smooth else { return }
                profile.scrolling?.smooth = knob.setting(value, in: smooth)
            }
        case .curve(let match, let curve):
            config.editProfile(match) { $0.scrolling?.smooth?.curve = curve }
        case .holdToScroll(let match, let settings):
            config.editProfile(match) { profile in
                var scrolling = profile.scrolling ?? ScrollSettings()
                scrolling.holdToScroll = settings
                profile.scrolling = scrolling
            }
        case .forget(let match):
            config.devices.removeAll { $0.match == match }
        case .ignore(let match, true):
            guard !config.ignored.contains(match), !config.devices.contains(where: { $0.match == match }) else { break }
            config.ignored.append(match)
        case .ignore(let match, false):
            config.ignored.removeAll { $0 == match }
        }
        return config
    }

    /// For the log, in the file's own key names.
    var logDescription: String {
        switch self {
        case .hyperKey(let key): "hyper.key = \(key.name ?? "?")"
        case .addDevice(let match, _, .preset(let preset)): "devices += \(Self.json(match)) from preset \(preset)"
        case .addDevice(let match, _, .copy(let other)): "devices += \(Self.json(match)) from copy of \(Self.json(other))"
        case .addDevice(let match, _, .blank): "devices += \(Self.json(match)) blank"
        case .hyperOn(let match, let on): "\(Self.profile(match)).hyper = \(on)"
        case .rename(let match, let name): "\(Self.profile(match)).name = \(Self.json(name))"
        case .kind(let match, let kind): "\(Self.profile(match)).kind = \(kind.rawValue)"
        case .addRule(let match, let rule): "\(Self.profile(match)).rules += \(Self.json(rule))"
        case .replaceRule(let match, let key, let rule):
            "\(Self.profile(match)).rules[\(Self.json(key.control)) \(key.trigger.name)] = \(Self.json(rule))"
        case .removeRule(let match, let key):
            "\(Self.profile(match)).rules -= \(Self.json(key.control)) \(key.trigger.name)"
        case .gestureFire(let match, let fire): "\(Self.profile(match)).gestures.fire = \(fire.rawValue)"
        case .gestureDistance(let match, let distance): "\(Self.profile(match)).gestures.distance = \(distance)"
        case .smooth(let match, let smooth):
            "\(Self.profile(match)).scrolling.smooth = \(smooth.map(Self.json) ?? "none")"
        case .smoothKnob(let match, let knob, let value):
            "\(Self.profile(match)).scrolling.smooth.\(knob.key) = \(value.formatted(.number.locale(Locale(identifier: "en_US_POSIX")).grouping(.never)))"
        case .curve(let match, let curve): "\(Self.profile(match)).scrolling.smooth.curve = \(Self.json(curve))"
        case .holdToScroll(let match, let settings):
            "\(Self.profile(match)).scrolling.holdToScroll = \(Self.json(settings))"
        case .forget(let match): "devices -= \(Self.json(match))"
        case .ignore(let match, let on): "ignored \(on ? "+=" : "-=") \(Self.json(match))"
        }
    }

    private static func profile(_ match: DeviceMatch) -> String { "devices[\(json(match))]" }

    private static func json(_ value: some Encodable) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(value)).map { String(decoding: $0, as: UTF8.self) } ?? "?"
    }
}

enum ProfileSource: Hashable, Sendable {
    case preset(DevicePreset)
    case copy(of: DeviceMatch)
    case blank
}

extension Config {
    fileprivate mutating func editProfile(_ match: DeviceMatch, _ change: (inout DeviceProfile) -> Void) {
        guard let index = devices.firstIndex(where: { $0.match == match }) else { return }
        change(&devices[index])
    }
}
