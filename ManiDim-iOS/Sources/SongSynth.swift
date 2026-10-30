import Foundation
import AVFoundation

// MARK: - Arrangement description

enum SectionKind { case intro, verse, chorus, breakdown, outro }
enum DrumStyle { case fourOnFloor, breakbeat, dnb, lofi }
enum LeadVoice { case saw, pluck, soft }
enum DrumKind { case kick, snare, clap, hat, openHat }

struct Arrangement {
    var key: String
    var title: String
    var artist: String
    var bpm: Double
    var keyCount: Int
    var rootMidi: Int
    var minor: Bool
    var progression: [Int]
    var blocks: [(SectionKind, Int)]
    var drums: DrumStyle
    var voice: LeadVoice
    var seed: UInt64
    var hue: Double
    var tutorial = false
    var levels: [Int] = [3, 6, 9]
}

struct MelodyNote {
    var start: Double
    var dur: Double
    var lane: Int
    var midi: Int
    var section: SectionKind
    var bar: Int
}
struct DrumHit { var t: Double; var kind: DrumKind; var vel: Double; var section: SectionKind }
struct BassNote { var t: Double; var dur: Double; var midi: Int }
struct PadChord { var t: Double; var dur: Double; var midis: [Int] }

struct Composition {
    var melody: [MelodyNote] = []
    var drums: [DrumHit] = []
    var bass: [BassNote] = []
    var pads: [PadChord] = []
    var sections: [(kind: SectionKind, start: Double, bars: Int)] = []
    var duration: Double = 0
}

// MARK: - Composition

enum Composer {
    static func compose(_ a: Arrangement) -> Composition {
        var rng = SplitMix64(seed: a.seed)
        let spb = 60.0 / a.bpm
        let s16 = spb / 4
        let barLen = spb * 4
        let scale = a.minor ? [0, 2, 3, 5, 7, 8, 10] : [0, 2, 4, 5, 7, 9, 11]
        func semis(_ d: Int) -> Int { scale[d % 7] + 12 * (d / 7) }
        let laneDeg = [0, 2, 4, 6, 7, 9, 11, 13]
        let n = a.keyCount
        var c = Composition()

        var bar = 0
        var lane = n / 2
        var prevLanes: [Int] = []
        var prevTemplate = -1
        var prevKind: SectionKind = .intro

        for (kind, nBars) in a.blocks {
            c.sections.append((kind: kind, start: Double(bar) * barLen, bars: nBars))
            for i in 0..<nBars {
                let r = a.progression[bar % a.progression.count]
                let t0 = Double(bar) * barLen
                let last = i == nBars - 1

                // ---- drums
                func hit(_ k: DrumKind, _ step: Double, _ vel: Double) {
                    c.drums.append(DrumHit(t: t0 + step * s16, kind: k, vel: vel, section: kind))
                }
                let p = drumPattern(a.drums, kind, i, nBars)
                for s in p.kick { hit(.kick, s, 0.95) }
                for s in p.snare { hit(.snare, s, 0.8) }
                for s in p.clap { hit(.clap, s, 0.7) }
                for (s, v) in p.hat { hit(.hat, s, v) }
                for s in p.open { hit(.openHat, s, 0.5) }
                if last && (kind == .verse || kind == .chorus) {
                    c.drums.removeAll { $0.kind == .snare && abs($0.t - (t0 + 12 * s16)) < 0.001 }
                    for (k, s) in [12.0, 13, 14, 15].enumerated() { hit(.snare, s, 0.45 + 0.15 * Double(k)) }
                }

                // ---- bass
                let bassPat = bassPattern(a.drums, kind, i, nBars)
                for (s, len, off, oct) in bassPat {
                    let midi = a.rootMidi - 12 + semis(r + off) + 12 * oct
                    c.bass.append(BassNote(t: t0 + Double(s) * s16, dur: Double(len) * s16 * 0.92, midi: midi))
                }

                // ---- pad
                if !(kind == .intro && i < nBars / 2 && nBars > 2) {
                    let chord = [r, r + 2, r + 4, r + 7].map { a.rootMidi + semis($0) }
                    c.pads.append(PadChord(t: t0, dur: barLen, midis: chord))
                }

                // ---- melody
                if kind != .intro {
                    let tpls = templates(for: kind)
                    var ti = rng.int(0...(tpls.count - 1))
                    var lanes: [Int] = []
                    let reuse = (i % 2 == 1) && !prevLanes.isEmpty && kind == prevKind && prevTemplate >= 0 && rng.chance(0.7)
                    if reuse {
                        ti = prevTemplate
                        lanes = prevLanes
                    } else {
                        var l = lane
                        for _ in tpls[ti] {
                            let steps = kind == .breakdown ? [-1, 1, 1, -1, 1] : [-2, -1, -1, 0, 1, 1, 2]
                            let s = rng.pick(steps)
                            var nl = clamp(l + s, 0, n - 1)
                            if nl == l && lanes.last == l { nl = clamp(l + (rng.chance(0.5) ? 1 : -1), 0, n - 1) }
                            lanes.append(nl)
                            l = nl
                        }
                        lane = l
                    }
                    for (k, tpl) in tpls[ti].enumerated() {
                        let ln = lanes[k]
                        let midi = a.rootMidi + 12 + semis(r + laneDeg[ln])
                        c.melody.append(MelodyNote(start: t0 + Double(tpl.0) * s16, dur: Double(tpl.1) * s16,
                                                   lane: ln, midi: midi, section: kind, bar: bar))
                    }
                    prevLanes = lanes
                    prevTemplate = ti
                }
                prevKind = kind
                bar += 1
            }
        }
        c.duration = Double(bar) * barLen + 1.5
        return c
    }

    static func templates(for kind: SectionKind) -> [[(Int, Int)]] {
        switch kind {
        case .verse:
            return [
                [(0, 4), (4, 4), (8, 4), (12, 4)],
                [(0, 6), (6, 2), (8, 4), (12, 4)],
                [(0, 4), (4, 2), (6, 2), (8, 4), (12, 2), (14, 2)],
                [(0, 3), (3, 3), (6, 2), (8, 4), (12, 4)],
            ]
        case .chorus:
            return [
                [(0, 2), (2, 2), (4, 2), (6, 2), (8, 2), (10, 2), (12, 2), (14, 2)],
                [(0, 3), (3, 3), (6, 2), (8, 3), (11, 3), (14, 2)],
                [(0, 2), (2, 2), (4, 4), (8, 2), (10, 2), (12, 2), (14, 2)],
                [(0, 4), (4, 2), (6, 2), (8, 2), (10, 2), (12, 4)],
            ]
        case .breakdown:
            return [
                [(0, 8), (8, 4), (12, 4)],
                [(0, 12), (12, 4)],
                [(0, 6), (6, 6), (12, 4)],
                [(0, 8), (8, 8)],
            ]
        case .outro:
            return [[(0, 16)]]
        case .intro:
            return [[(0, 16)]]
        }
    }

    typealias DrumPattern = (kick: [Double], snare: [Double], clap: [Double], hat: [(Double, Double)], open: [Double])

    static func drumPattern(_ style: DrumStyle, _ kind: SectionKind, _ i: Int, _ n: Int) -> DrumPattern {
        let all8: [Double] = [0, 2, 4, 6, 8, 10, 12, 14]
        let off8: [Double] = [2, 6, 10, 14]
        let s16: [Double] = [1, 3, 5, 7, 9, 11, 13, 15]
        switch style {
        case .fourOnFloor:
            switch kind {
            case .intro: return ([0, 4, 8, 12], [], [], i >= n / 2 ? off8.map { ($0, 0.5) } : [], [])
            case .verse: return ([0, 4, 8, 12], [], [4, 12], off8.map { ($0, 0.55) }, [])
            case .chorus: return ([0, 4, 8, 12], [], [4, 12], off8.map { ($0, 0.6) } + s16.map { ($0, 0.22) }, [14])
            case .breakdown: return ([], [], [], [0, 4, 8, 12].map { ($0, 0.28) }, [])
            case .outro: return ([0, 8], [], [], [], [])
            }
        case .breakbeat:
            switch kind {
            case .intro: return ([0, 10], [], [], i >= n / 2 ? all8.map { ($0, 0.35) } : [], [])
            case .verse: return ([0, 10], [4, 12], [], all8.map { ($0, 0.45) }, [])
            case .chorus: return ([0, 6, 10], [4, 12], [], all8.map { ($0, 0.5) } + s16.map { ($0, 0.18) }, [14])
            case .breakdown: return ([], [], [], [0, 4, 8, 12].map { ($0, 0.25) }, [])
            case .outro: return ([0], [], [], [], [])
            }
        case .dnb:
            switch kind {
            case .intro: return ([0], [], [], i >= n / 2 ? all8.map { ($0, 0.3) } : [], [])
            case .verse: return ([0, 10], [4, 12], [], all8.map { ($0, 0.4) }, [])
            case .chorus: return ([0, 10], [4, 12, 7, 15].filter { $0 == 4 || $0 == 12 }, [7], all8.map { ($0, 0.45) } + s16.map { ($0, 0.2) }, [14])
            case .breakdown: return ([], [], [], [0, 4, 8, 12].map { ($0, 0.25) }, [])
            case .outro: return ([0], [], [], [], [])
            }
        case .lofi:
            let swingHat: [(Double, Double)] = all8.map { ($0.truncatingRemainder(dividingBy: 4) == 2 ? $0 + 0.5 : $0, $0.truncatingRemainder(dividingBy: 4) == 0 ? 0.4 : 0.25) }
            switch kind {
            case .intro: return ([], [], [], i >= n / 2 ? swingHat : [], [])
            case .verse: return ([0, 7, 10], [8], [], swingHat, [])
            case .chorus: return ([0, 7, 10], [4, 12], [], swingHat + s16.map { ($0 + 0.5, 0.12) }, [])
            case .breakdown: return ([0], [], [], [], [])
            case .outro: return ([0], [], [], [], [])
            }
        }
    }

    /// (step, length in 16ths, degree offset, octave)
    static func bassPattern(_ style: DrumStyle, _ kind: SectionKind, _ i: Int, _ n: Int) -> [(Int, Int, Int, Int)] {
        switch kind {
        case .intro: return i >= n / 2 || n <= 2 ? [(0, 16, 0, 0)] : []
        case .breakdown, .outro: return [(0, 16, 0, 0)]
        default: break
        }
        switch style {
        case .fourOnFloor: return [(2, 2, 0, 0), (6, 2, 0, 0), (10, 2, 0, 0), (14, 2, 0, 1)]
        case .dnb: return [(0, 3, 0, 0), (3, 3, 0, 0), (6, 2, 0, 0), (10, 3, 4, 0), (13, 3, 0, 0)]
        case .breakbeat: return [(0, 6, 0, 0), (6, 2, 0, 0), (8, 4, 0, 0), (12, 2, 4, 0), (14, 2, 0, 0)]
        case .lofi: return [(0, 7, 0, 0), (8, 5, 0, 0), (14, 2, 4, 0)]
        }
    }
}

// MARK: - Synth renderer

final class SynthMixer {
    let sr = 44100.0
    let n: Int
    var dryL: [Float], dryR: [Float], leadL: [Float], leadR: [Float]
    var noise: UInt32 = 0x9E3779B9

    init(seconds: Double) {
        n = Int(seconds * 44100)
        dryL = [Float](repeating: 0, count: n)
        dryR = dryL
        leadL = dryL
        leadR = dryL
    }

    @inline(__always) func rnd() -> Double {
        noise ^= noise << 13; noise ^= noise >> 17; noise ^= noise << 5
        return Double(noise) / Double(UInt32.max) * 2 - 1
    }

    @inline(__always) func blep(_ t: Double, _ dt: Double) -> Double {
        if t < dt { let x = t / dt; return x + x - x * x - 1 }
        if t > 1 - dt { let x = (t - 1) / dt; return x * x + x + x + 1 }
        return 0
    }
    @inline(__always) func saw(_ p: Double, _ dt: Double) -> Double { 2 * p - 1 - blep(p, dt) }
    func hz(_ midi: Int) -> Double { 440 * pow(2, Double(midi - 69) / 12) }

    func addDry(_ i: Int, _ v: Double, pan: Double = 0.5) {
        guard i < n, i >= 0 else { return }
        dryL[i] += Float(v * cos(pan * .pi / 2) * 1.414)
        dryR[i] += Float(v * sin(pan * .pi / 2) * 1.414)
    }

    func kick(_ t: Double, _ vel: Double) {
        let start = Int(t * sr), len = Int(0.45 * sr)
        var phase = 0.0
        for i in 0..<len {
            let tt = Double(i) / sr
            phase += 2 * .pi * (46 + 120 * exp(-tt * 30)) / sr
            var s = sin(phase) * exp(-tt * 6.5) * min(1, tt * 600)
            s += rnd() * exp(-tt * 350) * 0.2
            addDry(start + i, s * vel * 0.95)
        }
    }

    func snare(_ t: Double, _ vel: Double, clap: Bool) {
        let start = Int(t * sr), len = Int(0.28 * sr)
        var hp = 0.0, prev = 0.0
        for i in 0..<len {
            let tt = Double(i) / sr
            let nz = rnd()
            hp = 0.7 * (hp + nz - prev); prev = nz
            var s: Double
            if clap {
                let burst = (tt < 0.012 || (tt > 0.02 && tt < 0.032) || (tt > 0.04 && tt < 0.052)) ? 1.0 : 0
                s = hp * (burst * 0.9 + exp(-tt * 20) * 0.5) * 0.6
            } else {
                s = hp * exp(-tt * 16) * 0.65 + sin(2 * .pi * 190 * tt) * exp(-tt * 24) * 0.45
            }
            addDry(start + i, s * vel * 0.8, pan: clap ? 0.55 : 0.5)
        }
    }

    func hat(_ t: Double, _ vel: Double, open: Bool) {
        let start = Int(t * sr), len = Int((open ? 0.28 : 0.07) * sr)
        var prev = 0.0, hp = 0.0
        for i in 0..<len {
            let tt = Double(i) / sr
            let nz = rnd()
            hp = 0.85 * (hp + nz - prev); prev = nz
            addDry(start + i, hp * exp(-tt * (open ? 14 : 75)) * vel * 0.3, pan: 0.62)
        }
    }

    func bass(_ t: Double, _ dur: Double, _ midi: Int, _ drums: DrumStyle) {
        let f = hz(midi)
        let start = Int(t * sr), len = Int((dur + 0.12) * sr)
        var p = 0.0, sp = 0.0, lp = 0.0
        let dt = f / sr
        for i in 0..<len {
            let tt = Double(i) / sr
            p += dt; if p >= 1 { p -= 1 }
            sp += 2 * .pi * f / sr
            let cutoff = 260 + 900 * exp(-tt * 9)
            let a = 1 - exp(-2 * .pi * cutoff / sr)
            lp += a * (saw(p, dt) * 0.6 - lp)
            var env = min(1, tt / 0.004) * (0.65 + 0.35 * exp(-tt * 4))
            if tt > dur { env *= exp(-(tt - dur) * 40) }
            let s = (lp + sin(sp) * 0.55) * env
            addDry(start + i, s * 0.55)
        }
    }

    func lead(_ t: Double, _ dur: Double, _ midi: Int, _ voice: LeadVoice, pan: Double) {
        let f = hz(midi)
        let rel = voice == .pluck ? 0.2 : 0.28
        let start = Int(t * sr), len = Int((dur + rel) * sr)
        let dt1 = f * 1.0035 / sr, dt2 = f * 0.9965 / sr
        var p1 = 0.0, p2 = 0.0, lp = 0.0, ph = 0.0
        for i in 0..<len {
            let tt = Double(i) / sr
            p1 += dt1; if p1 >= 1 { p1 -= 1 }
            p2 += dt2; if p2 >= 1 { p2 -= 1 }
            var s: Double
            var env: Double
            switch voice {
            case .saw:
                let cutoff = 900 + 3600 * exp(-tt * 5)
                let a = 1 - exp(-2 * .pi * cutoff / sr)
                lp += a * ((saw(p1, dt1) + saw(p2, dt2)) * 0.5 - lp)
                s = lp
                env = min(1, tt / 0.006) * (0.7 + 0.3 * exp(-tt * 6))
            case .pluck:
                ph += 2 * .pi * f / sr
                s = sin(ph) + 0.4 * sin(2 * ph) * exp(-tt * 9) + 0.2 * sin(3 * ph) * exp(-tt * 14)
                env = min(1, tt / 0.002) * exp(-tt * 5.5)
            case .soft:
                ph += 2 * .pi * f * (1 + 0.0025 * sin(2 * .pi * 5.2 * tt)) / sr
                s = sin(ph) + 0.25 * sin(2 * ph) + 0.08 * sin(3 * ph)
                env = min(1, tt / 0.012) * (0.75 + 0.25 * exp(-tt * 3))
            }
            if tt > dur { env *= exp(-(tt - dur) * (voice == .pluck ? 25 : 14)) }
            let v = s * env * 0.3
            let idx = start + i
            guard idx < n else { break }
            leadL[idx] += Float(v * cos(pan * .pi / 2) * 1.414)
            leadR[idx] += Float(v * sin(pan * .pi / 2) * 1.414)
        }
    }

    func pad(_ t: Double, _ dur: Double, _ midis: [Int], level: Double) {
        let start = Int(t * sr), len = Int((dur + 0.7) * sr)
        for (k, m) in midis.enumerated() {
            let f = hz(m)
            let dt1 = f * 1.004 / sr, dt2 = f * 0.996 / sr
            var p1 = Double(k) * 0.13, p2 = Double(k) * 0.29, lp = 0.0
            let pan = 0.25 + 0.5 * Double(k % 2) + 0.05 * Double(k)
            let a = 1 - exp(-2 * .pi * 1100 / sr)
            for i in 0..<len {
                let tt = Double(i) / sr
                p1 += dt1; if p1 >= 1 { p1 -= 1 }
                p2 += dt2; if p2 >= 1 { p2 -= 1 }
                lp += a * ((saw(p1, dt1) + saw(p2, dt2)) * 0.5 - lp)
                var env = min(1, tt / 0.35)
                if tt > dur { env *= exp(-(tt - dur) * 6) }
                addDry(start + i, lp * env * level * 0.5, pan: min(1, pan))
            }
        }
    }

    /// Ping-pong delay of the lead bus, then mix everything and normalize.
    func finish(delaySeconds: Double, fadeSeconds: Double = 0) -> ([Float], [Float]) {
        let d = max(1, Int(delaySeconds * sr))
        let fb: Float = 0.38
        if n > d {
            for i in d..<n {
                leadL[i] += leadR[i - d] * fb
                leadR[i] += leadL[i - d] * fb
            }
        }
        var peak: Float = 0.0001
        for i in 0..<n {
            dryL[i] += leadL[i] * 0.9
            dryR[i] += leadR[i] * 0.9
            peak = max(peak, abs(dryL[i]), abs(dryR[i]))
        }
        let g = 0.88 / peak
        let fadeN = Int(fadeSeconds * sr)
        for i in 0..<n {
            var f: Float = 1
            if fadeN > 0, i > n - fadeN {
                let p = Float(i - (n - fadeN)) / Float(fadeN)
                f = 0.5 + 0.5 * cosf(p * .pi)
            }
            dryL[i] = tanhf(dryL[i] * g * 1.1) * f
            dryR[i] = tanhf(dryR[i] * g * 1.1) * f
        }
        return (dryL, dryR)
    }
}

enum SongSynth {
    static func render(_ a: Arrangement, comp: Composition) -> ([Float], [Float]) {
        let m = SynthMixer(seconds: comp.duration + 1.0)
        for d in comp.drums {
            switch d.kind {
            case .kick: m.kick(d.t, d.vel)
            case .snare: m.snare(d.t, d.vel, clap: false)
            case .clap: m.snare(d.t, d.vel, clap: true)
            case .hat: m.hat(d.t, d.vel, open: false)
            case .openHat: m.hat(d.t, d.vel, open: true)
            }
        }
        for b in comp.bass { m.bass(b.t, b.dur, b.midi, a.drums) }
        let padLevel = a.voice == .soft ? 0.5 : 0.32
        for p in comp.pads { m.pad(p.t, p.dur, p.midis, level: padLevel) }
        for (i, n) in comp.melody.enumerated() {
            m.lead(n.start, n.dur * 0.95, n.midi, a.voice, pan: 0.38 + 0.24 * Double(i % 2))
        }
        return m.finish(delaySeconds: 60.0 / a.bpm * 0.75, fadeSeconds: 3.0)
    }

    static func writeWAV(left: [Float], right: [Float], to url: URL) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        let fmt = file.processingFormat
        let chunk = 1 << 16
        var pos = 0
        while pos < left.count {
            let cnt = min(chunk, left.count - pos)
            let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(cnt))!
            buf.frameLength = AVAudioFrameCount(cnt)
            let l = buf.floatChannelData![0], r = buf.floatChannelData![1]
            for i in 0..<cnt { l[i] = left[pos + i]; r[i] = right[pos + i] }
            try file.write(from: buf)
            pos += cnt
        }
    }

    /// Render a metronome/drum loop so blank songs have something to play against.
    static func renderBlank(bpm: Double, bars: Int, to url: URL) throws {
        let spb = 60.0 / bpm
        let total = Double(bars) * spb * 4 + 1
        let m = SynthMixer(seconds: total + 1)
        for b in 0..<(bars * 4) {
            let t = Double(b) * spb
            if b % 4 == 0 { m.kick(t, 0.8) }
            if b % 4 == 2 { m.kick(t, 0.6) }
            if b % 4 == 1 || b % 4 == 3 { m.snare(t, 0.5, clap: false) }
            m.hat(t + spb / 2, 0.45, open: false)
            m.hat(t, b % 4 == 0 ? 0.7 : 0.4, open: false)
        }
        let (l, r) = m.finish(delaySeconds: spb)
        try writeWAV(left: l, right: r, to: url)
    }
}

// MARK: - Chart generation from a composition

enum Diff: Int, CaseIterable {
    case easy, normal, hard
    var name: String { ["Easy", "Normal", "Hard"][rawValue] }
}

enum ChartBuilder {
    static func build(_ comp: Composition, a: Arrangement, diff: Diff) -> Chart {
        var rng = SplitMix64(seed: a.seed &+ UInt64(diff.rawValue) &* 7919)
        let n = a.keyCount
        let spb = 60.0 / a.bpm
        let s16 = spb / 4
        let minGap = [0.30, 0.17, 0.095][diff.rawValue]
        let holdMin = [0.80, 0.65, 0.55][diff.rawValue]
        let maxChain = [0, 1, 2][diff.rawValue]
        var notes: [Note] = []
        var busy: [(lane: Int, from: Double, to: Double)] = []
        var lastTime = -10.0

        func free(_ lane: Int, _ from: Double, _ to: Double, pad: Double = 0.1) -> Bool {
            !busy.contains { $0.lane == lane && $0.from < to + pad && $0.to > from - pad }
        }
        func add(_ note: Note) -> Bool {
            let segs = note.segments(count: n)
            for s in segs where !free(s.lane, s.from, s.to) { return false }
            notes.append(note)
            busy.append(contentsOf: segs.map { (lane: $0.lane, from: $0.from, to: $0.to) })
            return true
        }

        let mel = comp.melody
        var i = 0
        while i < mel.count {
            let m = mel[i]
            i += 1
            if diff == .easy {
                let idx = Int((m.start / s16).rounded())
                if idx % 4 != 0 && m.dur < holdMin { continue }
            }
            if m.start - lastTime < minGap { continue }
            var note = Note(time: m.start, lane: m.lane)
            if m.dur >= holdMin {
                var endT = m.start + m.dur - 0.06
                var curEnd = m.start + m.dur
                var curLane = m.lane
                var chain = 0
                while chain < maxChain && i < mel.count {
                    let nx = mel[i]
                    if abs(nx.start - curEnd) < 0.02 && abs(nx.lane - curLane) == 1 && rng.chance([0.0, 0.6, 0.5][diff.rawValue]) {
                        note.slides.append(SlideEvent(time: nx.start, dir: nx.lane - curLane))
                        curLane = nx.lane
                        endT = nx.start + nx.dur - 0.06
                        curEnd = nx.start + nx.dur
                        i += 1
                        chain += 1
                    } else { break }
                }
                note.duration = endT - m.start
            }
            if add(note) { lastTime = m.start }
        }

        // Drum accents for the harder charts.
        if diff != .easy {
            var alt = 0
            for d in comp.drums.sorted(by: { $0.t < $1.t }) {
                let want: Bool
                switch (diff, d.kind, d.section) {
                case (.normal, .kick, .chorus): want = abs((d.t / (spb * 4)).truncatingRemainder(dividingBy: 1)) < 0.01
                case (.hard, .kick, .chorus), (.hard, .snare, .chorus), (.hard, .clap, .chorus): want = true
                case (.hard, .snare, .verse), (.hard, .kick, .verse): want = rng.chance(0.4)
                default: want = false
                }
                guard want, d.t - lastTime >= 0.09 else { continue }
                if notes.contains(where: { abs($0.time - d.t) < 0.09 }) { continue }
                let lane = (alt % 2 == 0) ? 0 : n - 1
                alt += 1
                if add(Note(time: d.t, lane: lane)) { lastTime = max(lastTime, d.t) }
            }
            if diff == .hard {
                // Mirror the downbeat note of chorus bars for a "chord" feel.
                let barLen = spb * 4
                for nt in notes where !nt.isHold && nt.slides.isEmpty {
                    let pos = (nt.time / barLen).truncatingRemainder(dividingBy: 1)
                    if pos < 0.01 || pos > 0.99, let m = mel.first(where: { abs($0.start - nt.time) < 0.001 }), m.section == .chorus {
                        let mirror = n - 1 - nt.lane
                        if mirror != nt.lane { _ = add(Note(time: nt.time, lane: mirror)) }
                    }
                }
            }
        }

        var chart = Chart(name: diff.name, level: 1, notes: notes)
        chart.events = events(comp, a: a, diff: diff)
        chart.sortNotes()
        let span = max(1, (chart.notes.last?.endTime ?? 1) - (chart.notes.first?.time ?? 0))
        let nps = Double(chart.objectCount) / span
        chart.level = clamp(Int((nps * 2.1).rounded()), 1, 15)
        return chart
    }

    /// Stage effects tied to the song's structure: bigger moments get bigger effects.
    static func events(_ comp: Composition, a: Arrangement, diff: Diff) -> [ChartEvent] {
        var ev: [ChartEvent] = []
        let barLen = 60.0 / a.bpm * 4
        let lastChorus = comp.sections.lastIndex { $0.kind == .chorus }
        func add(_ t: Double, _ k: EventKind, hue: Double? = nil, dur: Double = 0) {
            ev.append(ChartEvent(time: t, kind: k, hue: hue ?? a.hue, duration: dur))
        }
        for (i, s) in comp.sections.enumerated() {
            switch s.kind {
            case .chorus:
                add(s.start, .flash, hue: a.hue)
                add(s.start, .sparkles)
                if diff != .easy { add(s.start, .pulse) }
                if diff == .hard { add(s.start, .shake) }
                var bar = 4
                while bar < s.bars {
                    let t = s.start + Double(bar) * barLen
                    add(t, diff == .hard && bar % 8 == 4 ? .fireworks : .sparkles, hue: a.hue + 0.3)
                    if diff != .easy { add(t, .pulse, hue: a.hue + 0.1) }
                    bar += 4
                }
                if diff == .hard && i == lastChorus { add(s.start + barLen, .lasers, hue: a.hue, dur: Double(s.bars - 2) * barLen) }
            case .breakdown:
                add(s.start, .tint, hue: a.hue, dur: Double(s.bars) * barLen)
                add(s.start + Double(s.bars) * barLen - 0.01, .shake)
            case .outro:
                add(s.start, .sparkles, hue: a.hue + 0.5)
            default: break
            }
        }
        return ev.sorted { $0.time < $1.time }
    }

    static func tutorial(_ a: Arrangement) -> Chart {
        let spb = 60.0 / a.bpm
        let bar = spb * 4
        var notes: [Note] = []
        func tap(_ b: Int, _ beat: Double, _ lane: Int) { notes.append(Note(time: Double(b) * bar + beat * spb, lane: lane)) }
        func hold(_ b: Int, _ beat: Double, _ lane: Int, _ len: Double, slides: [(Double, Int)] = []) {
            var n = Note(time: Double(b) * bar + beat * spb, lane: lane, duration: len * spb - 0.08)
            n.slides = slides.map { SlideEvent(time: Double(b) * bar + $0.0 * spb, dir: $0.1) }
            notes.append(n)
        }
        // Taps
        for (k, l) in [0, 1, 2, 3].enumerated() { tap(2, Double(k), l) }
        for (k, l) in [3, 2, 1, 0].enumerated() { tap(3, Double(k), l) }
        for (k, l) in [0, 1, 2, 3, 0, 1, 2, 3].enumerated() { tap(4, Double(k) / 2, l) }
        for (k, l) in [0, 0, 3, 3, 1, 1, 2, 2].enumerated() { tap(5, Double(k) / 2, l) }
        // Holds
        hold(6, 0, 1, 2); tap(6, 3, 2)
        hold(7, 0, 2, 2); tap(7, 3, 1)
        hold(8, 0, 0, 3); tap(8, 1, 3); tap(8, 2, 3)
        for (k, l) in [3, 0, 2, 1].enumerated() { tap(9, Double(k), l) }
        // Slides — each one is followed by a gap, so a lesson never stops the song mid-hold.
        hold(10, 0, 1, 3, slides: [(1.5, 1)])
        tap(11, 0, 2); tap(11, 1, 3)
        hold(12, 0, 2, 3, slides: [(1.5, -1)])
        hold(13, 0, 0, 2, slides: [(0.7, 1), (1.3, 1)])
        // Mix
        var rng = SplitMix64(seed: 42)
        for b in 14..<22 {
            if b % 4 == 1 {
                let l = rng.int(0...2)
                hold(b, 0, l, 4, slides: [(2, rng.chance(0.5) ? 1 : -1)].filter { _ in true })
                if let last = notes.last, last.lane + (last.slides.first?.dir ?? 0) < 0 || last.lane + (last.slides.first?.dir ?? 0) > 3 {
                    notes[notes.count - 1].slides = [SlideEvent(time: last.slides[0].time, dir: -last.slides[0].dir)]
                }
            } else {
                var prev = -1
                for k in 0..<8 {
                    if k % 2 == 1 && b % 2 == 0 { continue }
                    var l = rng.int(0...3)
                    if l == prev { l = (l + 1) % 4 }
                    prev = l
                    tap(b, Double(k) / 2, l)
                }
            }
        }
        var chart = Chart(name: "Tutorial", level: 2, notes: notes)
        chart.sortNotes()
        let lead = 0.9            // how long before the note arrives the song comes to a stop
        let slideLead = 0.55
        chart.lessons = [
            Lesson(time: 2 * bar - lead, title: "Tap notes",
                   text: "Notes fly out of the fan toward the big circle. When one touches the circle, tap the pad for its lane at the bottom of the screen. Lanes go left to right, and so do the pads.\n\nThe closer to the middle of the circle you press, the better the rating.",
                   key: "space"),
            Lesson(time: 6 * bar - lead, title: "Hold notes",
                   text: "A note with a tail is a hold. Touch its pad as the head touches the circle and KEEP your finger down until the round tail cap touches the circle, then let go.\n\nLetting go early breaks your combo. Your other fingers are free to tap other lanes while you hold.",
                   key: "space"),
            Lesson(time: 10 * bar - lead, title: "Slide notes",
                   text: "A hold with white arrows on it is a slide. Hit it like any hold and keep your finger on the SAME pad that started it — never let go of it.\n\nWhen the arrow touches the circle, tap the ▶ SLIDE pad (arrow points right) or the ◀ SLIDE pad (arrow points left) with another finger. The note slides over to the next lane.",
                   key: "slideRight"),
            Lesson(time: 12 * bar - lead, title: "More slides",
                   text: "Slides can point either way, and some have several arrows in a row. Keep your first finger down the whole time and tap a SLIDE pad for every arrow.\n\nThe next slide points left: ◀. The one after it has two arrows to the right.",
                   key: "slideLeft"),
            Lesson(time: 14 * bar - 0.35, title: "You're ready!",
                   text: "Now a mix of everything: taps, holds and slides.\n\nTap the pause button (top-right) any time. Good luck!",
                   key: "space"),
        ]
        chart.events = [
            ChartEvent(time: 14 * bar, kind: .flash, hue: a.hue),
            ChartEvent(time: 14 * bar, kind: .sparkles),
            ChartEvent(time: 18 * bar, kind: .pulse, hue: a.hue),
            ChartEvent(time: 18 * bar, kind: .fireworks, hue: a.hue),
            ChartEvent(time: 22 * bar, kind: .sparkles, hue: a.hue + 0.4),
        ]
        return chart
    }
}

// MARK: - Built-in songs

enum BuiltinSongs {
    static let arrangements: [Arrangement] = [
        Arrangement(key: "first-steps", title: "First Steps", artist: "ManiDim", bpm: 100, keyCount: 4,
                    rootMidi: 55, minor: false, progression: [0, 3, 4, 0],
                    blocks: [(.intro, 2), (.verse, 4), (.chorus, 4), (.verse, 4), (.breakdown, 4), (.chorus, 4), (.outro, 2)],
                    drums: .breakbeat, voice: .soft, seed: 11, hue: 0.33, tutorial: true),
        Arrangement(key: "rainy-window", title: "Rainy Window", artist: "Mori Kite", bpm: 78, keyCount: 4,
                    rootMidi: 48, minor: true, progression: [0, 3, 5, 4],
                    blocks: [(.intro, 2), (.verse, 8), (.chorus, 8), (.verse, 8), (.breakdown, 4), (.chorus, 8), (.outro, 2)],
                    drums: .lofi, voice: .soft, seed: 4242, hue: 0.58),
        Arrangement(key: "paper-lanterns", title: "Paper Lanterns", artist: "Mori Kite", bpm: 88, keyCount: 4,
                    rootMidi: 60, minor: false, progression: [0, 4, 5, 3],
                    blocks: [(.intro, 2), (.verse, 8), (.chorus, 8), (.verse, 8), (.breakdown, 4), (.chorus, 8), (.outro, 2)],
                    drums: .lofi, voice: .pluck, seed: 2024, hue: 0.08, levels: [2, 4, 7]),
        Arrangement(key: "turbo-kitten", title: "Turbo Kitten", artist: "Pixel Paws", bpm: 160, keyCount: 4,
                    rootMidi: 55, minor: false, progression: [0, 5, 3, 4],
                    blocks: [(.intro, 2), (.verse, 8), (.chorus, 8), (.verse, 8), (.chorus, 8), (.breakdown, 4), (.chorus, 8), (.outro, 4)],
                    drums: .breakbeat, voice: .pluck, seed: 31337, hue: 0.15),
        Arrangement(key: "neon-drive", title: "Neon Drive", artist: "Vector Hearts", bpm: 128, keyCount: 4,
                    rootMidi: 57, minor: true, progression: [0, 5, 2, 6],
                    blocks: [(.intro, 4), (.verse, 8), (.chorus, 8), (.breakdown, 8), (.verse, 8), (.chorus, 8), (.chorus, 8), (.outro, 4)],
                    drums: .fourOnFloor, voice: .saw, seed: 8128, hue: 0.83),
        Arrangement(key: "cherry-blossom-rush", title: "Cherry Blossom Rush", artist: "Sakura Static", bpm: 150, keyCount: 5,
                    rootMidi: 57, minor: false, progression: [3, 4, 2, 5],
                    blocks: [(.intro, 2), (.verse, 8), (.chorus, 8), (.verse, 8), (.chorus, 8), (.breakdown, 4), (.chorus, 8), (.chorus, 8), (.outro, 4)],
                    drums: .breakbeat, voice: .pluck, seed: 5150, hue: 0.94),
        Arrangement(key: "glass-sunrise", title: "Glass Sunrise", artist: "Aurelia", bpm: 112, keyCount: 6,
                    rootMidi: 50, minor: false, progression: [0, 4, 5, 3],
                    blocks: [(.intro, 4), (.verse, 8), (.chorus, 8), (.breakdown, 8), (.chorus, 8), (.verse, 8), (.chorus, 8), (.outro, 4)],
                    drums: .breakbeat, voice: .soft, seed: 777, hue: 0.55),
        Arrangement(key: "deep-blue-static", title: "Deep Blue Static", artist: "Aurelia", bpm: 100, keyCount: 6,
                    rootMidi: 54, minor: true, progression: [0, 3, 6, 5],
                    blocks: [(.intro, 2), (.verse, 8), (.chorus, 8), (.breakdown, 4), (.chorus, 8), (.verse, 8), (.chorus, 8), (.outro, 2)],
                    drums: .lofi, voice: .soft, seed: 60606, hue: 0.62),
        Arrangement(key: "midnight-arcade", title: "Midnight Arcade", artist: "Vector Hearts", bpm: 140, keyCount: 4,
                    rootMidi: 50, minor: true, progression: [0, 6, 5, 6],
                    blocks: [(.intro, 4), (.verse, 8), (.chorus, 8), (.breakdown, 8), (.verse, 8), (.chorus, 8), (.chorus, 8), (.outro, 4)],
                    drums: .fourOnFloor, voice: .saw, seed: 1984, hue: 0.74),
        Arrangement(key: "eclipse", title: "Eclipse", artist: "Umbra", bpm: 132, keyCount: 8,
                    rootMidi: 45, minor: true, progression: [0, 2, 5, 6],
                    blocks: [(.intro, 4), (.verse, 8), (.chorus, 8), (.breakdown, 4), (.chorus, 8), (.verse, 8), (.chorus, 8), (.outro, 4)],
                    drums: .fourOnFloor, voice: .saw, seed: 2112, hue: 0.12),
        Arrangement(key: "hyperloop", title: "Hyperloop", artist: "Static Bloom", bpm: 170, keyCount: 5,
                    rootMidi: 52, minor: true, progression: [0, 0, 5, 6],
                    blocks: [(.intro, 4), (.verse, 8), (.chorus, 8), (.breakdown, 4), (.chorus, 8), (.verse, 8), (.chorus, 8), (.chorus, 8), (.outro, 4)],
                    drums: .dnb, voice: .saw, seed: 9001, hue: 0.0),
        Arrangement(key: "solar-flare", title: "Solar Flare", artist: "Umbra", bpm: 175, keyCount: 7,
                    rootMidi: 52, minor: true, progression: [0, 0, 6, 5],
                    blocks: [(.intro, 4), (.verse, 8), (.chorus, 8), (.breakdown, 4), (.chorus, 8), (.verse, 8), (.chorus, 8), (.chorus, 8), (.outro, 4)],
                    drums: .dnb, voice: .saw, seed: 17517, hue: 0.04),
    ]

    static func arrangement(forKey key: String) -> Arrangement? { arrangements.first { $0.key == key } }

    static func makeSongs() -> [Song] {
        arrangements.map { a in
            let comp = Composer.compose(a)
            let charts: [Chart]
            if a.tutorial {
                charts = [ChartBuilder.tutorial(a)]
            } else {
                charts = Diff.allCases.map { ChartBuilder.build(comp, a: a, diff: $0) }
            }
            return Song(id: "builtin." + a.key, title: a.title, artist: a.artist, bpm: a.bpm, offset: 0,
                        keyCount: a.keyCount, duration: comp.duration, audioFile: nil, builtinKey: a.key,
                        hue: a.hue, charts: charts)
        }
    }

    static let audioVersion = 4

    static func audioURL(for a: Arrangement) -> URL {
        AppPaths.cache.appendingPathComponent("\(a.key)-v\(audioVersion).wav")
    }

    /// Renders (once) and caches the audio for a built-in song.
    static func ensureAudio(key: String) async -> URL? {
        guard let a = arrangement(forKey: key) else { return nil }
        let url = audioURL(for: a)
        if FileManager.default.fileExists(atPath: url.path) { return url }
        return await Task.detached(priority: .userInitiated) { () -> URL? in
            let comp = Composer.compose(a)
            let (l, r) = SongSynth.render(a, comp: comp)
            let tmp = url.appendingPathExtension("tmp")
            try? FileManager.default.removeItem(at: tmp)
            do {
                try SongSynth.writeWAV(left: l, right: r, to: tmp)
                try? FileManager.default.removeItem(at: url)
                try FileManager.default.moveItem(at: tmp, to: url)
                return url
            } catch { return nil }
        }.value
    }
}
