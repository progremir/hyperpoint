import Foundation
import HyperpointKit
import Testing

@testable import Hyperpoint

@Suite struct KnobTests {
    let english = Locale(identifier: "en_US")

    @Test func valuesShowWithTheirUnit() {
        #expect(SmoothKnob.speed.unit.format(60, locale: english) == "60 points")
        #expect(SmoothKnob.startBoost.unit.format(2, locale: english) == "2×")
        #expect(SmoothKnob.startBoost.unit.format(1.5, locale: english) == "1.5×")
        #expect(SmoothKnob.duration.unit.format(4, locale: english) == "0.4 s")
        #expect(SmoothKnob.duration.unit.format(20, locale: english) == "2.0 s")
        #expect(SmoothKnob.easeIn.unit.format(120, locale: english) == "120 ms")
        #expect(SmoothKnob.brake.unit.format(2, locale: english) == "2")
        #expect(SmoothKnob.accelerationFrom.unit.format(4, locale: english) == "4 steps/s")
        #expect(GestureKnob.unit.format(120, locale: english) == "120 counts")
        #expect(SmoothKnob.duration.unit.format(4, locale: Locale(identifier: "ru_RU")) == "0,4 s")
    }

    @Test func titlesArePlainWords() {
        let texts = SmoothKnob.allCases.flatMap { [$0.title, $0.detail] } + [GestureKnob.title, GestureKnob.detail]
        for text in texts {
            #expect(!text.isEmpty)
            let camelCase = text.split(separator: " ").contains { word in
                word.first?.isLowercase == true && word.contains(where: \.isUppercase)
            }
            #expect(!camelCase, "\(text)")
        }
        #expect(Set(SmoothKnob.allCases.map(\.title)).count == SmoothKnob.allCases.count)
    }

    @Test(arguments: SmoothKnob.allCases)
    func everySliderPositionSaves(_ knob: SmoothKnob) {
        let smooth = profile(.default, mx)!.scrolling!.smooth!
        for position in stride(from: 0.0, through: 1.0, by: 0.05) {
            let value = knob.scale(in: smooth).value(at: position)
            let edited = SettingsEdit.smoothKnob(mx, knob, value).applied(to: .default)
            #expect(saves(edited), "\(knob) at \(position) is \(value)")
            #expect(profile(edited, mx)?.scrolling?.smooth.map(knob.value) == value)
        }
    }

    @Test(arguments: SmoothKnob.allCases)
    func aValueOnAStepComesBackFromItsPosition(_ knob: SmoothKnob) {
        let scale = knob.scale(in: .default)
        for position in stride(from: 0.0, through: 1.0, by: 0.1) {
            let value = scale.value(at: position)
            #expect(scale.value(at: scale.position(of: value)) == value, "\(knob) \(value)")
        }
    }

    @Test func slidersRoundToTheirStep() {
        let boost = SmoothKnob.startBoost.scale(in: .default)
        for position in stride(from: 0.0, through: 1.0, by: 0.01) {
            let value = boost.value(at: position)
            #expect(value == (value * 10).rounded() / 10, "\(value)")
        }
    }

    @Test func theDefaultSpeedSitsMidSlider() {
        let position = SmoothKnob.speed.scale(in: .default).position(of: SmoothScroll.defaultSpeed)
        #expect(position > 0.4 && position < 0.7)
    }

    @Test func aValueOutsideTheSliderRangeShowsWhereItIs() {
        var smooth = SmoothScroll.default
        smooth.acceleration = Acceleration(from: 4, to: 400, max: 3)
        let scale = SmoothKnob.accelerationTo.scale(in: smooth)
        #expect(scale.value(at: scale.position(of: 400)) == 400)
    }

    @Test func gestureDistanceSaves() {
        let scale = GestureKnob.scale(for: 120)
        for position in [0.0, 0.5, 1.0] {
            let edited = SettingsEdit.gestureDistance(mx, Int(scale.value(at: position))).applied(to: .default)
            #expect(saves(edited))
        }
    }
}
