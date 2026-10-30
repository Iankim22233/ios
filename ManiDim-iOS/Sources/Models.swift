import Foundation
import SwiftUI

// MARK: - Chart data

/// A slide event: while a hold is being held, the player taps the slide key
/// (default: left/right ⌘) and the hold's path moves one lane in `dir`.
struct SlideEvent: Codable, Hashable {
    var time: Double
    var dir: Int            // -1 = left, +1 = right
}

// Lenient decoding so hand-written / third-party chart JSON can omit optional fields.
extension Note {
    enum CodingKeys: String, CodingKey { case id, time, lane, duration, slides }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        time = try c.decode(Double.self, forKey: .time)
        lane = try c.decode(Int.self, forKey: .lane)
        duration = (try? c.decode(Double.self, forKey: .duration)) ?? 0
        slides = (try? c.decode([SlideEvent].self, forKey: .slides)) ?? []
    }
}
extension Chart {
    enum CodingKeys: String, CodingKey { case id, name, level, notes, events, lessons, keys }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        name = (try? c.decode(String.self, forKey: .name)) ?? "Chart"
        level = (try? c.decode(Int.self, forKey: .level)) ?? 1
        notes = try c.decode([Note].self, forKey: .notes)
        events = (try? c.decode([ChartEvent].self, forKey: .events)) ?? []
        lessons = (try? c.decode([Lesson].self, forKey: .lessons)) ?? []
        keys = (try? c.decode(Int.self, forKey: .keys)).map { min(8, max(1, $0)) }
    }
}
extension Song {
    enum CodingKeys: String, CodingKey { case id, title, artist, bpm, offset, keyCount, duration, audioFile, builtinKey, hue, charts, timeSigNum, timeSigDen, source }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? "custom." + UUID().uuidString.prefix(8).lowercased()
        title = (try? c.decode(String.self, forKey: .title)) ?? "Untitled"
        artist = (try? c.decode(String.self, forKey: .artist)) ?? "Unknown artist"
        bpm = (try? c.decode(Double.self, forKey: .bpm)) ?? 120
        offset = (try? c.decode(Double.self, forKey: .offset)) ?? 0
        keyCount = min(8, max(3, (try? c.decode(Int.self, forKey: .keyCount)) ?? 4))
        duration = (try? c.decode(Double.self, forKey: .duration)) ?? 0
        audioFile = try? c.decode(String.self, forKey: .audioFile)
        builtinKey = try? c.decode(String.self, forKey: .builtinKey)
        hue = (try? c.decode(Double.self, forKey: .hue)) ?? Double.random(in: 0...1)
        charts = try c.decode([Chart].self, forKey: .charts)
        timeSigNum = max(1, (try? c.decode(Int.self, forKey: .timeSigNum)) ?? 4)
        timeSigDen = max(1, (try? c.decode(Int.self, forKey: .timeSigDen)) ?? 4)
        source = try? c.decode(String.self, forKey: .source)
    }
}

struct Note: Codable, Identifiable, Hashable {
    var id = UUID()
    var time: Double
    var lane: Int
    var duration: Double = 0
    var slides: [SlideEvent] = []

    var isHold: Bool { duration > 0.001 }
    var endTime: Double { time + max(0, duration) }

    /// Lane occupied by this note's path at time `t`.
    func lane(at t: Double, count: Int) -> Int {
        var l = lane
        for s in slides where s.time <= t { l = min(max(l + s.dir, 0), count - 1) }
        return l
    }

    func finalLane(count: Int) -> Int { lane(at: .infinity, count: count) }

    /// (lane, from, to) path segments, used for overlap checks.
    func segments(count: Int) -> [(lane: Int, from: Double, to: Double)] {
        var out: [(Int, Double, Double)] = []
        var l = lane
        var start = time
        for s in slides {
            out.append((l, start, s.time))
            l = min(max(l + s.dir, 0), count - 1)
            start = s.time
        }
        out.append((l, start, max(endTime, start)))
        return out.map { (lane: $0.0, from: $0.1, to: $0.2) }
    }
}

/// Visual effects a chart can trigger at a point in the song (placed in the editor's FX row).
enum EventKind: String, Codable, CaseIterable, Identifiable {
    case sparkles, flash, shake, pulse, fireworks, lasers, tint
    var id: String { rawValue }
    var title: String {
        switch self {
        case .sparkles: return "Sparkles"
        case .flash: return "Flash"
        case .shake: return "Shake"
        case .pulse: return "Pulse"
        case .fireworks: return "Fireworks"
        case .lasers: return "Lasers"
        case .tint: return "Colour wash"
        }
    }
    var icon: String {
        switch self {
        case .sparkles: return "sparkles"
        case .flash: return "bolt.fill"
        case .shake: return "waveform.path"
        case .pulse: return "dot.radiowaves.left.and.right"
        case .fireworks: return "party.popper.fill"
        case .lasers: return "rays"
        case .tint: return "paintpalette.fill"
        }
    }
    var usesHue: Bool { self == .flash || self == .tint || self == .lasers || self == .fireworks || self == .pulse }
    var usesDuration: Bool { self == .lasers || self == .tint }
    var defaultDuration: Double {
        switch self {
        case .sparkles: return 2.4
        case .flash: return 0.45
        case .shake: return 0.5
        case .pulse: return 0.9
        case .fireworks: return 1.9
        case .lasers: return 4
        case .tint: return 4
        }
    }
}

struct ChartEvent: Codable, Identifiable, Hashable {
    var id = UUID()
    var time: Double
    var kind: EventKind
    var hue: Double = 0.12
    var duration: Double = 0          // 0 = the effect's default length

    var length: Double { duration > 0 ? duration : kind.defaultDuration }
    var seed: UInt64 {
        let k = UInt64(EventKind.allCases.firstIndex(of: kind) ?? 0)
        return UInt64(max(0, time * 1000).rounded()) &* 2654435761 &+ k &* 97
    }
}

extension ChartEvent {
    enum CodingKeys: String, CodingKey { case id, time, kind, hue, duration }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        time = try c.decode(Double.self, forKey: .time)
        kind = (try? c.decode(EventKind.self, forKey: .kind)) ?? .sparkles
        hue = (try? c.decode(Double.self, forKey: .hue)) ?? 0.12
        duration = (try? c.decode(Double.self, forKey: .duration)) ?? 0
    }
}

/// A tutorial step: the song slows to a stop at `time`, shows a message, and waits for `key`.
struct Lesson: Codable, Hashable {
    var time: Double
    var title: String
    var text: String            // may contain {SL} {SR} {K1}…{K8} placeholders
    var key: String             // "space" | "slideLeft" | "slideRight"
}

struct Chart: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var level: Int
    var notes: [Note]
    var events: [ChartEvent] = []
    var lessons: [Lesson] = []
    /// Key count of this chart when it differs from the song's (osu sets mix 4K/5K/7K); nil = the song's.
    var keys: Int? = nil

    /// Number of scored objects (tap = 1, hold = head + tail + one per slide).
    var objectCount: Int {
        notes.reduce(0) { $0 + ($1.isHold ? 2 + $1.slides.count : 1) }
    }

    mutating func sortNotes() {
        notes.sort { ($0.time, $0.lane) < ($1.time, $1.lane) }
    }

    var lastTime: Double { notes.map(\.endTime).max() ?? 0 }
}

struct Song: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var artist: String
    var bpm: Double
    var offset: Double          // time (s) of beat 0 in the audio
    var keyCount: Int
    var duration: Double
    var audioFile: String?      // file name inside the song folder (custom songs)
    var builtinKey: String?     // key of a procedurally generated song
    var hue: Double
    var charts: [Chart]
    /// Time signature used by the text chart format (does not change gameplay).
    var timeSigNum = 4
    var timeSigDen = 4
    /// Where the song came from ("osz" for osu!mania beatmaps), shown as a label in the song list.
    var source: String? = nil

    var isBuiltin: Bool { builtinKey != nil }

    func keys(_ chartIndex: Int) -> Int { charts.indices.contains(chartIndex) ? (charts[chartIndex].keys ?? keyCount) : keyCount }
    var mixedKeys: Bool { charts.contains { ($0.keys ?? keyCount) != keyCount } }
    var keysLabel: String {
        let ks = Set(charts.map { $0.keys ?? keyCount })
        guard let lo = ks.min(), let hi = ks.max(), lo != hi else { return "\(keyCount)K" }
        return "\(lo)–\(hi)K"
    }
}

// MARK: - Results

enum Judgment: Int, CaseIterable {
    case perfect, great, good, miss

    var weight: Double {
        switch self {
        case .perfect: return 1.0
        case .great: return 0.7
        case .good: return 0.4
        case .miss: return 0
        }
    }
    var title: String {
        switch self {
        case .perfect: return "PERFECT"
        case .great: return "GREAT"
        case .good: return "GOOD"
        case .miss: return "MISS"
        }
    }
    var color: Color {
        switch self {
        case .perfect: return Color(red: 1.0, green: 0.86, blue: 0.25)
        case .great: return Color(red: 0.45, green: 0.95, blue: 0.55)
        case .good: return Color(red: 0.45, green: 0.72, blue: 1.0)
        case .miss: return Color(red: 1.0, green: 0.35, blue: 0.38)
        }
    }
}

struct ResultData {
    var songID: String
    var songTitle: String
    var artist: String
    var chartName: String
    var chartLevel: Int
    var hue: Double
    var score: Int
    var accuracy: Double
    var maxCombo: Int
    var counts: [Int]           // indexed by Judgment.rawValue
    var offsets: [Double]       // hit offsets in seconds (negative = early)
    var totalObjects: Int
    var autoplay: Bool
    var fromEditor: Bool
    var newBest: Bool = false
    var multiplier: Double = 1
    var modLabel: String = ""
    var baseScore: Int = 0
    var failed: Bool = false
    var failReason: String = ""

    var fullCombo: Bool { counts[Judgment.miss.rawValue] == 0 && totalObjects > 0 }
    var allPerfect: Bool { counts[Judgment.perfect.rawValue] == totalObjects && totalObjects > 0 }

    var grade: String {
        if failed { return "F" }
        if allPerfect { return "SS" }
        switch accuracy {
        case 0.97...: return "S"
        case 0.92...: return "A"
        case 0.85...: return "B"
        case 0.72...: return "C"
        default: return "D"
        }
    }
}

struct ScoreRecord: Codable {
    var score: Int
    var accuracy: Double
    var maxCombo: Int
    var grade: String
    var fullCombo: Bool
    var mods: String? = nil
}

// MARK: - Paths

enum AppPaths {
    static var support: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("ManiDim", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    static var songs: URL {
        let dir = support.appendingPathComponent("Songs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    static var cache: URL {
        let dir = support.appendingPathComponent("Cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    static func songDir(_ id: String) -> URL {
        let dir = songs.appendingPathComponent(id, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

// MARK: - Misc helpers

struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
    mutating func chance(_ p: Double) -> Bool { unit() < p }
    mutating func pick<T>(_ a: [T]) -> T { a[Int(next() % UInt64(a.count))] }
    mutating func int(_ r: ClosedRange<Int>) -> Int { r.lowerBound + Int(next() % UInt64(r.count)) }
}

func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
func clamp<T: Comparable>(_ v: T, _ lo: T, _ hi: T) -> T { min(max(v, lo), hi) }
func smoothstep(_ t: Double) -> Double { let x = clamp(t, 0, 1); return x * x * (3 - 2 * x) }

func formatTime(_ s: Double) -> String {
    let t = Int(max(0, s).rounded())
    return String(format: "%d:%02d", t / 60, t % 60)
}
