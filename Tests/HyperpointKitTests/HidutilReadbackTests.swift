@testable import HyperpointKit
import Testing

@Suite struct HidutilReadbackTests {
    @Test func emptyAndUnsetMappingsReadAsEmpty() {
        let measured = """
            RegistryID  Key                   Value
            100000cdb   UserKeyMapping   (
            )
            100000930   UserKeyMapping   (null)

            """
        #expect(HidutilReadback.parse(measured) == [0x1_0000_0CDB: [], 0x1_0000_0930: []])
    }

    @Test func mappingPairsAreReadPerService() {
        let output = """
            RegistryID  Key                   Value
            10001bc2e   UserKeyMapping   (
                    {
                    HIDKeyboardModifierMappingDst = 30064771181;
                    HIDKeyboardModifierMappingSrc = 30064771129;
                },
                    {
                    HIDKeyboardModifierMappingDst = 0x7000000E6;
                    HIDKeyboardModifierMappingSrc = 0x700000029;
                }
            )
            100000cdb   UserKeyMapping   (
            )

            """
        #expect(
            HidutilReadback.parse(output) == [
                0x1_0001_BC2E: [
                    .init(source: 0x7_0000_0039, destination: 0x7_0000_006D),
                    .init(source: 0x7_0000_0029, destination: 0x7_0000_00E6),
                ],
                0x1_0000_0CDB: [],
            ])
    }

    @Test func noMatchingServiceListsNothing() {
        #expect(HidutilReadback.parse("").isEmpty)
    }
}
