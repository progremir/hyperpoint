import HyperpointKit

struct SetupChoices {
    var suggested: ProfileSource
    var others: [ProfileSource]

    init(for device: SettingsDevice, in config: Config) {
        let presets = DevicePreset.offered(for: device.match, kind: device.kind)
        let blank: [ProfileSource] = device.kind == .mouse ? [.blank] : []
        func setsNothing(_ profile: DeviceProfile) -> Bool { profile == DeviceProfile(match: profile.match, name: profile.name) }
        func isAnOfferedPreset(_ profile: DeviceProfile) -> Bool {
            presets.contains { $0.profile(for: profile.match, name: profile.name) == profile }
        }
        let copies = config.devices.filter {
            SettingsDevice.kind(of: $0) == device.kind && !setsNothing($0) && !isAnOfferedPreset($0)
        }
        let sources = presets.map(ProfileSource.preset) + blank + copies.map { .copy(of: $0.match) }
        suggested = sources[0]
        others = Array(sources.dropFirst())
    }
}
