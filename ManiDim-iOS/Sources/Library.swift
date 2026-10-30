import Foundation
import Observation

@Observable
final class SongLibrary {
    static let shared = SongLibrary()
    var songs: [Song] = []

    init() { reload() }

    func reload() {
        var list = BuiltinSongs.makeSongs()
        var custom: [Song] = []
        let fm = FileManager.default
        if let dirs = try? fm.contentsOfDirectory(at: AppPaths.songs, includingPropertiesForKeys: nil) {
            for d in dirs {
                let j = d.appendingPathComponent("song.json")
                if let data = try? Data(contentsOf: j), let s = try? JSONDecoder().decode(Song.self, from: data) {
                    custom.append(s)
                }
            }
        }
        custom.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        list.append(contentsOf: custom)
        songs = list
    }

    func song(id: String?) -> Song? {
        guard let id else { return nil }
        return songs.first { $0.id == id }
    }

    func save(_ song: Song) {
        guard !song.isBuiltin else { return }
        let dir = AppPaths.songDir(song.id)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(song) {
            try? data.write(to: dir.appendingPathComponent("song.json"), options: .atomic)
        }
        if let i = songs.firstIndex(where: { $0.id == song.id }) {
            songs[i] = song
        } else {
            songs.append(song)
        }
    }

    func delete(_ song: Song) {
        guard !song.isBuiltin else { return }
        try? FileManager.default.removeItem(at: AppPaths.songDir(song.id))
        songs.removeAll { $0.id == song.id }
    }

    func audioURL(for song: Song) -> URL? {
        if let f = song.audioFile { return AppPaths.songDir(song.id).appendingPathComponent(f) }
        return nil
    }
}
