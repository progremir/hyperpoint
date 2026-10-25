import Foundation
@testable import HyperpointKit
import Testing

private let setup = HIDPPSetup(
    controls: [topButton: .press(.shortcut(Chord(key: KeyCode(name: "4")!, modifiers: [.shift, .command])))],
    thumbWheelInverted: true)

@Suite struct HIDPPWritesTests {
    @Test func aFreshConnectionWithNothingDesiredSendsNothing() {
        var writes = HIDPPWrites(crashMayHaveDiverted: false)
        #expect(writes.send(desired: nil) == nil)
    }

    @Test func aConnectionACrashMayHaveDivertedSendsNative() {
        var writes = HIDPPWrites(crashMayHaveDiverted: true)
        #expect(writes.send(desired: nil) == .native)
    }

    @Test func afterASetupIsSentNothingDesiredMeansNative() {
        var writes = HIDPPWrites(crashMayHaveDiverted: false)
        _ = writes.send(desired: setup)
        #expect(writes.send(desired: nil) == .native)
    }

    @Test func aConnectionThatOnlyDiscoveredStillSendsNothing() {
        var writes = HIDPPWrites(crashMayHaveDiverted: false)
        _ = writes.send(desired: nil)
        #expect(writes.send(desired: nil) == nil, "reading the controls is not a write to undo")
    }

    @Test func aDesiredSetupIsSentAsIs() {
        var fresh = HIDPPWrites(crashMayHaveDiverted: false)
        var owing = HIDPPWrites(crashMayHaveDiverted: true)
        #expect(fresh.send(desired: setup) == setup)
        #expect(owing.send(desired: setup) == setup)
    }
}
