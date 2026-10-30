import SwiftUI

/// The "Classic" skin: a vertical, osu!mania-style stage. Same game, same engine — only the layout changes.
extension GameRenderer {
    static func drawClassic(_ ctx: inout GraphicsContext, size: CGSize, geo: FanGeometry, theme: Theme, rs: RenderState, beatPos: Double, pulse: Double) {
        let u = geo.u
        let n = geo.n
        let fx = rs.fx
        let x0 = geo.stageX, w = geo.stageW
        let hitY = geo.hitY
        let H = Double(size.height)

        // Stage panel
        ctx.fill(Path(CGRect(x: x0, y: -20, width: w, height: H + 40)), with: .color(.black.opacity(rs.ambient ? 0.72 : 0.9)))

        // Lane press glow
        for i in 0..<n {
            let g = fx.laneGlow[i]
            guard g > 0.01 else { continue }
            let col = Palette.lane(i, of: n)
            let r = CGRect(x: x0 + geo.laneW * Double(i), y: hitY - 460 * u, width: geo.laneW, height: 460 * u)
            ctx.fill(Path(r), with: .linearGradient(
                Gradient(stops: [.init(color: col.opacity(0), location: 0), .init(color: col.opacity(0.55 * g), location: 1)]),
                startPoint: CGPoint(x: r.midX, y: r.minY), endPoint: CGPoint(x: r.midX, y: r.maxY)))
        }

        // Beat / bar lines
        let spb = 60.0 / max(40, rs.bpm)
        var k = max(0, Int(floor(beatPos)) - 1)
        while true {
            let tk = rs.offset + Double(k) * spb
            let y = geo.y(dt: tk - rs.time)
            if y < -10 { break }
            if y < H {
                let bar = k % 4 == 0
                ctx.fill(Path(CGRect(x: x0, y: y - (bar ? 1.5 : 0.75) * u, width: w, height: (bar ? 3 : 1.5) * u)),
                         with: .color(.white.opacity(bar ? 0.3 : 0.12)))
            }
            k += 1
            if k > Int(floor(beatPos)) + 90 { break }
        }

        // Lane separators and side borders
        for i in 0...n {
            let x = x0 + geo.laneW * Double(i)
            if i == 0 || i == n {
                let bx = i == 0 ? x - 9 * u : x
                ctx.fill(Path(CGRect(x: bx, y: -20, width: 9 * u, height: H + 40)), with: .color(Color(white: 0.42)))
                ctx.fill(Path(CGRect(x: bx + (i == 0 ? 6 * u : 0), y: -20, width: 3 * u, height: H + 40)), with: .color(Color(white: 0.62)))
            } else {
                ctx.fill(Path(CGRect(x: x - 0.9 * u, y: -20, width: 1.8 * u, height: H + 40)), with: .color(.white.opacity(0.85)))
            }
        }

        // Notes
        let horizon = hitY / geo.pps + 0.3
        var holds: [RNote] = [], taps: [RNote] = []
        for rn in rs.engine.notes {
            let nt = rn.note
            if nt.time - rs.time > horizon { break }
            if nt.endTime - rs.time < -0.7 { continue }
            switch rn.state {
            case .done: continue
            case .missed, .dropped: if rs.time - rn.changedAt > 0.5 { continue }
            default: break
            }
            if nt.isHold { holds.append(rn) } else { taps.append(rn) }
        }
        for rn in holds { classicHold(&ctx, geo: geo, rs: rs, rn: rn) }
        for rn in taps {
            let nt = rn.note
            let y = geo.y(dt: nt.time - rs.time)
            if rn.state == .missed {
                classicBar(&ctx, geo: geo, x: geo.laneX(nt.lane), y: y, color: .gray, alpha: max(0, 0.6 - (rs.time - rn.changedAt) * 1.2) * classicAlpha(geo, rs, y: y), gray: true)
            } else {
                classicBar(&ctx, geo: geo, x: geo.laneX(nt.lane), y: y, color: Palette.lane(nt.lane, of: n), alpha: classicAlpha(geo, rs, y: y))
            }
        }

        // Receptors
        let keysTop = geo.keysTop
        let judge = CGRect(x: x0, y: hitY - 7 * u, width: w, height: 14 * u)
        ctx.fill(Path(judge), with: .linearGradient(Gradient(colors: [Color(red: 0.62, green: 0.70, blue: 0.84), Color(red: 0.36, green: 0.43, blue: 0.58)]),
                                                    startPoint: CGPoint(x: 0, y: judge.minY), endPoint: CGPoint(x: 0, y: judge.maxY)))
        ctx.fill(Path(CGRect(x: x0, y: judge.minY, width: w, height: 2 * u)), with: .color(.white.opacity(0.6)))
        for i in 0..<n {
            let press = fx.capPress[i]
            let light = min(i, n - 1 - i) % 2 == 0
            let base = light ? Color(red: 0.86, green: 0.76, blue: 0.90) : Color(red: 0.76, green: 0.33, blue: 0.58)
            let col = Palette.lane(i, of: n)
            let pad = CGRect(x: x0 + geo.laneW * Double(i) + 1.5 * u, y: keysTop + 7 * u + 4 * u * press, width: geo.laneW - 3 * u, height: H - keysTop + 20 * u)
            ctx.fill(Path(pad), with: .color(base.blended(with: col, by: 0.65 * press)))
            ctx.fill(Path(CGRect(x: pad.minX, y: pad.minY, width: pad.width, height: 3 * u)), with: .color(.white.opacity(0.35 + 0.4 * press)))
            let lab = i < rs.keyLabels.count ? rs.keyLabels[i] : ""
            text(&ctx, lab, CGPoint(x: pad.midX, y: pad.minY + 46 * u), size: (lab.count > 2 ? 15 : 26) * u, color: .black.opacity(0.55 + 0.35 * press))
        }

        // Slide keys sit beside the stage.
        for (idx, glyph) in ["◀", "▶"].enumerated() {
            let left = idx == 0
            let press = left ? fx.slideLeftPress : fx.slideRightPress
            let r = CGRect(x: left ? x0 - 12 * u - 96 * u : x0 + w + 12 * u, y: keysTop + 22 * u, width: 96 * u, height: 48 * u)
            ctx.fill(Path(roundedRect: r, cornerRadius: 10 * u), with: .color(press > 0.2 ? Color(red: 0.55, green: 0.85, blue: 1) : .white.opacity(0.14)))
            ctx.stroke(Path(roundedRect: r, cornerRadius: 10 * u), with: .color(.white.opacity(0.7)), style: StrokeStyle(lineWidth: 2.5 * u))
            let lab = left ? (rs.keyLabels.count > n ? rs.keyLabels[n] : "") : (rs.keyLabels.count > n + 1 ? rs.keyLabels[n + 1] : "")
            text(&ctx, "\(glyph) \(lab)", CGPoint(x: r.midX, y: r.midY), size: 16 * u, color: press > 0.2 ? .black : .white)
        }

        // Effects: rings, slide sweeps, sparks
        if !rs.ambient || true {
            emitHoldSparks(geo: geo, rs: rs)
            for ring in fx.rings {
                let age = (rs.wall - ring.born) / 0.5
                guard age < 1, ring.lane < n else { continue }
                let e = 1 - pow(1 - age, 3)
                let c = geo.receptor(ring.lane)
                let rw = geo.laneW * 0.5 + (ring.big ? 80 : 50) * u * e
                let rh = 14 * u + (ring.big ? 36 : 22) * u * e
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - rw, y: c.y - rh, width: rw * 2, height: rh * 2)),
                           with: .color(ring.color.opacity((1 - age) * 0.85)), style: StrokeStyle(lineWidth: max(1, 7 * u * (1 - age))))
            }
            for b in fx.slideBursts {
                let age = (rs.wall - b.born) / 0.5
                guard age < 1, b.lane < n else { continue }
                let c = geo.receptor(b.lane)
                let from = c.x - Double(b.dir) * geo.laneW * (1 - age * 0.3)
                ctx.stroke(line([CGPoint(x: from, y: c.y), CGPoint(x: c.x, y: c.y)]), with: .color(.white.opacity((1 - age) * 0.9)),
                           style: StrokeStyle(lineWidth: 10 * u * (1 - age), lineCap: .round))
            }
        }
        drawParticles(&ctx, fx: fx)

        guard rs.showHUD && !rs.ambient else { return }
        let theme = Theme.make(.classic)
        _ = theme
        // Combo in the middle of the stage.
        let eng = rs.engine
        if eng.combo >= 2 {
            let age = rs.wall - fx.comboBorn
            let sc = 1 + 0.28 * exp(-age * 14)
            var c = ctx
            c.translateBy(x: x0 + w / 2, y: hitY * 0.36)
            c.scaleBy(x: sc, y: sc)
            outlinedText(&c, "\(eng.combo)", .zero, size: 68 * u, color: .white.opacity(0.92), outline: .black.opacity(0.6), width: 2.5 * u)
            text(&c, "COMBO", CGPoint(x: 0, y: 46 * u), size: 15 * u, color: .white.opacity(0.7))
        }
        drawPop(&ctx, fx: fx, wall: rs.wall, at: CGPoint(x: x0 + w / 2, y: hitY - 150 * u), u: u)

        // Score block on the right.
        let rx = Double(size.width) - 34 * u
        text(&ctx, "SCORE", CGPoint(x: rx, y: 92 * u), size: 14 * u, color: .white.opacity(0.65), anchor: .trailing)
        text(&ctx, String(format: "%07d", Int((Double(eng.score) * rs.scoreMult).rounded())), CGPoint(x: rx, y: 132 * u), size: 50 * u, color: .white, anchor: .trailing, mono: true)
        text(&ctx, String(format: "%.2f%%", eng.accuracy * 100), CGPoint(x: rx, y: 176 * u), size: 24 * u, color: .white.opacity(0.85), anchor: .trailing, mono: true)
        text(&ctx, "MAX \(eng.maxCombo)", CGPoint(x: rx, y: 204 * u), size: 14 * u, color: .white.opacity(0.55), anchor: .trailing, mono: true)
    }

    static func classicAlpha(_ geo: FanGeometry, _ rs: RenderState, y: Double) -> Double {
        guard rs.visibility != .none else { return 1 }
        return visAlpha(rs.visibility, (geo.hitY - y) / max(1, geo.hitY))
    }

    static func classicBar(_ ctx: inout GraphicsContext, geo: FanGeometry, x: Double, y: Double, color: Color, alpha: Double, gray: Bool = false) {
        guard y > -40, y < Double(geo.size.height) + 40 else { return }
        let u = geo.u
        let wd = geo.laneW - 9 * u, h = 28 * u
        let r = CGRect(x: x - wd / 2, y: y - h / 2, width: wd, height: h)
        var g = ctx
        g.opacity = alpha
        let col = gray ? Color(white: 0.55) : color
        g.fill(Path(roundedRect: r.insetBy(dx: -5 * u, dy: -5 * u), cornerRadius: 14 * u), with: .color(col.opacity(0.25)))
        g.fill(Path(roundedRect: r, cornerRadius: 9 * u), with: .linearGradient(Gradient(colors: [.white, col]),
                                                                                 startPoint: CGPoint(x: x, y: r.minY), endPoint: CGPoint(x: x, y: r.maxY)))
        g.fill(Path(roundedRect: CGRect(x: r.minX + 8 * u, y: r.minY + 4 * u, width: r.width - 16 * u, height: 3.5 * u), cornerRadius: 2 * u), with: .color(.white.opacity(0.55)))
    }

    static func classicHold(_ ctx: inout GraphicsContext, geo: FanGeometry, rs: RenderState, rn: RNote) {
        let u = geo.u
        let nt = rn.note
        let t = rs.time
        let holdingNow = rn.state == .holding
        let dead = rn.state == .missed || rn.state == .dropped
        let tStart = holdingNow ? max(t, nt.time) : nt.time
        let maxT = t + (geo.hitY + 80 * u) / geo.pps
        let tEnd = min(nt.endTime, maxT)
        guard tEnd > tStart else { return }

        var times: [Double] = [tStart]
        if !nt.slides.isEmpty || rs.visibility != .none {
            let step = max(0.008, (rs.visibility != .none ? 5 : 10) / geo.pps)
            var s = tStart + step
            while s < tEnd { times.append(s); s += step }
        }
        times.append(tEnd)
        let pts = times.map { CGPoint(x: geo.pathX(nt, $0), y: geo.y(dt: $0 - t)) }

        let base = dead ? Color(white: 0.6) : Palette.lane(nt.lane, of: geo.n)
        var g = ctx
        if dead { g.opacity = max(0, 0.55 - (t - rn.changedAt) * 1.1) }
        let pulse = holdingNow ? 0.85 + 0.15 * sin(rs.wall * 22) : 1.0
        let bodyW = geo.laneW * 0.52 * pulse

        if rs.visibility != .none {
            for i in 0..<(pts.count - 1) {
                let mid = (times[i] + times[i + 1]) / 2
                let va = classicAlpha(geo, rs, y: geo.y(dt: mid - t))
                guard va > 0.01 else { continue }
                var sg = g
                sg.opacity = g.opacity * va
                let col = dead ? Color(white: 0.6) : geo.pathColor(nt, mid)
                let seg = seg(pts[i], pts[i + 1])
                sg.stroke(seg, with: .color(col.opacity(holdingNow ? 0.4 : 0.22)), style: StrokeStyle(lineWidth: bodyW + 16 * u, lineCap: .butt))
                sg.stroke(seg, with: .color(col), style: StrokeStyle(lineWidth: bodyW, lineCap: .butt))
                sg.stroke(seg, with: .color(.white.opacity(0.5)), style: StrokeStyle(lineWidth: 4 * u, lineCap: .butt))
            }
        } else {
        g.stroke(line(pts), with: .color(base.opacity(holdingNow ? 0.4 : 0.22)), style: StrokeStyle(lineWidth: bodyW + 16 * u, lineCap: .round, lineJoin: .round))
        if nt.slides.isEmpty {
            let other = Palette.lane(min(nt.lane + 1, geo.n - 1), of: geo.n)
            g.stroke(line(pts), with: .linearGradient(Gradient(colors: [dead ? Color(white: 0.7) : other, base]), startPoint: pts.last!, endPoint: pts.first!),
                     style: StrokeStyle(lineWidth: bodyW, lineCap: .round))
        } else {
            for i in 0..<(pts.count - 1) {
                let col = dead ? Color(white: 0.6) : geo.pathColor(nt, (times[i] + times[i + 1]) / 2)
                g.stroke(line([pts[i], pts[i + 1]]), with: .color(col), style: StrokeStyle(lineWidth: bodyW, lineCap: .round))
            }
        }
        g.stroke(line(pts), with: .color(.white.opacity(0.5)), style: StrokeStyle(lineWidth: 4 * u, lineCap: .round, lineJoin: .round))
        }

        if rn.state == .waiting || dead {
            let hy = geo.y(dt: nt.time - t)
            classicBar(&g, geo: geo, x: geo.pathX(nt, nt.time), y: hy, color: base, alpha: classicAlpha(geo, rs, y: hy), gray: dead)
        }
        if nt.endTime <= maxT {
            let c = CGPoint(x: geo.pathX(nt, nt.endTime), y: geo.y(dt: nt.endTime - t))
            let cap = CGRect(x: c.x - geo.laneW * 0.34, y: c.y - 9 * u, width: geo.laneW * 0.68, height: 18 * u)
            var g = g
            g.opacity *= classicAlpha(geo, rs, y: c.y)
            g.fill(Path(roundedRect: cap, cornerRadius: 8 * u), with: .color(.white))
            g.stroke(Path(roundedRect: cap, cornerRadius: 8 * u), with: .color(dead ? Color(white: 0.6) : geo.pathColor(nt, nt.endTime)), style: StrokeStyle(lineWidth: 5 * u))
        }

        var l = nt.lane
        for (i, s) in nt.slides.enumerated() {
            let nl = min(max(l + s.dir, 0), geo.n - 1)
            defer { l = nl }
            if rn.nextSlide > i && !dead { continue }
            let y = geo.y(dt: s.time - t)
            if y > geo.hitY + 10 * u || y < -30 { continue }
            let cx = (geo.laneX(l) + geo.laneX(nl)) / 2
            var cg = g
            cg.opacity *= classicAlpha(geo, rs, y: y)
            classicChevron(&cg, geo: geo, center: CGPoint(x: cx, y: y), dir: s.dir, dead: dead, wall: rs.wall)
        }
    }

    static func classicChevron(_ ctx: inout GraphicsContext, geo: FanGeometry, center c: CGPoint, dir: Int, dead: Bool, wall: Double) {
        let u = geo.u
        let d = Double(dir)
        let s = u * (1 + 0.08 * sin(wall * 10))
        func pt(_ along: Double, _ across: Double) -> CGPoint { CGPoint(x: c.x + along * d * s, y: c.y - across * s) }
        var p = Path()
        p.move(to: pt(26, 0)); p.addLine(to: pt(-6, 24)); p.addLine(to: pt(-6, 9)); p.addLine(to: pt(-24, 9))
        p.addLine(to: pt(-24, -9)); p.addLine(to: pt(-6, -9)); p.addLine(to: pt(-6, -24)); p.closeSubpath()
        ctx.fill(p, with: .color(dead ? Color(white: 0.8) : .white))
        ctx.stroke(p, with: .color(.black), style: StrokeStyle(lineWidth: 4 * u, lineJoin: .round))
    }
}
