import Foundation
@testable import HyperpointKit
import Testing

private let mxService = SenderID(rawValue: 0x1_0003_7032)
private let keysService = SenderID(rawValue: 0x1_0005_2151)
private let pointerService = SenderID(rawValue: 0x1_0005_214E)
private let mx = discovered(present(3, Bags.mxMaster3, services: [mxService.rawValue]))
private let mouse24G = present(6, Bags.mouse24GKeys, services: [pointerService.rawValue, keysService.rawValue])
private let devices = thisMac.filter { $0.id != mx.id } + [mx, mouse24G]
private let escape = HIDUsage(name: "escape")!
private let enter = HIDUsage(name: "return")!

private func compile(
    _ config: Config = .example, paused: Bool = false, tapAvailable: Bool = true, listening device: PresentDevice? = nil
) -> Intent {
    Intent.compile(
        config, paused: paused, tapAvailable: tapAvailable, present: devices,
        listening: device.map { ListenTarget(id: ListenID(rawValue: 1), device: $0.id) })
}

@Suite struct ListeningIntentTests {
    @Test func listeningOverlaysTheTargetOnly() throws {
        let plain = compile()
        let listening = compile(listening: mouse24G)
        #expect(listening.setup(for: mouse24G.id).keyMap == .neutral, "its keys reach the tap as themselves")
        #expect(listening.setup(for: mx.id) == plain.setup(for: mx.id))
        #expect(listening.setup(for: thisMac[0].id) == plain.setup(for: thisMac[0].id))
        let listen = try #require(listening.tap.listen)
        #expect(listen.senders == [pointerService, keysService])
        var others = listening.tap
        others.listen = nil
        #expect(others == plain.tap, "another device may share the Return carrier")
    }

    @Test func listeningDivertsEveryControlOfTheTarget() throws {
        let hidpp = try #require(compile(listening: mx).setup(for: mx.id).hidpp)
        #expect(hidpp == .listening(over: compile().setup(for: mx.id).hidpp))
    }

    @Test func listeningDivertsAMouseWithoutHIDPPRules() throws {
        var config = Config.example
        config.devices[0].rules = [Rule(control: .button(1), trigger: .holdMove(nil), action: .scroll)]
        #expect(compile(config).setup(for: mx.id).hidpp == nil)
        #expect(compile(config, listening: mx).setup(for: mx.id).hidpp == .listening(over: nil))
    }

    @Test func pauseAndQuitIgnoreListening() {
        #expect(compile(paused: true, listening: mx) == .neutral)
    }

    @Test func withoutAccessibilityOnlyHIDPPListens() {
        let intent = compile(tapAvailable: false, listening: mx)
        #expect(intent.tap.listen == nil)
        #expect(intent.setup(for: mx.id).hidpp?.listening == true)
    }

    @Test func aTargetThatIsGoneListensNowhere() {
        let gone = present(9, Bags.plainMouse, services: [0x1_0009_0000])
        let intent = compile(listening: gone)
        #expect(intent.listening == nil)
        #expect(intent.tap.listen == nil)
        #expect(intent.setups == compile().setups)
    }

    @Test func aPressIsNamedTheWayTheConfigNamesIt() throws {
        let plan = try #require(compile(listening: mouse24G).listening)
        #expect(plan.heard(.key(Carrier.f13.keyCode)) == .control(.key(enter)), "Return pressed before the clear lands")
        #expect(plan.heard(.key(KeyCode(name: "return")!)) == .control(.key(enter)))
        #expect(plan.heard(.key(KeyCode(name: "escape")!)) == .control(.key(escape)))
        #expect(plan.heard(.key(Carrier.f16.keyCode)) == .unnamed, "F16, which the config cannot name")
        #expect(plan.heard(.button(3)) == .control(.button(3)))
        #expect(plan.heard(.button(32)) == .unnamed)
        #expect(plan.heard(.hidpp(CID(rawValue: 0xC3))) == .control(.hidpp(CID(rawValue: 0xC3))))
    }
}

@Suite struct ListenerTests {
    let mxMatch = DeviceMatch(identifying: mx.properties)
    let match24G = DeviceMatch(identifying: mouse24G.properties)
    let now = Date(timeIntervalSince1970: 1000)

    func arm(_ listener: inout Listener, _ match: DeviceMatch, _ device: DeviceInstanceID) throws -> Listener.Armed {
        let armed = listener.start(match: match, device: device, refusal: nil, now: now)
        return try #require(armed)
    }

    @Test func aListenEndsAfterTheTimeout() throws {
        var listener = Listener()
        let armed = try arm(&listener, mxMatch, mx.id)
        #expect(armed.until == now.addingTimeInterval(ListenStatus.timeout))
        #expect(listener.target == ListenTarget(id: armed.id, device: mx.id))
        let ended = listener.end(.timedOut, only: .listen(armed.id))
        #expect(ended)
        #expect(listener.state == .ended(mxMatch, .timedOut))
        #expect(listener.target == nil)
    }

    @Test func aPressEndsTheListenSilently() throws {
        var listener = Listener()
        let armed = listener.start(match: mxMatch, device: mx.id, refusal: nil, now: now)
        let heard = listener.hear(from: .device(mx.id))
        #expect(heard != nil && heard == armed)
        #expect(listener.state == .idle)
    }

    @Test func aLatePressOrTimerChangesNothing() throws {
        var listener = Listener()
        let armed = try arm(&listener, mxMatch, mx.id)
        let stopped = listener.end(nil)
        let late = listener.hear(from: .listen(armed.id))
        let timer = listener.end(.timedOut, only: .listen(armed.id))
        let again = listener.end(nil)
        #expect(stopped && late == nil && !timer && !again)
        #expect(listener.state == .idle)
    }

    @Test func aSecondListenReplacesTheFirst() throws {
        var listener = Listener()
        let first = try arm(&listener, mxMatch, mx.id)
        let second = try arm(&listener, match24G, mouse24G.id)
        #expect(first.id != second.id)
        let lateTap = listener.hear(from: .listen(first.id))
        let lateSlot = listener.hear(from: .device(mx.id))
        let firstTimer = listener.end(.timedOut, only: .listen(first.id))
        #expect(lateTap == nil && lateSlot == nil && !firstTimer)
        let heard = listener.hear(from: .listen(second.id))
        #expect(heard == second)
    }

    @Test func aDisconnectEndsOnlyTheListenOnThatDevice() throws {
        var listener = Listener()
        _ = listener.start(match: mxMatch, device: mx.id, refusal: nil, now: now)
        let other = listener.end(.disconnected, only: .device(mouse24G.id))
        #expect(!other && listener.armed != nil)
        let target = listener.end(.disconnected, only: .device(mx.id))
        #expect(target)
        #expect(listener.state == .ended(mxMatch, .disconnected))
    }

    @Test func aRefusedListenEndsAtOnceWithItsReason() throws {
        var listener = Listener()
        let first = try arm(&listener, mxMatch, mx.id)
        let disconnected = listener.start(match: match24G, device: nil, refusal: .disconnected, now: now)
        #expect(disconnected == nil)
        #expect(listener.state == .ended(match24G, .disconnected), "and the listen it replaced is over")
        let late = listener.hear(from: .listen(first.id))
        #expect(late == nil)
        let paused = listener.start(match: mxMatch, device: mx.id, refusal: .paused, now: now)
        #expect(paused == nil)
        #expect(listener.state == .ended(mxMatch, .paused))
        let dismissed = listener.dismiss()
        let again = listener.dismiss()
        #expect(dismissed && !again)
        #expect(listener.state == .idle)
    }
}
