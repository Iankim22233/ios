import SwiftUI
import UIKit

/// Multi-touch game input. Each finger is a "key": touching a lane (by angle around the fan's apex, or by column
/// in the classic layout) presses that lane; lifting releases it. A horizontal swipe while a finger is down
/// fires a slide. Events are fed through `InputCenter` as synthetic keys so the game logic is untouched.
struct TouchLayer: UIViewRepresentable {
    let session: GameSession

    func makeUIView(context: Context) -> TouchView {
        let v = TouchView()
        v.session = session
        return v
    }
    func updateUIView(_ v: TouchView, context: Context) { v.session = session }
}

final class TouchView: UIView {
    weak var session: GameSession?
    private struct Track { var code: UInt16?; var lastX: CGFloat; var pad = false }
    private var tracks: [UITouch: Track] = [:]
    private let slideDistance: CGFloat = 34

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
        isExclusiveTouch = false
    }
    required init?(coder: NSCoder) { fatalError() }

    private func send(_ code: UInt16, down: Bool, time: TimeInterval) {
        InputCenter.shared.dispatch(KeyEvent(code: code, isDown: down, time: time, chars: "", isRepeat: false, isModifier: false))
    }

    /// Touch inside the pad row: a lane code, or a slide key (returned as `slide`).
    private func padHit(at p: CGPoint) -> (code: UInt16, isSlide: Bool)? {
        guard let s = session, p.y >= PadLayout.barTop(bounds.size) - 10 else { return nil }
        let n = s.engine.laneCount
        let keys = s.settings.keys(for: s.song.keyCount)
        guard keys.count >= n else { return nil }
        let slots = PadLayout.slots(size: bounds.size, lanes: n)
        // nearest slot by x (pads have gaps / margins; the whole bottom strip stays live)
        var best = 0, bd = CGFloat.infinity
        for (i, r) in slots.enumerated() {
            let d = p.x < r.minX ? r.minX - p.x : (p.x > r.maxX ? p.x - r.maxX : 0)
            if d < bd { bd = d; best = i }
        }
        if best == 0 { return (s.settings.slideLeft.code, true) }
        if best == n + 1 { return (s.settings.slideRight.code, true) }
        return (keys[best - 1].code, false)
    }

    private func laneCode(at p: CGPoint) -> UInt16? {
        guard let s = session else { return nil }
        let n = s.engine.laneCount
        let keys = s.settings.keys(for: s.song.keyCount)
        guard n > 0, keys.count >= n else { return nil }
        let geo = FanGeometry(size: bounds.size, laneCount: n, speed: s.settings.scrollSpeed,
                              centerY: PadLayout.centerY(size: bounds.size, classic: s.mods.classic), classic: s.mods.classic, uScale: PadLayout.uScale)
        var best = 0
        if geo.classic {
            best = min(n - 1, max(0, Int((Double(p.x) - geo.stageX) / geo.laneW)))
        } else {
            let span = 80.0 * Double.pi / 180
            let dx = Double(p.x) - geo.apex.x
            let dy = Double(p.y) - geo.apex.y
            let a: Double
            if dy < -4 { a = atan2(dx, -dy) }                 // above the apex: true angle
            else { a = max(-span, min(span, dx / (Double(bounds.width) * 0.5) * span * 1.4)) }   // thumb zone: by column
            var bd = Double.infinity
            for (i, la) in geo.angles.enumerated() where abs(la - a) < bd { bd = abs(la - a); best = i }
        }
        return keys[best].code
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let s = session else { return }
        for t in touches {
            let p = t.location(in: self)
            if s.phase == .running, s.activeLesson != nil {         // tutorial card: any tap continues
                send(49, down: true, time: t.timestamp); send(49, down: false, time: t.timestamp)
                tracks[t] = Track(code: nil, lastX: p.x)
                continue
            }
            if let hit = padHit(at: p), hit.isSlide {              // slide pads are taps
                send(hit.code, down: true, time: t.timestamp); send(hit.code, down: false, time: t.timestamp)
                tracks[t] = Track(code: nil, lastX: p.x, pad: true)
                continue
            }
            let code = padHit(at: p)?.code ?? laneCode(at: p)
            tracks[t] = Track(code: code, lastX: p.x, pad: padHit(at: p) != nil)
            if let c = code { send(c, down: true, time: t.timestamp) }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let s = session else { return }
        for t in touches {
            guard var tr = tracks[t], !tr.pad else { continue }   // pad touches don't swipe-slide
            let x = t.location(in: self).x
            let dx = x - tr.lastX
            if abs(dx) >= slideDistance {
                let key = dx < 0 ? s.settings.slideLeft : s.settings.slideRight
                send(key.code, down: true, time: t.timestamp); send(key.code, down: false, time: t.timestamp)
                tr.lastX = x
                tracks[t] = tr
            }
        }
    }

    private func finish(_ touches: Set<UITouch>) {
        for t in touches {
            if let tr = tracks.removeValue(forKey: t), let c = tr.code { send(c, down: false, time: t.timestamp) }
        }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { finish(touches) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { finish(touches) }
}


/// Reports the exact timestamp of each touch-down (SwiftUI gestures don't expose it).
struct TapCatcher: UIViewRepresentable {
    var onTap: (TimeInterval) -> Void
    final class TapView: UIView {
        var onTap: ((TimeInterval) -> Void)?
        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            if let t = touches.first { onTap?(t.timestamp) }
        }
    }
    func makeUIView(context: Context) -> TapView { let v = TapView(); v.backgroundColor = .clear; v.onTap = onTap; return v }
    func updateUIView(_ v: TapView, context: Context) { v.onTap = onTap }
}
