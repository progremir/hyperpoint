import Foundation
import HyperpointKit
import Testing

let documentedExampleJSON: String = {
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
    @Test func theDocumentedFileIsTheExample() throws {
        #expect(try decode(documentedExampleJSON) == Config.example)
    }

    @Test func aFileWithoutTheHyperSwitchHasTheHyperKeyOn() throws {
        #expect(documentedExampleJSON.contains(#""hyper": { "key": "capsLock", "onTap": "nothing" }"#))
        #expect(try decode(documentedExampleJSON).hyper.enabled)
        let off = documentedExampleJSON.replacingOccurrences(
            of: #""onTap": "nothing" }"#, with: #""onTap": "nothing", "enabled": false }"#)
        var expected = Config.example
        expected.hyper.enabled = false
        #expect(try decode(off) == expected)
    }

    @Test func encodedConfigDecodesToTheSameValue() throws {
        let everyShape = Config(
            version: 1,
            hyper: HyperSettings(key: HIDUsage(name: "f12")!, onTap: .nothing),
            devices: Config.example.devices + [
                DeviceProfile(
                    match: .device(vendor: VendorID(rawValue: 0x1234), product: ProductID(rawValue: 0xABCD)),
                    name: "Other Mouse",
                    kind: .keyboard,
                    rules: [
                        Rule(control: .button(4), trigger: .click, action: .system(.spaceLeft)),
                        Rule(control: .hidpp(CID(rawValue: 0x1A0)), trigger: .holdMove(.up), action: .shortcut(
                            Chord(key: KeyCode(name: "leftBracket")!, modifiers: .hyper))),
                        Rule(control: .button(3), trigger: .hold, action: .modifier(.rightCommand)),
                        Rule(control: .hidpp(CID(rawValue: 0x53)), trigger: .hold, action: .shortcut(
                            Chord(key: KeyCode(name: "space")!, modifiers: [.control, .option]))),
                    ],
                    gestures: GestureSettings(fire: .onRelease, distance: 300),
                    scrolling: ScrollSettings(
                        smooth: SmoothScroll(
                            duration: 8, brake: 1, easeIn: 120,
                            curve: try SpeedCurve([
                                .init(stepsPerSecond: 2, pointsPerSecond: 80), .init(stepsPerSecond: 2.5, pointsPerSecond: 80),
                                .init(stepsPerSecond: 150, pointsPerSecond: 30_000),
                            ])),
                        hiResWheel: false),
                    hyper: false
                )
            ],
            ignored: [.device(vendor: VendorID(rawValue: 0x05AC), product: ProductID(rawValue: 0x024F))]
        )
        for config in [Config.example, everyShape] {
            let bytes = ConfigCodec.encode(config)
            #expect(try ConfigCodec.decode(bytes) == config)
            #expect(ConfigCodec.encode(try ConfigCodec.decode(bytes)) == bytes, "encoding is canonical")
        }
    }

    @Test func aFileWithoutEaseInEasesIn() throws {
        let older = documentedExampleJSON.replacingOccurrences(of: "\"easeIn\": 60, ", with: "")
        #expect(older != documentedExampleJSON, "the documented file names easeIn")
        #expect(try decode(older).devices[0].scrolling?.smooth?.easeIn == SmoothScroll.defaultEaseIn)
        #expect(try decode(older) == Config.example)
    }

    @Test func aFileWithoutACurveGetsTheDefaultOne() throws {
        let curve = try #require(documentedExampleJSON.range(of: #",\s*"curve": \[[^\]]*\]"#, options: .regularExpression))
        var without = documentedExampleJSON
        without.removeSubrange(curve)
        #expect(try decode(without) == Config.example)
    }

    /// The smooth section as the settings window wrote it before the curve, with the user's own values.
    static let beforeTheCurve = #"{ "acceleration": false, "brake": 1, "duration": 4, "easeIn": 60, "speed": 60, "startBoost": 1 }"#

    static func withSmooth(_ section: String) throws -> String {
        let range = try #require(documentedExampleJSON.range(of: #""smooth": \{[^\]]*\]\s*\}"#, options: .regularExpression))
        return documentedExampleJSON.replacingCharacters(in: range, with: "\"smooth\": \(section)")
    }

    @Test func theOldSpeedKeysConvertToACurveThatScrollsTheSame() throws {
        let smooth = try #require(try decode(Self.withSmooth(Self.beforeTheCurve)).devices[0].scrolling?.smooth)
        #expect(smooth.duration == 4 && smooth.brake == 1 && smooth.easeIn == 60)
        for rate in [1.0, 3, 10, 36, 121, 150] {
            #expect(abs(smooth.curve.distancePerStep(at: rate) - 60) < 1e-9, "60 points a step at \(rate) steps/s")
        }
    }

    @Test func aConvertedFileIsWrittenWithTheCurveAlone() throws {
        let config = try decode(Self.withSmooth(Self.beforeTheCurve))
        let tree = try JSONSerialization.jsonObject(with: ConfigCodec.encode(config)) as? [String: Any]
        let devices = try #require(tree?["devices"] as? [[String: Any]])
        let smooth = try #require((devices[0]["scrolling"] as? [String: Any])?["smooth"] as? [String: Any])
        #expect(Set(smooth.keys) == ["duration", "brake", "easeIn", "curve"])
        #expect(try ConfigCodec.decode(ConfigCodec.encode(config)) == config)
    }

    @Test func theOldBoostAndAccelerationConvertWhereTheyBend() throws {
        let old = #"{ "duration": 4, "brake": 2, "acceleration": { "from": 4, "to": 40, "max": 3 }, "speed": 40, "startBoost": 2 }"#
        let curve = try #require(try decode(Self.withSmooth(old)).devices[0].scrolling?.smooth?.curve)
        func oldDistance(_ rate: Double) -> Double {
            let boost = 1 + min(1, 1 / (rate * 0.4))
            let gain = 1 + min(1, max(0, (rate - 4) / 36)) * 2
            return 40 * boost * gain
        }
        #expect(curve.distancePerStep(at: curve.slowest) == 80, "a step from rest went speed × startBoost")
        for rate in [2.5, 4, 40] { #expect(abs(curve.distancePerStep(at: rate) - oldDistance(rate)) < 1e-9, "\(rate) steps/s") }
        for rate in stride(from: 1.0, through: 150, by: 0.25) {
            #expect(abs(curve.distancePerStep(at: rate) / oldDistance(rate) - 1) < 0.07, "\(rate) steps/s")
        }
        #expect(try decode(Self.withSmooth(old.replacingOccurrences(of: #"{ "from": 4, "to": 40, "max": 3 }"#, with: "true"))).devices[0].scrolling?.smooth?.curve == curve)
    }

    /// The scrolling section as files wrote it before hold to scroll, without the right-button rule it implied.
    static func beforeHoldToScroll(momentum: Bool, keepRule: Bool = false) throws -> String {
        var json = documentedExampleJSON.replacingOccurrences(
            of: #""holdToScroll": { "speed": 1, "direction": "grab", "momentum": true }"#,
            with: #""rightButtonPan": { "momentum": \#(momentum) }"#)
        if !keepRule {
            let rule = try #require(json.range(of: #",\s*\{ "control": \{ "button": 1 \}[^\n]*"#, options: .regularExpression))
            json.removeSubrange(rule)
        }
        #expect(json.contains("rightButtonPan") && json.contains("\"button\"") == keepRule)
        return json
    }

    @Test func rightButtonPanBecomesARightButtonScrollRule() throws {
        #expect(try decode(Self.beforeHoldToScroll(momentum: true)) == Config.example)
        #expect(try decode(Self.beforeHoldToScroll(momentum: true, keepRule: true)) == Config.example, "no second rule")
        let still = try decode(Self.beforeHoldToScroll(momentum: false))
        #expect(still.devices[0].scrolling?.holdToScroll == HoldToScroll(speed: 1, direction: .grab, momentum: false))
        let written = try #require(String(data: ConfigCodec.encode(still), encoding: .utf8))
        #expect(!written.contains("rightButtonPan") && written.contains("holdToScroll"), "the next save writes the new key")
    }

    @Test func rightButtonPanStillRejectsATypo() throws {
        let json = try Self.beforeHoldToScroll(momentum: true)
            .replacingOccurrences(of: #"{ "momentum": true }"#, with: #"{ "momentum": true, "speed": 2 }"#)
        #expect(rejection(json)?.path == "devices[0].scrolling.rightButtonPan.speed")
    }

    @Test func aButtonHeldHoldsAModifierOrAShortcut() throws {
        let json = documentedExampleJSON.replacingOccurrences(
            of: #"{ "control": { "button": 1 }, "when": "holdMove", "do": "scroll" }"#,
            with: #"{ "control": { "button": 1 }, "when": "holdMove", "do": "scroll" }, "#
                + #"{ "control": { "button": 3 }, "when": "hold", "do": { "modifier": "leftCommand" } }, "#
                + #"{ "control": { "hidpp": "0x56" }, "when": "hold", "do": { "shortcut": "ctrl+opt+space" } }"#)
        let rules = try #require(try decode(json).devices[0].rules)
        #expect(
            rules.suffix(2) == [
                Rule(control: .button(3), trigger: .hold, action: .modifier(.leftCommand)),
                Rule(
                    control: .hidpp(CID(rawValue: 0x56)), trigger: .hold,
                    action: .shortcut(Chord(key: KeyCode(name: "space")!, modifiers: [.control, .option]))),
            ])
    }

    @Test func aHoldCannotShareItsControlWithAClickOrAMove() throws {
        let click = documentedExampleJSON.replacingOccurrences(
            of: #""when": "holdMoveDown", "do": "appExpose""#, with: #""when": "hold", "do": { "modifier": "leftCommand" }"#)
        let clickError = try #require(rejection(click))
        #expect(clickError.path == "devices[0].rules[1].when")
        #expect(clickError.message.contains("holds them from its press, so it has no click of its own"))

        let move = documentedExampleJSON.replacingOccurrences(
            of: #"{ "control": { "button": 1 }, "when": "holdMove", "do": "scroll" }"#,
            with: #"{ "control": { "button": 1 }, "when": "holdMove", "do": "scroll" }, "#
                + #"{ "control": { "button": 1 }, "when": "hold", "do": { "modifier": "leftCommand" } }"#)
        let moveError = try #require(rejection(move))
        #expect(moveError.path == "devices[0].rules[7].when")
        #expect(moveError.message.contains("so its movement only moves the pointer"))
    }

    @Test func chordsAcceptAliasesAndAnyOrder() throws {
        let json = documentedExampleJSON.replacingOccurrences(of: "\"shift+cmd+4\"", with: "\"Command+Shift+4\"")
        #expect(try decode(json) == Config.example)
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
            find: "{ \"control\": { \"key\": \"return\" }, \"when\": \"click\"",
            replace: "{ \"control\": { \"key\": \"escape\" }, \"when\": \"click\"", path: "devices[1].rules[1].when"),
        Mutation(
            find: "\"when\": \"holdMoveDown\", \"do\": \"appExpose\"",
            replace: "\"when\": \"click\", \"do\": \"appExpose\"", path: "devices[0].rules[1]"),
        Mutation(find: "\"distance\": 120", replace: "\"distance\": 5", path: "devices[0].gestures.distance"),
        Mutation(find: "\"brake\": 2,", replace: "", path: "devices[0].scrolling.smooth.brake"),
        Mutation(find: "\"duration\": 4,", replace: "\"duration\": 40,", path: "devices[0].scrolling.smooth.duration"),
        Mutation(find: "\"brake\": 2,", replace: "\"brake\": 0,", path: "devices[0].scrolling.smooth.brake"),
        Mutation(find: "\"easeIn\": 60,", replace: "\"easeIn\": -1,", path: "devices[0].scrolling.smooth.easeIn"),
        Mutation(find: "\"easeIn\": 60,", replace: "\"easeIn\": 301,", path: "devices[0].scrolling.smooth.easeIn"),
        Mutation(
            find: "\"pointsPerSecond\": 250", replace: "\"pointsPerSecond\": 25",
            path: "devices[0].scrolling.smooth.curve[1].pointsPerSecond"),
        Mutation(
            find: "\"stepsPerSecond\": 15,", replace: "\"stepsPerSecond\": 4,",
            path: "devices[0].scrolling.smooth.curve[2].stepsPerSecond"),
        Mutation(
            find: "\"stepsPerSecond\": 120,", replace: "\"stepsPerSecond\": 200,",
            path: "devices[0].scrolling.smooth.curve[4].stepsPerSecond"),
        Mutation(
            find: "\"pointsPerSecond\": 9000", replace: "\"pointsPerSecond\": 90000",
            path: "devices[0].scrolling.smooth.curve[4].pointsPerSecond"),
        Mutation(
            find: "{ \"stepsPerSecond\": 5, \"pointsPerSecond\": 250 }", replace: "{ \"stepsPerSecond\": 5 }",
            path: "devices[0].scrolling.smooth.curve[1].pointsPerSecond"),
        Mutation(
            find: "{ \"stepsPerSecond\": 1, \"pointsPerSecond\": 40 }",
            replace: "{ \"stepsPerSecond\": 1, \"pointsPerSecond\": 40, \"weight\": 1 }",
            path: "devices[0].scrolling.smooth.curve[0].weight"),
        Mutation(
            find: "\"curve\": [", replace: "\"curve\": [{ \"stepsPerSecond\": 1, \"pointsPerSecond\": 40 }], \"unused\": [",
            path: "devices[0].scrolling.smooth.curve"),
        Mutation(
            find: "\"easeIn\": 60,", replace: "\"easeIn\": 60, \"speed\": 40,", path: "devices[0].scrolling.smooth.speed"),
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
        Mutation(
            find: "\"when\": \"click\", \"do\": \"missionControl\"", replace: "\"when\": \"holdMove\", \"do\": \"missionControl\"",
            path: "devices[0].rules[0].do"),
        Mutation(
            find: "\"when\": \"click\", \"do\": \"missionControl\"", replace: "\"when\": \"holdMove\", \"do\": \"scroll\"",
            path: "devices[0].rules[1].when"),
        Mutation(
            find: "{ \"control\": \"thumbWheel\", \"when\": \"scroll\", \"do\": \"reverse\" }",
            replace: "{ \"control\": \"thumbWheel\", \"when\": \"scroll\", \"do\": \"scroll\" }",
            path: "devices[0].rules[5].do"),
        Mutation(
            find: "{ \"button\": 1 }, \"when\": \"holdMove\", \"do\": \"scroll\"",
            replace: "{ \"button\": 1 }, \"when\": \"holdMove\", \"do\": \"missionControl\"",
            path: "devices[0].rules[6].do"),
        Mutation(
            find: "{ \"control\": { \"hidpp\": \"0xC4\" }, \"when\": \"click\", \"do\": { \"shortcut\": \"shift+cmd+4\" } }",
            replace: "{ \"control\": { \"hidpp\": \"0xC4\" }, \"when\": \"holdMove\", \"do\": \"scroll\" }, "
                + "{ \"control\": { \"hidpp\": \"0xC4\" }, \"when\": \"holdMoveUp\", \"do\": \"appExpose\" }",
            path: "devices[0].rules[5].when"),
        Mutation(find: "{ \"button\": 1 }", replace: "{ \"button\": 0 }", path: "devices[0].rules[6].control.button"),
        Mutation(
            find: "{ \"control\": { \"key\": \"return\" }, \"when\": \"click\"",
            replace: "{ \"control\": { \"button\": 0 }, \"when\": \"click\"", path: "devices[1].rules[1].control.button"),
        Mutation(
            find: "{ \"control\": { \"key\": \"return\" }, \"when\": \"click\"",
            replace: "{ \"control\": { \"button\": 32 }, \"when\": \"click\"", path: "devices[1].rules[1].control.button"),
        Mutation(
            find: "{ \"control\": { \"key\": \"return\" }, \"when\": \"click\", \"do\": { \"shortcut\": \"opt+shift+s\" } }",
            replace: "{ \"control\": { \"button\": 2 }, \"when\": \"holdMoveDown\", \"do\": \"scroll\" }",
            path: "devices[1].rules[1].when"),
        Mutation(find: "\"kind\": \"mouse\"", replace: "\"kind\": \"trackpad\"", path: "devices[1].kind"),
        Mutation(
            find: "\"when\": \"click\", \"do\": \"missionControl\"", replace: "\"when\": \"hold\", \"do\": \"missionControl\"",
            path: "devices[0].rules[0].do"),
        Mutation(
            find: "\"when\": \"hold\", \"do\": { \"modifier\": \"rightOption\" }",
            replace: "\"when\": \"hold\", \"do\": { \"shortcut\": \"cmd+c\" }", path: "devices[1].rules[0].do"),
        Mutation(
            find: "{ \"control\": \"thumbWheel\", \"when\": \"scroll\", \"do\": \"reverse\" }",
            replace: "{ \"control\": \"thumbWheel\", \"when\": \"hold\", \"do\": { \"modifier\": \"leftShift\" } }",
            path: "devices[0].rules[5].when"),
        Mutation(find: "\"speed\": 1,", replace: "\"speed\": 9,", path: "devices[0].scrolling.holdToScroll.speed"),
        Mutation(find: "\"speed\": 1,", replace: "\"speed\": 0.1,", path: "devices[0].scrolling.holdToScroll.speed"),
        Mutation(
            find: "\"direction\": \"grab\"", replace: "\"direction\": \"drag\"",
            path: "devices[0].scrolling.holdToScroll.direction"),
        Mutation(
            find: "\"momentum\": true }", replace: "\"momentum\": true, \"friction\": 1 }",
            path: "devices[0].scrolling.holdToScroll.friction"),
        Mutation(find: "\"direction\": \"grab\", ", replace: "", path: "devices[0].scrolling.holdToScroll.direction"),
    ]

    @Test(arguments: mutations)
    func invalidFileIsRejectedWithItsPath(_ mutation: Mutation) throws {
        #expect(documentedExampleJSON.contains(mutation.find), "the mutation applies to the documented file")
        let json = documentedExampleJSON.replacingOccurrences(of: mutation.find, with: mutation.replace)
        let error = try #require(rejection(json), "the file is rejected")
        #expect(error.path == mutation.path)
    }
}

@Suite struct RuleAcceptanceTests {
    static let controls: [Control] = [.hidpp(CID(rawValue: 0xC3)), .thumbWheel, .key(HIDUsage(name: "escape")!), .button(4)]
    static let triggers: [Trigger] = [.click, .hold, .holdMove(.up), .holdMove(nil), .scroll]
    static let actions: [Action] = [
        .system(.missionControl), .shortcut(Chord(key: KeyCode(name: "4")!, modifiers: [.command])),
        .modifier(.rightOption), .reverse, .scroll,
    ]

    static func parses(_ rule: Rule) -> Bool {
        var config = Config.example
        config.devices[0].rules = [rule]
        return (try? ConfigCodec.decode(ConfigCodec.encode(config))) != nil
    }

    @Test(arguments: controls)
    func acceptsMatchesWhatTheParserTakes(_ control: Control) {
        for trigger in Self.triggers {
            let parsesWithSomeAction = Self.actions.contains {
                Self.parses(Rule(control: control, trigger: trigger, action: $0))
            }
            #expect(control.accepts(trigger) == parsesWithSomeAction, "\(control) \(trigger)")
            for action in Self.actions {
                #expect(
                    control.accepts(action, on: trigger)
                        == Self.parses(Rule(control: control, trigger: trigger, action: action)),
                    "\(control) \(trigger) \(action)")
            }
        }
    }
}
