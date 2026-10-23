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
        let secondService = SenderID(rawValue: 0x1_0003_7040)
        #expect(
            roster.interfaceAppeared(0xC, properties: mx, services: [secondService])
                == .servicesChanged(device.adding([secondService])),
            "an interface that brings services reports them")
        #expect(roster.interfaceAppeared(0xA, properties: mx, services: [mxService]) == nil, "an interface is tracked once")
        #expect(roster.devices.map(\.id) == [device.id])
        #expect(roster.devices.first?.eventServices == [mxService, secondService])
    }

    @Test func aServicePublishedAfterItsDeviceMatchedJoinsThatDevice() {
        var roster = DeviceRoster()
        let hidInterface: UInt64 = 0x1_0003_A5D4
        let userDevice: UInt64 = 0x1_0003_A5D2
        guard case .appeared(let connected) = roster.interfaceAppeared(userDevice, properties: mx, services: []) else {
            Issue.record("the device appears without its service, as on a BLE reconnect")
            return
        }

        let change = roster.serviceAppeared(mxService, ancestors: [hidInterface, userDevice, 0x1_0000_0001])

        #expect(change == .servicesChanged(connected.adding([mxService])))
        #expect(roster.devices.map(\.eventServices) == [[mxService]])
        #expect(roster.devices.map(\.id) == [connected.id], "the device keeps its instance")
        #expect(roster.serviceAppeared(mxService, ancestors: [hidInterface, userDevice]) == nil, "a service is recorded once")
    }

    @Test func aServiceOfAnUntrackedDeviceChangesNothing() {
        var roster = DeviceRoster()
        _ = roster.interfaceAppeared(0xA, properties: magic, services: [])
        let trackpad = SenderID(rawValue: 0x1_0000_0D10)
        #expect(roster.serviceAppeared(trackpad, ancestors: [0xD0C, 0xD00]) == nil)
        #expect(roster.devices.map(\.eventServices) == [[]])
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

extension PresentDevice {
    fileprivate func adding(_ services: [SenderID]) -> PresentDevice {
        var device = self
        device.eventServices += services
        return device
    }
}
