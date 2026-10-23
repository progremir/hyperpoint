import Foundation
import HyperpointKit
import Testing

let documentedDefaultJSON: String = {
    let doc = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "docs/architecture.md")
    let text = try! String(contentsOf: doc, encoding: .utf8)
    let start = text.range(of: "```json\n")!.upperBound
    let end = text.range(of: "\n```", range: start..<text.endIndex)!.lowerBound
    return String(text[start..<end])
}()

func decode(_ json: String) throws(ConfigError) -> Config {
    try ConfigCodec.decode(Data(json.utf8))
}

func rejection(_ json: String) -> ConfigError? {
    do {
        _ = try decode(json)
        return nil
    } catch {
        return error
    }
}

@Suite struct ConfigCodecTests {
    @Test func defaultConfigIsTheDocumentedFile() throws {
        #expect(try decode(documentedDefaultJSON) == Config.default)
    }

    @Test func encodedConfigDecodesToTheSameValue() throws {
        let everyShape = Config(
            version: 1,
            hyper: HyperSettings(key: HIDUsage(name: "f12")!, onTap: .nothing),
            devices: Config.default.devices + [
                DeviceProfile(
                    match: .device(vendor: VendorID(rawValue: 0x1234), product: ProductID(rawValue: 0xABCD)),
                    name: "Other Mouse",
                    rules: [
                        Rule(control: .button(4), trigger: .click, action: .system(.spaceLeft)),
                        Rule(control: .hidpp(CID(rawValue: 0x1A0)), trigger: .holdMove(.up), action: .shortcut(
                            Chord(key: KeyCode(name: "leftBracket")!, modifiers: .hyper))),
                    ],
                    gestures: GestureSettings(fire: .onRelease, distance: 300),
                    scrolling: ScrollSettings(
                        smooth: SmoothScroll(
                            duration: 8, brake: 1, acceleration: nil, speed: 60, startBoost: 1, easeIn: 120),
                        hiResWheel: false),
                    hyper: false
                )
            ],
            ignored: [.device(vendor: VendorID(rawValue: 0x05AC), product: ProductID(rawValue: 0x024F))]
        )
        for config in [Config.default, everyShape] {
            let bytes = ConfigCodec.encode(config)
            #expect(try ConfigCodec.decode(bytes) == config)
            #expect(ConfigCodec.encode(try ConfigCodec.decode(bytes)) == bytes, "encoding is canonical")
        }
    }

    @Test func aFileWrittenBeforeTheScrollKnobsKeepsItsDefaults() throws {
        let older = documentedDefaultJSON.replacingOccurrences(of: ", \"speed\": 40, \"startBoost\": 2", with: "")
        #expect(older != documentedDefaultJSON, "the documented file names both knobs")
        #expect(try decode(older) == Config.default)
    }

    @Test func aFileWithoutEaseInStartsGlidesAtFullVelocity() throws {
        let older = documentedDefaultJSON.replacingOccurrences(of: "\"easeIn\": 0, ", with: "")
        #expect(older != documentedDefaultJSON, "the documented file names easeIn")
        let config = try decode(older)
        #expect(config.devices[0].scrolling?.smooth?.easeIn == 0)
        #expect(config == Config.default)
        let longest = documentedDefaultJSON.replacingOccurrences(of: "\"easeIn\": 0,", with: "\"easeIn\": 300,")
        #expect(try decode(longest).devices[0].scrolling?.smooth?.easeIn == 300)
    }

    @Test func accelerationIsFalseTrueOrAnObject() throws {
        let object = "\"acceleration\": { \"from\": 4, \"to\": 40, \"max\": 3 }"
        #expect(documentedDefaultJSON.contains(object), "the documented file spells out the knobs")
        func acceleration(_ value: String) throws -> Acceleration? {
            let json = documentedDefaultJSON.replacingOccurrences(of: object, with: "\"acceleration\": \(value)")
            return try decode(json).devices[0].scrolling?.smooth?.acceleration
        }
        #expect(try acceleration("true") == Acceleration(from: 4, to: 40, max: 3))
        #expect(try acceleration("false") == nil)
        #expect(try acceleration("{ \"from\": 2, \"to\": 30, \"max\": 5 }") == Acceleration(from: 2, to: 30, max: 5))
    }

    @Test func chordsAcceptAliasesAndAnyOrder() throws {
        let json = documentedDefaultJSON.replacingOccurrences(of: "\"shift+cmd+4\"", with: "\"Command+Shift+4\"")
        #expect(try decode(json) == Config.default)
    }

    struct Mutation: CustomTestStringConvertible, Sendable {
        let find: String
        let replace: String
        let path: String
        var testDescription: String { path.isEmpty ? "whole file" : path }
    }

    static let mutations: [Mutation] = [
        Mutation(find: "\"version\": 1,", replace: "\"version\": 1,,", path: ""),
        Mutation(find: "\"version\": 1", replace: "\"version\": 2", path: "version"),
        Mutation(find: "\"ignored\": []", replace: "\"ignored\": [], \"theme\": \"dark\"", path: "theme"),
        Mutation(find: "\"onTap\": \"nothing\"", replace: "\"onTap\": \"escape\"", path: "hyper.onTap"),
        Mutation(find: "\"key\": \"capsLock\"", replace: "\"key\": \"f18\"", path: "hyper.key"),
        Mutation(find: "\"name\": \"MX Master 3\",", replace: "", path: "devices[0].name"),
        Mutation(
            find: "\"name\": \"MX Master 3\",", replace: "\"name\": \"MX Master 3\", \"nmae\": \"x\",",
            path: "devices[0].nmae"),
        Mutation(find: "\"vendor\": \"0x046D\"", replace: "\"vendor\": \"046D\"", path: "devices[0].match.vendor"),
        Mutation(
            find: "{ \"builtIn\": true }", replace: "{ \"builtIn\": false }", path: "devices[2].match.builtIn"),
        Mutation(
            find: "{ \"builtIn\": true }", replace: "{ \"builtIn\": true, \"vendor\": \"0x0001\" }",
            path: "devices[2].match.builtIn"),
        Mutation(
            find: "\"name\": \"Built-in Keyboard\", \"hyper\": true",
            replace: "\"name\": \"Built-in Keyboard\", \"hyper\": \"yes\"", path: "devices[2].hyper"),
        Mutation(
            find: "\"name\": \"Built-in Keyboard\", \"hyper\": true",
            replace: "\"name\": \"Built-in Keyboard\", \"hyper\": null", path: "devices[2].hyper"),
        Mutation(
            find: "{ \"control\": { \"hidpp\": \"0xC3\" }, \"when\": \"click\"",
            replace: "{ \"control\": { \"hidpp\": \"0xC3\", \"divert\": true }, \"when\": \"click\"",
            path: "devices[0].rules[0].control.divert"),
        Mutation(
            find: "{ \"control\": { \"hidpp\": \"0xC3\" }, \"when\": \"click\"",
            replace: "{ \"control\": { \"hidpp\": \"0xC3\", \"button\": 5 }, \"when\": \"click\"",
            path: "devices[0].rules[0].control"),
        Mutation(
            find: "\"when\": \"click\", \"do\": \"missionControl\"", replace: "\"when\": \"hover\", \"do\": \"missionControl\"",
            path: "devices[0].rules[0].when"),
        Mutation(
            find: "\"do\": \"missionControl\"", replace: "\"do\": \"missonControl\"", path: "devices[0].rules[0].do"),
        Mutation(
            find: "\"shift+cmd+4\"", replace: "\"hyper+4\"", path: "devices[0].rules[4].do.shortcut"),
        Mutation(find: "\"shift+cmd+4\"", replace: "\"shift+cmd+\"", path: "devices[0].rules[4].do.shortcut"),
        Mutation(
            find: "\"when\": \"scroll\", \"do\": \"reverse\"", replace: "\"when\": \"scroll\", \"do\": \"missionControl\"",
            path: "devices[0].rules[5].do"),
        Mutation(
            find: "{ \"control\": \"thumbWheel\", \"when\": \"scroll\"",
            replace: "{ \"control\": \"thumbWheel\", \"when\": \"click\"", path: "devices[0].rules[5].when"),
        Mutation(
            find: "{ \"control\": \"thumbWheel\"", replace: "{ \"control\": \"thumbwheel\"",
            path: "devices[0].rules[5].control"),
        Mutation(
            find: "{ \"control\": { \"key\": \"escape\" }, \"when\": \"hold\"",
            replace: "{ \"control\": { \"key\": \"escape\" }, \"when\": \"holdMoveDown\"",
            path: "devices[1].rules[0].when"),
        Mutation(
            find: "\"when\": \"click\", \"do\": { \"shortcut\": \"opt+shift+s\" }",
            replace: "\"when\": \"click\", \"do\": { \"modifier\": \"rightOption\" }", path: "devices[1].rules[1].do"),
        Mutation(find: "{ \"key\": \"escape\" }", replace: "{ \"key\": \"escap\" }", path: "devices[1].rules[0].control.key"),
        Mutation(
            find: "\"when\": \"holdMoveDown\", \"do\": \"appExpose\"",
            replace: "\"when\": \"click\", \"do\": \"appExpose\"", path: "devices[0].rules[1]"),
        Mutation(find: "\"distance\": 120", replace: "\"distance\": 5", path: "devices[0].gestures.distance"),
        Mutation(find: "\"brake\": 2,", replace: "", path: "devices[0].scrolling.smooth.brake"),
        Mutation(find: "\"duration\": 4,", replace: "\"duration\": 40,", path: "devices[0].scrolling.smooth.duration"),
        Mutation(find: "\"brake\": 2,", replace: "\"brake\": 0,", path: "devices[0].scrolling.smooth.brake"),
        Mutation(find: "\"speed\": 40", replace: "\"speed\": 0", path: "devices[0].scrolling.smooth.speed"),
        Mutation(
            find: "\"startBoost\": 2", replace: "\"startBoost\": 0.5", path: "devices[0].scrolling.smooth.startBoost"),
        Mutation(
            find: "\"startBoost\": 2", replace: "\"startBoost\": 2, \"boost\": 2",
            path: "devices[0].scrolling.smooth.boost"),
        Mutation(find: "\"easeIn\": 0,", replace: "\"easeIn\": -1,", path: "devices[0].scrolling.smooth.easeIn"),
        Mutation(find: "\"easeIn\": 0,", replace: "\"easeIn\": 301,", path: "devices[0].scrolling.smooth.easeIn"),
        Mutation(find: "\"from\": 4", replace: "\"from\": -1", path: "devices[0].scrolling.smooth.acceleration.from"),
        Mutation(find: "\"to\": 40", replace: "\"to\": 4", path: "devices[0].scrolling.smooth.acceleration.to"),
        Mutation(find: "\"max\": 3", replace: "\"max\": 0.5", path: "devices[0].scrolling.smooth.acceleration.max"),
        Mutation(find: ", \"max\": 3", replace: "", path: "devices[0].scrolling.smooth.acceleration.max"),
        Mutation(
            find: "\"max\": 3", replace: "\"max\": 3, \"min\": 1", path: "devices[0].scrolling.smooth.acceleration.min"),
        Mutation(
            find: "{ \"from\": 4, \"to\": 40, \"max\": 3 }", replace: "\"fast\"",
            path: "devices[0].scrolling.smooth.acceleration"),
        Mutation(find: "\"hiResWheel\": true", replace: "\"hiResWheels\": true", path: "devices[0].scrolling.hiResWheels"),
        Mutation(
            find: "\"product\": \"0x0321\"", replace: "\"product\": \"0x0321\", \"location\": 1",
            path: "devices[3].match.location"),
        Mutation(
            find: "{ \"vendor\": \"0x004C\", \"product\": \"0x0321\" }", replace: "{ \"builtIn\": true }",
            path: "devices[3].match"),
        Mutation(
            find: "\"ignored\": []", replace: "\"ignored\": [{ \"builtIn\": true }]", path: "devices[2].match"),
        Mutation(find: "\"ignored\": []", replace: "\"ignored\": {}", path: "ignored"),
    ]

    @Test(arguments: mutations)
    func invalidFileIsRejectedWithItsPath(_ mutation: Mutation) throws {
        #expect(documentedDefaultJSON.contains(mutation.find), "the mutation applies to the documented file")
        let json = documentedDefaultJSON.replacingOccurrences(of: mutation.find, with: mutation.replace)
        let error = try #require(rejection(json), "the file is rejected")
        #expect(error.path == mutation.path)
    }
}
