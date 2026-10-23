import CoreServices
public import Foundation

/// The config file's state. `config` is the last good config, which stays in force while the file is invalid.
public struct ConfigSnapshot: Equatable, Sendable {
    public var config: Config?
    public var error: ConfigError?
}

/// The only reader and writer of the config file. Engine and UI learn of every change through `snapshots()`.
public actor ConfigStore {
    public nonisolated let url: URL
    private var current: ConfigSnapshot?
    private var subscribers: [UUID: AsyncStream<ConfigSnapshot>.Continuation] = [:]
    private var stream: FSEventStreamRef?

    public static var defaultURL: URL { URL.homeDirectory.appending(path: ".config/hyperpoint/config.json") }

    public init(url: URL = ConfigStore.defaultURL) { self.url = url }

    /// Writes `Config.default` when the file is missing, loads it, then watches its directory. Editors save by
    /// replacing the file, so a watch on the file itself would go stale after the first save.
    public func start() {
        guard stream == nil else { return }
        let directory = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: url.path) {
                try ConfigCodec.encode(.default).write(to: url, options: .atomic)
            }
        } catch {
            publish(ConfigSnapshot(config: nil, error: ConfigError(path: "", message: "cannot write \(url.path): \(error)")))
        }
        reload()
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        guard
            let stream = FSEventStreamCreate(
                nil, configDirectoryChanged, &context, [directory.path] as CFArray,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.15,
                FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents))
        else { return }
        FSEventStreamSetDispatchQueue(stream, DispatchQueue(label: "dev.emir.hyperpoint.config"))
        FSEventStreamStart(stream)
        self.stream = stream
    }

    /// Emits the current state first, then every change.
    public func snapshots() -> AsyncStream<ConfigSnapshot> {
        let (stream, continuation) = AsyncStream.makeStream(of: ConfigSnapshot.self)
        let id = UUID()
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in Task { await self?.unsubscribe(id) } }
        if let current { continuation.yield(current) }
        return stream
    }

    func reload() {
        let last = current?.config
        do {
            let config = try ConfigCodec.decode(try Data(contentsOf: url))
            publish(ConfigSnapshot(config: config, error: nil))
        } catch let error as ConfigError {
            publish(ConfigSnapshot(config: last, error: error))
        } catch {
            publish(ConfigSnapshot(config: last, error: ConfigError(path: "", message: "cannot read the file: \(error)")))
        }
    }

    private func publish(_ snapshot: ConfigSnapshot) {
        guard snapshot != current else { return }
        current = snapshot
        for continuation in subscribers.values { continuation.yield(snapshot) }
    }

    private func unsubscribe(_ id: UUID) { subscribers[id] = nil }
}

nonisolated private func configDirectoryChanged(
    _ stream: ConstFSEventStreamRef, _ info: UnsafeMutableRawPointer?, _ count: Int, _ paths: UnsafeMutableRawPointer,
    _ flags: UnsafePointer<FSEventStreamEventFlags>, _ ids: UnsafePointer<FSEventStreamEventId>
) {
    guard let info else { return }
    let store = Unmanaged<ConfigStore>.fromOpaque(info).takeUnretainedValue()
    Task { await store.reload() }
}
