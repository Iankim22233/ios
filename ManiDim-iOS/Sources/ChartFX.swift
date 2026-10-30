import SwiftUI

/// Draws chart events (sparkles, fireworks, lasers…). Everything is a pure function of
/// (event, time), so it works the same during play, scrubbing and editor playback.
enum ChartFX {
    static func shake(_ events: [ChartEvent], at t: Double, u: Double) -> CGSize {
        var s = CGSize.zero
        for e in events where e.kind == .shake {
            let a = t - e.time
            guard a >= 0, a < e.length else { continue }
            let decay = pow(1 - a / e.length, 2)
            s.width += sin(a * 70) * 16 * u * decay
            s.height += cos(a * 83) * 12 * u * decay
        }
        return s
    }

    static func draw(_ ctx: inout GraphicsContext, size: CGSize, center: CGPoint, u: Double, events: [ChartEvent], time t: Double) {
        let W = Double(size.width), H = Double(size.height)
        let maxR = hypot(W, H)
        var additive: [(ChartEvent, Double)] = []

        for e in events {
            let a = t - e.time
            guard a >= 0, a < e.length else { continue }
            let k = a / e.length
            switch e.kind {
            case .flash:
                let c = Color(hue: e.hue, saturation: 0.25, brightness: 1)
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(c.opacity(pow(1 - k, 2) * 0.55)))
            case .tint:
                let env = min(1, a / 0.6, (e.length - a) / 0.9)
                ctx.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .color(Color(hue: e.hue, saturation: 0.65, brightness: 1).opacity(0.24 * max(0, env))))
            case .pulse:
                for i in 0..<3 {
                    let ai = a - Double(i) * 0.12
                    guard ai > 0 else { continue }
                    let p = min(1, ai / 0.7)
                    let r = (1 - pow(1 - p, 3)) * maxR * 0.85
                    let col = Color(hue: (e.hue + Double(i) * 0.08).truncatingRemainder(dividingBy: 1), saturation: 0.6, brightness: 1)
                    ctx.stroke(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
                               with: .color(col.opacity((1 - p) * 0.85)), style: StrokeStyle(lineWidth: max(1, 16 * u * (1 - p))))
                }
            case .shake:
                break
            case .sparkles, .fireworks, .lasers:
                additive.append((e, a))
            }
        }
        guard !additive.isEmpty else { return }

        for (e, a) in additive {
            switch e.kind {
            case .sparkles: sparkles(&ctx, e, a, W, H, u)
            case .fireworks: fireworks(&ctx, e, a, W, H, u)
            case .lasers: lasers(&ctx, e, a, W, H, u)
            default: break
            }
        }
    }

    private static func star(_ c: CGPoint, _ r: Double) -> Path {
        var p = Path()
        let inner = r * 0.22
        for i in 0..<8 {
            let ang = Double(i) * .pi / 4 - .pi / 2
            let rad = i % 2 == 0 ? r : inner
            let pt = CGPoint(x: c.x + cos(ang) * rad, y: c.y + sin(ang) * rad)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }

    private static func sparkles(_ ctx: inout GraphicsContext, _ e: ChartEvent, _ a: Double, _ W: Double, _ H: Double, _ u: Double) {
        let k = a / e.length
        var rng = SplitMix64(seed: e.seed)
        for _ in 0..<70 {
            let x0 = rng.unit() * W
            let delay = rng.unit() * e.length * 0.45
            let vy = (140 + rng.unit() * 280) * u
            let size = (3 + rng.unit() * 6) * u
            let hue = rng.unit()
            let phase = rng.unit() * 6.28
            let sway = (8 + rng.unit() * 22) * u
            let age = a - delay
            guard age > 0 else { continue }
            let y = -30 * u + vy * age
            guard y < H + 30 else { continue }
            let x = x0 + sin(age * 2.2 + phase) * sway
            let tw = 0.55 + 0.45 * sin(age * 13 + phase)
            let fade = max(0, 1 - k) * min(1, age * 4)
            let col = Color(hue: hue, saturation: 0.7, brightness: 1)
            let c = CGPoint(x: x, y: y)
            ctx.fill(Path(ellipseIn: CGRect(x: x - size * 2.6, y: y - size * 2.6, width: size * 5.2, height: size * 5.2)),
                     with: .radialGradient(Gradient(colors: [col.opacity(0.35 * tw * fade), col.opacity(0)]), center: c, startRadius: 0, endRadius: size * 2.6))
            let st = star(c, size * (1.2 + 0.6 * tw))
            ctx.fill(st, with: .color(col.opacity(min(1, tw * fade * 1.3))))
            ctx.stroke(st, with: .color(.black.opacity(0.45 * fade)), style: StrokeStyle(lineWidth: 1.2 * u, lineJoin: .round))
        }
    }

    private static func fireworks(_ ctx: inout GraphicsContext, _ e: ChartEvent, _ a: Double, _ W: Double, _ H: Double, _ u: Double) {
        var rng = SplitMix64(seed: e.seed)
        for b in 0..<3 {
            let cx = W * (0.15 + 0.7 * rng.unit()), cy = H * (0.12 + 0.33 * rng.unit())
            let baseHue = (e.hue + Double(b) * 0.27).truncatingRemainder(dividingBy: 1)
            let ab = a - Double(b) * 0.38
            let life = 1.35
            let sparks = 40
            let jit = rng.unit() * 6.28
            let speeds = (0..<sparks).map { _ in (150 + rng.unit() * 190) * u }
            let hues = (0..<sparks).map { _ in baseHue + rng.unit() * 0.12 }
            guard ab > 0, ab < life else { continue }
            let p = ab / life
            for j in 0..<sparks {
                let ang = Double(j) / Double(sparks) * 2 * .pi + jit
                func pos(_ tt: Double) -> CGPoint {
                    let d = 1 - exp(-tt * 2.6)
                    return CGPoint(x: cx + cos(ang) * speeds[j] * d * 1.4, y: cy + sin(ang) * speeds[j] * d * 1.4 + 150 * u * tt * tt)
                }
                let head = pos(ab), tail = pos(max(0, ab - 0.09))
                let col = Color(hue: hues[j].truncatingRemainder(dividingBy: 1), saturation: 0.75, brightness: 1)
                var path = Path()
                path.move(to: tail); path.addLine(to: head)
                ctx.stroke(path, with: .color(col.opacity((1 - p) * 0.9)), style: StrokeStyle(lineWidth: 3.2 * u * (1 - p * 0.5), lineCap: .round))
            }
            let flash = max(0, 1 - ab / 0.18)
            if flash > 0 {
                ctx.fill(Path(ellipseIn: CGRect(x: cx - 60 * u, y: cy - 60 * u, width: 120 * u, height: 120 * u)),
                         with: .radialGradient(Gradient(colors: [.white.opacity(0.8 * flash), .white.opacity(0)]), center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: 60 * u))
            }
        }
    }

    private static func lasers(_ ctx: inout GraphicsContext, _ e: ChartEvent, _ a: Double, _ W: Double, _ H: Double, _ u: Double) {
        let env = max(0, min(1, a / 0.5, (e.length - a) / 0.6))
        let n = 7
        for i in 0..<n {
            let ox = W * (Double(i) + 0.5) / Double(n)
            let ang = sin(a * 1.3 + Double(i) * 0.9) * 0.62
            let end = CGPoint(x: ox + sin(ang) * H * 1.6, y: cos(ang) * H * 1.6)
            let col = Color(hue: (e.hue + Double(i) * 0.07 + a * 0.05).truncatingRemainder(dividingBy: 1), saturation: 0.8, brightness: 1)
            var p = Path()
            p.move(to: CGPoint(x: ox, y: -10)); p.addLine(to: end)
            ctx.stroke(p, with: .linearGradient(Gradient(colors: [col.opacity(0.28 * env), col.opacity(0)]), startPoint: CGPoint(x: ox, y: 0), endPoint: end),
                       style: StrokeStyle(lineWidth: 34 * u, lineCap: .round))
            ctx.stroke(p, with: .linearGradient(Gradient(colors: [col.opacity(0.8 * env), col.opacity(0)]), startPoint: CGPoint(x: ox, y: 0), endPoint: end),
                       style: StrokeStyle(lineWidth: 7 * u, lineCap: .round))
        }
    }
}
