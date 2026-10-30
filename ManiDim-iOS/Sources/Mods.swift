import SwiftUI

enum ModCategory: String, CaseIterable, Identifiable {
    case conversion, easy, hard
    var id: String { rawValue }
    var title: String {
        switch self {
        case .conversion: return "Conversion"
        case .easy: return "Easy"
        case .hard: return "Hard"
        }
    }
    var blurb: String {
        switch self {
        case .conversion: return "Change how the chart is laid out"
        case .easy: return "Make the song more forgiving"
        case .hard: return "Turn up the challenge"
        }
    }
    var tint: Color {
        switch self {
        case .conversion: return Color(red: 0.62, green: 0.74, blue: 1.0)
        case .easy: return Color(red: 0.55, green: 0.92, blue: 0.6)
        case .hard: return Color(red: 1.0, green: 0.5, blue: 0.5)
        }
    }
}

enum Visibility { case none, blindSpot, blindSpot2, blackout }
enum FailMode { case none, suddenDeath, perfectOnly }

enum Mod: String, Codable, CaseIterable, Identifiable {
    // Conversion
    case k1, k2, k3, k4, k5, k6, k7, k8, mirror, random
    // Easy
    case classic, halfTime, noSlides, holdOff, wideWindows
    // Hard
    case blindSpot, blindSpot2, blackout, fastForward, doubleTime, strict, suddenDeath, perfectOnly, doubleNotes

    var id: String { rawValue }

    var keyCount: Int? {
        switch self {
        case .k1: return 1
        case .k2: return 2
        case .k3: return 3
        case .k4: return 4
        case .k5: return 5
        case .k6: return 6
        case .k7: return 7
        case .k8: return 8
        default: return nil
        }
    }

    var category: ModCategory {
        switch self {
        case .k1, .k2, .k3, .k4, .k5, .k6, .k7, .k8, .mirror, .random: return .conversion
        case .classic, .halfTime, .noSlides, .holdOff, .wideWindows: return .easy
        default: return .hard
        }
    }

    /// Mods in the same group can't be combined.
    var group: String? {
        switch self {
        case .k1, .k2, .k3, .k4, .k5, .k6, .k7, .k8: return "keys"
        case .mirror, .random: return "layout"
        case .halfTime, .fastForward, .doubleTime: return "speed"
        case .noSlides, .holdOff: return "holds"
        case .blindSpot, .blindSpot2, .blackout: return "vis"
        case .suddenDeath, .perfectOnly: return "fail"
        case .strict, .wideWindows: return "windows"
        default: return nil
        }
    }

    var title: String {
        switch self {
        case .k1, .k2, .k3, .k4, .k5, .k6, .k7, .k8: return "\(keyCount!)K"
        case .mirror: return "Mirror"
        case .random: return "Random"
        case .classic: return "Classic Layout"
        case .halfTime: return "Half Time"
        case .noSlides: return "No Slides"
        case .holdOff: return "Hold Off"
        case .wideWindows: return "Wide Windows"
        case .blindSpot: return "Blind Spot"
        case .blindSpot2: return "Blind Spot 2"
        case .blackout: return "Blackout"
        case .fastForward: return "Fast Forward"
        case .doubleTime: return "Double Time"
        case .strict: return "Strict Timing"
        case .suddenDeath: return "Sudden Death"
        case .perfectOnly: return "Perfect Only"
        case .doubleNotes: return "Double Notes"
        }
    }

    var acronym: String {
        switch self {
        case .k1, .k2, .k3, .k4, .k5, .k6, .k7, .k8: return "\(keyCount!)K"
        case .mirror: return "MR"
        case .random: return "RD"
        case .classic: return "CL"
        case .halfTime: return "HT"
        case .noSlides: return "NS"
        case .holdOff: return "HO"
        case .wideWindows: return "WW"
        case .blindSpot: return "BS"
        case .blindSpot2: return "B2"
        case .blackout: return "BO"
        case .fastForward: return "FF"
        case .doubleTime: return "DT"
        case .strict: return "ST"
        case .suddenDeath: return "SD"
        case .perfectOnly: return "PF"
        case .doubleNotes: return "DN"
        }
    }

    var blurb: String {
        switch self {
        case .k1, .k2, .k3, .k4, .k5, .k6, .k7, .k8:
            return keyCount == 1 ? "One lane: a pure rhythm chart." : "Squeeze or spread the chart onto \(keyCount!) lanes."
        case .mirror: return "Flip the chart left ↔ right."
        case .random: return "Shuffle which lane is which (the same shuffle every time)."
        case .classic: return "A vertical, mania-style stage — easier to read."
        case .halfTime: return "The song plays at 0.75× speed (lower pitch)."
        case .noSlides: return "Slide notes become plain holds."
        case .holdOff: return "Every hold becomes a simple tap."
        case .wideWindows: return "Timing windows are 40% more forgiving."
        case .blindSpot: return "Notes vanish halfway to the circle."
        case .blindSpot2: return "Notes only fade in as they get close."
        case .blackout: return "Notes are invisible. Play by ear!"
        case .fastForward: return "The song plays at 1.25× speed."
        case .doubleTime: return "The song plays at 1.5× speed (higher pitch)."
        case .strict: return "Timing windows are 40% tighter."
        case .suddenDeath: return "Any miss fails the song."
        case .perfectOnly: return "Anything but PERFECT fails the song."
        case .doubleNotes: return "Lone taps get a mirrored partner note."
        }
    }

    var icon: String {
        switch self {
        case .k1, .k2, .k3, .k4, .k5, .k6, .k7, .k8: return "square.grid.3x1.below.line.grid.1x2"
        case .mirror: return "arrow.left.and.right.righttriangle.left.righttriangle.right"
        case .random: return "shuffle"
        case .classic: return "rectangle.split.3x1"
        case .halfTime: return "tortoise.fill"
        case .noSlides: return "minus.circle"
        case .holdOff: return "hand.tap"
        case .wideWindows: return "arrow.up.left.and.arrow.down.right"
        case .blindSpot: return "eye.slash"
        case .blindSpot2: return "sun.haze"
        case .blackout: return "moon.fill"
        case .fastForward: return "forward.fill"
        case .doubleTime: return "hare.fill"
        case .strict: return "scope"
        case .suddenDeath: return "heart.slash.fill"
        case .perfectOnly: return "star.fill"
        case .doubleNotes: return "square.on.square"
        }
    }

    /// Score multiplier for everything except the key-count mods (which depend on the song).
    var multiplier: Double {
        switch self {
        case .mirror: return 1.0
        case .random: return 1.05
        case .classic: return 0.9
        case .halfTime: return 0.7
        case .noSlides: return 0.85
        case .holdOff: return 0.75
        case .wideWindows: return 0.85
        case .blindSpot: return 1.12
        case .blindSpot2: return 1.10
        case .blackout: return 1.4
        case .fastForward: return 1.1
        case .doubleTime: return 1.3
        case .strict: return 1.1
        case .suddenDeath: return 1.15
        case .perfectOnly: return 1.3
        case .doubleNotes: return 1.2
        default: return 1.0
        }
    }
}

struct ModSet: Equatable {
    var mods: Set<Mod> = []

    var isEmpty: Bool { mods.isEmpty }
    func has(_ m: Mod) -> Bool { mods.contains(m) }
    var keyCount: Int? { mods.compactMap(\.keyCount).first }
    var classic: Bool { has(.classic) }

    var speed: Double {
        if has(.halfTime) { return 0.75 }
        if has(.fastForward) { return 1.25 }
        if has(.doubleTime) { return 1.5 }
        return 1
    }
    var windowScale: Double { has(.strict) ? 0.6 : (has(.wideWindows) ? 1.4 : 1) }
    var visibility: Visibility {
        if has(.blackout) { return .blackout }
        if has(.blindSpot2) { return .blindSpot2 }
        if has(.blindSpot) { return .blindSpot }
        return .none
    }
    var failMode: FailMode { has(.suddenDeath) ? .suddenDeath : (has(.perfectOnly) ? .perfectOnly : .none) }

    /// Fewer lanes than the chart was written for is easier, more lanes is harder.
    static func keyMultiplier(from orig: Int, to target: Int) -> Double {
        if target == orig { return 1 }
        if target < orig { return 0.55 + 0.45 * Double(target) / Double(max(1, orig)) }
        return 1 + 0.07 * Double(target - orig)
    }

    func multiplier(origKeys: Int) -> Double {
        var m = 1.0
        for mod in mods {
            if let k = mod.keyCount { m *= Self.keyMultiplier(from: origKeys, to: k) } else { m *= mod.multiplier }
        }
        return m
    }

    var label: String {
        Mod.allCases.filter { mods.contains($0) }.map(\.acronym).joined(separator: " ")
    }

    mutating func toggle(_ m: Mod) {
        if mods.contains(m) { mods.remove(m); return }
        if let g = m.group { mods = mods.filter { $0.group != g } }
        mods.insert(m)
    }

    var rawValues: [String] { Mod.allCases.filter { mods.contains($0) }.map(\.rawValue) }
    init(mods: Set<Mod> = []) { self.mods = mods }
    init(raw: [String]) { mods = Set(raw.compactMap(Mod.init(rawValue:))) }
}

// MARK: - Chart conversion

enum ModApplier {
    private static func stableSeed(_ s: String) -> UInt64 {
        var h: UInt64 = 1469598103934665603
        for u in s.unicodeScalars { h = (h ^ UInt64(u.value)) &* 1099511628211 }
        return h
    }

    /// Returns the song with the chosen chart rewritten for the active mods (key count, mirror, slides…).
    static func apply(song: Song, chartIndex: Int, mods: ModSet) -> Song {
        guard !mods.isEmpty, !song.charts.isEmpty else { return song }
        let ci = min(chartIndex, song.charts.count - 1)
        var chart = song.charts[ci]
        let orig = song.keyCount
        let N = mods.keyCount ?? orig
        var rng = SplitMix64(seed: stableSeed(song.id + chart.name))

        // Lane map: original lane -> new lane
        var map = Array(0..<orig)
        if N != orig {
            for l in 0..<orig {
                if N < orig { map[l] = min(N - 1, l * N / orig) }
                else if orig == 1 { map[l] = N / 2 }
                else { map[l] = Int((Double(l) * Double(N - 1) / Double(orig - 1)).rounded()) }
            }
        }
        if mods.has(.random) {
            var perm = Array(0..<N)
            for i in stride(from: N - 1, to: 0, by: -1) { perm.swapAt(i, rng.int(0...i)) }
            for l in 0..<orig { map[l] = perm[map[l]] }
        }
        if mods.has(.mirror) { for l in 0..<orig { map[l] = N - 1 - map[l] } }

        let upscale = N > orig
        var converted: [Note] = []
        for n in chart.notes {
            var lane = map[min(max(n.lane, 0), orig - 1)]
            if upscale && !n.isHold {
                lane = min(N - 1, max(0, lane + rng.pick([-1, 0, 0, 1])))
            }
            var out = Note(time: n.time, lane: lane, duration: n.duration)
            if mods.has(.holdOff) { out.duration = 0 }
            if out.isHold && !mods.has(.noSlides) && !mods.has(.holdOff) {
                var cur = lane
                var l = n.lane
                for s in n.slides {
                    l = min(max(l + s.dir, 0), orig - 1)
                    let target = map[l]
                    if target == cur { continue }
                    if abs(target - cur) == 1 {
                        out.slides.append(SlideEvent(time: s.time, dir: target - cur))
                        cur = target
                    } else { break }
                }
            }
            converted.append(out)
        }
        converted.sort { ($0.time, $0.lane) < ($1.time, $1.lane) }

        // Resolve overlaps created by merging lanes (earliest note wins).
        var busy = [[(from: Double, to: Double)]](repeating: [], count: N)
        func free(_ lane: Int, _ from: Double, _ to: Double, pad: Double) -> Bool {
            !busy[lane].contains { $0.from < to + pad && $0.to > from - pad }
        }
        let pad = N <= 2 ? 0.12 : 0.09
        var kept: [Note] = []
        for n in converted {
            let segs = n.segments(count: N)
            if segs.contains(where: { !free($0.lane, $0.from, $0.to, pad: pad) }) { continue }
            for s in segs { busy[s.lane].append((s.from, s.to)) }
            kept.append(n)
        }

        if mods.has(.doubleNotes) && N >= 2 {
            let times = kept.map(\.time)
            for n in kept where !n.isHold {
                let near = times.filter { abs($0 - n.time) < 0.1 }.count
                guard near == 1, rng.chance(0.7) else { continue }
                let m = N - 1 - n.lane
                if m != n.lane, free(m, n.time, n.time, pad: pad) {
                    busy[m].append((n.time, n.time))
                    kept.append(Note(time: n.time, lane: m))
                }
            }
        }

        kept.sort { ($0.time, $0.lane) < ($1.time, $1.lane) }
        chart.notes = kept
        var out = song
        out.keyCount = N
        out.charts[ci] = chart
        return out
    }
}
