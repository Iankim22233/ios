import SwiftUI

extension Notification.Name {
    static let editorUndo = Notification.Name("ManiDim.editorUndo")
    static let editorRedo = Notification.Name("ManiDim.editorRedo")
}

struct EditorHost: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        if let s = app.library.song(id: app.editorSongID), !s.isBuiltin {
            EditorView(song: s).id(s.id)
        } else {
            Color.clear.onAppear { app.go(.songSelect) }
        }
    }
}

/// Immutable copy of everything the timeline canvas draws (so SwiftUI tracks the right dependencies).
struct TimelineState {
    var notes: [Note]
    var keyCount: Int
    var bpm: Double
    var offset: Double
    var duration: Double
    var viewStart: Double
    var pxPerSec: Double
    var playhead: Double
    var snap: Int
    var laneKeys: [String]
    var tool: EditorTool
    var hover: CGPoint?
    var dragStart: CGPoint?
    var dragNow: CGPoint?
    var pending: [PendingRec]
    var recording: Bool
    var playing: Bool
    var events: [ChartEvent]
    var chartEffects: Bool
}

struct EditorView: View {
    @Environment(AppModel.self) private var app
    @State private var m: EditorModel
    @State private var confirmClear = false
    @State private var mouseInside = false

    init(song: Song) {
        _m = State(initialValue: EditorModel(song: song, settings: SettingsStore.shared.value))
    }

    private var timelineState: TimelineState {
        TimelineState(notes: m.notes, keyCount: m.song.keyCount, bpm: m.song.bpm, offset: m.song.offset, duration: m.song.duration,
                      viewStart: m.viewStart, pxPerSec: m.pxPerSec, playhead: m.playhead, snap: m.snap,
                      laneKeys: m.settings.keys(for: m.song.keyCount).map(\.label), tool: m.tool, hover: m.hover,
                      dragStart: m.dragStart, dragNow: m.dragNow, pending: Array(m.pending.values), recording: m.recording, playing: m.playing,
                      events: m.chart.events, chartEffects: m.settings.chartEffects)
    }

    var body: some View {
        VStack(spacing: 14) {
            topBar
            HStack(alignment: .top, spacing: 16) {
                sidebar.frame(width: 286)
                VStack(spacing: 12) {
                    timeline
                    minimap
                }
            }
        }
        .padding(.horizontal, 28).padding(.top, 30).padding(.bottom, 22)
        .overlay(alignment: .bottom) {
            if let msg = m.message {
                Text(msg).font(UI.font(16)).padding(.horizontal, 18).padding(.vertical, 10)
                    .background(Capsule().fill(.white).overlay(Capsule().stroke(.black, lineWidth: 3.5)))
                    .shadow(color: .black.opacity(0.7), radius: 0, y: 4)
                    .padding(.bottom, 90).transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: m.message)
        .overlay {
            if m.busy {
                ZStack {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    HStack(spacing: 14) { ProgressView(); Text(m.busyText).font(UI.font(20)) }
                        .padding(26).background(RoundedRectangle(cornerRadius: 18).fill(.white).overlay(RoundedRectangle(cornerRadius: 18).stroke(.black, lineWidth: 4)))
                }
            }
        }
        .alert("Clear every note in this chart?", isPresented: $confirmClear) {
            Button("Clear", role: .destructive) { m.clearChart() }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear {
            m.chartIndex = min(app.editorChartIndex, m.song.charts.count - 1)
            m.playhead = app.editorPlayhead
            m.viewStart = max(-0.6, m.playhead - 1)
            installInput()
        }
        .onDisappear { leave(save: true) }
        .onReceive(NotificationCenter.default.publisher(for: .editorUndo)) { _ in m.undo() }
        .onReceive(NotificationCenter.default.publisher(for: .editorRedo)) { _ in m.redo() }
    }

    // MARK: Input

    private func installInput() {
        InputCenter.shared.scrollHandler = { e in
            guard mouseInside else { return false }
            if e.zoom {
                m.zoom(by: 1 + e.deltaY * 0.01, anchorX: e.x)
            } else {
                let d = abs(e.deltaX) > abs(e.deltaY) ? e.deltaX : e.deltaY
                m.scrollBy(dx: d)
            }
            return true
        }
        InputCenter.shared.handler = { ev in
            let keys = m.settings.keys(for: m.song.keyCount)
            if m.recording && m.playing {
                if let lane = keys.firstIndex(where: { $0.code == ev.code }) {
                    if !ev.isRepeat { m.recordKey(lane: lane, down: ev.isDown, code: ev.code, eventTime: ev.time) }
                    return true
                }
                if ev.isDown && !ev.isRepeat {
                    if ev.code == m.settings.slideLeft.code { m.recordSlide(dir: -1, eventTime: ev.time); return true }
                    if ev.code == m.settings.slideRight.code { m.recordSlide(dir: 1, eventTime: ev.time); return true }
                }
            }
            guard ev.isDown else { return false }
            let step = m.spb / Double(m.snap)
            switch ev.code {
            case 49: if !ev.isRepeat { m.togglePlay() }
            case 123: m.seek(m.snapped(m.playhead) - step)
            case 124: m.seek(m.snapped(m.playhead) + step)
            case 115: m.seek(0)
            case 53: if !ev.isRepeat { back() }
            case 15: if !ev.isRepeat { toggleRecord() }
            case 17: if !ev.isRepeat { testPlay() }
            case 18, 19, 20, 21, 23, 22:
                let idx = [18: 0, 19: 1, 20: 2, 21: 3, 23: 4, 22: 5][ev.code]!
                m.tool = EditorTool(rawValue: idx)!
            case 33: m.snapIndex = max(0, m.snapIndex - 1)
            case 30: m.snapIndex = min(EditorModel.snaps.count - 1, m.snapIndex + 1)
            case 27: m.zoom(by: 0.85)
            case 24: m.zoom(by: 1.18)
            default: return false
            }
            return true
        }
    }

    private func leave(save: Bool) {
        m.stopAll()
        if save { m.persist() }
        InputCenter.shared.lockKeys = false
    }

    private func back() {
        AudioManager.shared.play(.back)
        app.editorPlayhead = 0
        app.editorChartIndex = 0
        app.go(.songSelect)
    }

    private func toggleRecord() {
        m.recording.toggle()
        InputCenter.shared.lockKeys = m.recording
        m.flash(m.recording ? "Recording: play the lane keys + slide keys along with the song" : "Recording off")
        if m.recording && !m.playing { m.play() }
    }

    private func testPlay() {
        guard !m.notes.isEmpty else { m.flash("Add some notes first"); return }
        m.stopAll()
        m.persist()
        app.editorPlayhead = m.playhead
        app.editorChartIndex = m.chartIndex
        app.startGame(song: m.song, chartIndex: m.chartIndex, startTime: max(0, m.snapped(m.playhead) - 0.01), fromEditor: true)
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 12) {
            Button { back() } label: { Label("Songs", systemImage: "chevron.left") }.buttonStyle(MDButtonStyle(compact: true))
            VStack(alignment: .leading, spacing: 0) {
                Text(m.song.title).font(UI.font(26)).foregroundStyle(.white).shadow(color: .black, radius: 0, y: 2).lineLimit(1)
                Text("Chart editor · \(m.notes.count) notes").font(UI.font(12, .bold)).foregroundStyle(.white.opacity(0.85))
            }
            Spacer()
            Button { m.persist(); app.exportSong(m.song) } label: { Label("Export", systemImage: "square.and.arrow.up") }
                .buttonStyle(MDButtonStyle(compact: true))
            Button { m.undo() } label: { Image(systemName: "arrow.uturn.backward") }.buttonStyle(MDButtonStyle(compact: true)).disabled(m.undoStack.isEmpty)
            Button { m.redo() } label: { Image(systemName: "arrow.uturn.forward") }.buttonStyle(MDButtonStyle(compact: true)).disabled(m.redoStack.isEmpty)
            Button { m.togglePlay() } label: {
                Label(m.playing ? "Pause" : "Play", systemImage: m.playing ? "pause.fill" : "play.fill").frame(width: 84)
            }.buttonStyle(MDButtonStyle(accent: UI.accent(0.33), compact: true))
            Button { toggleRecord() } label: {
                Label(m.recording ? "Recording" : "Record", systemImage: "circle.fill").foregroundStyle(m.recording ? .red : .black)
            }.buttonStyle(MDButtonStyle(compact: true, selected: m.recording))
            Button { testPlay() } label: { Label("Test Play", systemImage: "gamecontroller.fill") }
                .buttonStyle(MDButtonStyle(accent: UI.accent(0.84), compact: true))
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                card("Tools") {
                    VStack(spacing: 7) {
                        ForEach(EditorTool.allCases, id: \.rawValue) { t in
                            Button { m.tool = t; AudioManager.shared.play(.move) } label: {
                                HStack { Image(systemName: t.icon); Text(t.title); Spacer(); Text("\(t.rawValue + 1)").font(UI.font(12)).foregroundStyle(.black.opacity(0.35)) }
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(MDButtonStyle(compact: true, selected: m.tool == t))
                        }
                    }
                    Text(m.tool.hint).font(UI.font(12, .semibold)).foregroundStyle(.black.opacity(0.5)).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Text("Snap 1/\(m.snap * 4 / 1)".replacingOccurrences(of: "1/\(m.snap * 4)", with: "\(m.snap) per beat")).font(UI.font(13))
                        Spacer()
                        Button { m.snapIndex = max(0, m.snapIndex - 1) } label: { Image(systemName: "minus") }.buttonStyle(MDButtonStyle(compact: true))
                        Button { m.snapIndex = min(EditorModel.snaps.count - 1, m.snapIndex + 1) } label: { Image(systemName: "plus") }.buttonStyle(MDButtonStyle(compact: true))
                    }
                    HStack {
                        Text("Hit sounds").font(UI.font(13)); Spacer(); MDToggle(isOn: $m.hitSounds).scaleEffect(0.8)
                    }
                    HStack {
                        Text("Quantize recording").font(UI.font(13)); Spacer(); MDToggle(isOn: $m.quantizeRec).scaleEffect(0.8)
                    }
                }
                if m.tool == .event {
                    card("Effect") {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                            ForEach(EventKind.allCases) { k in
                                Button { m.eventKind = k; AudioManager.shared.play(.move) } label: {
                                    HStack(spacing: 5) { Image(systemName: k.icon); Text(k.title).lineLimit(1).minimumScaleFactor(0.7) }
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(MDButtonStyle(compact: true, selected: m.eventKind == k))
                            }
                        }
                        if m.eventKind.usesHue {
                            Text("COLOUR").font(UI.font(11)).foregroundStyle(.black.opacity(0.4))
                            MDSlider(value: $m.eventHue, range: 0...1, tint: Color(hue: m.eventHue, saturation: 0.6, brightness: 1))
                        }
                        if m.eventKind.usesDuration {
                            HStack {
                                Text("Length \(Int(m.eventDuration)) s").font(UI.font(13))
                                Spacer()
                                Button { m.eventDuration = max(1, m.eventDuration - 1) } label: { Image(systemName: "minus") }.buttonStyle(MDButtonStyle(compact: true))
                                Button { m.eventDuration = min(30, m.eventDuration + 1) } label: { Image(systemName: "plus") }.buttonStyle(MDButtonStyle(compact: true))
                            }
                        }
                        Text("\(m.chart.events.count) effects in this chart. Scrub or play to preview them over the lanes.")
                            .font(UI.font(12, .semibold)).foregroundStyle(.black.opacity(0.45))
                    }
                }
                card("Chart") {
                    HStack(spacing: 6) {
                        ForEach(Array(m.song.charts.enumerated()), id: \.element.id) { i, c in
                            Button(c.name) { m.chartIndex = i; AudioManager.shared.play(.move) }
                                .buttonStyle(MDButtonStyle(compact: true, selected: m.chartIndex == i))
                        }
                    }
                    field("Name", text: Binding(get: { m.chart.name }, set: { m.chart.name = $0 }))
                    HStack {
                        Button { m.addChart() } label: { Label("Add", systemImage: "plus") }.buttonStyle(MDButtonStyle(compact: true))
                        Button { m.deleteChart() } label: { Label("Delete", systemImage: "trash") }.buttonStyle(MDButtonStyle(compact: true))
                        Button { confirmClear = true } label: { Image(systemName: "xmark.bin") }.buttonStyle(MDButtonStyle(compact: true))
                    }
                    Text("Level \(m.chart.level) · \(m.chart.objectCount) scored objects").font(UI.font(12, .bold)).foregroundStyle(.black.opacity(0.5))
                }
                card("Auto-chart") {
                    HStack(spacing: 6) {
                        ForEach(Diff.allCases, id: \.rawValue) { d in
                            Button(d.name) { m.autoDiff = d }.buttonStyle(MDButtonStyle(compact: true, selected: m.autoDiff == d))
                        }
                    }
                    Button { m.autoGenerate() } label: { Label("Generate from audio", systemImage: "wand.and.stars").frame(maxWidth: .infinity) }
                        .buttonStyle(MDButtonStyle(accent: UI.accent(0.84), compact: true))
                    Text("Replaces this chart's notes using the song's beats. Undo works.").font(UI.font(12, .semibold)).foregroundStyle(.black.opacity(0.45))
                }
                card("Song") {
                    field("Title", text: $m.song.title, submit: { m.persist() })
                    field("Artist", text: $m.song.artist, submit: { m.persist() })
                    HStack(spacing: 10) {
                        numField("BPM", value: $m.song.bpm)
                        numField("Offset (s)", value: $m.song.offset)
                    }
                    HStack(spacing: 6) {
                        Button { m.detectTempo() } label: { Label("Detect", systemImage: "metronome") }.buttonStyle(MDButtonStyle(compact: true))
                        Button { m.setOffsetToPlayhead() } label: { Label("Beat 1 = playhead", systemImage: "scope") }.buttonStyle(MDButtonStyle(compact: true))
                    }
                    Text("KEYS").font(UI.font(11)).foregroundStyle(.black.opacity(0.4))
                    HStack(spacing: 5) {
                        ForEach(GameSettings.songKeyCounts, id: \.self) { k in
                            Button("\(k)") { m.setKeyCount(k) }.buttonStyle(MDButtonStyle(compact: true, selected: m.song.keyCount == k))
                        }
                    }
                }
                Text("Space play · ←/→ step · 1–6 tools · R record · T test · [ ] snap · ⌥-scroll or pinch to zoom")
                    .font(UI.font(11, .semibold)).foregroundStyle(.white.opacity(0.85)).multilineTextAlignment(.center)
            }
            .padding(.bottom, 8)
        }
    }

    private func card(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        Panel(radius: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title.uppercased()).font(UI.font(12)).tracking(1.5).foregroundStyle(.black.opacity(0.45))
                content()
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func field(_ label: String, text: Binding<String>, submit: @escaping () -> Void = {}) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased()).font(UI.font(11)).foregroundStyle(.black.opacity(0.4))
            TextField("", text: text).textFieldStyle(.plain).font(UI.font(15, .bold))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.96)).overlay(RoundedRectangle(cornerRadius: 10).stroke(.black, lineWidth: 2.5)))
                .onSubmit(submit)
        }
    }

    private func numField(_ label: String, value: Binding<Double>) -> some View {
        NumberField(label: label, value: value) { m.persist() }
    }

    // MARK: Timeline

    private var timeline: some View {
        let state = timelineState
        return GeometryReader { geo in
            Canvas { ctx, size in
                EditorDraw.draw(&ctx, size: size, s: state)
            }
            .onAppear { m.canvasSize = geo.size }
            .onChange(of: geo.size) { _, s in m.canvasSize = s }
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in
                    if m.dragStart == nil {
                        m.pointerDown(v.startLocation)
                    }
                    m.pointerMoved(v.location)
                }
                .onEnded { v in m.pointerUp(v.location) })
            .simultaneousGesture(MagnifyGesture().onChanged { v in m.zoom(by: 1 + (v.velocity - 1) * 0.02) })
            .onContinuousHover { phase in
                switch phase {
                case .active(let p): m.hover = p; mouseInside = true
                case .ended: m.hover = nil; mouseInside = false
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.black, lineWidth: 4))
        .shadow(color: .black.opacity(0.28), radius: 0, y: 7)
    }

    private var minimap: some View {
        let notes = m.notes
        let dur = m.song.duration
        let ph = m.playhead
        let vs = m.viewStart
        let vw = (m.canvasSize.width - EditorModel.gutter) / m.pxPerSec
        let n = m.song.keyCount
        return Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.95)))
            let bins = Int(size.width / 3)
            var c = [Int](repeating: 0, count: bins)
            for nt in notes { c[min(bins - 1, max(0, Int(nt.time / dur * Double(bins))))] += 1 }
            let peak = Double(max(3, c.max() ?? 3))
            for (i, v) in c.enumerated() {
                let h = (size.height - 8) * Double(v) / peak
                ctx.fill(Path(CGRect(x: Double(i) * 3, y: size.height - 4 - h, width: 2.2, height: h)), with: .color(Palette.lane(n / 2, of: n).opacity(0.9)))
            }
            let vx = max(0, vs / dur) * size.width
            ctx.fill(Path(roundedRect: CGRect(x: vx, y: 2, width: min(size.width - vx, vw / dur * size.width), height: size.height - 4), cornerRadius: 5),
                     with: .color(.black.opacity(0.12)))
            ctx.stroke(Path(roundedRect: CGRect(x: vx, y: 2, width: min(size.width - vx, vw / dur * size.width), height: size.height - 4), cornerRadius: 5),
                       with: .color(.black.opacity(0.5)), style: StrokeStyle(lineWidth: 2))
            let px = ph / dur * size.width
            ctx.fill(Path(CGRect(x: px - 1.5, y: 0, width: 3, height: size.height)), with: .color(Color(red: 1, green: 0.25, blue: 0.3)))
        }
        .frame(height: 46)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.black, lineWidth: 3.5))
        .overlay(alignment: .trailing) {
            Text("\(formatTime(m.playhead)) / \(formatTime(m.song.duration))").font(UI.font(12)).monospacedDigit()
                .padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(.white.opacity(0.9))).padding(8)
        }
        .gesture(DragGesture(minimumDistance: 0).onChanged { v in
            let t = clamp(v.location.x / max(1, m.canvasSize.width - 286 - 16 - 56), 0, 1) * m.song.duration
            m.seek(t)
            m.viewStart = t - vw * 0.3
        })
    }
}

// MARK: - Timeline drawing

enum EditorDraw {
    static func draw(_ ctx: inout GraphicsContext, size: CGSize, s: TimelineState) {
        let g = EditorModel.gutter, rh = EditorModel.ruler, er = EditorModel.eventRow
        let n = s.keyCount
        let laneH = (size.height - rh - er) / Double(n)
        func X(_ t: Double) -> Double { g + (t - s.viewStart) * s.pxPerSec }
        func T(_ x: Double) -> Double { s.viewStart + (x - g) / s.pxPerSec }
        func Y(_ l: Int) -> Double { rh + er + (Double(l) + 0.5) * laneH }

        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.97)))
        for l in 0..<n {
            let r = CGRect(x: 0, y: rh + er + Double(l) * laneH, width: size.width, height: laneH)
            ctx.fill(Path(r), with: .color(l % 2 == 0 ? Palette.lane(l, of: n).opacity(0.10) : Palette.lane(l, of: n).opacity(0.05)))
        }

        var inner = ctx
        inner.clip(to: Path(CGRect(x: g, y: rh, width: size.width - g, height: size.height - rh)))

        // Grid
        let spb = 60 / max(30, s.bpm)
        let sub = spb / Double(s.snap)
        let t0 = T(g), t1 = T(size.width)
        var k = Int(ceil((t0 - s.offset) / sub))
        let subVisible = sub * s.pxPerSec >= 6
        while true {
            let t = s.offset + Double(k) * sub
            if t > t1 { break }
            let isBeat = k % s.snap == 0
            let beatIdx = k / s.snap
            let isBar = isBeat && ((beatIdx % 4) + 4) % 4 == 0
            if isBar || isBeat || subVisible {
                let x = X(t)
                inner.fill(Path(CGRect(x: x - (isBar ? 1 : 0.5), y: rh, width: isBar ? 2 : 1, height: size.height - rh)),
                           with: .color(.black.opacity(isBar ? 0.5 : (isBeat ? 0.22 : 0.07))))
            }
            k += 1
        }
        // Lane separators
        for l in 0...n {
            let y = rh + er + Double(l) * laneH
            inner.fill(Path(CGRect(x: g, y: y - 0.75, width: size.width, height: 1.5)), with: .color(.black.opacity(0.25)))
        }

        // Notes
        let hh = laneH * 0.62
        for note in s.notes {
            if note.endTime < t0 - 0.5 || note.time > t1 + 0.5 { continue }
            let segs = note.segments(count: n)
            let first = segs.first!.lane
            let col = Palette.lane(first, of: n)
            if !note.isHold {
                let r = CGRect(x: X(note.time) - 11, y: Y(note.lane) - hh / 2, width: 22, height: hh)
                inner.fill(Path(roundedRect: r, cornerRadius: 8), with: .linearGradient(Gradient(colors: [.white, col]), startPoint: CGPoint(x: r.minX, y: r.minY), endPoint: CGPoint(x: r.maxX, y: r.maxY)))
                inner.stroke(Path(roundedRect: r, cornerRadius: 8), with: .color(.black), style: StrokeStyle(lineWidth: 2.5))
            } else {
                for (i, sg) in segs.enumerated() {
                    let c = Palette.lane(sg.lane, of: n)
                    let r = CGRect(x: X(sg.from) - (i == 0 ? 11 : 0), y: Y(sg.lane) - hh * 0.36, width: max(8, X(sg.to) - X(sg.from) + (i == 0 ? 11 : 0)), height: hh * 0.72)
                    inner.fill(Path(roundedRect: r, cornerRadius: 8), with: .color(c.opacity(0.85)))
                    inner.stroke(Path(roundedRect: r, cornerRadius: 8), with: .color(.black), style: StrokeStyle(lineWidth: 2.5))
                }
                // head
                let hr = CGRect(x: X(note.time) - 11, y: Y(note.lane) - hh / 2, width: 22, height: hh)
                inner.fill(Path(roundedRect: hr, cornerRadius: 8), with: .linearGradient(Gradient(colors: [.white, col]), startPoint: CGPoint(x: hr.minX, y: hr.minY), endPoint: CGPoint(x: hr.maxX, y: hr.maxY)))
                inner.stroke(Path(roundedRect: hr, cornerRadius: 8), with: .color(.black), style: StrokeStyle(lineWidth: 2.5))
                // slide connectors
                for (i, sl) in note.slides.enumerated() {
                    let from = segs[i].lane, to = segs[i + 1].lane
                    let x = X(sl.time)
                    var p = Path()
                    p.move(to: CGPoint(x: x, y: Y(from)))
                    p.addLine(to: CGPoint(x: x, y: Y(to)))
                    inner.stroke(p, with: .color(.black), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    inner.stroke(p, with: .color(.white), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    let mid = CGPoint(x: x, y: (Y(from) + Y(to)) / 2)
                    let badge = Path(ellipseIn: CGRect(x: mid.x - 11, y: mid.y - 11, width: 22, height: 22))
                    inner.fill(badge, with: .color(.white))
                    inner.stroke(badge, with: .color(.black), style: StrokeStyle(lineWidth: 2.5))
                    inner.draw(Text(sl.dir < 0 ? "◀" : "▶").font(.system(size: 10, weight: .black)).foregroundColor(.black), at: mid)
                }
            }
        }

        // Pending recordings
        for p in s.pending {
            let w = max(10, X(s.playhead) - X(p.start))
            let r = CGRect(x: X(p.start) - 11, y: Y(p.lane) - hh * 0.36, width: w + 11, height: hh * 0.72)
            inner.fill(Path(roundedRect: r, cornerRadius: 8), with: .color(Color.red.opacity(0.6)))
            inner.stroke(Path(roundedRect: r, cornerRadius: 8), with: .color(.black), style: StrokeStyle(lineWidth: 2.5))
        }

        // Hover ghost / drag preview
        if let h = s.hover, h.x > g, h.y > rh + er, s.dragStart == nil {
            let l = Int((h.y - rh - er) / laneH)
            if l >= 0 && l < n && (s.tool == .tap || s.tool == .hold) {
                let st = s.offset + ((T(h.x) - s.offset) / sub).rounded() * sub
                let r = CGRect(x: X(st) - 11, y: Y(l) - hh / 2, width: 22, height: hh)
                inner.fill(Path(roundedRect: r, cornerRadius: 8), with: .color(Palette.lane(l, of: n).opacity(0.45)))
                inner.stroke(Path(roundedRect: r, cornerRadius: 8), with: .color(.black.opacity(0.5)), style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
            } else if l >= 0 && l < n {
                let x = X(s.offset + ((T(h.x) - s.offset) / sub).rounded() * sub)
                inner.fill(Path(CGRect(x: x - 1, y: Y(l) - laneH / 2, width: 2, height: laneH)), with: .color(.black.opacity(0.4)))
            }
        }
        if s.tool == .hold, let a = s.dragStart, let b = s.dragNow, a.y > rh + er {
            let l = Int((a.y - rh - er) / laneH)
            if l >= 0 && l < n {
                let snap = { (x: Double) in s.offset + ((T(x) - s.offset) / sub).rounded() * sub }
                let x0 = X(min(snap(a.x), snap(b.x))), x1 = X(max(snap(a.x), snap(b.x)))
                let r = CGRect(x: x0 - 11, y: Y(l) - hh * 0.36, width: max(22, x1 - x0 + 22), height: hh * 0.72)
                inner.fill(Path(roundedRect: r, cornerRadius: 8), with: .color(Palette.lane(l, of: n).opacity(0.6)))
                inner.stroke(Path(roundedRect: r, cornerRadius: 8), with: .color(.black.opacity(0.7)), style: StrokeStyle(lineWidth: 2.5, dash: [5, 3]))
            }
        }

        // FX row
        inner.fill(Path(CGRect(x: g, y: rh, width: size.width - g, height: er)), with: .color(Color(red: 0.93, green: 0.88, blue: 0.99)))
        inner.fill(Path(CGRect(x: g, y: rh + er - 1, width: size.width - g, height: 2)), with: .color(.black.opacity(0.35)))
        for e in s.events {
            if e.time > t1 + 0.5 || e.time + e.length < t0 - 0.5 { continue }
            let col = Color(hue: e.hue, saturation: 0.55, brightness: 1)
            let x = X(e.time)
            if e.kind.usesDuration {
                let r = CGRect(x: x, y: rh + 6, width: max(8, e.length * s.pxPerSec), height: er - 12)
                inner.fill(Path(roundedRect: r, cornerRadius: 7), with: .color(col.opacity(0.45)))
                inner.stroke(Path(roundedRect: r, cornerRadius: 7), with: .color(.black.opacity(0.6)), style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
            }
            let chip = CGRect(x: x - 14, y: rh + 3, width: 28, height: er - 6)
            inner.fill(Path(roundedRect: chip, cornerRadius: 9), with: .color(col))
            inner.stroke(Path(roundedRect: chip, cornerRadius: 9), with: .color(.black), style: StrokeStyle(lineWidth: 2.5))
            inner.draw(Image(systemName: e.kind.icon).renderingMode(.template), in: CGRect(x: chip.midX - 7, y: chip.midY - 7, width: 14, height: 14))
        }
        // Live preview of effects at the playhead (works while playing and while scrubbing).
        if s.chartEffects, !s.events.isEmpty {
            var oc = ctx
            let area = CGSize(width: size.width - g, height: size.height - rh - er)
            oc.translateBy(x: g, y: rh + er)
            oc.clip(to: Path(CGRect(origin: .zero, size: area)))
            ChartFX.draw(&oc, size: area, center: CGPoint(x: area.width * 0.5, y: area.height * 0.7), u: 0.6, events: s.events, time: s.playhead)
        }

        // Playhead
        let px = X(s.playhead)
        if px >= g {
            ctx.fill(Path(CGRect(x: px - 1.5, y: 0, width: 3, height: size.height)), with: .color(Color(red: 1, green: 0.25, blue: 0.3)))
        }

        // Ruler
        ctx.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: rh)), with: .color(Color(white: 0.18)))
        var rr = ctx
        rr.clip(to: Path(CGRect(x: g, y: 0, width: size.width - g, height: rh)))
        var kb = Int(ceil((t0 - s.offset) / spb))
        while true {
            let t = s.offset + Double(kb) * spb
            if t > t1 { break }
            let x = X(t)
            let bar = ((kb % 4) + 4) % 4 == 0
            rr.fill(Path(CGRect(x: x - 0.5, y: bar ? 14 : 26, width: 1, height: bar ? rh - 14 : rh - 26)), with: .color(.white.opacity(bar ? 0.9 : 0.4)))
            if bar && s.pxPerSec * spb * 4 > 36 {
                rr.draw(Text("\(kb / 4 + 1)").font(.system(size: 11, weight: .heavy, design: .rounded)).foregroundColor(.white), at: CGPoint(x: x + 4, y: 8), anchor: .leading)
            }
            kb += 1
        }
        if px >= g {
            var tri = Path()
            tri.move(to: CGPoint(x: px - 8, y: 0)); tri.addLine(to: CGPoint(x: px + 8, y: 0)); tri.addLine(to: CGPoint(x: px, y: 14)); tri.closeSubpath()
            ctx.fill(tri, with: .color(Color(red: 1, green: 0.25, blue: 0.3)))
        }

        // Gutter with lane/key labels
        ctx.fill(Path(CGRect(x: 0, y: 0, width: g, height: size.height)), with: .color(Color(white: 0.92)))
        ctx.fill(Path(CGRect(x: g - 2, y: 0, width: 4, height: size.height)), with: .color(.black))
        ctx.draw(Text(formatTime(max(0, s.playhead))).font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundColor(.white), at: CGPoint(x: g / 2, y: rh / 2))
        ctx.fill(Path(CGRect(x: 0, y: 0, width: g - 2, height: rh)), with: .color(Color(white: 0.18)))
        ctx.draw(Text(formatTime(max(0, s.playhead))).font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundColor(.white), at: CGPoint(x: g / 2, y: rh / 2))
        ctx.draw(Text("FX").font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundColor(.black.opacity(0.55)), at: CGPoint(x: g / 2, y: rh + er / 2))
        for l in 0..<n {
            let c = Palette.lane(l, of: n)
            let r = CGRect(x: 10, y: Y(l) - min(18, laneH / 2 - 3), width: g - 24, height: min(36, laneH - 6))
            ctx.fill(Path(roundedRect: r, cornerRadius: 9), with: .color(c))
            ctx.stroke(Path(roundedRect: r, cornerRadius: 9), with: .color(.black), style: StrokeStyle(lineWidth: 3))
            let lab = l < s.laneKeys.count ? s.laneKeys[l] : "\(l + 1)"
            ctx.draw(Text(lab).font(.system(size: lab.count > 2 ? 11 : 16, weight: .heavy, design: .rounded)).foregroundColor(.black), at: CGPoint(x: r.midX, y: r.midY))
        }
        if s.recording {
            ctx.draw(Text("● REC").font(.system(size: 12, weight: .heavy, design: .rounded)).foregroundColor(.red), at: CGPoint(x: g / 2, y: rh + 12))
        }
    }
}

/// Numeric text field without a formatter: invalid keys are silently dropped instead of triggering the system error sound.
struct NumberField: View {
    let label: String
    @Binding var value: Double
    var onCommit: () -> Void
    @State private var text = ""

    private static func format(_ v: Double) -> String {
        var s = String(format: "%.3f", v)
        while s.contains(".") && (s.hasSuffix("0") || s.hasSuffix(".")) { s.removeLast() }
        return s.isEmpty ? "0" : s
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased()).font(UI.font(11)).foregroundStyle(.black.opacity(0.4))
            TextField("", text: $text)
                .textFieldStyle(.plain).font(UI.font(15, .bold))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.96)).overlay(RoundedRectangle(cornerRadius: 10).stroke(.black, lineWidth: 2.5)))
                .onSubmit { text = Self.format(value); onCommit() }     // tidy what's shown once it's committed
                .onChange(of: text) { _, t in
                    let clean = t.filter { "0123456789.-".contains($0) }
                    if clean != t { text = clean; return }
                    if let v = Double(clean), v != value { value = v }
                }
                .onChange(of: value) { _, v in
                    if Double(text) != v { text = Self.format(v) }
                }
                .onAppear { text = Self.format(value) }
        }
    }
}
