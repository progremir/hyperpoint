import Foundation
@testable import HyperpointKit
import Testing

private let mx = DeviceMatch.device(vendor: .logitech, product: ProductID(rawValue: 0xB023))

@Suite struct DivertLatchTests {
    let suite = "dev.emir.hyperpoint.tests.latch-\(UUID().uuidString)"

    func withDefaults(_ body: (UserDefaults) -> Void) {
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        body(defaults)
    }

    @Test func anInsertedMouseIsContained() {
        withDefaults { defaults in
            let latch = DivertLatch(defaults: defaults)
            #expect(!latch.contains(mx))
            latch.insert(mx)
            #expect(latch.contains(mx))
        }
    }

    @Test func theEntryOutlivesARelaunch() {
        withDefaults { defaults in
            DivertLatch(defaults: defaults).insert(mx)
            #expect(DivertLatch(defaults: UserDefaults(suiteName: suite)!).contains(mx))
        }
    }

    @Test func clearRemovesTheEntry() {
        withDefaults { defaults in
            let latch = DivertLatch(defaults: defaults)
            latch.insert(mx)
            latch.clear()
            #expect(!latch.contains(mx))
        }
    }

    @Test func insertingTwiceKeepsOneEntry() {
        withDefaults { defaults in
            let latch = DivertLatch(defaults: defaults)
            latch.insert(mx)
            latch.insert(mx)
            #expect(defaults.stringArray(forKey: "listenDiverted") == [mx.hidutilKeyboardMatching])
        }
    }
}
