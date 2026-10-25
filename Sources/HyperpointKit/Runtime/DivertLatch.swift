import Foundation

/// The mice a listen diverted since the last clean quit, kept across a crash. A slot for one starts as if this
/// connection had written, so a profile without HID++ rules writes native once instead of keeping the listen's divert.
/// An entry that outlived its divert costs one native write, which is right in every state a crash could leave.
struct DivertLatch {
    private static let key = "listenDiverted"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private var entries: [String] { defaults.stringArray(forKey: Self.key) ?? [] }

    func contains(_ match: DeviceMatch) -> Bool { entries.contains(match.hidutilKeyboardMatching) }

    /// Before the listen's first HID++ write, so a crash right after it still finds the entry.
    func insert(_ match: DeviceMatch) {
        guard !contains(match) else { return }
        defaults.set(entries + [match.hidutilKeyboardMatching], forKey: Self.key)
    }

    func clear() { defaults.removeObject(forKey: Self.key) }
}
