import SwiftUI

/// Runs a looping autoplay of Neon Drive behind the home screen (synced to the menu music when available).
final class DemoRunner {
    static let shared = DemoRunner()

    let fx = FX()
    private(set) var engine: GameEngine
    private let song: Song
    private let chart: Chart
    private let segStart = 22.5
    private let segEnd = 58.0
    private let lead = 1.6
    private var runStart = 0.0
    private var musicOn = false
    private var wantMusic = false

    init() {
        let a = BuiltinSongs.arrangement(forKey: "neon-drive")!
        let songs = BuiltinSongs.makeSongs()
        song = songs.first { $0.builtinKey == a.key }!
        chart = song.charts[2]
        engine = GameEngine(chart: chart, laneCount: song.keyCount, startTime: segStart)
        engine.bot = true
        engine.onEvent = { [fx] e in fx.queue.append(e) }
    }

    var hue: Double { song.hue }
    var bpm: Double { song.bpm }

    func setMusic(_ on: Bool) {
        wantMusic = on
        if on { restart(wall: Clock.hostNow()) } else if musicOn {
            AudioManager.shared.stop(); musicOn = false
        }
    }

    private func restart(wall: Double) {
        engine = GameEngine(chart: chart, laneCount: song.keyCount, startTime: segStart)
        engine.bot = true
        engine.onEvent = { [fx] e in fx.queue.append(e) }
        fx.reset()
        runStart = wall
        guard wantMusic else { return }
        Task { @MainActor in
            if let url = await BuiltinSongs.ensureAudio(key: "neon-drive"), self.wantMusic, AudioManager.shared.load(url: url) {
                let a = AudioManager.shared
                a.applyVolumes(SettingsStore.shared.value)
                a.music.volume = a.musicVolume * 0.55
                a.play(from: self.segStart, delay: self.lead)
                self.runStart = a.startHost - self.lead
                self.musicOn = true
                self.engine = GameEngine(chart: self.chart, laneCount: self.song.keyCount, startTime: self.segStart)
                self.engine.bot = true
                self.engine.onEvent = { [fx = self.fx] e in fx.queue.append(e) }
            }
        }
    }

    func time(wall: Double) -> Double {
        if runStart == 0 { restart(wall: wall) }
        let t = segStart - lead + (wall - runStart)
        if t > segEnd { restart(wall: wall) }
        engine.update(now: t)
        return t
    }
}

/// Full-screen animated backdrop used by the menus.
struct AttractView: View {
    var showFan: Bool
    var centerX: Double = 0.68
    var hue: Double? = nil
    @Environment(AppModel.self) private var app

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                _ = tl.date
                let wall = Clock.hostNow()
                let demo = DemoRunner.shared
                var settings = app.settings
                settings.particles = true
                settings.screenShake = false
                if showFan {
                    let t = demo.time(wall: wall)
                    let rs = RenderState(engine: demo.engine, fx: demo.fx, time: t, wall: wall, settings: settings,
                                         bpm: demo.bpm, offset: 0, hue: hue ?? demo.hue, centerX: centerX, showHUD: false, ambient: true)
                    GameRenderer.draw(&ctx, size: size, rs: rs)
                } else {
                    let u = max(0.4, min(size.height / 800, size.width / 1180))
                    GameRenderer.drawBackdrop(&ctx, size: size, apex: CGPoint(x: size.width / 2, y: size.height * 0.6), u: u,
                                              spec: settings.background.spec(for: settings.skin), hue: hue ?? demo.hue, wall: wall)
                }
            }
        }
        .ignoresSafeArea()
    }
}
