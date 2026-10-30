import UIKit
import SwiftUI

// A small design system that echoes the prototype: flat greys, white shapes, thick black outlines.

enum UI {
    static func font(_ size: CGFloat, _ weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
    static let line: CGFloat = 4
    static let paper = Color.white
    static let ink = Color.black
    static func accent(_ hue: Double) -> Color { Color(hue: hue, saturation: 0.62, brightness: 1.0) }
}

struct Panel<Content: View>: View {
    var radius: CGFloat = 20
    var fill: Color = .white
    var shadow = true
    @ViewBuilder var content: Content
    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(fill)
                    .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(UI.ink, lineWidth: UI.line))
                    .shadow(color: .black.opacity(shadow ? 0.28 : 0), radius: 0, x: 0, y: shadow ? 7 : 0)
            )
    }
}

enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
}

/// Visible + haptic touch feedback for custom (non-MD) buttons.
struct PressFeedbackStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .brightness(configuration.isPressed ? -0.1 : 0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, p in if p { Haptics.tap() } }
    }
}

struct MDButtonStyle: ButtonStyle {
    var accent: Color? = nil
    var compact = false
    var selected = false
    func makeBody(configuration: Configuration) -> some View {
        MDButtonBody(configuration: configuration, accent: accent, compact: compact, selected: selected)
    }
}

private struct MDButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let accent: Color?
    let compact: Bool
    let selected: Bool
    @State private var hover = false
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        let pressed = configuration.isPressed
        let base = accent ?? .white
        configuration.label
            .font(UI.font(compact ? 15 : 20))
            .foregroundStyle(.black)
            .padding(.horizontal, compact ? 14 : 22)
            .padding(.vertical, compact ? 8 : 13)
            .background(
                RoundedRectangle(cornerRadius: compact ? 12 : 16, style: .continuous)
                    .fill(selected ? UI.accent(0.13) : (pressed ? base.blended(with: .black, by: 0.22) : (hover ? base.blended(with: .white, by: accent == nil ? 0 : 0.25) : base)))
                    .overlay(RoundedRectangle(cornerRadius: compact ? 12 : 16, style: .continuous).stroke(.black, lineWidth: UI.line))
                    .shadow(color: .black.opacity(0.9), radius: 0, x: 0, y: pressed ? 1 : (hover ? 6 : 4))
            )
            .offset(y: pressed ? 3 : (hover ? -2 : 0))
            .scaleEffect(pressed ? 0.94 : (hover ? 1.03 : 1))
            .opacity(enabled ? 1 : 0.45)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hover)
            .animation(.easeOut(duration: 0.08), value: pressed)
            .onChange(of: pressed) { _, p in if p && enabled { Haptics.tap() } }
            .onHover { h in
                hover = h
                if h && enabled { AudioManager.shared.play(.move, volume: 0.5) }
            }
    }
}

struct Keycap: View {
    var label: String
    var color: Color = .white
    var width: CGFloat = 64
    var active = false
    var body: some View {
        Text(label)
            .font(UI.font(label.count > 2 ? 15 : 24))
            .foregroundStyle(.black)
            .frame(width: width, height: 54)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(active ? color : Color.white)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.black, lineWidth: 4))
                    .overlay(alignment: .top) {
                        Capsule().fill(color.opacity(active ? 0 : 1)).frame(height: 7).padding(.horizontal, 9).padding(.top, 5)
                    }
                    .shadow(color: .black.opacity(0.9), radius: 0, x: 0, y: active ? 1 : 5)
            )
            .offset(y: active ? 4 : 0)
    }
}

struct MDSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double = 0
    var tint: Color = UI.accent(0.55)
    @State private var dragging = false

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let t = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            ZStack(alignment: .leading) {
                Capsule().fill(Color(white: 0.9)).overlay(Capsule().stroke(.black, lineWidth: 3.5))
                Capsule().fill(tint).frame(width: max(18, w * t)).overlay(Capsule().stroke(.black, lineWidth: 3.5))
                Circle().fill(.white).overlay(Circle().stroke(.black, lineWidth: 4))
                    .frame(width: dragging ? 30 : 26, height: dragging ? 30 : 26)
                    .shadow(color: .black.opacity(0.35), radius: 0, x: 0, y: 3)
                    .offset(x: clamp(w * t - 13, -2, w - 24))
            }
            .frame(height: 22)
            .position(x: w / 2, y: g.size.height / 2)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in
                    dragging = true
                    var nt = clamp(v.location.x / w, 0, 1)
                    var nv = range.lowerBound + nt * (range.upperBound - range.lowerBound)
                    if step > 0 { nv = (nv / step).rounded() * step; nt = (nv - range.lowerBound) / (range.upperBound - range.lowerBound) }
                    if nv != value { value = nv }
                }
                .onEnded { _ in dragging = false })
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: dragging)
        }
        .frame(height: 30)
    }
}

struct MDToggle: View {
    @Binding var isOn: Bool
    var body: some View {
        Button { isOn.toggle(); AudioManager.shared.play(.move) } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? UI.accent(0.33) : Color(white: 0.88)).overlay(Capsule().stroke(.black, lineWidth: 3.5))
                Circle().fill(.white).overlay(Circle().stroke(.black, lineWidth: 3.5)).padding(3)
            }
            .frame(width: 58, height: 32)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isOn)
        }
        .buttonStyle(PressFeedbackStyle())
    }
}

/// The wedge/circle motif as a small icon.
struct FanIcon: View {
    var lanes = 4
    var hue: Double = 0.55
    var animate = false
    var inverted = false
    var body: some View {
        TimelineView(.animation(paused: !animate)) { tl in
            Canvas { ctx, size in
                let fillC: Color = inverted ? .black : .white
                let lineC: Color = inverted ? .white : .black
                let t = tl.date.timeIntervalSinceReferenceDate
                let u = min(size.width, size.height) / 100
                let apex = CGPoint(x: size.width / 2, y: size.height * 0.68)
                let span = 80.0 * .pi / 180
                let step = 2 * span / Double(max(1, lanes - 1))
                for i in 0..<(lanes - 1) {
                    let mid = -span + step * (Double(i) + 0.5)
                    let hw = step * 0.27
                    func pt(_ a: Double, _ r: Double) -> CGPoint { CGPoint(x: apex.x + r * sin(a), y: apex.y - r * cos(a)) }
                    var p = Path()
                    p.move(to: apex)
                    p.addLine(to: pt(mid - hw, 62 * u))
                    p.addLine(to: pt(mid + hw, 62 * u))
                    p.closeSubpath()
                    ctx.fill(p, with: .color(fillC))
                    var e = Path()
                    e.move(to: pt(mid - hw, 62 * u)); e.addLine(to: apex); e.addLine(to: pt(mid + hw, 62 * u))
                    ctx.stroke(e, with: .color(lineC), style: StrokeStyle(lineWidth: 4 * u, lineCap: .round, lineJoin: .round))
                }
                for i in 0..<lanes {
                    let a = -span + step * Double(i)
                    let phase = animate ? (t * 0.8 + Double(i) * 0.37).truncatingRemainder(dividingBy: 1) : 0.5
                    let r = (14 + 56 * (1 - phase)) * u
                    let c = CGPoint(x: apex.x + r * sin(a), y: apex.y - r * cos(a))
                    let col = Palette.lane(i, of: lanes)
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - 5 * u, y: c.y - 5 * u, width: 10 * u, height: 10 * u)), with: .color(col))
                }
                let box = CGRect(x: size.width * 0.1, y: apex.y - 4 * u, width: size.width * 0.8, height: 30 * u)
                ctx.fill(Path(roundedRect: box, cornerRadius: 3 * u), with: .color(fillC))
                ctx.stroke(Path(roundedRect: box, cornerRadius: 3 * u), with: .color(lineC), style: StrokeStyle(lineWidth: 4 * u))
                let c = Path(ellipseIn: CGRect(x: apex.x - 17 * u, y: apex.y - 17 * u, width: 34 * u, height: 34 * u))
                ctx.fill(c, with: .color(fillC))
                ctx.stroke(c, with: .color(lineC), style: StrokeStyle(lineWidth: 4 * u))
                let d = Path(ellipseIn: CGRect(x: apex.x - 5 * u, y: apex.y - 5 * u, width: 10 * u, height: 10 * u))
                ctx.fill(d, with: .color(fillC))
                ctx.stroke(d, with: .color(lineC), style: StrokeStyle(lineWidth: 3 * u))
            }
        }
    }
}

struct ScreenHeader: View {
    var title: String
    var subtitle: String? = nil
    var onBack: () -> Void
    var trailing: AnyView? = nil
    var body: some View {
        HStack(spacing: 18) {
            Button(action: { AudioManager.shared.play(.back); onBack() }) {
                Label("Back", systemImage: "chevron.left")
            }
            .buttonStyle(MDButtonStyle(compact: true))
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(UI.font(34)).foregroundStyle(.white)
                    .shadow(color: .black, radius: 0, x: 0, y: 3)
                if let s = subtitle { Text(s).font(UI.font(14, .bold)).foregroundStyle(.white.opacity(0.85)) }
            }
            Spacer()
            if let t = trailing { t }
        }
    }
}

extension Color {
    func blended(with other: Color, by t: Double) -> Color {
        let a = self.rgbTuple(), b = other.rgbTuple()
        return Color(red: lerp(a.0, b.0, t), green: lerp(a.1, b.1, t), blue: lerp(a.2, b.2, t))
    }
}
