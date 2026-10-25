import IOKit
import IOKit.hid

/// Tracks which keyboards, mice and HID++ devices are present. The manager is never opened, so it seizes nothing, and
/// it still delivers matching callbacks (measured).
@HIDActor
final class DeviceHub {
    private let onEvent: @HIDActor (DeviceRoster.Change) -> Void
    private var manager: IOHIDManager?
    private var roster = DeviceRoster()
    private var hidppInterfaces: [DeviceKey: IOHIDDevice] = [:]
    private var servicePort: IONotificationPortRef?

    init(onEvent: @escaping @HIDActor (DeviceRoster.Change) -> Void) { self.onEvent = onEvent }

    var devices: [PresentDevice] { roster.devices }

    func hidppInterface(of device: DeviceInstanceID) -> IOHIDDevice? {
        roster.devices.first { $0.id == device }.flatMap { hidppInterfaces[$0.key] }
    }

    func start() -> [PresentDevice] {
        guard manager == nil else { return devices }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        // The MX Master 3 matches all three. The manager then lists one IOHIDDevice object per match for its one
        // service, which the registry id folds into one interface (measured).
        IOHIDManagerSetDeviceMatchingMultiple(
            manager,
            [
                [kIOHIDPrimaryUsagePageKey: kHIDPage_GenericDesktop, kIOHIDPrimaryUsageKey: kHIDUsage_GD_Keyboard],
                [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Mouse],
                [kIOHIDVendorIDKey: Int(VendorID.logitech.rawValue), kIOHIDDeviceUsagePageKey: UsagePair.hidppPage],
            ] as CFArray)
        for device in (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? [] {
            interfaceAppeared(device)
        }
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, hubDeviceMatched, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, hubDeviceRemoved, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.commonModes.rawValue)
        self.manager = manager
        watchEventServices()
        return devices
    }

    private func watchEventServices() {
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        CFRunLoopAddSource(CFRunLoopGetCurrent(), IONotificationPortGetRunLoopSource(port).takeUnretainedValue(), .commonModes)
        var iterator: io_iterator_t = 0
        guard
            IOServiceAddMatchingNotification(
                port, kIOFirstMatchNotification, IOServiceMatching("IOHIDEventService"), hubEventServicesPublished,
                Unmanaged.passUnretained(self).toOpaque(), &iterator) == KERN_SUCCESS
        else {
            IONotificationPortDestroy(port)
            return
        }
        servicePort = port
        servicesPublished(iterator)
    }

    /// Draining the iterator also arms the next notification.
    fileprivate func servicesPublished(_ iterator: io_iterator_t) {
        while case let service = IOIteratorNext(iterator), service != 0 {
            let change = roster.serviceAppeared(
                SenderID(rawValue: Self.registryID(of: service)), ancestors: Self.ancestors(of: service))
            IOObjectRelease(service)
            if let change { onEvent(change) }
        }
    }

    @discardableResult
    fileprivate func interfaceAppeared(_ interface: IOHIDDevice) -> DeviceRoster.Change? {
        let service = IOHIDDeviceGetService(interface)
        let registryID = Self.registryID(of: service)
        guard !roster.tracks(interface: registryID) else { return nil }
        var bag: [String: Any] = [:]
        for key in HIDProperties.keys {
            if let value = IOHIDDeviceGetProperty(interface, key as CFString) { bag[key] = value }
        }
        let properties = HIDProperties(bag: bag)
        let key = DeviceKey(properties)
        if properties.speaksHIDPP, hidppInterfaces[key] == nil { hidppInterfaces[key] = interface }
        return roster.interfaceAppeared(registryID, properties: properties, services: Self.eventServices(under: service))
    }

    fileprivate func matched(_ interface: IOHIDDevice) {
        if let change = interfaceAppeared(interface) { onEvent(change) }
    }

    fileprivate func removed(_ interface: IOHIDDevice) {
        guard let change = roster.interfaceRemoved(Self.registryID(of: IOHIDDeviceGetService(interface))) else { return }
        if case .disappeared(let device) = change { hidppInterfaces[device.key] = nil }
        onEvent(change)
    }

    private static func registryID(of entry: io_registry_entry_t) -> UInt64 {
        var id: UInt64 = 0
        IORegistryEntryGetRegistryEntryID(entry, &id)
        return id
    }

    private static func ancestors(of entry: io_registry_entry_t) -> [UInt64] {
        var ids: [UInt64] = []
        var current = entry
        IOObjectRetain(current)
        while true {
            var parent: io_registry_entry_t = 0
            let found = IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent) == KERN_SUCCESS
            IOObjectRelease(current)
            guard found else { return ids }
            ids.append(registryID(of: parent))
            current = parent
        }
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

nonisolated private func hubEventServicesPublished(_ context: UnsafeMutableRawPointer?, _ iterator: io_iterator_t) {
    guard let context else { return }
    let hub = Unmanaged<DeviceHub>.fromOpaque(context).takeUnretainedValue()
    HIDActor.assumeIsolated { hub.servicesPublished(iterator) }
}
