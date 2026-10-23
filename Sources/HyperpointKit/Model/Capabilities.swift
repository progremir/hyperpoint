/// What HID++ discovery found on one connected device. Discovered on every connection, never stored in config.
public struct HIDPPCapabilities: Equatable, Sendable {
    public struct Control: Equatable, Sendable {
        public var cid: CID
        /// Temporarily divertable, so its presses can come to Hyperpoint instead of the OS.
        public var divertable: Bool
        /// Can report raw movement while held, which a gesture needs.
        public var rawXY: Bool

        public init(cid: CID, divertable: Bool, rawXY: Bool) {
            self.cid = cid
            self.divertable = divertable
            self.rawXY = rawXY
        }
    }

    /// In the order the device lists them.
    public var controls: [Control]
    public var thumbWheel: Bool

    public init(controls: [Control], thumbWheel: Bool) {
        self.controls = controls
        self.thumbWheel = thumbWheel
    }

    public func control(_ cid: CID) -> Control? { controls.first { $0.cid == cid } }
}
