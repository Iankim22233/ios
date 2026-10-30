import Foundation
import AVFoundation
import Accelerate

enum ImportError: Error, LocalizedError {
    case unreadable
    var errorDescription: String? { "That audio file couldn't be read." }
}

enum AudioImporter {
    static let wavSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: 44100.0,
        AVNumberOfChannelsKey: 2,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
    ]

    /// Decode any supported audio file and re-encode it as 44.1 kHz stereo WAV. Returns the duration in seconds.
    static func convert(from src: URL, to dest: URL) throws -> Double {
        let inFile = try AVAudioFile(forReading: src)
        let inFmt = inFile.processingFormat
        guard let target = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2),
              let converter = AVAudioConverter(from: inFmt, to: target) else { throw ImportError.unreadable }
        try? FileManager.default.removeItem(at: dest)
        var outFile: AVAudioFile? = try AVAudioFile(forWriting: dest, settings: wavSettings)
        let chunk: AVAudioFrameCount = 16384
        guard let inBuf = AVAudioPCMBuffer(pcmFormat: inFmt, frameCapacity: chunk) else { throw ImportError.unreadable }
        let outCap = AVAudioFrameCount(Double(chunk) * 44100 / inFmt.sampleRate + 2048)
        guard let outBuf = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: outCap) else { throw ImportError.unreadable }

        var finished = false
        while !finished {
            outBuf.frameLength = 0
            var err: NSError?
            let status = converter.convert(to: outBuf, error: &err) { _, outStatus in
                inBuf.frameLength = 0
                do { try inFile.read(into: inBuf, frameCount: chunk) } catch { outStatus.pointee = .endOfStream; return nil }
                if inBuf.frameLength == 0 { outStatus.pointee = .endOfStream; return nil }
                outStatus.pointee = .haveData
                return inBuf
            }
            if let err { throw err }
            if outBuf.frameLength > 0 { try outFile?.write(from: outBuf) }
            if status == .endOfStream || status == .error { finished = true }
        }
        outFile = nil
        let check = try AVAudioFile(forReading: dest)
        return Double(check.length) / check.processingFormat.sampleRate
    }
}

// MARK: - Analysis

struct Onset {
    var time: Double
    var strength: Double
    var low: Double
    var mid: Double
    var high: Double
}

struct AudioAnalysis {
    var bpm: Double
    var offset: Double
    var onsets: [Onset]
    var duration: Double
}

enum Autocharter {
    static func analyze(url: URL) throws -> AudioAnalysis {
        let file = try AVAudioFile(forReading: url)
        let fmt = file.processingFormat
        let sr = fmt.sampleRate
        let hop = 512
        let hopSec = Double(hop) / sr
        let total = Int(file.length)

        // Band split with one-pole filters.
        let a1 = Float(1 - exp(-2 * Double.pi * 200 / sr))
        let a2 = Float(1 - exp(-2 * Double.pi * 2200 / sr))
        var lp1: Float = 0, lp2: Float = 0
        var eLow: [Float] = [], eMid: [Float] = [], eHigh: [Float] = []
        eLow.reserveCapacity(total / hop + 1); eMid.reserveCapacity(total / hop + 1); eHigh.reserveCapacity(total / hop + 1)

        let chunk: AVAudioFrameCount = 1 << 16
        guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: chunk) else { throw ImportError.unreadable }
        var accL: Float = 0, accM: Float = 0, accH: Float = 0
        var count = 0
        while file.framePosition < file.length {
            try file.read(into: buf, frameCount: chunk)
            let n = Int(buf.frameLength)
            if n == 0 { break }
            let chs = Int(fmt.channelCount)
            let data = buf.floatChannelData!
            for i in 0..<n {
                var x: Float = 0
                for c in 0..<chs { x += data[c][i] }
                x /= Float(chs)
                lp1 += a1 * (x - lp1)
                lp2 += a2 * (x - lp2)
                let low = lp1, mid = lp2 - lp1, high = x - lp2
                accL += low * low; accM += mid * mid; accH += high * high
                count += 1
                if count == hop {
                    let k = 1 / Float(hop)
                    eLow.append(accL * k); eMid.append(accM * k); eHigh.append(accH * k)
                    accL = 0; accM = 0; accH = 0; count = 0
                }
            }
        }
        let frames = eLow.count
        guard frames > 32 else { throw ImportError.unreadable }

        func flux(_ e: [Float], gain: Float) -> [Float] {
            var out = [Float](repeating: 0, count: e.count)
            var prevAvg: Float = 0
            for i in 0..<e.count {
                let c = log(1 + gain * e[i])
                if i > 0 { out[i] = max(0, c - prevAvg) }
                prevAvg = i == 0 ? c : 0.5 * prevAvg + 0.5 * c
            }
            return out
        }
        let fLow = flux(eLow, gain: 4000), fMid = flux(eMid, gain: 8000), fHigh = flux(eHigh, gain: 20000)
        var f = [Float](repeating: 0, count: frames)
        for i in 0..<frames { f[i] = fLow[i] * 1.0 + fMid[i] * 1.0 + fHigh[i] * 0.8 }

        // Adaptive peak picking.
        let w = Int(0.5 / hopSec)
        var prefix = [Double](repeating: 0, count: frames + 1)
        var prefix2 = [Double](repeating: 0, count: frames + 1)
        for i in 0..<frames { prefix[i + 1] = prefix[i] + Double(f[i]); prefix2[i + 1] = prefix2[i] + Double(f[i] * f[i]) }
        var onsets: [Onset] = []
        var lastIdx = -100
        let minSpacing = Int(0.05 / hopSec)
        for i in 2..<(frames - 2) {
            let v = f[i]
            guard v > f[i - 1], v >= f[i + 1], v > f[i - 2], v >= f[i + 2] else { continue }
            let lo = max(0, i - w), hi = min(frames, i + w)
            let n = Double(hi - lo)
            let mean = (prefix[hi] - prefix[lo]) / n
            let varc = max(0, (prefix2[hi] - prefix2[lo]) / n - mean * mean)
            let thr = mean + 0.9 * sqrt(varc) + 0.02
            guard Double(v) > thr else { continue }
            if i - lastIdx < minSpacing {
                if let l = onsets.last, Double(v) > l.strength { onsets.removeLast() } else { continue }
            }
            let tot = max(1e-6, fLow[i] + fMid[i] + fHigh[i])
            onsets.append(Onset(time: Double(i) * hopSec + hopSec / 2, strength: Double(v),
                                low: Double(fLow[i] / tot), mid: Double(fMid[i] / tot), high: Double(fHigh[i] / tot)))
            lastIdx = i
        }

        // Tempo estimation by autocorrelation of the onset envelope.
        func interp(_ idx: Double) -> Double {
            let i = Int(idx)
            guard i >= 0, i + 1 < frames else { return 0 }
            let fr = idx - Double(i)
            return Double(f[i]) * (1 - fr) + Double(f[i + 1]) * fr
        }
        var bestBPM = 120.0, bestScore = -1.0
        var bpm = 70.0
        while bpm <= 190 {
            let lag = 60 / bpm / hopSec
            var s = 0.0
            var i = 0.0
            while i + 2 * lag < Double(frames) {
                s += interp(i) * (interp(i + lag) + 0.5 * interp(i + 2 * lag))
                i += 1
            }
            // Mild preference for common dance/pop tempos.
            let prior = exp(-pow((log2(bpm / 120)), 2) / 0.8)
            s *= (0.6 + 0.4 * prior)
            if s > bestScore { bestScore = s; bestBPM = bpm }
            bpm += 0.5
        }
        // Guard against 3:2 / 4:3 confusions (dotted rhythms): prefer the faster pulse if it is nearly as strong.
        func rawScore(_ b: Double) -> Double {
            let lag = 60 / b / hopSec
            var s = 0.0
            var i = 0.0
            while i + 2 * lag < Double(frames) { s += interp(i) * (interp(i + lag) + 0.5 * interp(i + 2 * lag)); i += 1 }
            return s
        }
        let base = rawScore(bestBPM)
        for ratio in [1.5, 4.0 / 3.0] where bestBPM * ratio <= 185 {
            let cand = rawScore(bestBPM * ratio)
            if cand > 0.5 * base { bestBPM *= ratio; break }
        }
        // Refine to 0.1 BPM.
        var refined = bestBPM, refinedScore = -1.0
        var b = bestBPM - 0.6
        while b <= bestBPM + 0.6 {
            let lag = 60 / b / hopSec
            var s = 0.0
            var i = 0.0
            while i + 2 * lag < Double(frames) { s += interp(i) * (interp(i + lag) + 0.5 * interp(i + 2 * lag)); i += 1 }
            if s > refinedScore { refinedScore = s; refined = b }
            b += 0.1
        }
        let period = 60 / refined / hopSec
        var bestPhase = 0.0, bestPS = -1.0
        var ph = 0.0
        while ph < period {
            var s = 0.0
            var k = ph
            while k < Double(frames - 1) { s += interp(k); k += period }
            if s > bestPS { bestPS = s; bestPhase = ph }
            ph += 0.5
        }
        let offset = bestPhase * hopSec
        return AudioAnalysis(bpm: (refined * 10).rounded() / 10, offset: offset, onsets: onsets,
                             duration: Double(total) / sr)
    }

    static func buildNotes(_ an: AudioAnalysis, keyCount n: Int, diff: Diff, seed: UInt64 = 1) -> [Note] {
        var rng = SplitMix64(seed: seed)
        let minGap = [0.32, 0.19, 0.115][diff.rawValue]
        let keepFrac = [0.40, 0.70, 1.0][diff.rawValue]
        let spb = 60 / an.bpm
        let sorted = an.onsets.sorted { $0.strength > $1.strength }
        let cutoff = sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * keepFrac))].strength
        let onsets = an.onsets.filter { $0.strength >= cutoff || diff == .hard }.sorted { $0.time < $1.time }

        var notes: [Note] = []
        var busy: [(lane: Int, from: Double, to: Double)] = []
        func free(_ lane: Int, _ from: Double, _ to: Double, pad: Double = 0.09) -> Bool {
            !busy.contains { $0.lane == lane && $0.from < to + pad && $0.to > from - pad }
        }
        func add(_ note: Note) -> Bool {
            let segs = note.segments(count: n)
            for s in segs where !free(s.lane, s.from, s.to) { return false }
            notes.append(note)
            busy.append(contentsOf: segs.map { (lane: $0.lane, from: $0.from, to: $0.to) })
            return true
        }

        var last = -10.0
        var sweep = n / 2
        var sweepDir = 1
        var prevLane = -1
        var outerAlt = 0
        for (i, o) in onsets.enumerated() {
            var t = o.time
            let grid = spb / 4
            let snapped = an.offset + ((t - an.offset) / grid).rounded() * grid
            if abs(snapped - t) < 0.04 { t = snapped }
            if t - last < minGap { continue }

            var lane: Int
            if o.low > 0.5 {
                lane = outerAlt % 2 == 0 ? 0 : n - 1
                outerAlt += 1
            } else if o.high > 0.5 && n > 2 {
                lane = rng.int(1...(n - 2))
            } else {
                sweep += sweepDir
                if sweep >= n - 1 { sweep = n - 1; sweepDir = -1 }
                if sweep <= 0 { sweep = 0; sweepDir = 1 }
                lane = sweep
            }
            if lane == prevLane && t - last < 0.35 { lane = (lane + 1 + rng.int(0...max(0, n - 2))) % n }

            var note = Note(time: t, lane: lane)
            let nextT = i + 1 < onsets.count ? onsets[i + 1].time : t + 2
            let gap = nextT - t
            if gap >= 0.75 && diff != .easy ? rng.chance(0.55) : (gap >= 1.0 && rng.chance(0.4)) {
                var dur = min(gap - 0.18, 2.6)
                dur = max(0.3, (dur / (spb / 2)).rounded(.down) * (spb / 2))
                if dur >= 0.4 {
                    note.duration = dur
                    if diff != .easy && dur >= 1.0 && rng.chance(0.5) {
                        var dir = lane < n / 2 ? 1 : -1
                        if lane == 0 { dir = 1 } else if lane == n - 1 { dir = -1 }
                        note.slides = [SlideEvent(time: t + dur / 2, dir: dir)]
                    }
                }
            }
            if add(note) {
                last = t
                prevLane = lane
                if diff == .hard && o.strength > (sorted.first?.strength ?? 0) * 0.55 && rng.chance(0.35) && !note.isHold {
                    let mirror = n - 1 - lane
                    if mirror != lane { _ = add(Note(time: t, lane: mirror)) }
                }
            }
        }
        return notes.sorted { ($0.time, $0.lane) < ($1.time, $1.lane) }
    }
}
