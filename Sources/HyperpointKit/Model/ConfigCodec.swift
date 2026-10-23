public import Foundation

/// Why a config file was rejected. `path` is the coding path, such as `devices[1].rules[0].when`, and is empty
/// for a problem with the whole file.
public struct ConfigError: Error, Equatable, Sendable, CustomStringConvertible {
    public var path: String
    public var message: String

    public init(path: String, message: String) {
        self.path = path
        self.message = message
    }

    public var description: String { path.isEmpty ? message : "\(path): \(message)" }
}

public enum ConfigCodec {
    public static func decode(_ data: Data) throws(ConfigError) -> Config {
        let tree: Any
        do {
            tree = try JSONSerialization.jsonObject(with: data)
        } catch {
            let detail = (error as NSError).userInfo["NSDebugDescription"] as? String ?? "\(error)"
            throw ConfigError(path: "", message: "not valid JSON. \(detail)")
        }
        let config: Config
        do {
            config = try JSONDecoder().decode(Config.self, from: data)
        } catch let error as DecodingError {
            throw ConfigError(error)
        } catch {
            throw ConfigError(path: "", message: "\(error)")
        }
        if let error = unknownKey(in: tree, against: schema(of: config), path: "") { throw error }
        if let error = validate(config) { throw error }
        return config
    }

    /// Pretty printed with sorted keys and a trailing newline, so the same config always gives the same bytes.
    public static func encode(_ config: Config) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try! encoder.encode(config) + Data("\n".utf8)
    }

    private static func schema(of config: Config) -> Any {
        (try? JSONSerialization.jsonObject(with: encode(config))) ?? [:]
    }

    private static func unknownKey(in user: Any, against schema: Any, path: String) -> ConfigError? {
        if let user = user as? [String: Any], let schema = schema as? [String: Any] {
            for key in user.keys.sorted() {
                let child = path.isEmpty ? key : "\(path).\(key)"
                if user[key] is NSNull {
                    return ConfigError(path: child, message: "null is not allowed. Leave the key out instead")
                }
                guard let known = schema[key] else { return ConfigError(path: child, message: "unknown key") }
                if let error = unknownKey(in: user[key]!, against: known, path: child) { return error }
            }
        } else if let user = user as? [Any], let schema = schema as? [Any] {
            for (index, (item, known)) in zip(user, schema).enumerated() {
                if let error = unknownKey(in: item, against: known, path: "\(path)[\(index)]") { return error }
            }
        }
        return nil
    }

    static func validate(_ config: Config) -> ConfigError? {
        if config.version != Config.currentVersion {
            return ConfigError(path: "version", message: "version \(config.version) is not supported")
        }
        for (index, profile) in config.devices.enumerated() {
            let path = "devices[\(index)]"
            if let earlier = config.devices[..<index].firstIndex(where: { $0.match == profile.match }) {
                return ConfigError(path: "\(path).match", message: "the same device as devices[\(earlier)]")
            }
            if config.ignored.contains(profile.match) {
                return ConfigError(path: "\(path).match", message: "this device is also in ignored")
            }
            if let distance = profile.gestures?.distance, !(20...2000).contains(distance) {
                return ConfigError(path: "\(path).gestures.distance", message: "must be between 20 and 2000")
            }
            for (ruleIndex, rule) in (profile.rules ?? []).enumerated() {
                let rulePath = "\(path).rules[\(ruleIndex)]"
                if let problem = RuleShape.problem(with: rule) {
                    return ConfigError(path: "\(rulePath).\(problem.key)", message: problem.message)
                }
                let rules = profile.rules ?? []
                if let earlier = rules[..<ruleIndex].firstIndex(where: {
                    $0.control == rule.control && $0.trigger == rule.trigger
                }) {
                    return ConfigError(path: rulePath, message: "the same control and trigger as rules[\(earlier)]")
                }
            }
        }
        return nil
    }
}

enum RuleShape {
    enum ControlKind { case hidpp, thumbWheel, key, button }
    enum TriggerKind: Hashable { case click, hold, holdMove, scroll }
    enum ActionKind { case system, shortcut, modifier, reverse }

    static let table: [ControlKind: [TriggerKind: Set<ActionKind>]] = [
        .hidpp: [.click: [.system, .shortcut], .holdMove: [.system, .shortcut]],
        .thumbWheel: [.scroll: [.reverse]],
        .key: [.click: [.shortcut], .hold: [.modifier]],
        .button: [.click: [.system, .shortcut]],
    ]

    static func problem(with rule: Rule) -> (key: String, message: String)? {
        let control = kind(of: rule.control)
        let triggers = table[control] ?? [:]
        guard let actions = triggers[kind(of: rule.trigger)] else {
            return ("when", "\"\(rule.trigger.name)\" does not work with this control")
        }
        guard actions.contains(kind(of: rule.action)) else {
            return ("do", "this action does not work with \"\(rule.trigger.name)\" on this control")
        }
        return nil
    }

    static func kind(of control: Control) -> ControlKind {
        switch control {
        case .hidpp: .hidpp
        case .thumbWheel: .thumbWheel
        case .key: .key
        case .button: .button
        }
    }

    static func kind(of trigger: Trigger) -> TriggerKind {
        switch trigger {
        case .click: .click
        case .hold: .hold
        case .holdMove: .holdMove
        case .scroll: .scroll
        }
    }

    static func kind(of action: Action) -> ActionKind {
        switch action {
        case .system: .system
        case .shortcut: .shortcut
        case .modifier: .modifier
        case .reverse: .reverse
        }
    }
}

extension ConfigError {
    init(_ error: DecodingError) {
        switch error {
        case .keyNotFound(let key, let context):
            self.init(path: Self.path(context.codingPath + [key]), message: "missing key")
        case .typeMismatch(let type, let context):
            self.init(path: Self.path(context.codingPath), message: "expected \(Self.describe(type))")
        case .valueNotFound(let type, let context):
            self.init(path: Self.path(context.codingPath), message: "expected \(Self.describe(type))")
        case .dataCorrupted(let context):
            self.init(path: Self.path(context.codingPath), message: context.debugDescription)
        @unknown default:
            self.init(path: "", message: "\(error)")
        }
    }

    static func path(_ keys: [any CodingKey]) -> String {
        keys.reduce(into: "") { path, key in
            if let index = key.intValue {
                path += "[\(index)]"
            } else {
                path += path.isEmpty ? key.stringValue : ".\(key.stringValue)"
            }
        }
    }

    static func describe(_ type: Any.Type) -> String {
        switch type {
        case is String.Type: "a string"
        case is Bool.Type: "true or false"
        case is Int.Type, is Double.Type: "a number"
        case is [Any].Type: "a list"
        case is [String: Any].Type: "an object"
        default: "\(type)"
        }
    }
}
