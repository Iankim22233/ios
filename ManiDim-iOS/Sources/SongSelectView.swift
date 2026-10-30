import SwiftUI

struct SongSelectView: View {
    @Environment(AppModel.self) private var app
    @State private var previewTask: Task<Void, Never>?
    @State private var confirmDelete = false
    @State private var appeared = false
    @State private var expanded: Set<String> = []

    private var songs: [Song] { app.library.songs }
    private var song: Song? { app.library.song(id: app.selectedSongID) ?? songs.first }
    private var chartIndex: Int { min(app.selectedChart, max(0, (song?.charts.count ?? 1) - 1)) }

    var body: some View {
        VStack(spacing: 18) {
            ScreenHeader(title: "Songs", subtitle: "\(songs.count) tracks", onBack: { app.go(.home) },
                         trailing: AnyView(
                            HStack(spacing: 12) {
                                Button { app.pickAndImport() } label: { Label("Import", systemImage: "square.and.arrow.down") }
                                    .buttonStyle(MDButtonStyle(compact: true))
                                Button { app.showNewSong = true } label: { Label("New Song", systemImage: "plus") }
                                    .buttonStyle(MDButtonStyle(accent: UI.accent(0.84), compact: true))
                            }))
            HStack(alignment: .top, spacing: 26) {
                list.frame(width: 470)
                if let s = song { detail(s) }
            }
        }
        .padding(.horizontal, 44)
        .padding(.top, 38)
        .padding(.bottom, 34)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 24)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) { appeared = true }
            if let id = song?.id { expanded = [id] }
            schedulePreview()
            InputCenter.shared.handler = { ev in handleKey(ev) }
        }
        .onDisappear {
            previewTask?.cancel()
            AudioManager.shared.stopPreview()
        }
        .onChange(of: app.selectedSongID) { _, id in
            if let id { withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { expanded = [id] } }
            app.selectedChart = min(app.selectedChart, max(0, (song?.charts.count ?? 1) - 1))
            schedulePreview()
        }
        .alert("Delete this song?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                if let s = song {
                    let idx = songs.firstIndex(where: { $0.id == s.id }) ?? 0
                    app.library.delete(s)
                    app.selectedSongID = app.library.songs[max(0, min(idx - 1, app.library.songs.count - 1))].id
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("The chart and its audio will be removed from this device.") }
    }

    // MARK: Keyboard

    private func handleKey(_ ev: KeyEvent) -> Bool {
        guard ev.isDown else { return true }
        switch ev.code {
        case 126: move(-1)
        case 125: move(1)
        case 123: if let s = song { app.selectedChart = max(0, chartIndex - 1); _ = s; AudioManager.shared.play(.move) }
        case 124: if let s = song { app.selectedChart = min(s.charts.count - 1, chartIndex + 1); AudioManager.shared.play(.move) }
        case 36, 76: play()
        case 46: app.showMods = true; AudioManager.shared.play(.select)
        case 53: app.go(.home); AudioManager.shared.play(.back)
        default: return false
        }
        return true
    }

    private func move(_ d: Int) {
        guard let cur = songs.firstIndex(where: { $0.id == song?.id }) else { return }
        let n = (cur + d + songs.count) % songs.count
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { app.selectedSongID = songs[n].id }
        AudioManager.shared.play(.move)
    }

    private func play() {
        guard let s = song, !s.charts.isEmpty else { return }
        AudioManager.shared.play(.select)
        app.startGame(song: s, chartIndex: chartIndex)
    }

    private func schedulePreview() {
        previewTask?.cancel()
        guard let s = song else { return }
        previewTask = Task {
            try? await Task.sleep(nanoseconds: 380_000_000)
            if Task.isCancelled { return }
            var url: URL?
            if let k = s.builtinKey { url = await BuiltinSongs.ensureAudio(key: k) } else { url = app.library.audioURL(for: s) }
            if Task.isCancelled || app.screen != .songSelect { return }
            if let u = url, FileManager.default.fileExists(atPath: u.path) {
                AudioManager.shared.applyVolumes(app.settings)
                AudioManager.shared.playPreview(url: u, from: s.duration * 0.28)
            }
        }
    }

    // MARK: List

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 14) {
                    let builtin = songs.filter(\.isBuiltin)
                    let custom = songs.filter { !$0.isBuiltin }
                    sectionLabel("Built-in")
                    ForEach(builtin) { s in card(s) }
                    sectionLabel("Your songs")
                    if custom.isEmpty {
                        Panel(radius: 16, fill: Color.white.opacity(0.35), shadow: false) {
                            VStack(spacing: 8) {
                                Text("Nothing here yet").font(UI.font(18)).foregroundStyle(.white)
                                Text("Press New Song to import a track and chart it, or remix a built-in song.")
                                    .font(UI.font(14, .semibold)).foregroundStyle(.white.opacity(0.85)).multilineTextAlignment(.center)
                            }
                            .padding(18).frame(maxWidth: .infinity)
                        }
                    }
                    ForEach(custom) { s in card(s) }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .onChange(of: app.selectedSongID) { _, id in
                if let id { withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(id, anchor: .center) } }
            }
        }
    }

    private func sectionLabel(_ t: String) -> some View {
        Text(t.uppercased()).font(UI.font(13)).tracking(2).foregroundStyle(.white.opacity(0.85))
            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6).padding(.leading, 6)
    }

    private func card(_ s: Song) -> some View {
        let selected = s.id == song?.id
        let open = expanded.contains(s.id)
        let n = s.charts.count
        return VStack(spacing: 8) {
            Button {
                if selected { play() } else { withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { app.selectedSongID = s.id }; AudioManager.shared.play(.move) }
            } label: {
                HStack(spacing: 14) {
                    FanIcon(lanes: s.keyCount, hue: s.hue)
                        .frame(width: 70, height: 70)
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 14).fill(UI.accent(s.hue)).overlay(RoundedRectangle(cornerRadius: 14).stroke(.black, lineWidth: 3.5)))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(s.title).font(UI.font(21)).lineLimit(1)
                        HStack(spacing: 6) {
                            Text(s.artist).font(UI.font(14, .semibold)).foregroundStyle(.black.opacity(0.55)).lineLimit(1)
                            if s.source == "osz" { pill("OSZ IMPORTED", fill: UI.accent(0.55)).fixedSize() }
                        }
                        HStack(spacing: 6) {
                            pill("\(Int(s.bpm.rounded())) BPM")
                            pill(s.keysLabel)
                            pill(formatTime(s.duration))
                            if !s.isBuiltin && s.source == nil { pill("CUSTOM", fill: UI.accent(0.84)) }
                        }
                    }
                    Spacer(minLength: 0)
                    VStack(spacing: 4) {
                        Text("\(n) beatmap\(n == 1 ? "" : "s")").font(UI.font(14)).lineLimit(1).minimumScaleFactor(0.7)
                        Image(systemName: "chevron.down").font(.system(size: 22, weight: .black))
                            .rotationEffect(.degrees(open ? 180 : 0))
                    }
                    .frame(width: 100)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        AudioManager.shared.play(.move)
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            if open { expanded.remove(s.id) } else { expanded.insert(s.id) }
                        }
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(selected ? Color.white : Color.white.opacity(0.88))
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.black, lineWidth: UI.line))
                        .shadow(color: .black.opacity(0.85), radius: 0, x: 0, y: selected ? 8 : 4)
                )
            }
            .buttonStyle(PressFeedbackStyle())

            if open {
                VStack(spacing: 8) {
                    ForEach(Array(s.charts.enumerated()), id: \.element.id) { i, c in chartRow(s, i, c, songSelected: selected) }
                }
                .padding(.leading, 26)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .offset(x: selected ? -8 : 0)
        .scaleEffect(selected ? 1.02 : 1)
        .id(s.id)
        .animation(.spring(response: 0.35, dampingFraction: 0.72), value: selected)
    }

    private func chartRow(_ s: Song, _ i: Int, _ c: Chart, songSelected: Bool) -> some View {
        let sel = songSelected && i == chartIndex
        let best = ScoreStore.shared.best(s.id, c.name)
        return Button {
            if sel { play() } else {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { app.selectedSongID = s.id; app.selectedChart = i }
                AudioManager.shared.play(.move)
            }
        } label: {
            HStack(spacing: 10) {
                Circle().fill(diffColor(i, s.charts.count)).frame(width: 18, height: 18).overlay(Circle().stroke(.black, lineWidth: 2.5))
                Text(c.name).font(UI.font(17)).lineLimit(1)
                Text("Lv. \(c.level)").font(UI.font(12, .bold)).foregroundStyle(.black.opacity(0.55))
                if s.mixedKeys { pill("\(c.keys ?? s.keyCount)K") }
                Spacer(minLength: 0)
                Text(best.map { "\($0.grade)  \($0.score)" } ?? "—").font(UI.font(12, .bold)).monospacedDigit().foregroundStyle(.black.opacity(0.5))
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(sel ? diffColor(i, s.charts.count) : Color.white.opacity(0.9))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.black, lineWidth: sel ? 3.5 : 2.5))
                .shadow(color: .black.opacity(0.8), radius: 0, x: 0, y: sel ? 4 : 2))
        }
        .buttonStyle(PressFeedbackStyle())
    }

    private func pill(_ t: String, fill: Color = Color(white: 0.92)) -> some View {
        Text(t).font(UI.font(11)).lineLimit(1).fixedSize().padding(.horizontal, 7).padding(.vertical, 2.5)
            .background(Capsule().fill(fill).overlay(Capsule().stroke(.black, lineWidth: 2)))
    }

    // MARK: Detail

    private func detail(_ s: Song) -> some View {
        let chart = s.charts.isEmpty ? nil : s.charts[chartIndex]
        let keys = s.keys(chartIndex)
        return VStack(spacing: 18) {
            Panel(radius: 28) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.title).font(.system(size: 44, weight: .black, design: .rounded)).lineLimit(1).minimumScaleFactor(0.6)
                            Text(s.artist).font(UI.font(20, .bold)).foregroundStyle(.black.opacity(0.55))
                        }
                        Spacer()
                        FanIcon(lanes: keys, hue: s.hue, animate: true).frame(width: 96, height: 96)
                    }
                    if let c = chart {
                        DensityGraph(chart: c, keyCount: keys, duration: s.duration)
                            .frame(height: 96)
                            .id(c.id)
                        stats(s, c)
                    }
                    difficulty(s)
                }
                .padding(26)
            }
            HStack(spacing: 14) {
                Button(action: play) {
                    HStack { Image(systemName: "play.fill"); Text("PLAY").tracking(3) }
                        .font(UI.font(30)).frame(maxWidth: .infinity)
                }
                .buttonStyle(MDButtonStyle(accent: UI.accent(0.33)))
                .disabled(s.charts.isEmpty)

                Button { app.showMods = true; AudioManager.shared.play(.select) } label: {
                    VStack(spacing: 0) {
                        Text("MODS").font(UI.font(18)).tracking(2)
                        let ms = app.settings.modSet
                        Text(ms.isEmpty ? "none" : "\(ms.label)  ×" + String(format: "%.2f", ms.multiplier(origKeys: keys)))
                            .font(UI.font(11, .bold)).foregroundStyle(.black.opacity(0.6)).lineLimit(1)
                    }
                    .frame(width: 150, height: 44)
                }
                .buttonStyle(MDButtonStyle(accent: app.settings.modSet.isEmpty ? nil : UI.accent(0.13)))

                VStack(alignment: .leading, spacing: 6) {
                    Text("AUTOPLAY").font(UI.font(11)).foregroundStyle(.white.opacity(0.9))
                    @Bindable var st = app.settingsStore
                    MDToggle(isOn: $st.value.autoplay)
                }
                .padding(.horizontal, 6)
            }
            HStack(spacing: 12) {
                Button { app.exportSong(s) } label: { Label("Export", systemImage: "square.and.arrow.up") }
                    .buttonStyle(MDButtonStyle(compact: true))
                if s.isBuiltin {
                    Button { remix(s) } label: { Label("Remix in Editor", systemImage: "square.and.pencil") }
                        .buttonStyle(MDButtonStyle(compact: true))
                } else {
                    Button { app.editorSongID = s.id; app.go(.editor) } label: { Label("Edit Chart", systemImage: "square.and.pencil") }
                        .buttonStyle(MDButtonStyle(accent: UI.accent(0.84), compact: true))
                        .disabled(s.mixedKeys)      // the editor works on one key count per song
                        .opacity(s.mixedKeys ? 0.45 : 1)
                        .help(s.mixedKeys ? "This song mixes key counts (imported beatmap set), which the editor can't edit." : "")
                    Button { confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
                        .buttonStyle(MDButtonStyle(compact: true))
                }
                Spacer()
            }
            Spacer(minLength: 0)
        }
    }

    private func stats(_ s: Song, _ c: Chart) -> some View {
        let holds = c.notes.filter(\.isHold).count
        let slides = c.notes.reduce(0) { $0 + $1.slides.count }
        return HStack(spacing: 10) {
            stat("NOTES", "\(c.notes.count)")
            stat("HOLDS", "\(holds)")
            stat("SLIDES", "\(slides)")
            stat("LENGTH", formatTime(s.duration))
            stat("BPM", "\(Int(s.bpm.rounded()))")
            stat("KEYS", "\(s.keys(chartIndex))")
        }
    }

    private func stat(_ k: String, _ v: String) -> some View {
        VStack(spacing: 2) {
            Text(v).font(UI.font(22)).monospacedDigit()
            Text(k).font(UI.font(10)).foregroundStyle(.black.opacity(0.45))
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.95)).overlay(RoundedRectangle(cornerRadius: 12).stroke(.black, lineWidth: 2.5)))
    }

    private func difficulty(_ s: Song) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: s.charts.count > 6 ? 6 : 12) {
                ForEach(Array(s.charts.enumerated()), id: \.element.id) { i, c in
                    let sel = i == chartIndex
                    let best = ScoreStore.shared.best(s.id, c.name)
                    Button { app.selectedChart = i; AudioManager.shared.play(.move) } label: {
                        VStack(spacing: 2) {
                            Text(c.name).font(UI.font(18)).lineLimit(1).minimumScaleFactor(0.45)
                            Text(s.mixedKeys ? "\(c.keys ?? s.keyCount)K · Lv. \(c.level)" : "Lv. \(c.level)").font(UI.font(13, .bold)).foregroundStyle(.black.opacity(0.6)).lineLimit(1).minimumScaleFactor(0.6)
                            Text(best.map { "\($0.grade)  \($0.score)" } ?? "—").font(UI.font(12, .bold)).monospacedDigit().foregroundStyle(.black.opacity(0.5))
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 10).padding(.horizontal, 3)
                        .background(RoundedRectangle(cornerRadius: 14)
                            .fill(sel ? diffColor(i, s.charts.count) : Color(white: 0.96))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.black, lineWidth: sel ? 4 : 2.5))
                            .shadow(color: .black.opacity(sel ? 0.8 : 0), radius: 0, x: 0, y: 4))
                        .offset(y: sel ? -3 : 0)
                    }
                    .buttonStyle(PressFeedbackStyle())
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: sel)
                }
            }
        }
    }

    private func diffColor(_ i: Int, _ n: Int) -> Color {
        let t = n <= 1 ? 0.5 : Double(i) / Double(n - 1)
        return Color(hue: 0.38 - 0.38 * t, saturation: 0.55, brightness: 1)
    }

    private func remix(_ s: Song) {
        Task {
            guard let k = s.builtinKey, let src = await BuiltinSongs.ensureAudio(key: k) else { return }
            var copy = s
            copy.id = "custom." + UUID().uuidString.prefix(8)
            copy.title = s.title + " (Remix)"
            copy.builtinKey = nil
            copy.audioFile = "audio.wav"
            copy.charts = s.charts.map { c in var n = c; n.id = UUID(); return n }
            let dest = AppPaths.songDir(copy.id).appendingPathComponent("audio.wav")
            try? FileManager.default.copyItem(at: src, to: dest)
            app.library.save(copy)
            app.editorSongID = copy.id
            app.go(.editor)
        }
    }
}

struct DensityGraph: View {
    let chart: Chart
    let keyCount: Int
    let duration: Double
    var body: some View {
        Canvas { ctx, size in
            let bins = Int(max(1, duration / 1.0))
            var counts = [[Int]](repeating: [Int](repeating: 0, count: keyCount), count: bins)
            for n in chart.notes {
                let b = min(bins - 1, max(0, Int(n.time)))
                counts[b][min(n.lane, keyCount - 1)] += 1
                if n.isHold { for k in b...min(bins - 1, Int(n.endTime)) where k != b { counts[k][min(n.lane, keyCount - 1)] += 0 } }
            }
            let w = size.width / Double(bins)
            let peak = Double(max(4, counts.map { $0.reduce(0, +) }.max() ?? 4))
            for (i, row) in counts.enumerated() {
                var y = size.height
                for (l, c) in row.enumerated() where c > 0 {
                    let h = (size.height - 4) * Double(c) / peak 
                    ctx.fill(Path(roundedRect: CGRect(x: Double(i) * w + 0.5, y: y - h, width: max(1, w - 1), height: h), cornerRadius: 1.5),
                             with: .color(Palette.lane(l, of: keyCount)))
                    y -= h
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.94)))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.black, lineWidth: 3))
    }
}
