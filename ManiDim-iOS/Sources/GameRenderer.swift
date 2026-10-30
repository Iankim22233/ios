import SwiftUI

// MARK: - Geometry

struct FanGeometry {
    let size: CGSize
    let u: Double
    let apex: CGPoint
    let n: Int
    let angles: [Double]
    let laneHalf: Double
    let hw: Double
    let circleR: Double
    let hitR: Double
    let pps: Double
    let boxRect: CGRect
    let maxR: Double
    // Classic (vertical) layout
    let classic: Bool
    let laneW: Double
    let stageX: Double
    let stageW: Double
    let hitY: Double
    let keysTop: Double

    init(size: CGSize, laneCount n: Int, speed: Double, centerX: Double = 0.5, centerY: Double = 0.62, boxWidthU: Double? = nil, classic: Bool = false, uScale: Double = 1) {
        let uu = max(0.3, min(Double(size.height) / 800, Double(size.width) / 1180)) * uScale
        let ap = CGPoint(x: size.width * centerX, y: size.height * centerY)
        let span = 80.0 * Double.pi / 180
        let step = n > 1 ? 2 * span / Double(n - 1) : 0
        let lw = n > 1 ? min(26.0 * Double.pi / 180, step * 0.5) : 26.0 * Double.pi / 180
        self.size = size
        self.u = uu
        self.apex = ap
        self.n = n
        self.angles = (0..<n).map { n == 1 ? 0 : -span + step * Double($0) }
        self.laneHalf = lw / 2
        self.hw = max(0.025, (step - lw) / 2)
        self.classic = classic
        let cw = min(84 * uu, Double(size.width) * 0.6 / Double(max(1, n)))
        self.laneW = cw
        self.stageW = cw * Double(n)
        self.stageX = Double(size.width) * centerX - cw * Double(n) / 2
        self.keysTop = Double(size.height) - 128 * uu
        self.hitY = Double(size.height) - 128 * uu
        self.circleR = 76 * uu
        self.hitR = classic ? 0 : 80 * uu
        self.pps = speed * 62 * uu
        let bw = boxWidthU.map { $0 * uu } ?? min(Double(size.width) * 0.84, 980 * uu)
        self.boxRect = CGRect(x: ap.x - bw / 2, y: ap.y - 17 * uu, width: bw, height: 190 * uu)
        self.maxR = classic ? Double(size.height) - 128 * uu + 120 * uu
                            : hypot(max(ap.x, size.width - ap.x), max(ap.y, size.height - ap.y)) + 140 * uu
    }

    /// Distance from the receptor to the screen edge along a lane direction (used for visibility mods).
    func visibleLength(_ a: Double) -> Double {
        let dx = sin(a), dy = -cos(a)
        var t = Double.infinity
        if dx > 1e-6 { t = min(t, (Double(size.width) - apex.x) / dx) } else if dx < -1e-6 { t = min(t, (0 - apex.x) / dx) }
        if dy < -1e-6 { t = min(t, (0 - apex.y) / dy) }
        return max(60, t - hitR)
    }

    func laneX(_ i: Int) -> Double { stageX + laneW * (Double(i) + 0.5) }
    func receptor(_ lane: Int) -> CGPoint {
        let l = min(max(lane, 0), n - 1)
        return classic ? CGPoint(x: laneX(l), y: hitY) : point(angles[l], circleR + 6 * u)
    }
    func outward(_ lane: Int) -> CGVector {
        let l = min(max(lane, 0), n - 1)
        return classic ? CGVector(dx: 0, dy: -1) : CGVector(dx: sin(angles[l]), dy: -cos(angles[l]))
    }
    func y(dt: Double) -> Double { hitY - dt * pps }

    /// Horizontal position of a note's path at time t (classic layout).
    func pathX(_ note: Note, _ t: Double) -> Double {
        var l = note.lane
        var x = laneX(min(max(l, 0), n - 1))
        let tw = 0.07
        for s in note.slides {
            let nl = min(max(l + s.dir, 0), n - 1)
            let w = smoothstep((t - (s.time - tw)) / (2 * tw))
            x += (laneX(nl) - laneX(l)) * w
            l = nl
        }
        return x
    }

    func point(_ a: Double, _ r: Double) -> CGPoint { CGPoint(x: apex.x + r * sin(a), y: apex.y - r * cos(a)) }
    func tangent(_ a: Double) -> CGVector { CGVector(dx: cos(a), dy: sin(a)) }
    func radius(dt: Double) -> Double { hitR + dt * pps }

    /// Angle of a note's path at time t (smooth transitions at slide events).
    func pathAngle(_ note: Note, _ t: Double) -> Double {
        var l = note.lane
        var ang = angles[min(max(l, 0), n - 1)]
        let tw = 0.07
        for s in note.slides {
            let nl = min(max(l + s.dir, 0), n - 1)
            let w = smoothstep((t - (s.time - tw)) / (2 * tw))
            ang += (angles[nl] - angles[l]) * w
            l = nl
        }
        return ang
    }

    func pathColor(_ note: Note, _ t: Double) -> Color {
        var l = note.lane
        var rgb = Palette.rgb(l, of: n)
        let tw = 0.07
        for s in note.slides {
            let nl = min(max(l + s.dir, 0), n - 1)
            let w = smoothstep((t - (s.time - tw)) / (2 * tw))
            if w > 0 {
                let a = Palette.rgb(l, of: n), b = Palette.rgb(nl, of: n)
                rgb = (lerp(a.0, b.0, w), lerp(a.1, b.1, w), lerp(a.2, b.2, w))
            }
            l = nl
        }
        return Color(red: rgb.0, green: rgb.1, blue: rgb.2)
    }
}

// MARK: - FX state

final class FX {
    struct Particle { var x, y, vx, vy, life, maxLife, size: Double; var color: Color }
    struct Ring { var born: Double; var color: Color; var big: Bool; var lane: Int }
    struct Pop { var text: String; var color: Color; var born: Double; var early: Int }

    var queue: [GameEvent] = []
    var particles: [Particle] = []
    var rings: [Ring] = []
    var laneGlow = [Double](repeating: 0, count: 10)
    var laneKey = [Bool](repeating: false, count: 10)
    var capPress = [Double](repeating: 0, count: 10)
    var slideLeftPress = 0.0, slideRightPress = 0.0
    var pop: Pop?
    var comboBorn = -10.0
    var shake = 0.0
    var flash = 0.0
    var flashColor = Color.white
    var circleFlash = 0.0
    var circleColor = Color.white
    var needleAngle = 0.0
    var needleAlpha = 0.0
    var lastWall = 0.0
    var holdEmit = 0.0
    var slideBursts: [(born: Double, lane: Int, dir: Int)] = []
    var frameDT = 1.0 / 60
    var fps = 60.0

    func reset() {
        queue.removeAll(); particles.removeAll(); rings.removeAll()
        laneGlow = [Double](repeating: 0, count: 10)
        laneKey = [Bool](repeating: false, count: 10)
        pop = nil; shake = 0; flash = 0; circleFlash = 0; needleAlpha = 0; slideBursts.removeAll()
    }

    func begin(wall: Double) {
        var dt = wall - lastWall
        if lastWall == 0 || dt > 0.25 || dt <= 0 { dt = 1.0 / 60 }
        lastWall = wall
        frameDT = dt
        fps = lerp(fps, 1 / dt, 0.05)
        shake = max(0, shake - dt * 30)
        flash = max(0, flash - dt * 2.4)
        circleFlash = max(0, circleFlash - dt * 3.2)
        for i in 0..<laneGlow.count { laneGlow[i] = max(laneGlow[i] - dt * 3.4, laneKey[i] ? 0.5 : 0) }
        slideLeftPress = max(0, slideLeftPress - dt * 5)
        slideRightPress = max(0, slideRightPress - dt * 5)
        for i in 0..<capPress.count { capPress[i] = laneKey[i] ? 1 : max(0, capPress[i] - dt * 9) }
        var k = 0
        while k < particles.count {
            particles[k].life -= dt
            if particles[k].life <= 0 { particles.swapAt(k, particles.count - 1); particles.removeLast(); continue }
            particles[k].x += particles[k].vx * dt
            particles[k].y += particles[k].vy * dt
            particles[k].vy += 380 * dt
            particles[k].vx *= (1 - dt * 1.4)
            k += 1
        }
        rings.removeAll { wall - $0.born > 0.55 }
        slideBursts.removeAll { wall - $0.born > 0.5 }
    }

    func consume(geo: FanGeometry, wall: Double, particlesOn: Bool, shakeOn: Bool, combo: Int) {
        let n = geo.n
        for e in queue {
            switch e {
            case .keyDown(let lane):
                if lane < laneKey.count { laneKey[lane] = true; laneGlow[lane] = max(laneGlow[lane], 0.9) }
            case .keyUp(let lane):
                if lane < laneKey.count { laneKey[lane] = false }
            case .hit(let lane, let j, let off, let kind):
                let col = Palette.lane(lane, of: n)
                laneGlow[min(lane, 9)] = 1
                rings.append(Ring(born: wall, color: col, big: j == .perfect || kind == .holdTail, lane: lane))
                circleFlash = 1
                circleColor = j.color
                flash = max(flash, j == .perfect ? 0.22 : 0.12)
                flashColor = col
                if kind != .holdTail || true {
                    pop = Pop(text: j.title, color: j.color, born: wall, early: abs(off) < 0.03 || kind == .holdTail ? 0 : (off < 0 ? -1 : 1))
                }
                comboBorn = wall
                if particlesOn { burst(geo: geo, lane: lane, color: col, count: j == .perfect ? 16 : 10) }
            case .miss(_, let kind):
                pop = Pop(text: "MISS", color: Judgment.miss.color, born: wall, early: 0)
                if shakeOn { shake = max(shake, 7) }
                circleFlash = 1
                circleColor = Judgment.miss.color
                comboBorn = wall - 5
                _ = kind
            case .mash:
                pop = Pop(text: "NO MASHING", color: Judgment.miss.color, born: wall, early: 0)
                if shakeOn { shake = max(shake, 9) }
            case .holdBegin:
                break
            case .holdEnd(let lane, let ok):
                if ok, particlesOn { burst(geo: geo, lane: lane, color: Palette.lane(lane, of: n), count: 22) }
            case .slide(let from, let to, _):
                let dir = to > from ? 1 : -1
                slideBursts.append((born: wall, lane: to, dir: dir))
                if particlesOn { burst(geo: geo, lane: to, color: .white, count: 14) }
            }
        }
        queue.removeAll(keepingCapacity: true)
        _ = combo
    }

    func burst(geo: FanGeometry, lane: Int, color: Color, count: Int) {
        guard lane >= 0, lane < geo.n else { return }
        let p = geo.receptor(lane)
        let o = geo.outward(lane)
        let a = atan2(o.dx, -o.dy)
        let dirx = o.dx, diry = o.dy
        for _ in 0..<count {
            let spread = Double.random(in: -0.9...0.9)
            let ca = a + spread
            let sp = Double.random(in: 120...460) * geo.u
            let life = Double.random(in: 0.35...0.8)
            particles.append(Particle(x: p.x, y: p.y,
                                      vx: sin(ca) * sp + dirx * 40, vy: -cos(ca) * sp + diry * 40 - 60,
                                      life: life, maxLife: life, size: Double.random(in: 2.5...6.5) * geo.u, color: color))
        }
        if particles.count > 500 { particles.removeFirst(particles.count - 500) }
    }
}

// MARK: - Render input

struct RenderState {
    var engine: GameEngine
    var fx: FX
    var time: Double
    var wall: Double
    var settings: GameSettings
    var bpm: Double
    var offset: Double
    var hue: Double
    var title: String = ""
    var artist: String = ""
    var chartName: String = ""
    var duration: Double = 0
    var keyLabels: [String] = []
    var centerX = 0.5
    var centerY = 0.62
    var uScale = 1.0
    var touchPads = false
    var events: [ChartEvent] = []
    var classic = false
    var visibility: Visibility = .none
    var scoreMult = 1.0
    var modLabel = ""
    var showHUD = true
    var ambient = false     // attract mode: no HUD, softer
}

// MARK: - Renderer

enum GameRenderer {
    /// Alpha for the visibility mods; p = how far the note is from the receptor (0 = at it, 1 = at the screen edge).
    static func visAlpha(_ v: Visibility, _ p: Double) -> Double {
        switch v {
        case .none: return 1
        case .blackout: return 0
        case .blindSpot: return smoothstep((p - 0.42) / 0.16)          // gone once it is halfway in
        case .blindSpot2: return 1 - smoothstep((p - 0.28) / 0.37)     // only appears when it is close
        }
    }

    static func fanAlpha(_ geo: FanGeometry, _ rs: RenderState, angle: Double, time t: Double) -> Double {
        guard rs.visibility != .none else { return 1 }
        let r = geo.radius(dt: t - rs.time)
        return visAlpha(rs.visibility, (r - geo.hitR) / geo.visibleLength(angle))
    }

    static func draw(_ ctx: inout GraphicsContext, size: CGSize, rs: RenderState) {
        let eng = rs.engine
        let fx = rs.fx
        let skin = rs.settings.skin
        let theme = Theme.make(skin)
        let geo = FanGeometry(size: size, laneCount: eng.laneCount, speed: rs.settings.scrollSpeed, centerX: rs.centerX, centerY: rs.centerY,
                              boxWidthU: rs.ambient ? 560 : nil, classic: rs.classic, uScale: rs.uScale)
        let u = geo.u

        fx.begin(wall: rs.wall)
        fx.consume(geo: geo, wall: rs.wall, particlesOn: rs.settings.particles, shakeOn: rs.settings.screenShake, combo: eng.combo)

        let spb = 60.0 / max(40, rs.bpm)
        let beatPos = (rs.time - rs.offset) / spb
        let frac = beatPos - floor(beatPos)
        let pulse = rs.settings.beatPulse ? exp(-frac * 4.5) : 0

        drawBackground(&ctx, size: size, geo: geo, theme: theme, rs: rs, pulse: pulse)

        var c = ctx
        if fx.shake > 0.01 {
            c.translateBy(x: Double.random(in: -1...1) * fx.shake * u, y: Double.random(in: -1...1) * fx.shake * u)
        }
        let fxOn = rs.settings.chartEffects && !rs.events.isEmpty && !rs.ambient
        if fxOn {
            let sh = ChartFX.shake(rs.events, at: rs.time, u: u)
            c.translateBy(x: sh.width, y: sh.height)
        }

        if geo.classic {
            drawClassic(&c, size: size, geo: geo, theme: theme, rs: rs, beatPos: beatPos, pulse: pulse)
        } else {
            drawLanes(&c, geo: geo, theme: theme, rs: rs, beatPos: beatPos)
            drawNotes(&c, geo: geo, theme: theme, rs: rs)
            drawBase(&c, geo: geo, theme: theme, rs: rs, pulse: pulse)
            drawNeedle(&c, geo: geo, rs: rs)
            drawEffects(&c, geo: geo, theme: theme, rs: rs)
        }
        if fxOn {
            let center = geo.classic ? CGPoint(x: geo.stageX + geo.stageW / 2, y: geo.hitY) : geo.apex
            ChartFX.draw(&c, size: size, center: center, u: u, events: rs.events, time: rs.time)
        }
        if rs.showHUD && !rs.ambient { drawTopHUD(&c, size: size, geo: geo, theme: theme, rs: rs) }
    }

    // MARK: Background

    static func drawBackground(_ ctx: inout GraphicsContext, size: CGSize, geo: FanGeometry, theme: Theme, rs: RenderState, pulse: Double) {
        drawBackdrop(&ctx, size: size, apex: geo.apex, u: geo.u, spec: rs.settings.background.spec(for: rs.settings.skin, classic: rs.classic), hue: rs.hue,
                     wall: rs.wall, pulse: pulse, flash: rs.fx.flash, flashColor: rs.fx.flashColor)
    }

    static func drawBackdrop(_ ctx: inout GraphicsContext, size: CGSize, apex: CGPoint, u: Double, spec: BackdropSpec, hue: Double,
                             wall: Double, pulse: Double = 0, flash: Double = 0, flashColor: Color = .white) {
        let rect = CGRect(origin: .zero, size: size)
        if let img = spec.image {
            let iw = img.size.width, ih = img.size.height
            let sc = max(size.width / iw, size.height / ih)
            let r = CGRect(x: (size.width - iw * sc) / 2, y: (size.height - ih * sc) / 2, width: iw * sc, height: ih * sc)
            ctx.fill(Path(rect), with: .color(.black))
            ctx.draw(Image(uiImage: img), in: r)
            ctx.fill(Path(rect), with: .color(.black.opacity(spec.dim)))
        } else {
            ctx.fill(Path(rect), with: .linearGradient(Gradient(colors: [spec.top, spec.bottom]),
                                                        startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
        }
        if spec.decor {
            // Drifting colour orbs tinted with the song hue.
            for i in 0..<6 {
                let fi = Double(i)
                let x = size.width * (0.5 + 0.45 * sin(wall * 0.07 + fi * 1.9))
                let y = size.height * (0.4 + 0.35 * cos(wall * 0.05 + fi * 2.3))
                let r = u * (180 + 90 * Double(i % 3))
                let col = Color(hue: (hue + fi * 0.09).truncatingRemainder(dividingBy: 1), saturation: 0.55, brightness: 1)
                ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                         with: .radialGradient(Gradient(colors: [col.opacity(0.13 + 0.03 * pulse), col.opacity(0)]),
                                               center: CGPoint(x: x, y: y), startRadius: 0, endRadius: r))
            }
        }
        if flash > 0.001 {
            ctx.fill(Path(rect), with: .color(flashColor.opacity(flash * 0.3)))
        }
        if spec.decor || spec.image != nil {
            ctx.fill(Path(rect), with: .radialGradient(Gradient(colors: [.clear, .black.opacity(0.32)]),
                                                        center: apex, startRadius: size.height * 0.35, endRadius: max(size.width, size.height) * 0.85))
        }
    }

    // MARK: Lanes

    /// A short stroke segment lengthened slightly at both ends so neighbouring pieces overlap without seams.
    static func seg(_ a: CGPoint, _ b: CGPoint, ext: Double = 1.6) -> Path {
        let dx = b.x - a.x, dy = b.y - a.y
        let len = max(0.001, hypot(dx, dy))
        let ux = dx / len * ext, uy = dy / len * ext
        return line([CGPoint(x: a.x - ux, y: a.y - uy), CGPoint(x: b.x + ux, y: b.y + uy)])
    }

    static func line(_ pts: [CGPoint]) -> Path {
        var p = Path()
        guard let f = pts.first else { return p }
        p.move(to: f)
        for q in pts.dropFirst() { p.addLine(to: q) }
        return p
    }

    static func drawLanes(_ ctx: inout GraphicsContext, geo: FanGeometry, theme: Theme, rs: RenderState, beatPos: Double) {
        let u = geo.u
        let n = geo.n
        let far = geo.maxR * 1.6

        // Lane highlight beams.
        for i in 0..<n {
            let g = rs.fx.laneGlow[i]
            guard g > 0.01 else { continue }
            let a = geo.angles[i]
            let col = Palette.lane(i, of: n)
            var p = Path()
            p.move(to: geo.apex)
            p.addLine(to: geo.point(a - geo.laneHalf * 1.02, far))
            p.addLine(to: geo.point(a + geo.laneHalf * 1.02, far))
            p.closeSubpath()
            ctx.fill(p, with: .linearGradient(
                Gradient(stops: [.init(color: col.opacity(0.75 * g), location: 0), .init(color: col.opacity(0), location: 1)]),
                startPoint: geo.apex, endPoint: geo.point(a, 1000 * u)))
        }

        // Beat / bar arcs scrolling toward the receptor.
        let spb = 60.0 / max(40, rs.bpm)
        var k = Int(floor(beatPos))
        if k < 0 { k = 0 }
        let arcColor = Color.white
        while true {
            let tk = rs.offset + Double(k) * spb
            let r = geo.radius(dt: tk - rs.time)
            if r > geo.maxR { break }
            if r > geo.circleR {
                let bar = k % 4 == 0
                var pts: [CGPoint] = []
                let lo = geo.angles.first! - 0.28, hi = geo.angles.last! + 0.28
                for s in 0...28 { pts.append(geo.point(lerp(lo, hi, Double(s) / 28), r)) }
                let fade = clamp((geo.maxR - r) / (geo.maxR * 0.4), 0, 1)
                ctx.stroke(line(pts), with: .color(arcColor.opacity((bar ? 0.34 : 0.14) * fade)),
                           style: StrokeStyle(lineWidth: (bar ? 5 : 3) * u, lineCap: .round))
            }
            k += 1
            if k > Int(floor(beatPos)) + 80 { break }
        }

        // White divider wedges that run off to infinity.
        for i in 0..<(n - 1) {
            let mid = (geo.angles[i] + geo.angles[i + 1]) / 2
            let l = geo.point(mid - geo.hw, far), r = geo.point(mid + geo.hw, far)
            var wedge = Path()
            wedge.move(to: geo.apex)
            wedge.addLine(to: l)
            wedge.addLine(to: r)
            wedge.closeSubpath()
            ctx.fill(wedge, with: .linearGradient(Gradient(colors: [theme.wedge, theme.wedge.opacity(0.94)]),
                                                  startPoint: geo.apex, endPoint: geo.point(mid, 900 * u)))
            ctx.stroke(line([l, geo.apex, r]), with: .color(theme.outline),
                       style: StrokeStyle(lineWidth: 9 * u, lineCap: .round, lineJoin: .round))
        }
    }

    // MARK: Notes

    static func drawNotes(_ ctx: inout GraphicsContext, geo: FanGeometry, theme: Theme, rs: RenderState) {
        let eng = rs.engine
        let t = rs.time
        let horizon = (geo.maxR - geo.hitR) / geo.pps + 0.2
        var holds: [RNote] = []
        var taps: [RNote] = []
        for rn in eng.notes {
            let nt = rn.note
            if nt.time - t > horizon { break }
            if nt.endTime - t < -0.7 { continue }
            switch rn.state {
            case .done:
                continue
            case .missed, .dropped:
                if t - rn.changedAt > 0.5 { continue }
            default: break
            }
            if nt.isHold { holds.append(rn) } else { taps.append(rn) }
        }
        for rn in holds { drawHold(&ctx, geo: geo, rs: rs, rn: rn) }
        for rn in taps { drawTap(&ctx, geo: geo, rs: rs, rn: rn) }
    }

    static func tapBar(_ ctx: inout GraphicsContext, geo: FanGeometry, angle: Double, r: Double, color: Color, alpha: Double, scale: Double = 1, gray: Bool = false) {
        guard r < geo.maxR else { return }
        let u = geo.u
        let c = geo.point(angle, r)
        let T = geo.tangent(angle)
        let len = clamp(2 * max(r, 40 * u) * sin(geo.laneHalf) * 0.92, 74 * u, 150 * u) * scale
        let p1 = CGPoint(x: c.x - T.dx * len / 2, y: c.y - T.dy * len / 2)
        let p2 = CGPoint(x: c.x + T.dx * len / 2, y: c.y + T.dy * len / 2)
        var g = ctx
        g.opacity = alpha
        let col = gray ? Color(white: 0.55) : color
        g.stroke(line([p1, p2]), with: .color(col.opacity(0.28)), style: StrokeStyle(lineWidth: 44 * u, lineCap: .round))
        g.stroke(line([p1, p2]), with: .linearGradient(Gradient(colors: [gray ? .white.opacity(0.8) : .white, col]), startPoint: p1, endPoint: p2),
                 style: StrokeStyle(lineWidth: 27 * u, lineCap: .round))
        g.stroke(line([CGPoint(x: p1.x + T.dx * 8 * u, y: p1.y + T.dy * 8 * u - 6 * u),
                       CGPoint(x: p2.x - T.dx * 14 * u, y: p2.y - T.dy * 14 * u - 6 * u)]),
                 with: .color(.white.opacity(0.35)), style: StrokeStyle(lineWidth: 4 * u, lineCap: .round))
    }

    static func drawTap(_ ctx: inout GraphicsContext, geo: FanGeometry, rs: RenderState, rn: RNote) {
        let nt = rn.note
        let a = geo.angles[nt.lane]
        let r = geo.radius(dt: nt.time - rs.time)
        if rn.state == .missed {
            let age = rs.time - rn.changedAt
            tapBar(&ctx, geo: geo, angle: a, r: r, color: .gray, alpha: max(0, 0.6 - age * 1.2) * fanAlpha(geo, rs, angle: a, time: nt.time), gray: true)
        } else {
            let approach = clamp((geo.maxR - r) / (120 * geo.u), 0, 1)
            tapBar(&ctx, geo: geo, angle: a, r: r, color: Palette.lane(nt.lane, of: geo.n), alpha: approach * fanAlpha(geo, rs, angle: a, time: nt.time))
        }
    }

    static func drawHold(_ ctx: inout GraphicsContext, geo: FanGeometry, rs: RenderState, rn: RNote) {
        let u = geo.u
        let nt = rn.note
        let t = rs.time
        let holdingNow = rn.state == .holding
        let dead = rn.state == .missed || rn.state == .dropped
        let tStart = holdingNow ? max(t, nt.time) : nt.time
        let maxT = t + (geo.maxR + 100 * u - geo.hitR) / geo.pps
        let tEnd = min(nt.endTime, maxT)
        guard tEnd > tStart else { return }

        // Sample the path.
        var times: [Double] = [tStart]
        if !nt.slides.isEmpty || rs.visibility != .none {
            let step = max(0.008, (rs.visibility != .none ? 5 : 10) / geo.pps)
            var s = tStart + step
            while s < tEnd { times.append(s); s += step }
        }
        times.append(tEnd)
        var pts: [CGPoint] = []
        for s in times { pts.append(geo.point(geo.pathAngle(nt, s), geo.radius(dt: s - t))) }

        let baseColor = dead ? Color(white: 0.6) : Palette.lane(nt.lane, of: geo.n)
        var g = ctx
        if dead { g.opacity = max(0, 0.55 - (t - rn.changedAt) * 1.1) }
        let pulse = holdingNow ? 0.8 + 0.2 * sin(rs.wall * 22) : 1.0

        if rs.visibility != .none {
            // Visibility mods: fade the body segment by segment.
            for i in 0..<(pts.count - 1) {
                let mid = (times[i] + times[i + 1]) / 2
                let va = fanAlpha(geo, rs, angle: geo.pathAngle(nt, mid), time: mid)
                guard va > 0.01 else { continue }
                var sg = g
                sg.opacity = g.opacity * va
                let col = dead ? Color(white: 0.6) : geo.pathColor(nt, mid)
                let seg = seg(pts[i], pts[i + 1])
                sg.stroke(seg, with: .color(col.opacity(holdingNow ? 0.42 : 0.24)), style: StrokeStyle(lineWidth: (holdingNow ? 52 : 44) * u, lineCap: .butt))
                sg.stroke(seg, with: .color(col), style: StrokeStyle(lineWidth: 24 * u * pulse, lineCap: .butt))
                sg.stroke(seg, with: .color(.white.opacity(0.5)), style: StrokeStyle(lineWidth: 5 * u, lineCap: .butt))
            }
        } else {
        // Glow underlay
        g.stroke(line(pts), with: .color(baseColor.opacity(holdingNow ? 0.42 : 0.24)),
                 style: StrokeStyle(lineWidth: (holdingNow ? 52 : 44) * u, lineCap: .round, lineJoin: .round))

        if nt.slides.isEmpty {
            let far = Palette.lane(min(nt.lane + 1, geo.n - 1), of: geo.n)
            let end = dead ? Color(white: 0.7) : (nt.lane == geo.n - 1 ? Palette.lane(max(nt.lane - 1, 0), of: geo.n) : far)
            g.stroke(line(pts), with: .linearGradient(Gradient(colors: [baseColor, end]), startPoint: pts.first!, endPoint: pts.last!),
                     style: StrokeStyle(lineWidth: 24 * u * pulse, lineCap: .round))
        } else {
            for i in 0..<(pts.count - 1) {
                let col = dead ? Color(white: 0.6) : geo.pathColor(nt, (times[i] + times[i + 1]) / 2)
                g.stroke(line([pts[i], pts[i + 1]]), with: .color(col), style: StrokeStyle(lineWidth: 24 * u * pulse, lineCap: .round))
            }
        }
        g.stroke(line(pts), with: .color(.white.opacity(0.5)), style: StrokeStyle(lineWidth: 5 * u, lineCap: .round, lineJoin: .round))
        }

        // Head bar (until it's been hit) and tail cap.
        if rn.state == .waiting || dead {
            let a = geo.pathAngle(nt, nt.time)
            let r = geo.radius(dt: nt.time - t)
            tapBar(&g, geo: geo, angle: a, r: r, color: baseColor, alpha: fanAlpha(geo, rs, angle: a, time: nt.time), gray: dead)
        }
        if nt.endTime <= maxT {
            let a = geo.pathAngle(nt, nt.endTime)
            let r = geo.radius(dt: nt.endTime - t)
            if r > geo.circleR * 0.8 {
                let c = geo.point(a, r)
                let col = dead ? Color(white: 0.6) : geo.pathColor(nt, nt.endTime)
                var g = g
                g.opacity *= fanAlpha(geo, rs, angle: a, time: nt.endTime)
                g.fill(Path(ellipseIn: CGRect(x: c.x - 15 * u, y: c.y - 15 * u, width: 30 * u, height: 30 * u)), with: .color(.white))
                g.stroke(Path(ellipseIn: CGRect(x: c.x - 15 * u, y: c.y - 15 * u, width: 30 * u, height: 30 * u)),
                         with: .color(col), style: StrokeStyle(lineWidth: 7 * u))
            }
        }

        // Slide markers.
        var l = nt.lane
        for (i, s) in nt.slides.enumerated() {
            let nl = min(max(l + s.dir, 0), geo.n - 1)
            defer { l = nl }
            if rn.nextSlide > i && !dead { continue }
            let r = geo.radius(dt: s.time - t)
            if r < geo.circleR * 0.9 || r > geo.maxR { continue }
            let a = (geo.angles[l] + geo.angles[nl]) / 2
            var cg = g
            cg.opacity *= fanAlpha(geo, rs, angle: a, time: s.time)
            chevron(&cg, geo: geo, angle: a, r: r, dir: s.dir, dead: dead, wall: rs.wall)
        }
    }

    static func chevron(_ ctx: inout GraphicsContext, geo: FanGeometry, angle: Double, r: Double, dir: Int, dead: Bool, wall: Double) {
        let u = geo.u
        let c = geo.point(angle, r)
        let T = geo.tangent(angle)
        let N = CGVector(dx: sin(angle), dy: -cos(angle))
        let d = Double(dir)
        let bounce = 1 + 0.08 * sin(wall * 10)
        let s = 1.0 * u * bounce
        func pt(_ along: Double, _ across: Double) -> CGPoint {
            CGPoint(x: c.x + T.dx * along * d * s + N.dx * across * s, y: c.y + T.dy * along * d * s + N.dy * across * s)
        }
        var p = Path()
        p.move(to: pt(26, 0))
        p.addLine(to: pt(-6, 24))
        p.addLine(to: pt(-6, 9))
        p.addLine(to: pt(-24, 9))
        p.addLine(to: pt(-24, -9))
        p.addLine(to: pt(-6, -9))
        p.addLine(to: pt(-6, -24))
        p.closeSubpath()
        ctx.fill(p, with: .color(dead ? Color(white: 0.8) : .white))
        ctx.stroke(p, with: .color(.black), style: StrokeStyle(lineWidth: 4 * u, lineJoin: .round))
    }

    // MARK: Base, circle, HUD

    static func text(_ ctx: inout GraphicsContext, _ s: String, _ p: CGPoint, size: Double, weight: Font.Weight = .heavy,
                     color: Color, anchor: UnitPoint = .center, mono: Bool = false, opacity: Double = 1, design: Font.Design = .rounded) {
        var t = Text(s).font(.system(size: size, weight: weight, design: design))
        if mono { t = t.monospacedDigit() }
        let r = ctx.resolve(t.foregroundColor(color))
        var c = ctx
        c.opacity = opacity
        c.draw(r, at: p, anchor: anchor)
    }

    static func outlinedText(_ ctx: inout GraphicsContext, _ s: String, _ p: CGPoint, size: Double, color: Color, outline: Color = .black,
                             width: Double, opacity: Double = 1, anchor: UnitPoint = .center) {
        let t = Text(s).font(.system(size: size, weight: .black, design: .rounded))
        let dark = ctx.resolve(t.foregroundColor(outline))
        let fill = ctx.resolve(t.foregroundColor(color))
        var c = ctx
        c.opacity = opacity
        for k in 0..<10 {
            let a = Double(k) / 10 * 2 * Double.pi
            c.draw(dark, at: CGPoint(x: p.x + cos(a) * width, y: p.y + sin(a) * width), anchor: anchor)
        }
        c.draw(fill, at: p, anchor: anchor)
    }

    static func drawBase(_ ctx: inout GraphicsContext, geo: FanGeometry, theme: Theme, rs: RenderState, pulse: Double) {
        let u = geo.u
        let eng = rs.engine
        let fx = rs.fx
        let box = geo.boxRect

        // Soft shadow + box.
        let boxPath = Path(roundedRect: box, cornerRadius: 8 * u)
        ctx.fill(Path(roundedRect: box.offsetBy(dx: 0, dy: 10 * u), cornerRadius: 8 * u), with: .color(.black.opacity(0.25)))
        ctx.fill(boxPath, with: .color(theme.box))
        ctx.stroke(boxPath, with: .color(theme.outline), style: StrokeStyle(lineWidth: 9 * u, lineJoin: .round))

        // Receptor dots around the circle.
        for i in 0..<geo.n {
            let a = geo.angles[i]
            let p = geo.point(a, geo.circleR * (1 + 0.04 * pulse))
            let col = Palette.lane(i, of: geo.n)
            let press = fx.capPress[i]
            let rad = (7 + 7 * press) * u
            if press > 0.01 {
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - rad * 2.2, y: p.y - rad * 2.2, width: rad * 4.4, height: rad * 4.4)),
                         with: .radialGradient(Gradient(colors: [col.opacity(0.8 * press), col.opacity(0)]), center: p, startRadius: 0, endRadius: rad * 2.2))
            }
            _ = rad
        }

        // Hit circle.
        let cr = geo.circleR * (1 + 0.035 * pulse)
        let circle = Path(ellipseIn: CGRect(x: geo.apex.x - cr, y: geo.apex.y - cr, width: cr * 2, height: cr * 2))
        ctx.fill(circle, with: .color(theme.box))
        if fx.circleFlash > 0.01 {
            ctx.fill(circle, with: .radialGradient(Gradient(colors: [fx.circleColor.opacity(0.0), fx.circleColor.opacity(0.75 * fx.circleFlash)]),
                                                   center: geo.apex, startRadius: cr * 0.2, endRadius: cr))
        }
        ctx.stroke(circle, with: .color(theme.outline), style: StrokeStyle(lineWidth: 11 * u))

        // Receptor markers on the rim, drawn over the stroke.
        for i in 0..<geo.n {
            let a = geo.angles[i]
            let p = geo.point(a, cr)
            let col = Palette.lane(i, of: geo.n)
            let press = fx.capPress[i]
            let rad = (6.5 + 4 * press) * u
            let dot = Path(ellipseIn: CGRect(x: p.x - rad, y: p.y - rad, width: rad * 2, height: rad * 2))
            ctx.fill(dot, with: .color(press > 0.5 ? .white : col))
            ctx.stroke(dot, with: .color(theme.outline), style: StrokeStyle(lineWidth: 3 * u))
        }

        guard rs.showHUD || !rs.ambient else { return }
        if rs.ambient { drawInnerDot(&ctx, geo: geo, theme: theme); return }

        // Key caps.
        let n = geo.n
        let capW = min(66 * u, (box.width * 0.55) / Double(n))
        let gap = 10 * u
        let totalW = capW * Double(n) + gap * Double(n - 1)
        let capY = geo.apex.y + 100 * u
        let capH = 50 * u
        if !rs.touchPads {
            for i in 0..<n {
                let x = geo.apex.x - totalW / 2 + Double(i) * (capW + gap)
                let press = fx.capPress[i]
                let rect = CGRect(x: x, y: capY + 5 * u * press, width: capW, height: capH)
                let col = Palette.lane(i, of: n)
                let path = Path(roundedRect: rect, cornerRadius: 10 * u)
                ctx.fill(Path(roundedRect: rect.offsetBy(dx: 0, dy: 5 * u * (1 - press)), cornerRadius: 10 * u), with: .color(theme.capShadow))
                ctx.fill(path, with: .linearGradient(Gradient(colors: [press > 0.3 ? col : theme.capTop, press > 0.3 ? col.opacity(0.85) : theme.capBottom]),
                                                     startPoint: CGPoint(x: x, y: rect.minY), endPoint: CGPoint(x: x, y: rect.maxY)))
                ctx.stroke(path, with: .color(theme.outline), style: StrokeStyle(lineWidth: 4 * u))
                let lab = i < rs.keyLabels.count ? rs.keyLabels[i] : ""
                text(&ctx, lab, CGPoint(x: rect.midX, y: rect.midY), size: (lab.count > 2 ? 15 : 24) * u, color: press > 0.3 ? .black : theme.capText)
            }
            // Slide key caps.
            let slideW = 92 * u
            for (idx, dir) in [(-1, "◀"), (1, "▶")].enumerated() {
                let left = idx == 0
                let x = left ? geo.apex.x - totalW / 2 - gap * 2 - slideW : geo.apex.x + totalW / 2 + gap * 2
                let press = left ? fx.slideLeftPress : fx.slideRightPress
                let rect = CGRect(x: x, y: capY + 5 * u * press, width: slideW, height: capH)
                let path = Path(roundedRect: rect, cornerRadius: 10 * u)
                ctx.fill(Path(roundedRect: rect.offsetBy(dx: 0, dy: 5 * u * (1 - press)), cornerRadius: 10 * u), with: .color(theme.capShadow))
                ctx.fill(path, with: .color(press > 0.2 ? Color(red: 0.55, green: 0.85, blue: 1) : theme.capTop))
                ctx.stroke(path, with: .color(theme.outline), style: StrokeStyle(lineWidth: 4 * u))
                let lab = left ? (rs.keyLabels.count > n ? rs.keyLabels[n] : "") : (rs.keyLabels.count > n + 1 ? rs.keyLabels[n + 1] : "")
                text(&ctx, "\(dir.1) \(lab)", CGPoint(x: rect.midX, y: rect.midY), size: 16 * u, color: press > 0.2 ? .black : theme.capText)
            }
        }

        // Score (left) and combo (right).
        let lx = geo.apex.x - box.width * 0.27
        let rx = geo.apex.x + box.width * 0.27
        text(&ctx, String(format: "SCORE   %.2f%%", eng.accuracy * 100), CGPoint(x: lx, y: box.minY + 36 * u), size: 15 * u, color: theme.ink.opacity(0.45), mono: true)
        text(&ctx, String(format: "%07d", Int((Double(eng.score) * rs.scoreMult).rounded())), CGPoint(x: lx, y: box.minY + 88 * u), size: 52 * u, color: theme.ink, mono: true)

        let comboAge = rs.wall - fx.comboBorn
        let comboScale = 1 + 0.32 * exp(-comboAge * 14)
        text(&ctx, "COMBO   MAX \(eng.maxCombo)", CGPoint(x: rx, y: box.minY + 36 * u), size: 15 * u, color: theme.ink.opacity(0.45), mono: true)
        var cc = ctx
        cc.translateBy(x: rx, y: box.minY + 90 * u)
        cc.scaleBy(x: comboScale, y: comboScale)
        text(&cc, "\(eng.combo)", .zero, size: 60 * u, color: eng.combo >= 50 ? Color(red: 0.95, green: 0.35, blue: 0.55) : theme.ink, mono: true)

        drawInnerDot(&ctx, geo: geo, theme: theme)
    }

    static func drawInnerDot(_ ctx: inout GraphicsContext, geo: FanGeometry, theme: Theme) {
        let u = geo.u
        let dot = Path(ellipseIn: CGRect(x: geo.apex.x - 18 * u, y: geo.apex.y - 18 * u, width: 36 * u, height: 36 * u))
        ctx.fill(dot, with: .color(theme.box))
        ctx.stroke(dot, with: .color(theme.outline), style: StrokeStyle(lineWidth: 9 * u))
    }

    // MARK: Needle

    static func drawNeedle(_ ctx: inout GraphicsContext, geo: FanGeometry, rs: RenderState) {
        let fx = rs.fx
        let dt = fx.frameDT
        var target: Double?
        if let idx = rs.engine.holding.first {
            target = geo.pathAngle(rs.engine.notes[idx].note, rs.time)
        }
        if let tg = target {
            if fx.needleAlpha < 0.05 { fx.needleAngle = tg }
            fx.needleAngle += (tg - fx.needleAngle) * min(1, dt * 16)
            fx.needleAlpha = min(1, fx.needleAlpha + dt * 8)
        } else {
            fx.needleAlpha = max(0, fx.needleAlpha - dt * 6)
        }
        guard fx.needleAlpha > 0.01 else { return }
        let u = geo.u
        let a = fx.needleAngle
        let tip = geo.point(a, geo.circleR * 1.12)
        let tail = geo.point(a + Double.pi, geo.circleR * 1.12)
        let N = CGVector(dx: cos(a), dy: sin(a))
        let w = 13 * u
        var p = Path()
        p.move(to: tip)
        p.addLine(to: CGPoint(x: tail.x + N.dx * w, y: tail.y + N.dy * w))
        p.addLine(to: CGPoint(x: tail.x - N.dx * w, y: tail.y - N.dy * w))
        p.closeSubpath()
        var c = ctx
        c.opacity = fx.needleAlpha
        c.fill(p, with: .linearGradient(Gradient(colors: [Color(red: 0.88, green: 0.95, blue: 1), Color(red: 0.55, green: 0.75, blue: 1)]),
                                        startPoint: tip, endPoint: tail))
        c.stroke(p, with: .color(.black), style: StrokeStyle(lineWidth: 3.5 * u, lineJoin: .round))
        let theme = Theme.make(rs.settings.skin)
        drawInnerDot(&c, geo: geo, theme: theme)
    }

    // MARK: Effects (rings, particles, judgement text)

    static func drawEffects(_ ctx: inout GraphicsContext, geo: FanGeometry, theme: Theme, rs: RenderState) {
        let u = geo.u
        let fx = rs.fx
        let wall = rs.wall

        emitHoldSparks(geo: geo, rs: rs)

        // Rings.
        for ring in fx.rings {
            let age = (wall - ring.born) / 0.5
            guard age < 1 else { continue }
            let e = 1 - pow(1 - age, 3)
            let r = geo.circleR + (ring.big ? 110 : 70) * u * e
            let circle = Path(ellipseIn: CGRect(x: geo.apex.x - r, y: geo.apex.y - r, width: r * 2, height: r * 2))
            ctx.stroke(circle, with: .color(ring.color.opacity((1 - age) * 0.8)), style: StrokeStyle(lineWidth: max(1, (ring.big ? 10 : 6) * u * (1 - age))))
        }

        // Slide bursts: arc sweep along the circle.
        for b in fx.slideBursts {
            let age = (wall - b.born) / 0.5
            guard age < 1, b.lane < geo.n else { continue }
            let a0 = geo.angles[b.lane] - Double(b.dir) * 0.5 * (1 - age)
            var pts: [CGPoint] = []
            for s in 0...10 {
                let aa = a0 - Double(b.dir) * Double(s) * 0.05
                pts.append(geo.point(aa, geo.circleR + 12 * u + 20 * u * age))
            }
            ctx.stroke(line(pts), with: .color(.white.opacity((1 - age) * 0.9)), style: StrokeStyle(lineWidth: 9 * u * (1 - age), lineCap: .round))
        }

        drawParticles(&ctx, fx: fx)
        drawPop(&ctx, fx: fx, wall: wall, at: CGPoint(x: geo.apex.x, y: geo.apex.y - geo.circleR - 120 * u), u: u)
    }

    static func emitHoldSparks(geo: FanGeometry, rs: RenderState) {
        let fx = rs.fx
        guard rs.settings.particles, !rs.engine.holding.isEmpty else { return }
        fx.holdEmit += fx.frameDT * 70
        while fx.holdEmit >= 1 {
            fx.holdEmit -= 1
            if let idx = rs.engine.holding.first {
                let nt = rs.engine.notes[idx].note
                let lane = nt.lane(at: rs.time, count: geo.n)
                fx.burst(geo: geo, lane: lane, color: Palette.lane(lane, of: geo.n), count: 1)
            }
        }
    }

    static func drawParticles(_ ctx: inout GraphicsContext, fx: FX) {
        guard !fx.particles.isEmpty else { return }
        ctx.drawLayer { l in
            l.blendMode = .plusLighter
            for p in fx.particles {
                let k = p.life / p.maxLife
                let s = p.size * (0.4 + 0.6 * k)
                l.fill(Path(ellipseIn: CGRect(x: p.x - s, y: p.y - s, width: s * 2, height: s * 2)), with: .color(p.color.opacity(k)))
            }
        }
    }

    static func drawPop(_ ctx: inout GraphicsContext, fx: FX, wall: Double, at base: CGPoint, u: Double) {
        guard let pop = fx.pop else { return }
        let age = wall - pop.born
        guard age < 0.7 else { return }
        let scale = 1 + 0.35 * exp(-age * 18)
        let alpha = age < 0.45 ? 1 : max(0, 1 - (age - 0.45) / 0.25)
        var c = ctx
        c.translateBy(x: base.x, y: base.y - 6 * u * min(1, age * 5))
        c.scaleBy(x: scale, y: scale)
        outlinedText(&c, pop.text, .zero, size: 44 * u, color: pop.color, width: 3.2 * u, opacity: alpha)
        if pop.early != 0 {
            text(&c, pop.early < 0 ? "EARLY" : "LATE", CGPoint(x: 0, y: 36 * u), size: 15 * u,
                 color: pop.early < 0 ? Color(red: 0.55, green: 0.85, blue: 1) : Color(red: 1, green: 0.7, blue: 0.4), opacity: alpha)
        }
    }

    // MARK: Top HUD

    static func drawTopHUD(_ ctx: inout GraphicsContext, size: CGSize, geo: FanGeometry, theme: Theme, rs: RenderState) {
        let u = geo.u
        let margin = 26 * u
        outlinedText(&ctx, rs.title, CGPoint(x: margin, y: 62 * u), size: 26 * u, color: .white, width: 2.2 * u, anchor: .leading)
        outlinedText(&ctx, "\(rs.artist)  ·  \(rs.chartName)", CGPoint(x: margin, y: 90 * u), size: 14 * u, color: .white, width: 1.8 * u, anchor: .leading)

        if !rs.modLabel.isEmpty {
            outlinedText(&ctx, "\(rs.modLabel)  ×\(String(format: "%.2f", rs.scoreMult))", CGPoint(x: margin, y: 118 * u), size: 15 * u,
                         color: Color(red: 1, green: 0.88, blue: 0.4), width: 1.8 * u, anchor: .leading)
        }
        if rs.settings.autoplay {
            text(&ctx, "AUTOPLAY", CGPoint(x: size.width - margin, y: 40 * u), size: 18 * u, color: Color(red: 1, green: 0.85, blue: 0.3), anchor: .trailing)
        }
        if rs.settings.showFPS {
            text(&ctx, String(format: "%.0f fps", rs.fx.fps), CGPoint(x: size.width - margin, y: 62 * u), size: 13 * u, weight: .bold, color: .white.opacity(0.8), anchor: .trailing, mono: true)
        }

        // Progress bar
        let barH = 8 * u
        let rect = CGRect(x: 0, y: 0, width: size.width, height: barH)
        ctx.fill(Path(rect), with: .color(.black.opacity(0.5)))
        let p = rs.duration > 0 ? clamp(rs.time / rs.duration, 0, 1) : 0
        ctx.fill(Path(CGRect(x: 0, y: 0, width: size.width * p, height: barH)),
                 with: .linearGradient(Gradient(colors: (0..<geo.n).map { Palette.lane($0, of: geo.n) }),
                                       startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0)))
        ctx.fill(Path(CGRect(x: 0, y: barH, width: size.width, height: 3 * u)), with: .color(.black))
    }
}
