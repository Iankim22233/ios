import SwiftUI
import Observation
import UniformTypeIdentifiers

@Observable
final class AppModel {
    enum Screen { case home, songSelect, game, results, settings, editor }

    var screen: Screen = .home
    var session: GameSession?
    var result: ResultData?
    var editorSongID: String?
    var showHowTo = false
    var showMods = false
    var showNewSong = false
    var selectedSongID: String?
    var selectedChart = 0
    var toast: String?
    var editorPlayhead = 0.0
    var editorChartIndex = 0

    let library = SongLibrary.shared
    let settingsStore = SettingsStore.shared

    var settings: GameSettings { settingsStore.value }

    init() {
        selectedSongID = library.songs.first(where: { $0.id == "builtin.neon-drive" })?.id ?? library.songs.first?.id
        selectedChart = 1
        AudioManager.shared.applyVolumes(settingsStore.value)
        InputCenter.shared.install()
        applyLaunchArguments()
    }

    /// Debug helpers: `--screen songs|settings|editor`, `--play <song-key> <chart-index> [--autoplay]`.
    private func applyLaunchArguments() {
        let a = CommandLine.arguments
        if a.contains(where: { ["--mods", "--skin", "--autoplay", "--play", "--screen", "--audiotest", "--showmods", "--importosu"].contains($0) }) { settingsStore.suppressSave = true }
        if a.contains("--autoplay") { settingsStore.value.autoplay = true }
        if let i = a.firstIndex(of: "--mods"), i + 1 < a.count {
            settingsStore.value.mods = a[i + 1] == "none" ? [] : a[i + 1].split(separator: ",").map(String.init)
        }
        if let i = a.firstIndex(of: "--importosu"), i + 1 < a.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.importMadim(URL(fileURLWithPath: a[i + 1])) }
        }
        if a.contains("--showmods") { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.go(.songSelect); self.showMods = true } }
        if let i = a.firstIndex(of: "--skin"), i + 1 < a.count, let k = Skin(rawValue: a[i + 1]) { settingsStore.value.skin = k }
        if a.contains("--audiotest") {
            DispatchQueue.main.async { self.go(.songSelect) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if let song = self.library.songs.first(where: { $0.builtinKey == "neon-drive" }) { self.startGame(song: song, chartIndex: 1) }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 9) {
                let au = AudioManager.shared
                print("audiotest: playing=\(au.isPlaying) nodePlaying=\(au.music.isPlaying) position=\(String(format: "%.2f", au.position()))")
                exit(au.isPlaying && au.music.isPlaying && au.position() > 2 ? 0 : 1)
            }
        } else if let i = a.firstIndex(of: "--play"), i + 2 < a.count,
           let song = library.songs.first(where: { $0.builtinKey == a[i + 1] }), let ci = Int(a[i + 2]) {
            DispatchQueue.main.async { self.startGame(song: song, chartIndex: ci, startTime: a.firstIndex(of: "--from").flatMap { Double(a[$0 + 1]) } ?? 0) }
        } else if let i = a.firstIndex(of: "--screen"), i + 1 < a.count {
            DispatchQueue.main.async {
                switch a[i + 1] {
                case "songs": self.go(.songSelect)
                case "settings": self.go(.settings)
                case "results":
                    self.result = ResultData(songID: "builtin.neon-drive", songTitle: "Neon Drive", artist: "Vector Hearts", chartName: "Hard", chartLevel: 7,
                                             hue: 0.83, score: 947210, accuracy: 0.962, maxCombo: 211, counts: [280, 30, 6, 2],
                                             offsets: (0..<300).map { _ in Double.random(in: -0.1...0.09) }, totalObjects: 318, autoplay: false, fromEditor: false, newBest: true)
                    self.go(.results)
                case "editor":
                    Task {
                        guard let s = self.library.songs.first(where: { $0.builtinKey == "neon-drive" }),
                              let src = await BuiltinSongs.ensureAudio(key: "neon-drive") else { return }
                        var copy = s
                        copy.id = "custom.debugdemo"; copy.title = "Neon Drive (Remix)"; copy.builtinKey = nil; copy.audioFile = "audio.wav"
                        let dest = AppPaths.songDir(copy.id).appendingPathComponent("audio.wav")
                        if !FileManager.default.fileExists(atPath: dest.path) { try? FileManager.default.copyItem(at: src, to: dest) }
                        self.library.save(copy)
                        self.editorSongID = copy.id
                        self.editorPlayhead = 30.9
                        self.go(.editor)
                    }
                default: break
                }
            }
        }
    }

    func go(_ s: Screen) {
        if screen == .home && s != .home { DemoRunner.shared.setMusic(false) }
        if s == .home && screen != .home { DemoRunner.shared.setMusic(true) }
        InputCenter.shared.lockKeys = false
        InputCenter.shared.handler = nil
        InputCenter.shared.overlayHandler = nil
        InputCenter.shared.captureHandler = nil
        InputCenter.shared.scrollHandler = nil
        withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { screen = s }
    }

    func showToast(_ text: String) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { toast = text }
        let t = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { [weak self] in
            if self?.toast == t { withAnimation(.easeOut(duration: 0.3)) { self?.toast = nil } }
        }
    }

    // MARK: .madim import / export

    func exportSong(_ song: Song) {
        Task { @MainActor in
            var src: URL?
            if let k = song.builtinKey { src = await BuiltinSongs.ensureAudio(key: k) } else { src = self.library.audioURL(for: song) }
            guard let audio = src, FileManager.default.fileExists(atPath: audio.path) else { self.showToast("Audio file missing – can't export"); return }
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let dest = dir.appendingPathComponent("ManiDimExport-\(MadimPackage.safeName(song.title)).\(MadimPackage.ext)")
            do {
                try await MadimPackage.export(song: song, audioSource: audio, to: dest)
                FilePicker.export(dest) { ok in if ok { self.showToast("Exported \(dest.lastPathComponent)") } }
            } catch { self.showToast(error.localizedDescription) }
        }
    }

    func pickAndImport() {
        FilePicker.open(types: [.item]) { [weak self] url in
            guard let url else { return }
            self?.importMadim(url)
        }
    }

    func importMadim(_ url: URL) {
        showToast("Importing \(url.lastPathComponent)…")
        let scoped = url.startAccessingSecurityScopedResource()
        Task { @MainActor in
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let ext = url.pathExtension.lowercased()
                let song = (ext == "osu" || ext == "osz") ? try await OsuImporter.importFile(at: url)
                                                           : try await MadimPackage.importPackage(at: url)
                library.save(song)
                selectedSongID = song.id
                selectedChart = 0
                showToast("Imported “\(song.title)”")
                if screen != .songSelect && screen != .game { go(.songSelect) }
            } catch { showToast(error.localizedDescription) }
        }
    }

    // MARK: Game flow

    func startGame(song original: Song, chartIndex: Int, startTime: Double = 0, fromEditor: Bool = false) {
        AudioManager.shared.stop()
        let ci = min(chartIndex, max(0, original.charts.count - 1))
        var song = original
        song.keyCount = original.keys(ci)       // charts can have their own key count
        let isTutorial = !(song.charts[ci].lessons.isEmpty)
        let mods = (fromEditor || isTutorial) ? ModSet() : settings.modSet     // tutorial & editor tests are always unmodded
        let played = ModApplier.apply(song: song, chartIndex: chartIndex, mods: mods)
        let s = GameSession(song: played, chartIndex: chartIndex, settings: settings, startTime: startTime, fromEditor: fromEditor,
                            mods: mods, origKeyCount: song.keyCount)
        s.onFinish = { [weak self] r in
            guard let self else { return }
            self.result = r
            self.go(.results)
        }
        s.onQuit = { [weak self] in self?.endGame(fromEditor: fromEditor) }
        s.onRestart = { [weak self] in self?.startGame(song: song, chartIndex: chartIndex, startTime: startTime, fromEditor: fromEditor) }
        session = s
        result = nil
        if screen == .game {
            // restarting: force a fresh GameView
            screen = .home
            DispatchQueue.main.async { self.go(.game) }
        } else {
            go(.game)
        }
    }

    func endGame(fromEditor: Bool) {
        session?.shutdown()
        session = nil
        go(fromEditor ? .editor : .songSelect)
    }

    func retryFromResults() {
        guard let r = result, let song = library.song(id: r.songID),
              let idx = song.charts.firstIndex(where: { $0.name == r.chartName }) else { go(.songSelect); return }
        startGame(song: song, chartIndex: idx, fromEditor: r.fromEditor)
    }
}
