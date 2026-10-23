import IOKit
import IOKit.hid

/// Tracks which keyboards are present. The manager is never opened, so no device is opened or seized, and it still
/// delivers matching callbacks (measured).
@HIDActor
final class DeviceHub {
    enum Event {
        case appeared(PresentDevice)
        case disappeared(PresentDevice)
    }

    private struct Entry {
        var device: PresentDevice
        var interfaces: Set<UInt64>
    }

    private let onEvent: @HIDActor (Event) -> Void
    private var manager: IOHIDManager?
    private var entries: [DeviceKey: Entry] = [:]
    private var keyOfInterface: [UInt64: DeviceKey] = [:]
    private var nextID: UInt64 = 1

    init(onEvent: @escaping @HIDActor (Event) -> Void) { self.onEvent = onEvent }

    var devices: [PresentDevice] { entries.values.map(\.device).sorted { $0.id.rawValue < $1.id.rawValue } }

    func start() -> [PresentDevice] {
        guard manager == nil else { return devices }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(
            manager, [kIOHIDPrimaryUsagePageKey: kHIDPage_GenericDesktop, kIOHIDPrimaryUsageKey: kHIDUsage_GD_Keyboard] as CFDictionary)
        for device in (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? [] {
            _ = interfaceAppeared(device)
        }
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, hubDeviceMatched, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, hubDeviceRemoved, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.commonModes.rawValue)
        self.manager = manager
        return devices
    }

    fileprivate func interfaceAppeared(_ interface: IOHIDDevice) -> PresentDevice? {
        let registryID = Self.registryID(of: IOHIDDeviceGetService(interface))
        guard keyOfInterface[registryID] == nil else { return nil }
        var bag: [String: Any] = [:]
        for key in HIDProperties.keys {
            if let value = IOHIDDeviceGetProperty(interface, key as CFString) { bag[key] = value }
        }
        let properties = HIDProperties(bag: bag)
        let key = DeviceKey(properties)
        keyOfInterface[registryID] = key
        let services = Self.eventServices(under: IOHIDDeviceGetService(interface))
        if var entry = entries[key] {
            entry.interfaces.insert(registryID)
            entry.device.eventServices += services
            entries[key] = entry
            return nil
        }
        let device = PresentDevice(
            id: DeviceInstanceID(rawValue: nextID), key: key, properties: properties, eventServices: services)
        nextID += 1
        entries[key] = Entry(device: device, interfaces: [registryID])
        return device
    }

    fileprivate func matched(_ interface: IOHIDDevice) {
        if let device = interfaceAppeared(interface) { onEvent(.appeared(device)) }
    }

    fileprivate func removed(_ interface: IOHIDDevice) {
        let registryID = Self.registryID(of: IOHIDDeviceGetService(interface))
        guard let key = keyOfInterface.removeValue(forKey: registryID), var entry = entries[key] else { return }
        entry.interfaces.remove(registryID)
        if entry.interfaces.isEmpty {
            entries[key] = nil
            onEvent(.disappeared(entry.device))
        } else {
            entries[key] = entry
        }
    }

    private static func registryID(of entry: io_registry_entry_t) -> UInt64 {
        var id: UInt64 = 0
        IORegistryEntryGetRegistryEntryID(entry, &id)
        return id
    }

    private static func eventServices(under service: io_service_t) -> [SenderID] {
        var iterator: io_iterator_t = 0
        guard IORegistryEntryCreateIterator(service, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &iterator)
            == KERN_SUCCESS
        else { return [] }
        defer { IOObjectRelease(iterator) }
        var services: [SenderID] = []
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            if IOObjectConformsTo(entry, "IOHIDEventService") != 0 {
                services.append(SenderID(rawValue: registryID(of: entry)))
            }
            IOObjectRelease(entry)
        }
        return services
    }
}

nonisolated private func hubDeviceMatched(
    _ context: UnsafeMutableRawPointer?, _ result: IOReturn, _ sender: UnsafeMutableRawPointer?, _ device: IOHIDDevice
) {
    guard let context else { return }
    let hub = Unmanaged<DeviceHub>.fromOpaque(context).takeUnretainedValue()
    nonisolated(unsafe) let device = device
    HIDActor.assumeIsolated { hub.matched(device) }
}

nonisolated private func hubDeviceRemoved(
    _ context: UnsafeMutableRawPointer?, _ result: IOReturn, _ sender: UnsafeMutableRawPointer?, _ device: IOHIDDevice
) {
    guard let context else { return }
    let hub = Unmanaged<DeviceHub>.fromOpaque(context).takeUnretainedValue()
    nonisolated(unsafe) let device = device
    HIDActor.assumeIsolated { hub.removed(device) }
}
