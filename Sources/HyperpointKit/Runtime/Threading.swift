import CoreFoundation
import Foundation

/// A dedicated thread running a CFRunLoop, used as a global actor's executor. Actor isolation is then thread
/// confinement, and a C callback that fires on the run loop enters the actor synchronously with `assumeIsolated`.
final class RunLoopExecutor: SerialExecutor, @unchecked Sendable {
    private let ready = DispatchSemaphore(value: 0)
    // Written once on the thread before `ready` is signalled, then only read.
    private nonisolated(unsafe) var loop: CFRunLoop!

    init(name: String) {
        let thread = Thread { [unowned self] in
            loop = CFRunLoopGetCurrent()
            var context = CFRunLoopSourceContext()
            // A run loop with no source returns at once, so this empty source keeps it alive.
            CFRunLoopAddSource(loop, CFRunLoopSourceCreate(nil, 0, &context), .commonModes)
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = name
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
    }

    func enqueue(_ job: consuming ExecutorJob) {
        let job = UnownedJob(job)
        let executor = asUnownedSerialExecutor()
        CFRunLoopPerformBlock(loop, CFRunLoopMode.commonModes.rawValue) { job.runSynchronously(on: executor) }
        CFRunLoopWakeUp(loop)
    }

    func asUnownedSerialExecutor() -> UnownedSerialExecutor { UnownedSerialExecutor(ordinary: self) }

    func isIsolatingCurrentContext() -> Bool? { CFRunLoopGetCurrent() == loop }
}

/// The device side: `Engine`, `DeviceHub`, every `Slot`.
@globalActor
public final actor HIDActor {
    public static let shared = HIDActor()
    static let executor = RunLoopExecutor(name: "dev.emir.hyperpoint.hid")
    public nonisolated var unownedExecutor: UnownedSerialExecutor { Self.executor.asUnownedSerialExecutor() }

    /// Synchronous entry from a C callback already on the HID run loop. The standard library ships this only for
    /// the main actor.
    static func assumeIsolated<T>(_ body: @HIDActor () throws -> T) rethrows -> T {
        shared.preconditionIsolated()
        typealias Unsafe = () throws -> T
        return try withoutActuallyEscaping(body) { try unsafeBitCast($0, to: Unsafe.self)() }
    }
}

/// The event tap and nothing else. Every keystroke on the Mac waits on this thread.
@globalActor
final actor TapActor {
    static let shared = TapActor()
    static let executor = RunLoopExecutor(name: "dev.emir.hyperpoint.tap")
    nonisolated var unownedExecutor: UnownedSerialExecutor { Self.executor.asUnownedSerialExecutor() }

    static func assumeIsolated<T>(_ body: @TapActor () throws -> T) rethrows -> T {
        shared.preconditionIsolated()
        typealias Unsafe = () throws -> T
        return try withoutActuallyEscaping(body) { try unsafeBitCast($0, to: Unsafe.self)() }
    }
}
