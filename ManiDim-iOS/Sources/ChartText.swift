import Foundation

/// ManiDim's compact text chart format (`.mdc`). See CHART_FORMAT.md.
///
///     T:Neon Drive            title            A:Vector Hearts   artist
///     B:128                   bpm (quarter notes per minute)
///     O:0.459                 seconds from the start of the audio to measure 1, beat 1
///     H:0.83                  colour hue 0…1   AUDIO:song.wav    audio file name
///
///     [Hard]                  starts a chart
///     4,3                     keys, difficulty level
///     4:4                     time signature (change later with  @12 3:4 )
///     K2 1,3.5 1 1|L|2,2 E:3,2
///        │   │   │   │      └─ end of the hold: measure,beat
///        │   │   │   └─ slide: 0 = none, or 1|L|m,b|R|m,b… (direction + where it happens)
///        │   │   └─ hold: 0 / 1
///        │   └─ measure,beat the note starts (both start at 1; beats can be fractional)
///        └─ lane (K1 = leftmost)
///     FX sparkles 5,1 hue=0.3 len=4      chart effect
///     LS 3,2 slideRight|Title|Text       tutorial lesson
enum ChartTextError: LocalizedError {
    case syntax(line: Int, message: String)
    var errorDescription: String? {
        switch self {
        case .syntax(let line, let msg): return line > 0 ? "Chart file, line \(line): \(msg)" : "Chart file: \(msg)"
        }
    }
}

enum ChartText {
    // MARK: Time signature helpers

    struct Sig {
        var changes: [(measure: Int, num: Int, den: Int)]

        /// Quarter-note position of (measure, beat). Measures before 1 extend the first signature backwards.
        func quarters(_ m: Int, _ b: Double) -> Double {
            let first = changes[0]
            if m <= first.measure {
                return Double(m - first.measure) * measureLen(first) + (b - 1) * 4 / Double(first.den)
            }
            var q = 0.0
            for (i, c) in changes.enumerated() {
                let end = i + 1 < changes.count ? min(changes[i + 1].measure, m) : m
                if m > c.measure { q += Double(max(0, end - c.measure)) * measureLen(c) }
                if i + 1 >= changes.count || changes[i + 1].measure > m {
                    return q + (b - 1) * 4 / Double(c.den)
                }
            }
            return q
        }

        private func measureLen(_ c: (measure: Int, num: Int, den: Int)) -> Double { Double(c.num) * 4 / Double(c.den) }
    }

    // MARK: Number formatting

    static func fmt(_ v: Double, digits: Int = 4) -> String {
        var s = String(format: "%.\(digits)f", v)
        if s.contains(".") { while s.hasSuffix("0") { s.removeLast() }; if s.hasSuffix(".") { s.removeLast() } }
        return s == "-0" ? "0" : s
    }

    // MARK: Writing

    static func write(_ song: Song) -> String {
        let num = max(1, song.timeSigNum), den = max(1, song.timeSigDen)
        let ql = Double(num) * 4 / Double(den)
        func pos(_ t: Double) -> String {
            let q = (t - song.offset) * song.bpm / 60
            var m = Int(floor(q / ql + 1e-9))
            var beat = (q - Double(m) * ql) * Double(den) / 4 + 1
            if beat >= Double(num) + 1 - 0.00005 { m += 1; beat = 1 }
            return "\(m + 1),\(fmt(beat))"
        }
        var out = """
        # ManiDim chart (.mdc) — see CHART_FORMAT.md. Everything after a # is a comment.
        # Note line:  K<lane> <measure>,<beat> <hold 0/1> <slide 0 | 1|L|m,b|R|m,b> [E:<measure>,<beat>]
        T:\(song.title)
        A:\(song.artist)
        B:\(fmt(song.bpm, digits: 3))
        O:\(fmt(song.offset, digits: 4))
        H:\(fmt(song.hue, digits: 3))

        """
        if let f = song.audioFile { out += "AUDIO:\(f)\n" }
        for chart in song.charts {
            out += "\n[\(chart.name)]\n"
            out += "\(chart.keys ?? song.keyCount),\(chart.level)   # keys, difficulty\n"
            out += "\(num):\(den)   # time signature\n"
            for n in chart.notes.sorted(by: { ($0.time, $0.lane) < ($1.time, $1.lane) }) {
                var line = "K\(n.lane + 1) \(pos(n.time)) "
                if n.isHold {
                    line += "1 "
                    if n.slides.isEmpty { line += "0" } else {
                        line += "1" + n.slides.sorted { $0.time < $1.time }.map { "|\($0.dir < 0 ? "L" : "R")|\(pos($0.time))" }.joined()
                    }
                    line += " E:\(pos(n.endTime))"
                } else {
                    line += "0 0"
                }
                out += line + "\n"
            }
            for e in chart.events.sorted(by: { $0.time < $1.time }) {
                var line = "FX \(e.kind.rawValue) \(pos(e.time))"
                if e.kind.usesHue { line += " hue=\(fmt(e.hue, digits: 3))" }
                if e.duration > 0 { line += " len=\(fmt(e.duration, digits: 3))" }
                out += line + "\n"
            }
            for l in chart.lessons {
                let text = l.text.replacingOccurrences(of: "\n", with: "\\n")
                out += "LS \(pos(l.time)) \(l.key)|\(l.title)|\(text)\n"
            }
        }
        return out
    }

    // MARK: Parsing

    private struct Tok { let s: String; let line: Int }
    private struct RawChart {
        var name = "Custom"
        var tokens: [Tok] = []
        var sigChanges: [(measure: Int, num: Int, den: Int, line: Int)] = []
        var fx: [(line: Int, kind: EventKind, m: Int, b: Double, hue: Double?, len: Double)] = []
        var lessons: [(line: Int, m: Int, b: Double, key: String, title: String, text: String)] = []
    }

    private static func err(_ line: Int, _ msg: String) -> ChartTextError { .syntax(line: line, message: msg) }

    private static func parsePos(_ s: String, line: Int) throws -> (Int, Double) {
        let p = s.split(separator: ",", omittingEmptySubsequences: false)
        guard p.count == 2, let m = Int(p[0]), let b = Double(p[1]) else {
            throw err(line, "expected measure,beat (like 3,2.5) but found “\(s)”")
        }
        return (m, b)
    }

    static func parse(_ text: String) throws -> Song {
        var title = "Untitled", artist = "Unknown artist", bpm = 120.0, offset = 0.0
        var hue: Double?
        var audio: String?
        var charts: [RawChart] = []

        func current() -> Int {
            if charts.isEmpty { charts.append(RawChart()) }
            return charts.count - 1
        }

        let lines = text.replacingOccurrences(of: "\u{FEFF}", with: "").components(separatedBy: .newlines)
        for (idx, raw) in lines.enumerated() {
            let ln = idx + 1
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            // Title and artist keep any '#' they contain.
            if trimmed.hasPrefix("T:") { title = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces); continue }
            if trimmed.hasPrefix("A:") { artist = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces); continue }
            var line = trimmed
            if let h = line.firstIndex(of: "#") { line = String(line[..<h]).trimmingCharacters(in: .whitespaces) }
            if line.isEmpty { continue }

            if line.hasPrefix("[") && line.hasSuffix("]") {
                var c = RawChart()
                c.name = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                if c.name.isEmpty { c.name = "Chart \(charts.count + 1)" }
                charts.append(c)
                continue
            }
            for key in ["B", "O", "H", "AUDIO"] where line.hasPrefix(key + ":") {
                let v = String(line.dropFirst(key.count + 1)).trimmingCharacters(in: .whitespaces)
                switch key {
                case "AUDIO": audio = v
                default:
                    guard let d = Double(v) else { throw err(ln, "\(key): needs a number, found “\(v)”") }
                    if key == "B" { bpm = d } else if key == "O" { offset = d } else { hue = d }
                }
                break
            }
            if ["B:", "O:", "H:", "AUDIO:"].contains(where: { line.hasPrefix($0) }) { continue }

            if line.hasPrefix("@") {
                let p = line.dropFirst().split(separator: " ", omittingEmptySubsequences: true)
                guard p.count == 2, let m = Int(p[0]) else { throw err(ln, "time-signature change looks like  @12 3:4") }
                let sg = p[1].split(separator: ":")
                guard sg.count == 2, let n = Int(sg[0]), let d = Int(sg[1]), n > 0, d > 0 else { throw err(ln, "bad time signature “\(p[1])”") }
                let ci = current()
                charts[ci].sigChanges.append((m, n, d, ln))
                continue
            }
            if line.hasPrefix("FX ") || line == "FX" {
                let p = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
                guard p.count >= 3, let kind = EventKind(rawValue: p[1]) else {
                    throw err(ln, "effect looks like  FX sparkles 5,1 [hue=0.3] [len=4]  — kinds: \(EventKind.allCases.map(\.rawValue).joined(separator: ", "))")
                }
                let (m, b) = try parsePos(p[2], line: ln)
                var h: Double?, len = 0.0
                for o in p.dropFirst(3) {
                    if o.hasPrefix("hue="), let v = Double(o.dropFirst(4)) { h = v }
                    else if o.hasPrefix("len="), let v = Double(o.dropFirst(4)) { len = v }
                    else { throw err(ln, "unknown effect option “\(o)”") }
                }
                let ci = current()
                charts[ci].fx.append((ln, kind, m, b, h, len))
                continue
            }
            if line.hasPrefix("LS ") {
                let rest = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
                guard let sp = rest.firstIndex(of: " ") else { throw err(ln, "lesson looks like  LS 3,2 space|Title|Text") }
                let (m, b) = try parsePos(String(rest[..<sp]), line: ln)
                let parts = rest[rest.index(after: sp)...].split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
                guard parts.count == 3 else { throw err(ln, "lesson looks like  LS 3,2 space|Title|Text") }
                let ci = current()
                charts[ci].lessons.append((ln, m, b, parts[0], parts[1], parts[2].replacingOccurrences(of: "\\n", with: "\n")))
                continue
            }
            let ci = current()
            for t in line.split(whereSeparator: { $0 == " " || $0 == "\t" }) { charts[ci].tokens.append(Tok(s: String(t), line: ln)) }
        }

        guard !charts.isEmpty else { throw err(0, "no charts found") }
        guard bpm >= 20, bpm <= 400 else { throw err(0, "B: (BPM) must be between 20 and 400") }

        var built: [Chart] = []
        var keyCount = 0
        var sigNum = 4, sigDen = 4
        for (ci, rc) in charts.enumerated() {
            let toks = rc.tokens
            var i = 0
            guard i < toks.count else { throw err(0, "chart “\(rc.name)” is empty — it needs a “keys,difficulty” line") }
            // header: keys,level
            let h = toks[i].s.split(separator: ",")
            guard h.count == 2, let keys = Int(h[0]), let level = Int(h[1]), (1...8).contains(keys) else {
                throw err(toks[i].line, "chart “\(rc.name)” must start with keys,difficulty (like 4,3; keys 1–8) — found “\(toks[i].s)”")
            }
            i += 1
            if keyCount == 0 { keyCount = keys }
            var num = 4, den = 4
            if i < toks.count, toks[i].s.contains(":"), !toks[i].s.hasPrefix("E:") {
                let sg = toks[i].s.split(separator: ":")
                guard sg.count == 2, let n = Int(sg[0]), let d = Int(sg[1]), n > 0, d > 0 else { throw err(toks[i].line, "bad time signature “\(toks[i].s)” (like 4:4)") }
                num = n; den = d
                i += 1
            }
            if ci == 0 { sigNum = num; sigDen = den }
            var changes: [(measure: Int, num: Int, den: Int)] = [(1, num, den)]
            for c in rc.sigChanges.sorted(by: { $0.measure < $1.measure }) { changes.append((c.measure, c.num, c.den)) }
            let sig = Sig(changes: changes)
            func time(_ m: Int, _ b: Double) -> Double { offset + sig.quarters(m, b) * 60 / bpm }

            var notes: [Note] = []
            while i < toks.count {
                let t = toks[i]
                guard t.s.hasPrefix("K"), let lane1 = Int(t.s.dropFirst()), lane1 >= 1, lane1 <= keys else {
                    throw err(t.line, "expected a note starting with K1…K\(keys) but found “\(t.s)”")
                }
                i += 1
                guard i < toks.count else { throw err(t.line, "note \(t.s) has no position") }
                let (m, b) = try parsePos(toks[i].s, line: toks[i].line)
                let startLine = toks[i].line
                i += 1
                var hold = false
                if i < toks.count, toks[i].s == "0" || toks[i].s == "1" {
                    hold = toks[i].s == "1"
                    i += 1
                }
                var slideSpec: [(dir: Int, m: Int, b: Double, line: Int)] = []
                if i < toks.count, toks[i].s == "0" || toks[i].s.hasPrefix("1|") {
                    let tk = toks[i]
                    i += 1
                    if tk.s != "0" {
                        let parts = tk.s.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
                        guard parts.count >= 3, parts.count % 2 == 1 else {
                            throw err(tk.line, "slide looks like 1|L|2,2 (direction L or R, then measure,beat) — found “\(tk.s)”")
                        }
                        var k = 1
                        while k + 1 < parts.count {
                            guard parts[k] == "L" || parts[k] == "R" else { throw err(tk.line, "slide direction must be L or R, found “\(parts[k])”") }
                            let (sm, sb) = try parsePos(parts[k + 1], line: tk.line)
                            slideSpec.append((parts[k] == "L" ? -1 : 1, sm, sb, tk.line))
                            k += 2
                        }
                    }
                }
                var note = Note(time: time(m, b), lane: lane1 - 1)
                if hold {
                    guard i < toks.count, toks[i].s.hasPrefix("E:") else { throw err(startLine, "hold at \(m),\(fmt(b)) needs an end like E:3,2") }
                    let (em, eb) = try parsePos(String(toks[i].s.dropFirst(2)), line: toks[i].line)
                    let endT = time(em, eb)
                    guard endT > note.time + 0.001 else { throw err(toks[i].line, "the hold ends before it starts") }
                    note.duration = endT - note.time
                    i += 1
                    var lane = lane1 - 1
                    for s in slideSpec {
                        let st = time(s.m, s.b)
                        guard st > note.time, st < endT else { throw err(s.line, "a slide must happen inside its hold (between start and E:)") }
                        lane += s.dir
                        guard lane >= 0, lane < keys else { throw err(s.line, "that slide would leave the lanes (K1…K\(keys))") }
                        note.slides.append(SlideEvent(time: st, dir: s.dir))
                    }
                    note.slides.sort { $0.time < $1.time }
                } else if !slideSpec.isEmpty {
                    throw err(startLine, "only holds can have slides (put hold = 1)")
                } else if i < toks.count, toks[i].s.hasPrefix("E:") {
                    i += 1          // harmless end marker on a tap
                }
                notes.append(note)
            }
            var chart = Chart(name: rc.name, level: max(1, level), notes: notes)
            chart.keys = keys == keyCount ? nil : keys
            chart.events = rc.fx.map { ChartEvent(time: time($0.m, $0.b), kind: $0.kind, hue: $0.hue ?? hue ?? 0.12, duration: $0.len) }
            chart.lessons = rc.lessons.map { Lesson(time: time($0.m, $0.b), title: $0.title, text: $0.text, key: $0.key) }
            chart.sortNotes()
            built.append(chart)
        }

        var song = Song(id: "custom." + UUID().uuidString.prefix(8).lowercased(), title: title, artist: artist, bpm: bpm, offset: offset,
                        keyCount: keyCount, duration: 0, audioFile: audio, builtinKey: nil, hue: hue ?? Double.random(in: 0...1), charts: built)
        song.timeSigNum = sigNum
        song.timeSigDen = sigDen
        return song
    }
}
