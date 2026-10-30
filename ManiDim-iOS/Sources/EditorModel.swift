import SwiftUI
import Observation

enum EditorTool: Int, CaseIterable {
    case tap, hold, slideL, slideR, erase, event
    var title: String { ["Tap", "Hold", "Slide ◀", "Slide ▶", "Erase", "Effect"][rawValue] }
    var icon: String { ["circle.fill", "capsule.fill", "arrow.left.circle.fill", "arrow.right.circle.fill", "eraser.fill", "sparkles"][rawValue] }
    var hint: String {
        ["Click a lane to drop a tap note.", "Click and drag along a lane to make a hold.",
         "Click on a hold to add a slide to the left.", "Click on a hold to add a slide to the right.",
         "Click a note, slide marker or effect to remove it.",
         "Click the FX row (above the lanes) to place the chosen effect. Click an effect to remove it."][rawValue]
    }
}

struct EditorSnapshot { var notes: [Note]; var events: [ChartEvent] }

struct PendingRec {
    var lane: Int
    var start: Double
    var slides: [SlideEvent] = []
}

@Observable
final class EditorModel {
    var song: Song
    var chartIndex = 0
    var tool: EditorTool = .tap
    var snapIndex = 3
    static let snaps = [1, 2, 3, 4, 6, 8, 12, 16]
    var snap: Int { Self.snaps[snapIndex] }

    var playhead = 0.0
    var playing = false
    var recording = false
    var quantizeRec = true
    var hitSounds = true
    var pxPerSec = 170.0
    var viewStart = -0.6
    var hover: CGPoint?
    var dragStart: CGPoint?
    var dragNow: CGPoint?
    var canvasSize = CGSize(width: 800, height: 400)

    var busy = false
    var busyText = ""
    var message: String?
    var analysis: AudioAnalysis?
    var autoDiff: Diff = .normal
    var undoStack: [EditorSnapshot] = []
    var redoStack: [EditorSnapshot] = []
    var eventKind: EventKind = .sparkles
    var eventHue = 0.12
    var eventDuration = 4.0

    var pending: [UInt16: PendingRec] = [:]
    private var timer: Timer?
    private var lastSoundTime = 0.0
    private let audio = AudioManager.shared
    var settings: GameSettings

    static let gutter = 70.0
    static let ruler = 38.0
    static let eventRow = 34.0

    init(song: Song, settings: GameSettings) {
        self.song = song
        self.settings = settings
        if song.charts.isEmpty {
            self.song.charts = [Chart(name: "Custom", level: 1, notes: [])]
        }
    }

    var chart: Chart {
        get { song.charts[min(chartIndex, song.charts.count - 1)] }
        set { song.charts[min(chartIndex, song.charts.count - 1)] = newValue }
    }
    var notes: [Note] { chart.notes }
    var spb: Double { 60 / max(30, song.bpm) }
    var audioURL: URL? { AppPaths.songDir(song.id).appendingPathComponent(song.audioFile ?? "audio.wav") }
    var laneH: Double { (canvasSize.height - Self.ruler - Self.eventRow) / Double(song.keyCount) }

    // MARK: Coordinates

    func x(_ t: Double) -> Double { Self.gutter + (t - viewStart) * pxPerSec }
    func time(_ x: Double) -> Double { viewStart + (x - Self.gutter) / pxPerSec }
    func lane(_ y: Double) -> Int { Int(floor((y - Self.ruler - Self.eventRow) / max(1, laneH))) }
    func laneY(_ l: Int) -> Double { Self.ruler + Self.eventRow + (Double(l) + 0.5) * laneH }

    func snapped(_ t: Double) -> Double {
        let step = spb / Double(snap)
        let k = ((t - song.offset) / step).rounded()
        return song.offset + k * step
    }

    // MARK: Undo

    func checkpoint() {
        undoStack.append(EditorSnapshot(notes: chart.notes, events: chart.events))
        if undoStack.count > 80 { undoStack.removeFirst() }
        redoStack.removeAll()
    }
    func undo() {
        guard let last = undoStack.popLast() else { return }
        redoStack.append(EditorSnapshot(notes: chart.notes, events: chart.events))
        chart.notes = last.notes
        chart.events = last.events
        persist()
    }
    func redo() {
        guard let n = redoStack.popLast() else { return }
        undoStack.append(EditorSnapshot(notes: chart.notes, events: chart.events))
        chart.notes = n.notes
        chart.events = n.events
        persist()
    }

    func persist() {
        var c = chart
        c.sortNotes()
        c.events.sort { $0.time < $1.time }
        c.level = clamp(Int((Double(c.objectCount) / max(10, song.duration) * 2.1).rounded()), 1, 15)
        chart = c
        SongLibrary.shared.save(song)
    }

    func flash(_ text: String) {
        message = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in if self?.message == text { self?.message = nil } }
    }

    // MARK: Hit testing

    func noteIndex(lane l: Int, at t: Double) -> Int? {
        let tol = 9 / pxPerSec
        for (i, n) in notes.enumerated() {
            if !n.isHold {
                if n.lane == l && abs(n.time - t) < tol { return i }
            } else {
                for s in n.segments(count: song.keyCount) where s.lane == l && t >= s.from - tol && t <= s.to + tol { return i }
            }
        }
        return nil
    }

    func slideIndex(in note: Note, near t: Double) -> Int? {
        let tol = 12 / pxPerSec
        return note.slides.firstIndex { abs($0.time - t) < tol }
    }

    // MARK: Editing actions (called from gestures)

    func pointerDown(_ p: CGPoint) {
        if p.y < Self.ruler { seek(max(0, time(p.x))); return }
        guard p.x >= Self.gutter else { return }
        dragStart = p
        dragNow = p
    }

    func pointerMoved(_ p: CGPoint) {
        guard dragStart != nil else { return }
        if dragStart!.y < Self.ruler { seek(max(0, time(p.x))); return }
        dragNow = p
    }

    func pointerUp(_ p: CGPoint) {
        defer { dragStart = nil; dragNow = nil }
        guard let s = dragStart else { return }
        if s.y < Self.ruler { return }
        if s.y < Self.ruler + Self.eventRow { eventClick(at: time(s.x)); return }
        let l = lane(s.y)
        guard l >= 0, l < song.keyCount else { return }
        if tool == .event { flash("Click the FX row above the lanes to place effects"); return }
        let t0 = time(s.x)
        let moved = hypot(p.x - s.x, p.y - s.y) > 6

        switch tool {
        case .tap:
            if let i = noteIndex(lane: l, at: t0) {
                checkpoint(); chart.notes.remove(at: i)
            } else {
                checkpoint()
                chart.notes.append(Note(time: max(0, snapped(t0)), lane: l))
            }
            persist()
        case .hold:
            let a = max(0, snapped(t0))
            let b = snapped(time(p.x))
            if moved && abs(b - a) >= spb / Double(snap) * 0.9 {
                let start = min(a, b), end = max(a, b)
                checkpoint()
                chart.notes.append(Note(time: start, lane: l, duration: end - start))
                persist()
            } else if let i = noteIndex(lane: l, at: t0) {
                checkpoint(); chart.notes.remove(at: i); persist()
            } else {
                checkpoint()
                chart.notes.append(Note(time: a, lane: l, duration: spb))
                persist()
            }
        case .slideL, .slideR:
            let dir = tool == .slideL ? -1 : 1
            guard let i = noteIndex(lane: l, at: t0), chart.notes[i].isHold else { flash("Click on a hold note to add a slide"); return }
            var n = chart.notes[i]
            if let si = slideIndex(in: n, near: t0) {
                checkpoint(); n.slides.remove(at: si); chart.notes[i] = n; persist(); return
            }
            let st = snapped(t0)
            guard st > n.time + 0.04, st < n.endTime - 0.04 else { flash("Slides go inside a hold, not on its ends"); return }
            let before = n.lane(at: st - 1e-6, count: song.keyCount)
            let after = clamp(before + dir, 0, song.keyCount - 1)
            guard after != before else { flash("No lane there to slide into"); return }
            checkpoint()
            n.slides.append(SlideEvent(time: st, dir: dir))
            n.slides.sort { $0.time < $1.time }
            chart.notes[i] = n
            persist()
        case .event:
            break
        case .erase:
            if let i = noteIndex(lane: l, at: t0) {
                var n = chart.notes[i]
                checkpoint()
                if let si = slideIndex(in: n, near: t0) { n.slides.remove(at: si); chart.notes[i] = n } else { chart.notes.remove(at: i) }
                persist()
            }
        }
        if hitSounds && !playing { audio.play(.move, volume: 0.6) }
    }

    func eventClick(at t: Double) {
        let tol = 13 / pxPerSec
        if let i = chart.events.firstIndex(where: { abs($0.time - t) < tol || (t >= $0.time && t <= $0.time + ($0.kind.usesDuration ? $0.length : 0)) }) {
            guard tool == .event || tool == .erase else { return }
            checkpoint(); chart.events.remove(at: i); persist()
            return
        }
        guard tool == .event else { if tool != .erase { flash("Pick the Effect tool (6) to place effects") }; return }
        checkpoint()
        chart.events.append(ChartEvent(time: max(0, snapped(t)), kind: eventKind, hue: eventHue,
                                       duration: eventKind.usesDuration ? eventDuration : 0))
        persist()
        if hitSounds && !playing { audio.play(.slide, volume: 0.5) }
    }



    func clearChart() { checkpoint(); chart.notes = []; chart.events = []; persist() }

    // MARK: Chart management

    func addChart() {
        var names = ["Easy", "Normal", "Hard", "Expert", "Custom 2", "Custom 3", "Custom 4"]
        names.removeAll { n in song.charts.contains { $0.name == n } }
        song.charts.append(Chart(name: names.first ?? "Chart \(song.charts.count + 1)", level: 1, notes: []))
        chartIndex = song.charts.count - 1
        persist()
    }
    func deleteChart() {
        guard song.charts.count > 1 else { flash("A song needs at least one chart"); return }
        song.charts.remove(at: chartIndex)
        chartIndex = max(0, chartIndex - 1)
        persist()
    }
    func setKeyCount(_ k: Int) {
        guard k != song.keyCount else { return }
        for ci in song.charts.indices {
            for ni in song.charts[ci].notes.indices {
                var n = song.charts[ci].notes[ni]
                n.lane = min(n.lane, k - 1)
                n.slides = n.slides.filter { _ in true }
                song.charts[ci].notes[ni] = n
            }
        }
        song.keyCount = k
        persist()
    }

    // MARK: Transport

    func seek(_ t: Double) {
        playhead = clamp(t, 0, song.duration)
        lastSoundTime = playhead
        if playing { startAudio() }
        keepPlayheadVisible(force: false)
    }

    private func startAudio() {
        guard let url = audioURL, audio.load(url: url) else { flash("Audio file missing"); playing = false; return }
        audio.applyVolumes(settings)
        audio.play(from: playhead, delay: 0.05)
    }

    func togglePlay() {
        if playing { pause() } else { play() }
    }

    func play() {
        guard !playing else { return }
        guard let url = audioURL, audio.load(url: url) else { flash("Audio file missing"); return }
        playing = true
        lastSoundTime = playhead
        startAudio()
        timer?.invalidate()
        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func pause() {
        guard playing else { return }
        playing = false
        timer?.invalidate(); timer = nil
        audio.stop()
        finishPending(at: playhead)
    }

    func stopAll() {
        if playing { pause() }
    }

    private func tick() {
        guard playing else { return }
        let now = audio.position() - settings.audioOffset
        guard now >= playhead - 0.5 else { return }
        if hitSounds && !recording {
            for n in notes where n.time > lastSoundTime && n.time <= now {
                audio.play(n.isHold ? .hold : .tap, volume: 0.7)
            }
            for n in notes where n.isHold {
                for s in n.slides where s.time > lastSoundTime && s.time <= now { audio.play(.slide, volume: 0.7) }
            }
        }
        lastSoundTime = now
        playhead = now
        if now >= song.duration { pause(); return }
        keepPlayheadVisible(force: true)
    }

    func keepPlayheadVisible(force: Bool) {
        let w = canvasSize.width - Self.gutter
        let px = x(playhead)
        if px > Self.gutter + w * 0.72 || px < Self.gutter {
            viewStart = playhead - w * 0.28 / pxPerSec
        }
    }

    func zoom(by f: Double, anchorX: Double? = nil) {
        let ax = anchorX ?? (Self.gutter + (canvasSize.width - Self.gutter) / 2)
        let tAnchor = time(ax)
        pxPerSec = clamp(pxPerSec * f, 30, 900)
        viewStart = tAnchor - (ax - Self.gutter) / pxPerSec
    }

    func scrollBy(dx: Double) { viewStart = clamp(viewStart - dx / pxPerSec, -1.5, song.duration) }

    // MARK: Recording

    func recordKey(lane l: Int, down: Bool, code: UInt16, eventTime: Double) {
        let t = audio.position(atHost: Clock.fromEvent(eventTime)) - settings.audioOffset
        if down {
            if pending[code] == nil { pending[code] = PendingRec(lane: l, start: t) }
        } else {
            finishPending(code: code, at: t)
        }
    }

    func recordSlide(dir: Int, eventTime: Double) {
        let t = audio.position(atHost: Clock.fromEvent(eventTime)) - settings.audioOffset
        guard let (code, p) = pending.max(by: { $0.value.start < $1.value.start }) else { return }
        var q = p
        let cur = clamp(p.lane + q.slides.reduce(0) { $0 + $1.dir }, 0, song.keyCount - 1)
        guard clamp(cur + dir, 0, song.keyCount - 1) != cur else { return }
        q.slides.append(SlideEvent(time: t, dir: dir))
        pending[code] = q
        audio.play(.slide, volume: 0.6)
    }

    private func finishPending(code: UInt16, at t: Double) {
        guard let p = pending.removeValue(forKey: code) else { return }
        checkpoint()
        let q = { (v: Double) in self.quantizeRec ? max(0, self.snapped(v)) : max(0, v) }
        let start = q(p.start)
        var n = Note(time: start, lane: p.lane)
        let dur = t - p.start
        if dur > 0.22 {
            var end = q(t)
            if end <= start + 0.05 { end = start + dur }
            n.duration = end - start
            n.slides = p.slides.map { SlideEvent(time: q($0.time), dir: $0.dir) }
                .filter { $0.time > n.time + 0.02 && $0.time < n.endTime - 0.02 }
        }
        chart.notes.append(n)
        audio.play(n.isHold ? .hold : .tap, volume: 0.6)
        persist()
    }

    private func finishPending(at t: Double) {
        for code in Array(pending.keys) { finishPending(code: code, at: t) }
    }

    // MARK: Analysis & auto charting

    func ensureAnalysis() async -> AudioAnalysis? {
        if let a = analysis { return a }
        guard let url = audioURL else { return nil }
        let res = await Task.detached(priority: .userInitiated) { try? Autocharter.analyze(url: url) }.value
        analysis = res
        return res
    }

    func detectTempo() {
        busy = true; busyText = "Analysing tempo…"
        Task {
            let a = await ensureAnalysis()
            busy = false
            if let a {
                song.bpm = a.bpm
                song.offset = a.offset
                persist()
                flash(String(format: "Detected %.1f BPM", a.bpm))
            } else { flash("Couldn't analyse the audio") }
        }
    }

    func autoGenerate() {
        busy = true; busyText = "Charting…"
        Task {
            guard var a = await ensureAnalysis() else { busy = false; flash("Couldn't analyse the audio"); return }
            a.bpm = song.bpm
            a.offset = song.offset
            let notes = Autocharter.buildNotes(a, keyCount: song.keyCount, diff: autoDiff, seed: UInt64.random(in: 1...UInt64.max))
            checkpoint()
            chart.notes = notes
            persist()
            busy = false
            flash("Generated \(notes.count) notes")
        }
    }

    func setOffsetToPlayhead() {
        song.offset = playhead
        persist()
        flash("Beat grid starts at \(String(format: "%.3f", playhead)) s")
    }
}
