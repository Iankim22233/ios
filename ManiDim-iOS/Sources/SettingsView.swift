import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    enum Tab: String, CaseIterable { case gameplay = "Gameplay", audio = "Audio", visuals = "Visuals" }
    enum Target: Equatable { case lane(Int), slideLeft, slideRight }

    @State private var tab: Tab = .gameplay
    @State private var keyCount = 4
    @State private var rebinding: Target?
    @State private var pressed = Set<UInt16>()
    @State private var showCalibration = false
    @State private var appeared = false

    var body: some View {
        @Bindable var store = app.settingsStore
        ZStack {
            VStack(spacing: 18) {
                ScreenHeader(title: "Settings", subtitle: "Changes are saved automatically", onBack: { app.go(.home) })
                HStack(alignment: .top, spacing: 24) {
                    VStack(spacing: 12) {
                        ForEach(Tab.allCases, id: \.self) { t in
                            Button { tab = t; rebinding = nil; AudioManager.shared.play(.move) } label: {
                                HStack { Image(systemName: icon(t)); Text(t.rawValue); Spacer() }
                                    .frame(width: 170)
                            }
                            .buttonStyle(MDButtonStyle(selected: tab == t))
                        }
                        Spacer()
                    }
                    Panel(radius: 28) {
                        ScrollView(showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 26) {
                                switch tab {
                                case .gameplay: gameplay(store)
                                case .audio: audio(store)
                                case .visuals: visuals(store)
                                }
                            }
                            .padding(30)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .frame(maxWidth: 900)
                }
            }
            .padding(.horizontal, 44).padding(.top, 38).padding(.bottom, 34)
            .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 24)

            if showCalibration {
                CalibrationView { showCalibration = false }
                    .transition(.opacity)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) { appeared = true }
        }
    }

    private func icon(_ t: Tab) -> String {
        switch t {
        case .gameplay: return "gamecontroller"
        case .audio: return "speaker.wave.2"
        case .visuals: return "paintpalette"
        }
    }

    // MARK: Tabs

    @ViewBuilder private func gameplay(_ store: SettingsStore) -> some View {
        @Bindable var s = store
        section("Note speed", "How fast notes travel from the edge of the screen to the circle.") {
            HStack(spacing: 16) {
                MDSlider(value: $s.value.scrollSpeed, range: 3...14, step: 0.5)
                Text(String(format: "%.1f", s.value.scrollSpeed)).font(UI.font(24)).monospacedDigit().frame(width: 60)
            }
            Text(String(format: "About %.1f seconds of warning on a 1080p screen.", 760.0 / (s.value.scrollSpeed * 62 * 1.35)))
                .font(UI.font(13, .semibold)).foregroundStyle(.black.opacity(0.45))
        }
        section("Audio offset", "If notes feel late (you keep hitting after the beat) raise it; if early, lower it.") {
            HStack(spacing: 16) {
                MDSlider(value: $s.value.audioOffsetMs, range: -150...250, step: 1, tint: UI.accent(0.84))
                Text(String(format: "%+.0f ms", s.value.audioOffsetMs)).font(UI.font(22)).monospacedDigit().frame(width: 100)
            }
            Button { showCalibration = true; AudioManager.shared.play(.select) } label: { Label("Calibrate by tapping along", systemImage: "metronome") }
                .buttonStyle(MDButtonStyle(compact: true))
        }
        section("Assist", nil) {
            toggleRow("Hit sounds", "Play a tick for every note you hit.", $s.value.hitSounds)
            toggleRow("Autoplay", "Let the game play for you (scores aren't saved).", $s.value.autoplay)
        }
    }

    @ViewBuilder private func audio(_ store: SettingsStore) -> some View {
        @Bindable var s = store
        section("Music volume", nil) {
            HStack(spacing: 16) {
                MDSlider(value: $s.value.musicVolume, range: 0...1, tint: UI.accent(0.33))
                Text("\(Int(s.value.musicVolume * 100))%").font(UI.font(22)).monospacedDigit().frame(width: 70)
            }
        }
        section("Effects volume", nil) {
            HStack(spacing: 16) {
                MDSlider(value: $s.value.sfxVolume, range: 0...1, tint: UI.accent(0.13))
                Text("\(Int(s.value.sfxVolume * 100))%").font(UI.font(22)).monospacedDigit().frame(width: 70)
            }
            HStack(spacing: 10) {
                ForEach([("Tap", SFX.tap), ("Hold", .hold), ("Slide", .slide), ("Miss", .miss)], id: \.0) { n, sfx in
                    Button(n) { AudioManager.shared.play(sfx) }.buttonStyle(MDButtonStyle(compact: true))
                }
            }
        }
    }

    @ViewBuilder private func visuals(_ store: SettingsStore) -> some View {
        @Bindable var s = store
        section("Style", "Same game, different look. (The vertical Classic layout is now an Easy mod — pick it under Mods.)") {
            HStack(spacing: 16) {
                ForEach(Skin.allCases.filter { $0 != .classic }) { k in
                    Button { s.value.skin = k; AudioManager.shared.play(.move) } label: {
                        VStack(spacing: 8) {
                            SkinPreview(skin: k, background: s.value.background)
                                .frame(width: 168, height: 108)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.black, lineWidth: s.value.skin == k ? 5 : 3))
                                .shadow(color: .black.opacity(s.value.skin == k ? 0.8 : 0), radius: 0, y: 5)
                            Text(k.title).font(UI.font(16))
                            Text(k.blurb).font(UI.font(11, .semibold)).foregroundStyle(.black.opacity(0.5))
                        }
                    }
                    .buttonStyle(PressFeedbackStyle())
                }
            }
        }
        section("Background", "Pick a colour, a gradient, or your own image. It shows behind the game and the menus.") {
            HStack(spacing: 8) {
                ForEach([("Style default", BackgroundSetting.Mode.skin), ("Presets", .preset), ("Custom colours", .custom), ("Image", .image)], id: \.0) { title, mode in
                    Button(title) { s.value.background.mode = mode; AudioManager.shared.play(.move) }
                        .buttonStyle(MDButtonStyle(compact: true, selected: s.value.background.mode == mode))
                }
            }
            switch s.value.background.mode {
            case .skin:
                Text("Each style brings its own backdrop: grey for Original, flat grey for High Contrast, black for Classic.")
                    .font(UI.font(13, .semibold)).foregroundStyle(.black.opacity(0.5))
            case .preset:
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(96), spacing: 12), count: 4), alignment: .leading, spacing: 12) {
                    ForEach(BackgroundSetting.presets, id: \.id) { p in
                        Button { s.value.background.preset = p.id; AudioManager.shared.play(.move) } label: {
                            VStack(spacing: 5) {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(LinearGradient(colors: [p.top.color, p.bottom.color], startPoint: .top, endPoint: .bottom))
                                    .frame(width: 96, height: 54)
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(.black, lineWidth: s.value.background.preset == p.id ? 5 : 3))
                                Text(p.name).font(UI.font(12))
                            }
                        }
                        .buttonStyle(PressFeedbackStyle())
                    }
                }
            case .custom:
                HStack(spacing: 22) {
                    colorPicker("Top", Binding(get: { s.value.background.top.color }, set: { s.value.background.top = RGBA(color: $0) }))
                    colorPicker("Bottom", Binding(get: { s.value.background.bottom.color }, set: { s.value.background.bottom = RGBA(color: $0) }))
                    Button("Same colour") { s.value.background.bottom = s.value.background.top }.buttonStyle(MDButtonStyle(compact: true))
                }
            case .image:
                HStack(spacing: 16) {
                    Group {
                        if let img = BackgroundImages.image(named: s.value.background.imageFile) {
                            Image(uiImage: img).resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Color(white: 0.9).overlay(Image(systemName: "photo").font(.system(size: 26, weight: .bold)).foregroundStyle(.black.opacity(0.35)))
                        }
                    }
                    .frame(width: 160, height: 90).clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(.black, lineWidth: 3))
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Button { pickBackgroundImage(store) } label: { Label("Choose image…", systemImage: "photo.on.rectangle") }
                                .buttonStyle(MDButtonStyle(accent: UI.accent(0.55), compact: true))
                            if s.value.background.imageFile != nil {
                                Button("Remove") {
                                    if let f = s.value.background.imageFile { try? FileManager.default.removeItem(at: AppPaths.support.appendingPathComponent(f)) }
                                    s.value.background.imageFile = nil
                                    s.value.background.mode = .skin
                                }.buttonStyle(MDButtonStyle(compact: true))
                            }
                        }
                        HStack(spacing: 12) {
                            Text("Dim").font(UI.font(14))
                            MDSlider(value: $s.value.background.dim, range: 0...0.9, tint: UI.accent(0.13)).frame(width: 220)
                            Text("\(Int(s.value.background.dim * 100))%").font(UI.font(14)).monospacedDigit()
                        }
                    }
                }
            }
        }
        section("Effects", nil) {
            toggleRow("Particles", "Sparks and bursts on every hit.", $s.value.particles)
            toggleRow("Screen shake", "A small jolt when you miss.", $s.value.screenShake)
            toggleRow("Beat pulse", "The circle and lights breathe with the music.", $s.value.beatPulse)
            toggleRow("Chart effects", "Sparkles, flashes, fireworks and lasers placed in a chart. Turn off if flashing bothers you.", $s.value.chartEffects)
            toggleRow("Show FPS", nil, $s.value.showFPS)
        }
    }

    private func colorPicker(_ label: String, _ binding: Binding<Color>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(UI.font(11)).foregroundStyle(.black.opacity(0.4))
            ColorPicker("", selection: binding, supportsOpacity: false).labelsHidden().scaleEffect(1.25, anchor: .leading)
        }
    }

    private func pickBackgroundImage(_ store: SettingsStore) {
        FilePicker.open(types: [.image]) { url in
            guard let url else { return }
            if let name = try? BackgroundImages.importImage(from: url, replacing: store.value.background.imageFile) {
                store.value.background.imageFile = name
                store.value.background.mode = .image
            } else {
                app.showToast("Couldn't use that image")
            }
        }
    }

    // MARK: Pieces

    private func section(_ title: String, _ subtitle: String?, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(UI.font(22))
                if let s = subtitle { Text(s).font(UI.font(13, .semibold)).foregroundStyle(.black.opacity(0.5)) }
            }
            content()
        }
    }

    private func toggleRow(_ title: String, _ sub: String?, _ binding: Binding<Bool>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(UI.font(17))
                if let s = sub { Text(s).font(UI.font(12, .semibold)).foregroundStyle(.black.opacity(0.45)) }
            }
            Spacer()
            MDToggle(isOn: binding)
        }
    }
}

// MARK: - Calibration

struct CalibrationView: View {
    @Environment(AppModel.self) private var app
    var onClose: () -> Void

    @State private var running = false
    @State private var deltas: [Double] = []
    @State private var finished = false
    @State private var flash = 0.0
    @State private var beatIndex = 0
    @State private var startHost = 0.0
    @State private var timer: Timer?
    private let interval = 0.6
    private let total = 14

    private var median: Double? {
        let d = deltas.sorted()
        guard d.count >= 5 else { return nil }
        return d[d.count / 2] * 1000
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            Panel(radius: 28) {
                VStack(spacing: 18) {
                    Text("Calibration").font(UI.font(36))
                    Text("Tap the circle exactly on each click. Ignore the first couple while you find the rhythm. Run this with the same headphones or speaker you play with.")
                        .font(UI.font(15, .semibold)).multilineTextAlignment(.center).foregroundStyle(.black.opacity(0.6))
                        .frame(width: 440)
                    ZStack {
                        Circle().fill(running ? UI.accent(0.13).opacity(0.5 + flash * 0.5) : Color(white: 0.92))
                            .overlay(Circle().stroke(.black, lineWidth: 5))
                            .frame(width: 150, height: 150)
                            .scaleEffect(1 + flash * 0.15)
                        Text(running ? "\(min(beatIndex, total))/\(total)" : (finished ? "done" : "ready"))
                            .font(UI.font(24)).monospacedDigit()
                    }
                    .frame(width: 260, height: 190)
                    .overlay { TapCatcher { ts in registerTap(ts) } }
                    if finished {
                        if let m = median {
                            Text(String(format: "Suggested offset: %+.0f ms", m)).font(UI.font(24))
                            HStack {
                                Button("Apply") {
                                    app.settingsStore.value.audioOffsetMs = clamp(m.rounded(), -150, 250)
                                    AudioManager.shared.play(.select)
                                    onClose()
                                }.buttonStyle(MDButtonStyle(accent: UI.accent(0.33)))
                                Button("Try again") { start() }.buttonStyle(MDButtonStyle())
                            }
                        } else {
                            Text("Not enough taps — try again.").font(UI.font(18))
                            Button("Try again") { start() }.buttonStyle(MDButtonStyle())
                        }
                    } else if !running {
                        Button("Start") { start() }.buttonStyle(MDButtonStyle(accent: UI.accent(0.33)))
                    }
                    Button("Close") { stop(); onClose() }.buttonStyle(MDButtonStyle(compact: true))
                }
                .padding(34)
            }
            .fixedSize()
        }
        .onDisappear { stop() }
    }

    private func start() {
        stop()
        deltas = []
        finished = false
        running = true
        beatIndex = 0
        let audio = AudioManager.shared
        audio.stop()
        startHost = Clock.hostNow() + 0.8
        for i in 0..<total { audio.schedule(.metronome, atHost: startHost + Double(i) * interval, volume: 1.2) }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { _ in
            let t = Clock.hostNow() - startHost
            beatIndex = max(0, Int(floor(t / interval)) + 1)
            let phase = t.truncatingRemainder(dividingBy: interval) / interval
            flash = t >= 0 ? max(0, 1 - phase * 5) : 0
            if t > Double(total) * interval { stop(); finished = true }
        }
    }

    private func registerTap(_ ts: Double) {
        guard running else { return }
        let t = Clock.fromEvent(ts) - startHost
        let i = Int((t / interval).rounded())
        let d = t - Double(i) * interval
        if i >= 2, i < total, abs(d) < 0.25 { deltas.append(d) }
    }

    private func stop() {
        timer?.invalidate(); timer = nil
        running = false
        flash = 0
        AudioManager.shared.stopSFX()
    }
}

/// Little thumbnail of a skin on the current background.
struct SkinPreview: View {
    let skin: Skin
    let background: BackgroundSetting
    var body: some View {
        let spec = background.spec(for: skin)
        ZStack {
            if let img = spec.image {
                Image(uiImage: img).resizable().aspectRatio(contentMode: .fill)
                Color.black.opacity(spec.dim)
            } else {
                LinearGradient(colors: [spec.top, spec.bottom], startPoint: .top, endPoint: .bottom)
            }
            switch skin {
            case .original: FanIcon(lanes: 4).padding(8)
            case .highContrast: FanIcon(lanes: 4, inverted: true).padding(8)
            case .classic: ClassicIcon().padding(.vertical, 6)
            }
        }
    }
}

struct ClassicIcon: View {
    var body: some View {
        Canvas { ctx, size in
            let n = 4
            let lw = size.width * 0.15
            let x0 = (size.width - lw * Double(n)) / 2
            ctx.fill(Path(CGRect(x: x0, y: 0, width: lw * Double(n), height: size.height)), with: .color(.black.opacity(0.92)))
            for i in 0...n {
                ctx.fill(Path(CGRect(x: x0 + lw * Double(i) - 0.8, y: 0, width: 1.6, height: size.height)), with: .color(i == 0 || i == n ? Color(white: 0.5) : .white.opacity(0.8)))
            }
            let hy = size.height * 0.72
            for (i, y) in [0.18, 0.42, 0.3, 0.55].enumerated() {
                let r = CGRect(x: x0 + lw * Double(i) + 3, y: size.height * y, width: lw - 6, height: 9)
                ctx.fill(Path(roundedRect: r, cornerRadius: 4), with: .color(Palette.lane(i, of: n)))
            }
            ctx.fill(Path(CGRect(x: x0, y: hy - 3, width: lw * Double(n), height: 6)), with: .color(Color(red: 0.5, green: 0.6, blue: 0.78)))
            for i in 0..<n {
                let light = min(i, n - 1 - i) % 2 == 0
                ctx.fill(Path(CGRect(x: x0 + lw * Double(i) + 1, y: hy + 3, width: lw - 2, height: size.height - hy)),
                         with: .color(light ? Color(red: 0.86, green: 0.76, blue: 0.9) : Color(red: 0.76, green: 0.33, blue: 0.58)))
            }
        }
    }
}
