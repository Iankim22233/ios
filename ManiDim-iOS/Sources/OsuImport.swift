import Foundation

enum OsuError: LocalizedError {
    case notMania, noMania, noAudio(String), unreadable(String)
    var errorDescription: String? {
        switch self {
        case .notMania: return "That .osu file is osu!standard, not osu!mania. Only mania (key) beatmaps can be imported."
        case .noMania: return "This beatmap has no osu!mania difficulties."
        case .noAudio(let n): return "The audio file “\(n)” wasn't found next to the .osu file."
        case .unreadable(let s): return "Couldn't read the beatmap: \(s)"
        }
    }
}

/// Imports osu!mania beatmaps (`.osu`, or a whole `.osz` beatmap set) as a custom song.
/// Every mania difficulty in the set that has the same key count and audio becomes one chart.
enum OsuImporter {
    private struct Map {
        var file: URL
        var audio = ""
        var title = "Untitled", artist = "Unknown artist", version = "Chart"
        var mode = 0
        var keys = 4
        var bpm = 120.0, offset = 0.0
        var notes: [Note] = []
    }

    // MARK: Parsing

    private static func parse(_ url: URL) throws -> Map {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        else { throw OsuError.unreadable(url.lastPathComponent) }
        var m = Map(file: url)
        var section = ""
        var gotTiming = false
        var rawObjects: [[Substring]] = []
        for lineSub in text.split(whereSeparator: \.isNewline) {
            let line = lineSub.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("//") { continue }
            if line.hasPrefix("[") && line.hasSuffix("]") { section = String(line.dropFirst().dropLast()); continue }
            switch section {
            case "General", "Metadata", "Difficulty":
                guard let c = line.firstIndex(of: ":") else { continue }
                let key = line[..<c].trimmingCharacters(in: .whitespaces)
                let val = line[line.index(after: c)...].trimmingCharacters(in: .whitespaces)
                switch key {
                case "AudioFilename": m.audio = val
                case "Mode": m.mode = Int(val) ?? 0
                case "Title": m.title = val
                case "Artist": m.artist = val
                case "Version": m.version = val
                case "CircleSize": m.keys = Int(Double(val) ?? 4)
                default: break
                }
            case "TimingPoints":
                guard !gotTiming else { continue }
                let p = line.split(separator: ",", omittingEmptySubsequences: false)
                guard p.count >= 2, let t = Double(p[0]), let beat = Double(p[1]), beat > 0 else { continue }
                // Uninherited (red) timing point: defines BPM and where beat 0 is.
                if p.count >= 7 && p[6].trimmingCharacters(in: .whitespaces) == "0" { continue }
                m.bpm = 60000 / beat
                m.offset = t / 1000
                gotTiming = true
            case "HitObjects":
                rawObjects.append(line.split(separator: ",", omittingEmptySubsequences: false))
            default: break
            }
        }
        guard m.mode == 3 else { return m }
        let keys = max(1, m.keys)
        var seen = Set<String>()
        for p in rawObjects {
            guard p.count >= 5, let x = Double(p[0]), let ms = Double(p[2]), let type = Int(p[3]) else { continue }
            let col = min(keys - 1, max(0, Int(x * Double(keys) / 512)))
            var dur = 0.0
            if type & 128 != 0, p.count > 5, let endMs = Double(p[5].split(separator: ":").first ?? "") {
                dur = (endMs - ms) / 1000
                if dur < 0.12 { dur = 0 }       // too short to be a playable hold
            } else if type & 1 == 0 { continue }
            let key = "\(Int(ms))-\(col)"
            if !seen.insert(key).inserted { continue }
            m.notes.append(Note(time: ms / 1000, lane: col, duration: dur))
        }
        return m
    }

    // MARK: Import

    static func importFile(at url: URL) async throws -> Song {
        try await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            var root = url.deletingLastPathComponent()
            var chosen: URL? = url
            var cleanup: URL?
            defer { if let c = cleanup { try? fm.removeItem(at: c) } }

            if url.pathExtension.lowercased() == "osz" {
                let tmp = fm.temporaryDirectory.appendingPathComponent("osz-in-" + UUID().uuidString)
                try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
                cleanup = tmp
                try MiniZip.extract(url, to: tmp)
                root = tmp
                chosen = nil
            }

            var files: [URL] = []
            if let en = fm.enumerator(at: root, includingPropertiesForKeys: nil, options: chosen == nil ? [] : [.skipsSubdirectoryDescendants]) {
                for case let f as URL in en where f.pathExtension.lowercased() == "osu" && !f.lastPathComponent.hasPrefix(".") { files.append(f) }
            }
            func same(_ a: URL, _ b: URL) -> Bool { a.resolvingSymlinksInPath().path == b.resolvingSymlinksInPath().path }
            if let c = chosen, !files.contains(where: { same($0, c) }) { files.append(c) }

            var maps: [Map] = []
            var firstParsed: Map?
            for f in files {
                guard let m = try? parse(f) else { continue }
                if let c = chosen, same(f, c) { firstParsed = m }
                if m.mode == 3, !m.notes.isEmpty { maps.append(m) }
            }
            if let fp = firstParsed, fp.mode != 3 { throw OsuError.notMania }
            guard !maps.isEmpty else { throw OsuError.noMania }

            // The primary key count (the chosen file's, or the most common in a set) is the song's;
            // every difficulty that uses the same audio becomes a chart, each keeping its own key count.
            let target: Map
            if let fp = firstParsed, fp.mode == 3 { target = fp } else {
                let groups = Dictionary(grouping: maps) { "\($0.keys)|\($0.audio)" }
                let best = groups.values.max { a, b in a.count != b.count ? a.count < b.count : a[0].keys < b[0].keys }!
                target = best[0]
            }
            var set = maps.filter { $0.audio == target.audio }
            guard !set.isEmpty else { throw OsuError.noMania }

            let audioURL = target.file.deletingLastPathComponent().appendingPathComponent(target.audio)
            guard fm.fileExists(atPath: audioURL.path) else { throw OsuError.noAudio(target.audio) }

            func level(_ m: Map) -> Int {
                let start = m.notes.map(\.time).min() ?? 0
                let end = m.notes.map(\.endTime).max() ?? 1
                let nps = Double(m.notes.count) / max(10, end - start)
                return min(20, max(1, Int((3 * nps.squareRoot()).rounded())))
            }
            func lanes(_ m: Map) -> Int { min(8, max(3, m.keys)) }
            set.sort { (lanes($0), level($0)) < (lanes($1), level($1)) }

            let keyCount = lanes(target)
            var song = Song(id: "custom." + UUID().uuidString.prefix(8).lowercased(),
                            title: target.title, artist: target.artist, bpm: (target.bpm * 100).rounded() / 100,
                            offset: target.offset, keyCount: keyCount, duration: 0, audioFile: "audio.wav",
                            builtinKey: nil, hue: Double(abs(target.title.hashValue % 1000)) / 1000, charts: [], source: "osz")
            for m in set {
                let k = lanes(m)
                var notes = m.notes
                if m.keys != k {      // fold unusual key counts (1–2K, 9–10K) into 3–8 lanes
                    var seen = Set<String>()
                    notes = notes.compactMap { n in
                        var n = n
                        n.lane = min(k - 1, n.lane * k / m.keys)
                        return seen.insert("\(Int(n.time * 1000))-\(n.lane)").inserted ? n : nil
                    }
                }
                var chart = Chart(name: m.version, level: level(m), notes: notes)
                chart.keys = k == keyCount ? nil : k
                chart.sortNotes()
                song.charts.append(chart)
            }
            let dest = AppPaths.songDir(song.id).appendingPathComponent("audio.wav")
            song.duration = try AudioImporter.convert(from: audioURL, to: dest)
            return song
        }.value
    }
}
