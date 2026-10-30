import Foundation

enum MadimError: LocalizedError {
    case noAudio, noChart, zipFailed(String), badChart(String)
    var errorDescription: String? {
        switch self {
        case .noAudio: return "This package has no audio file."
        case .noChart: return "This package has no chart JSON."
        case .zipFailed(let s): return "Couldn't read or write the .madim file. \(s)"
        case .badChart(let s): return "The chart JSON couldn't be read: \(s)"
        }
    }
}

/// `.madim` = a renamed zip:
///
///     ManiDimExport-<title>/
///         chart/<title>.mdc      (compact text chart: song info + every chart — see CHART_FORMAT.md)
///         audio/<title>.wav
///
/// Older packages with a JSON chart (JSON/<title>.json) still import.
enum MadimPackage {
    static let ext = "madim"
    private static let audioExts: Set<String> = ["wav", "mp3", "m4a", "aac", "aif", "aiff", "caf", "flac", "ogg", "mp4"]

    static func safeName(_ s: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t")
        let t = s.components(separatedBy: bad).joined(separator: "-").trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? "Song" : t
    }

    static func export(song: Song, audioSource: URL, to dest: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            let name = safeName(song.title)
            let tmp = fm.temporaryDirectory.appendingPathComponent("madim-" + UUID().uuidString)
            let root = tmp.appendingPathComponent("ManiDimExport-\(name)")
            try fm.createDirectory(at: root.appendingPathComponent("chart"), withIntermediateDirectories: true)
            try fm.createDirectory(at: root.appendingPathComponent("audio"), withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: tmp) }

            let audioName = "\(name).\(audioSource.pathExtension.isEmpty ? "wav" : audioSource.pathExtension)"
            try fm.copyItem(at: audioSource, to: root.appendingPathComponent("audio").appendingPathComponent(audioName))

            var out = song
            out.builtinKey = nil
            out.audioFile = audioName
            try ChartText.write(out).write(to: root.appendingPathComponent("chart").appendingPathComponent("\(name).mdc"),
                                           atomically: true, encoding: .utf8)

            let zip = tmp.appendingPathComponent("out.zip")
            try MiniZip.create(zip, folder: root)
            try? fm.removeItem(at: dest)
            try fm.moveItem(at: zip, to: dest)
        }.value
    }

    /// Unpacks a .madim (or plain .zip) into a new custom song. Returns the saved song.
    static func importPackage(at url: URL) async throws -> Song {
        try await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            let tmp = fm.temporaryDirectory.appendingPathComponent("madim-in-" + UUID().uuidString)
            try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: tmp) }
            try MiniZip.extract(url, to: tmp)

            var jsons: [URL] = [], audios: [URL] = []
            if let en = fm.enumerator(at: tmp, includingPropertiesForKeys: [.isRegularFileKey]) {
                for case let f as URL in en {
                    let comps = f.pathComponents
                    if comps.contains("__MACOSX") || f.lastPathComponent.hasPrefix(".") { continue }
                    guard (try? f.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
                    let e = f.pathExtension.lowercased()
                    if e == "json" || e == "mdc" || e == "txt" { jsons.append(f) } else if audioExts.contains(e) { audios.append(f) }
                }
            }
            guard !jsons.isEmpty else { throw MadimError.noChart }
            var song: Song?
            var lastErr = ""
            for j in jsons {
                do {
                    if j.pathExtension.lowercased() == "json" {
                        song = try JSONDecoder().decode(Song.self, from: Data(contentsOf: j))
                    } else {
                        song = try ChartText.parse(String(contentsOf: j, encoding: .utf8))
                    }
                    break
                } catch { lastErr = "\(j.lastPathComponent): \(error.localizedDescription)" }
            }
            guard var s = song else { throw MadimError.badChart(lastErr) }
            let audio = audios.first { $0.lastPathComponent == s.audioFile } ?? audios.first
            guard let audioURL = audio else { throw MadimError.noAudio }

            s.id = "custom." + UUID().uuidString.prefix(8).lowercased()
            s.builtinKey = nil
            s.audioFile = "audio.wav"
            if s.charts.isEmpty { s.charts = [Chart(name: "Custom", level: 1, notes: [])] }
            for ci in s.charts.indices {
                s.charts[ci].id = UUID()
                for ni in s.charts[ci].notes.indices { s.charts[ci].notes[ni].lane = min(max(0, s.charts[ci].notes[ni].lane), s.keys(ci) - 1) }
            }
            let dest = AppPaths.songDir(s.id).appendingPathComponent("audio.wav")
            s.duration = try AudioImporter.convert(from: audioURL, to: dest)
            return s
        }.value
    }
}
