import SwiftUI
import Observation

final class ScoreStore {
    static let shared = ScoreStore()
    private let key = "ManiDim.scores.v1"
    private(set) var records: [String: ScoreRecord] = [:]

    init() {
        if let d = UserDefaults.standard.data(forKey: key),
           let r = try? JSONDecoder().decode([String: ScoreRecord].self, from: d) { records = r }
    }

    static func id(_ songID: String, _ chart: String) -> String { "\(songID)|\(chart)" }
    func best(_ songID: String, _ chart: String) -> ScoreRecord? { records[Self.id(songID, chart)] }

    /// Returns true if this was a new best.
    @discardableResult
    func submit(_ r: ResultData) -> Bool {
        guard !r.autoplay, !r.fromEditor else { return false }
        let k = Self.id(r.songID, r.chartName)
        let rec = ScoreRecord(score: r.score, accuracy: r.accuracy, maxCombo: r.maxCombo, grade: r.grade, fullCombo: r.fullCombo, mods: r.modLabel.isEmpty ? nil : r.modLabel)
        if let old = records[k], old.score >= rec.score { return false }
        records[k] = rec
        if let d = try? JSONEncoder().encode(records) { UserDefaults.standard.set(d, forKey: key) }
        return true
    }
}

@Observable
final class GameSession {
    enum Phase { case loading, running, paused, countdown, finished, failed }

    let song: Song
    let chart: Chart
    let engine: GameEngine
    @ObservationIgnored let fx = FX()
    @ObservationIgnored var settings: GameSettings
    let startTime: Double
    let fromEditor: Bool
    let mods: ModSet
    let scoreMultiplier: Double

    var phase: Phase = .loading
    /// Non-nil while a tutorial lesson has the song stopped.
    var activeLesson: Lesson?
    var lessonNumber = 0
    var lessonTotal = 0
    var countdown = 0
    var pauseIndex = 0
    var errorText = ""

    @ObservationIgnored var onFinish: ((ResultData) -> Void)?
    @ObservationIgnored var onQuit: (() -> Void)?
    @ObservationIgnored var onRestart: (() -> Void)?

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var pausedTime = 0.0
    @ObservationIgnored private var clampMin: Double?
    @ObservationIgnored private var countdownEnd = 0.0
    @ObservationIgnored private var finishRequested = false
    @ObservationIgnored private var laneMap: [UInt16: Int] = [:]
    @ObservationIgnored private var laneCodes: [UInt16] = []
    @ObservationIgnored let keyLabels: [String]
    @ObservationIgnored private let audio = AudioManager.shared
    @ObservationIgnored private let leadIn = 2.6

    // Tutorial lessons: the clock is integrated so it can slow to a stop and start again.
    private enum LessonState { case none, stopping, stopped, resuming }
    @ObservationIgnored private var lessons: [Lesson] = []
    @ObservationIgnored private var lessonIdx = 0
    @ObservationIgnored private var lessonState = LessonState.none
    @ObservationIgnored private var songClock = 0.0
    @ObservationIgnored private var lastWall = 0.0
    @ObservationIgnored private var rate = 1.0
    @ObservationIgnored private var resumeBeginWall = 0.0
    @ObservationIgnored private let slowDur = 0.8
    private var scaled: Bool { !lessons.isEmpty }

    init(song: Song, chartIndex: Int, settings: GameSettings, startTime: Double = 0, fromEditor: Bool = false,
         mods: ModSet = ModSet(), origKeyCount: Int? = nil) {
        self.song = song
        self.mods = mods
        self.scoreMultiplier = mods.multiplier(origKeys: origKeyCount ?? song.keyCount)
        self.chart = song.charts[min(chartIndex, song.charts.count - 1)]
        self.settings = settings
        self.startTime = startTime
        self.fromEditor = fromEditor
        engine = GameEngine(chart: chart, laneCount: song.keyCount, startTime: startTime, windowScale: mods.windowScale)
        engine.bot = settings.autoplay
        lessons = settings.autoplay ? [] : self.chart.lessons.filter { $0.time > startTime }.sorted { $0.time < $1.time }
        lessonTotal = lessons.count
        let keys = settings.keys(for: song.keyCount)
        for (i, k) in keys.enumerated() { laneMap[k.code] = i; laneCodes.append(k.code) }
        keyLabels = keys.map { _ in "" } + ["swipe", "swipe"]
        engine.onEvent = { [weak self] e in self?.handle(e) }
    }

    // MARK: Lifecycle

    func prepare() async {
        phase = .loading
        var url: URL?
        if let key = song.builtinKey {
            url = await BuiltinSongs.ensureAudio(key: key)
        } else if let f = song.audioFile {
            url = AppPaths.songDir(song.id).appendingPathComponent(f)
        }
        guard let u = url, FileManager.default.fileExists(atPath: u.path), audio.load(url: u) else {
            errorText = "Couldn't load the audio for this song."
            phase = .failed
            return
        }
        audio.applyVolumes(settings)
        fx.reset()
        audio.owner = self
        audio.setRate(1)
        audio.setPlayRate(mods.speed)
        audio.play(from: startTime, delay: leadIn)
        if scaled {
            let w = Clock.hostNow()
            songClock = audio.position(atHost: w)
            lastWall = w
            rate = 1
        }
        phase = .running
        startLoop()
    }

    private func startLoop() {
        timer?.invalidate()
        let t = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func shutdown() {
        timer?.invalidate()
        timer = nil
        if phase == .finished {
            if audio.owner === self { audio.owner = nil }   // let the fade-out finish
        } else {
            audio.stop(ifOwner: self)
        }
    }

    // MARK: Clock

    func time(wall: Double = Clock.hostNow()) -> Double {
        switch phase {
        case .loading, .failed: return startTime - leadIn
        case .paused: return pausedTime
        case .finished: return max(engine.lastTime, scaled ? songClock - settings.audioOffset : audio.position(atHost: wall - settings.audioOffset))
        case .running, .countdown:
            // The audio offset is real-time latency, so it is applied to the wall clock (not to song seconds):
            // that keeps it correct under the speed mods.
            let raw = scaled ? songClock + (wall - lastWall) * rate - settings.audioOffset
                             : audio.position(atHost: wall - settings.audioOffset)
            if let m = clampMin { return max(raw, m) }
            return raw
        }
    }

    private func songTime(fromEvent ts: Double) -> Double {
        let h = Clock.fromEvent(ts)
        if scaled { return songClock + (h - lastWall) * rate - settings.audioOffset }
        return audio.position(atHost: h - settings.audioOffset)
    }

    // MARK: Tutorial lessons

    private func advanceScaled(wall: Double) {
        let dt = max(0, wall - lastWall)
        songClock += dt * rate
        lastWall = wall
        switch lessonState {
        case .none:
            rate = 1
            if lessonIdx < lessons.count, lessons[lessonIdx].time - songClock <= slowDur { lessonState = .stopping }
        case .stopping:
            let L = lessons[lessonIdx]
            let rem = L.time - songClock
            if rem <= 0.008 {
                songClock = L.time
                rate = 0
                lessonState = .stopped
                audio.stop()
                audio.play(.select, volume: 0.7)
                lessonNumber = lessonIdx + 1
                activeLesson = L
            } else {
                let r = rem / slowDur
                rate = r >= 0.25 ? r : 0.25 * (r / 0.25).squareRoot()
                audio.setRate(Float(max(0.25, rate)))
            }
        case .stopped:
            rate = 0
        case .resuming:
            let since = wall - resumeBeginWall
            if since < 0 { rate = 0 } else {
                let p = since / 0.7
                if p >= 1 {
                    rate = 1
                    audio.setRate(1)
                    lessonState = .none
                    lessonIdx += 1
                } else {
                    rate = 0.25 + 0.75 * smoothstep(p)
                    audio.setRate(Float(rate))
                }
            }
        }
    }

    private func lessonKeyMatches(_ code: UInt16, _ L: Lesson) -> Bool {
        if code == 49 || code == 36 || code == 76 { return true }   // Space / Return always work
        switch L.key {
        case "slideLeft": return code == settings.slideLeft.code
        case "slideRight": return code == settings.slideRight.code
        case "slide": return code == settings.slideLeft.code || code == settings.slideRight.code
        default: return false
        }
    }

    private func beginResume() {
        guard lessonState == .stopped else { return }
        activeLesson = nil
        audio.owner = self
        audio.setRate(0.25)
        audio.play(from: max(0, songClock), delay: 0.03)
        let w = Clock.hostNow()
        lastWall = w
        resumeBeginWall = w + 0.03
        rate = 0
        lessonState = .resuming
        audio.play(.select, volume: 0.6)
    }

    /// Text with {SL}/{SR}/{K1}… replaced by the player's real keys.
    func lessonText(_ L: Lesson) -> String {
        var t = L.text
        t = t.replacingOccurrences(of: "{SL}", with: "◀ SLIDE")
        t = t.replacingOccurrences(of: "{SR}", with: "SLIDE ▶")
        let keys = settings.keys(for: song.keyCount)
        for i in keys.indices { t = t.replacingOccurrences(of: "{K\(i + 1)}", with: "pad \(i + 1)") }
        return t
    }

    func lessonKeyLabels(_ L: Lesson) -> [String] {
        switch L.key {
        case "slideLeft": return [settings.slideLeft.label]
        case "slideRight": return [settings.slideRight.label]
        case "slide": return [settings.slideLeft.label, settings.slideRight.label]
        default: return ["Space"]
        }
    }

    private func tick() {
        let wall = Clock.hostNow()
        switch phase {
        case .countdown:
            let remaining = countdownEnd - wall
            let c = max(0, Int(ceil(remaining)))
            if c != countdown {
                countdown = c
                if c > 0 { audio.play(.beep) }
            }
            if remaining <= 0 {
                clampMin = nil
                audio.play(.go, volume: 0.6)
                if scaled { lastWall = wall; rate = 1 }
                phase = .running
            }
            // Keep the engine in sync with frozen time so holds don't expire.
            engine.update(now: pausedTime - 0.0001)
        case .running:
            if scaled { advanceScaled(wall: wall) }
            let t = time(wall: wall)
            engine.update(now: t)
            // Safety net: detect key-ups we never saw (e.g. while ⌘ is held).
            if !settings.autoplay {
                for lane in 0..<engine.laneCount where engine.keyDown[lane] {
                    if !InputCenter.shared.isReallyDown(laneCodes[lane]) { engine.release(lane: lane, at: t) }
                }
            }
            if !finishRequested {
                switch mods.failMode {
                case .suddenDeath where engine.counts[Judgment.miss.rawValue] > 0:
                    finishRequested = true; finish(failed: "Sudden Death — you missed")
                case .perfectOnly where engine.counts[Judgment.great.rawValue] + engine.counts[Judgment.good.rawValue] + engine.counts[Judgment.miss.rawValue] > 0:
                    finishRequested = true; finish(failed: "Perfect Only — not a PERFECT")
                default: break
                }
            }
            // After the last note, let the song play out (up to 7 s of outro) before the results.
            let outroEnd = min(song.duration - 0.3, engine.lastTime + 7)
            if !finishRequested, engine.isFinished, t > engine.lastTime + 0.8, t >= outroEnd {
                finishRequested = true
                finish()
            } else if !finishRequested, t > song.duration + 2 {
                finishRequested = true
                finish()
            }
        default: break
        }
    }

    private func finish(failed: String? = nil) {
        phase = .finished
        timer?.invalidate()
        var r = engine.result(song: song, chart: chart, autoplay: settings.autoplay, fromEditor: fromEditor)
        r.baseScore = r.score
        r.multiplier = scoreMultiplier
        r.modLabel = mods.label
        r.score = Int((Double(r.score) * scoreMultiplier).rounded())
        if let f = failed { r.failed = true; r.failReason = f }
        r.newBest = r.failed ? false : ScoreStore.shared.submit(r)
        audio.fadeOut(1.8)          // never cut the music off mid-note
        onFinish?(r)
    }

    // MARK: Pause

    func pause() {
        guard phase == .running || phase == .countdown else { return }
        pausedTime = time()
        if scaled {
            songClock += (Clock.hostNow() - lastWall) * rate
            lastWall = Clock.hostNow()
            if lessonState == .resuming { lessonState = .none; lessonIdx += 1; rate = 1 }
            if lessonState != .stopped { rate = 0 }
        }
        audio.stop()
        clampMin = nil
        pauseIndex = 0
        phase = .paused
    }

    func resume() {
        guard phase == .paused else { return }
        if scaled && lessonState == .stopped { phase = .running; return }   // still waiting on the lesson
        audio.play(.beep, volume: 0.5)
        clampMin = pausedTime
        audio.owner = self
        audio.setPlayRate(mods.speed)
        audio.play(from: max(0, pausedTime), delay: 3.0)
        if scaled { songClock = pausedTime + settings.audioOffset; lastWall = Clock.hostNow(); rate = 0 }
        countdownEnd = Clock.hostNow() + 3.0
        countdown = 3
        phase = .countdown
    }

    func restart() { shutdown(); onRestart?() }
    func quit() { shutdown(); onQuit?() }

    // MARK: Input

    func handleKey(_ ev: KeyEvent) -> Bool {
        if ev.isRepeat { return true }
        switch phase {
        case .loading, .failed:
            if ev.isDown && ev.code == 53 { quit() }
            return true
        case .paused:
            if ev.isDown {
                switch ev.code {
                case 53: resume()
                case 126: pauseIndex = (pauseIndex + 2) % 3; audio.play(.move)
                case 125: pauseIndex = (pauseIndex + 1) % 3; audio.play(.move)
                case 36, 76, 49:
                    audio.play(.select)
                    [{ self.resume() }, { self.restart() }, { self.quit() }][pauseIndex]()
                default: break
                }
            } else if let lane = laneMap[ev.code] {
                engine.release(lane: lane, at: pausedTime)
            }
            return true
        case .countdown:
            if ev.isDown && ev.code == 53 { pause() }
            else if !ev.isDown, let lane = laneMap[ev.code] { engine.release(lane: lane, at: pausedTime) }
            return true
        case .running:
            break
        case .finished:
            return true
        }

        if ev.isDown && ev.code == 53 { pause(); return true }
        if scaled, lessonState == .stopped, let L = activeLesson {
            if ev.isDown && lessonKeyMatches(ev.code, L) { beginResume() }
            return true
        }
        if settings.autoplay { return true }
        let st = songTime(fromEvent: ev.time)
        if let lane = laneMap[ev.code] {
            if ev.isDown {
                // Other lane keys already down physically but not yet delivered to us belong to the same burst.
                var pending = 0
                if InputCenter.shared.pollingReliable == true {
                    for l in 0..<engine.laneCount where l != lane && !engine.keyDown[l] && InputCenter.shared.physicallyDown(laneCodes[l]) { pending += 1 }
                }
                engine.press(lane: lane, at: st, pendingDown: pending)
            } else { engine.release(lane: lane, at: st) }
        } else if ev.isDown {
            if ev.code == settings.slideLeft.code { fx.slideLeftPress = 1; engine.slide(dir: -1, at: st) }
            else if ev.code == settings.slideRight.code { fx.slideRightPress = 1; engine.slide(dir: 1, at: st) }
        }
        return true
    }

    private func handle(_ e: GameEvent) {
        fx.queue.append(e)
        guard settings.hitSounds else { return }
        switch e {
        case .hit(_, _, _, let kind):
            switch kind {
            case .tap: audio.play(.tap)
            case .holdHead: audio.play(.hold)
            case .slide: audio.play(.slide)
            case .holdTail: audio.play(.tap, volume: 0.6)
            }
        case .miss(_, let kind):
            if kind == .tap || kind == .holdHead { audio.play(.miss, volume: 0.6) }
        default: break
        }
        if case .miss = e, !settings.hitSounds { return }
    }
}
