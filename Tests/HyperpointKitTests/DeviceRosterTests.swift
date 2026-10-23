@testable import HyperpointKit
import Testing

@Suite struct DeviceRosterTests {
    let mx = HIDProperties(bag: Bags.mxMaster3)
    let magic = HIDProperties(bag: Bags.magicKeyboard)
    let mxService = SenderID(rawValue: 0x1_0003_7032)

    @Test func interfacesOfOneDeviceFoldIntoOne() {
        var roster = DeviceRoster()
        guard case .appeared(let device) = roster.interfaceAppeared(0xA, properties: mx, services: [mxService]) else {
            Issue.record("the first interface makes the device appear")
            return
        }
        #expect(roster.interfaceAppeared(0xB, properties: mx, services: []) == nil, "a second interface is not a new device")
        #expect(roster.interfaceAppeared(0xA, properties: mx, services: [mxService]) == nil, "an interface is tracked once")
        #expect(roster.devices.map(\.id) == [device.id])
        #expect(roster.devices.first?.eventServices == [mxService])
    }

    @Test func aDeviceDisappearsWithItsLastInterface() {
        var roster = DeviceRoster()
        _ = roster.interfaceAppeared(0xA, properties: mx, services: [mxService])
        _ = roster.interfaceAppeared(0xB, properties: mx, services: [])
        _ = roster.interfaceAppeared(0xC, properties: magic, services: [])

        #expect(roster.interfaceRemoved(0xA) == nil)
        #expect(roster.devices.map(\.name) == ["MX Master 3", "Эмир’s Magic Keyboard"])
        guard case .disappeared(let device) = roster.interfaceRemoved(0xB) else {
            Issue.record("the last interface takes the device with it")
            return
        }
        #expect(device.name == "MX Master 3")
        #expect(roster.devices.map(\.name) == ["Эмир’s Magic Keyboard"])
        #expect(roster.interfaceRemoved(0xB) == nil, "a removal is reported once")
    }

    @Test func aReconnectIsANewInstance() {
        var roster = DeviceRoster()
        guard case .appeared(let before) = roster.interfaceAppeared(0xA, properties: mx, services: []) else {
            Issue.record("appeared")
            return
        }
        _ = roster.interfaceRemoved(0xA)
        guard case .appeared(let after) = roster.interfaceAppeared(0xD, properties: mx, services: []) else {
            Issue.record("appeared again")
            return
        }
        #expect(after.id != before.id)
    }
}
