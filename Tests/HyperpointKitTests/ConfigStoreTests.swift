import Foundation
import HyperpointKit
import Testing

private let firstLaunch = ConfigStore(
    url: FileManager.default.temporaryDirectory.appending(path: "hyperpoint-\(UUID().uuidString)/config.json"))

@Suite struct ConfigStoreTests {
    let url: URL

    init() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "hyperpoint-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appending(path: "config.json")
        try ConfigCodec.encode(.example).write(to: url)
    }

    func onDisk() throws -> Config { try ConfigCodec.decode(try Data(contentsOf: url)) }

    @Test func aFirstLaunchWritesAConfigWithNoDevices() async throws {
        await firstLaunch.start()
        #expect(try ConfigCodec.decode(try Data(contentsOf: firstLaunch.url)) == Config.empty)
    }

    @Test func updateSavesTheChangeAndPublishesIt() async throws {
        let store = ConfigStore(url: url)
        try await store.update { config in
            var config = config
            config.devices[0].scrolling?.smooth?.duration = 7
            return config
        }
        #expect(try onDisk().devices[0].scrolling?.smooth?.duration == 7)
        let published = await store.snapshots().first { _ in true }
        #expect(published?.config == (try onDisk()))
        #expect(published?.error == nil)
    }

    @Test func updateEditsTheFileAsItIsOnDisk() async throws {
        let store = ConfigStore(url: url)
        try await store.update { config in
            var config = config
            config.hyper.key = HIDUsage(name: "f5")!
            return config
        }
        var handEdited = try onDisk()
        handEdited.devices[1].name = "Edited by hand"
        try ConfigCodec.encode(handEdited).write(to: url)
        try await store.update { config in
            var config = config
            config.devices[0].scrolling?.smooth?.duration = 7
            return config
        }
        #expect(try onDisk().devices[1].name == "Edited by hand")
        #expect(try onDisk().hyper.key == HIDUsage(name: "f5"))
        #expect(try onDisk().devices[0].scrolling?.smooth?.duration == 7)
    }

    @Test func updateRefusesWhileTheFileIsInvalid() async throws {
        let store = ConfigStore(url: url)
        let broken = Data("{ \"version\": 1,".utf8)
        try broken.write(to: url)
        await #expect(throws: ConfigError.self) {
            try await store.update { config in
                var config = config
                config.hyper.key = HIDUsage(name: "f5")!
                return config
            }
        }
        #expect(try Data(contentsOf: url) == broken)
    }

    @Test func updateRefusesAResultTheParserRejects() async throws {
        let store = ConfigStore(url: url)
        let before = try Data(contentsOf: url)
        let error = await #expect(throws: ConfigError.self) {
            try await store.update { config in
                var config = config
                config.devices[0].scrolling?.smooth?.duration = 0
                return config
            }
        }
        #expect(error?.path == "devices[0].scrolling.smooth.duration")
        #expect(try Data(contentsOf: url) == before)
    }
}
