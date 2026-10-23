import HyperpointKit
import SwiftUI

/// The speed curve as a graph. Drag a point to change it, double-click the line to add one, double-click a point to
/// remove it. A drag saves once, when it ends.
struct SpeedGraph: View {
    let curve: SpeedCurve
    let commit: (SpeedCurve) -> Void

    /// The curve while a drag is in progress or a save has not come back yet.
    @State private var draft: SpeedCurve?
    @State private var drag: (index: Int, base: SpeedCurve)?
    @State private var pointer: CGPoint?
    @State private var plotSize = CGSize.zero
    @Environment(\.isEnabled) private var enabled

    nonisolated private static let margins = EdgeInsets(top: 24, leading: 64, bottom: 42, trailing: 16)

    var body: some View {
        let shown = draft ?? curve
        let graph = CurveGraph(size: plotSize)
        VStack(alignment: .leading, spacing: 6) {
            Canvas { context, _ in
                context.translateBy(x: Self.margins.leading, y: Self.margins.top)
                draw(shown, on: graph, in: &context)
            }
            .frame(height: 300)
            .onGeometryChange(for: CGSize.self) { proxy in
                CGSize(
                    width: proxy.size.width - Self.margins.leading - Self.margins.trailing,
                    height: proxy.size.height - Self.margins.top - Self.margins.bottom)
            } action: { plotSize = $0 }
            .contentShape(Rectangle())
            .gesture(dragGesture(graph))
            .onTapGesture(count: 2) { location in doubleClick(at: Self.plot(location), on: graph) }
            .onContinuousHover { phase in
                if case .active(let location) = phase { pointer = Self.plot(location) } else { pointer = nil }
            }
            Text(readout(shown, on: graph))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Text("Drag a point to change it. Double-click the line to add a point, or a point to remove it.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .opacity(enabled ? 1 : 0.45)
        .onChange(of: curve) { draft = nil }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Scroll speed for each spin speed")
        .accessibilityValue(
            shown.points.map { "\(CurveGraph.rateText($0.stepsPerSecond)) steps/s: \(CurveGraph.number($0.pointsPerSecond)) pt/s" }
                .joined(separator: ", "))
    }

    private static func plot(_ location: CGPoint) -> CGPoint {
        CGPoint(x: location.x - margins.leading, y: location.y - margins.top)
    }

    private func dragGesture(_ graph: CurveGraph) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                guard enabled else { return }
                if drag == nil {
                    let base = draft ?? curve
                    guard let index = graph.pointIndex(near: Self.plot(value.startLocation), in: base) else { return }
                    drag = (index, base)
                }
                guard let drag else { return }
                pointer = Self.plot(value.location)
                draft = CurveGraph.dragging(drag.base, point: drag.index, to: graph.point(at: Self.plot(value.location)))
            }
            .onEnded { _ in
                defer { drag = nil }
                guard drag != nil, let draft else { return }
                if draft == curve { self.draft = nil } else { commit(draft) }
            }
    }

    private func doubleClick(at location: CGPoint, on graph: CurveGraph) {
        guard enabled else { return }
        let base = draft ?? curve
        let edited =
            if let index = graph.pointIndex(near: location, in: base) {
                CurveGraph.removing(base, point: index)
            } else {
                CurveGraph.adding(base, at: graph.point(at: location).stepsPerSecond)
            }
        guard let edited else { return }
        draft = edited
        commit(edited)
    }

    /// The dragged or hovered point's values, or the curve's under the pointer.
    private func readout(_ shown: SpeedCurve, on graph: CurveGraph) -> String {
        if let drag { return CurveGraph.readout(shown, at: shown.points[drag.index].stepsPerSecond) }
        guard let pointer, CGRect(origin: .zero, size: graph.size).contains(pointer) else {
            let step = CurveGraph.number(shown.distancePerStep(at: shown.slowest))
            return "A single step from rest scrolls \(step) pt. Point at the graph to read it."
        }
        let rate = graph.pointIndex(near: pointer, in: shown).map { shown.points[$0].stepsPerSecond }
        return CurveGraph.readout(shown, at: rate ?? graph.point(at: pointer).stepsPerSecond)
    }

    private func draw(_ shown: SpeedCurve, on graph: CurveGraph, in context: inout GraphicsContext) {
        let size = graph.size
        let plot = CGRect(origin: .zero, size: size)
        let line = Color.secondary.opacity(0.18)

        context.fill(Path(plot), with: .color(.secondary.opacity(0.04)))
        for band in CurveGraph.bands {
            let left = graph.x(band.rates.lowerBound)
            let right = graph.x(band.rates.upperBound)
            context.fill(Path(CGRect(x: left, y: 0, width: right - left, height: size.height)), with: .color(.accentColor.opacity(0.09)))
            let label = context.resolve(Text(band.label).font(.caption2).foregroundStyle(.secondary))
            let width = label.measure(in: size).width
            let center = min(max((left + right) / 2, width / 2), size.width - width / 2)
            context.draw(label, at: CGPoint(x: center, y: -4), anchor: .bottom)
        }
        for rate in CurveGraph.rateTicks {
            let x = graph.x(rate)
            context.stroke(Path { $0.addLines([CGPoint(x: x, y: 0), CGPoint(x: x, y: size.height)]) }, with: .color(line))
            let label = context.resolve(Text(CurveGraph.rateText(rate)).font(.caption2).foregroundStyle(.secondary))
            context.draw(label, at: CGPoint(x: x, y: size.height + 4), anchor: .top)
        }
        for speed in CurveGraph.speedTicks {
            let y = graph.y(speed)
            context.stroke(Path { $0.addLines([CGPoint(x: 0, y: y), CGPoint(x: size.width, y: y)]) }, with: .color(line))
            let label = context.resolve(Text(CurveGraph.number(speed)).font(.caption2).foregroundStyle(.secondary))
            context.draw(label, at: CGPoint(x: -6, y: y), anchor: .trailing)
        }
        context.stroke(Path(plot), with: .color(.secondary.opacity(0.35)))
        let rateTitle = context.resolve(Text("Spin speed, steps per second").font(.caption).foregroundStyle(.secondary))
        context.draw(rateTitle, at: CGPoint(x: size.width / 2, y: size.height + 22), anchor: .top)
        var rotated = context
        rotated.translateBy(x: -50, y: size.height / 2)
        rotated.rotate(by: .degrees(-90))
        let speedTitle = context.resolve(Text("Scroll speed, points per second").font(.caption).foregroundStyle(.secondary))
        rotated.draw(speedTitle, at: .zero, anchor: .center)

        let positions = shown.points.map(graph.position(of:))
        let first = positions[0]
        let last = positions[positions.count - 1]
        let flat = StrokeStyle(lineWidth: 2, dash: [4, 4])
        context.stroke(Path { $0.addLines([CGPoint(x: 0, y: first.y), first]) }, with: .color(.accentColor.opacity(0.6)), style: flat)
        context.stroke(Path { $0.addLines([last, CGPoint(x: size.width, y: last.y)]) }, with: .color(.accentColor.opacity(0.6)), style: flat)
        context.stroke(Path { $0.addLines(positions) }, with: .color(.accentColor), lineWidth: 2)

        let active = drag?.index ?? pointer.flatMap { graph.pointIndex(near: $0, in: shown) }
        if active == nil, let pointer, plot.contains(pointer) {
            let rate = graph.point(at: pointer).stepsPerSecond
            let x = graph.x(rate)
            context.stroke(
                Path { $0.addLines([CGPoint(x: x, y: 0), CGPoint(x: x, y: size.height)]) },
                with: .color(.secondary.opacity(0.5)), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
            let dot = CGPoint(x: x, y: graph.y(shown.pointsPerSecond(at: rate)))
            context.fill(Path(ellipseIn: CGRect(x: dot.x - 3, y: dot.y - 3, width: 6, height: 6)), with: .color(.accentColor))
        }
        for (index, position) in positions.enumerated() {
            let radius: CGFloat = index == active ? 7 : 5
            let circle = Path(ellipseIn: CGRect(x: position.x - radius, y: position.y - radius, width: radius * 2, height: radius * 2))
            context.fill(circle, with: .color(.accentColor))
            context.stroke(circle, with: .color(.white), lineWidth: 1.5)
        }
    }
}
