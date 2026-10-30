import SwiftUI
import UIKit

/// Layout of the bottom row of big touch pads: [◀ slide] [lane 1 … lane n] [slide ▶].
enum PadLayout {
    static var sideInset: CGFloat {
        let w = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.windows.first
        return max(14, max(w?.safeAreaInsets.left ?? 0, w?.safeAreaInsets.right ?? 0))
    }
    static func barHeight(_ size: CGSize) -> CGFloat { min(max(size.height * 0.3, 90), 170) }
    static func barTop(_ size: CGSize) -> CGFloat { size.height - barHeight(size) - 6 }

    /// Playfield is drawn a bit smaller than the Mac version so the outer lanes have room to travel.
    static let uScale = 0.8

    /// Fan apex height as a fraction of the screen: as low as it can go while the score box still clears the pad row.
    static func centerY(size: CGSize, classic: Bool) -> Double {
        if classic { return 0.62 }
        let u = max(0.3, min(Double(size.height) / 800, Double(size.width) / 1180)) * uScale
        let apex = Double(barTop(size)) - 173 * u - 8
        return max(0.3, min(0.6, apex / Double(size.height)))
    }

    /// Slots left→right: slide-left, lanes…, slide-right.
    static func slots(size: CGSize, lanes n: Int) -> [CGRect] {
        let inset = sideInset
        let gap: CGFloat = 8
        let total = size.width - inset * 2
        let weights: [CGFloat] = [1.15] + Array(repeating: 1, count: n) + [1.15]
        let sum = weights.reduce(0, +)
        let avail = total - gap * CGFloat(weights.count - 1)
        var x = inset
        let top = barTop(size), h = barHeight(size)
        return weights.map { w in
            let ww = avail * w / sum
            defer { x += ww + gap }
            return CGRect(x: x, y: top, width: ww, height: h)
        }
    }
}

struct PadsView: View {
    let session: GameSession

    var body: some View {
        TimelineView(.animation) { _ in
            GeometryReader { geo in
                let n = session.engine.laneCount
                let slots = PadLayout.slots(size: geo.size, lanes: n)
                ForEach(0..<slots.count, id: \.self) { i in
                    let r = slots[i]
                    let isSlide = i == 0 || i == n + 1
                    let lane = i - 1
                    let pressed: Bool = isSlide ? (i == 0 ? session.fx.slideLeftPress > 0.25 : session.fx.slideRightPress > 0.25)
                                                : (lane < session.engine.keyDown.count && session.engine.keyDown[lane])
                    let col = isSlide ? Color(red: 0.55, green: 0.85, blue: 1) : Palette.lane(lane, of: n)
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(pressed ? col : col.opacity(isSlide ? 0.28 : 0.30))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.black, lineWidth: 4))
                        .overlay {
                            if isSlide {
                                VStack(spacing: 2) {
                                    Image(systemName: i == 0 ? "arrow.left" : "arrow.right").font(.system(size: 26, weight: .black))
                                    Text("SLIDE").font(.system(size: 11, weight: .black, design: .rounded))
                                }.foregroundStyle(pressed ? .black : .white)
                            }
                        }
                        .shadow(color: .black.opacity(0.5), radius: 0, y: pressed ? 1 : 4)
                        .offset(y: pressed ? 3 : 0)
                        .frame(width: r.width, height: r.height)
                        .position(x: r.midX, y: r.midY)
                }
            }
        }
    }
}
