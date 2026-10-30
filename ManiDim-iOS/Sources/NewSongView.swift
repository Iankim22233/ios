import SwiftUI
import UniformTypeIdentifiers

struct NewSongView: View {
    @Environment(AppModel.self) private var app
    var onClose: () -> Void

    @State private var sourceURL: URL?
    @State private var blank = false
    @State private var title = ""
    @State private var artist = ""
    @State private var bpmText = "120"
    @State private var bars = 48
    @State private var keys = 4
    @State private var autoChart = true
    @State private var analysis: AudioAnalysis?
    @State private var analyzing = false
    @State private var working = false
    @State private var status = ""
    @State private var error: String?

    private var canCreate: Bool {
        !working && (blank || sourceURL != nil) && !title.trimmingCharacters(in: .whitespaces).isEmpty && (Double(bpmText) ?? 0) >= 40
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea().onTapGesture { if !working { onClose() } }
            Panel(radius: 28) {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Text("New Song").font(UI.font(38))
                        Spacer()
                        Button { onClose() } label: { Image(systemName: "xmark") }.buttonStyle(MDButtonStyle(compact: true)).disabled(working)
                    }

                    HStack(spacing: 14) {
                        sourceButton(title: "Import audio…", icon: "waveform", selected: !blank && sourceURL != nil) { pickFile() }
                        sourceButton(title: "Blank metronome", icon: "metronome", selected: blank) {
                            blank = true; sourceURL = nil; analysis = nil
                            if title.isEmpty { title = "Untitled" }
                        }
                    }
                    if let u = sourceURL, !blank {
                        HStack(spacing: 8) {
                            Image(systemName: "music.note")
                            Text(u.lastPathComponent).font(UI.font(15, .semibold)).lineLimit(1)
                            if analyzing { ProgressView().controlSize(.small); Text("analysing tempo…").font(UI.font(13, .semibold)).foregroundStyle(.black.opacity(0.5)) }
                            else if let a = analysis { Text("detected \(String(format: "%.1f", a.bpm)) BPM · \(a.onsets.count) onsets").font(UI.font(13, .semibold)).foregroundStyle(.black.opacity(0.5)) }
                        }
                    }

                    VStack(spacing: 12) {
                        field("Title", text: $title)
                        field("Artist", text: $artist)
                        HStack(spacing: 14) {
                            field("BPM", text: $bpmText).frame(width: 140)
                            if blank { stepper("Bars", value: $bars, range: 8...256) }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("KEYS (LANES)").font(UI.font(12)).foregroundStyle(.black.opacity(0.45))
                        HStack(spacing: 8) {
                            ForEach(GameSettings.songKeyCounts, id: \.self) { k in
                                Button("\(k)") { keys = k; AudioManager.shared.play(.move) }
                                    .buttonStyle(MDButtonStyle(accent: nil, compact: true, selected: keys == k))
                            }
                        }
                    }
                    if !blank {
                        HStack {
                            MDToggle(isOn: $autoChart)
                            VStack(alignment: .leading, spacing: 0) {
                                Text("Auto-generate a starter chart").font(UI.font(16))
                                Text("Notes, holds and slides placed from the song's beats — then refine in the editor.")
                                    .font(UI.font(12, .semibold)).foregroundStyle(.black.opacity(0.5))
                            }
                        }
                    }
                    if let e = error { Text(e).font(UI.font(14, .bold)).foregroundStyle(.red) }

                    HStack {
                        if working { ProgressView().controlSize(.small); Text(status).font(UI.font(14, .semibold)) }
                        Spacer()
                        Button { create() } label: { Label("Create & Open Editor", systemImage: "arrow.right") }
                            .buttonStyle(MDButtonStyle(accent: UI.accent(0.33)))
                            .disabled(!canCreate)
                    }
                }
                .padding(32)
            }
            .frame(width: 640)
        }
        .transition(.opacity)
        .onAppear { InputCenter.shared.overlayHandler = { ev in if ev.isDown && ev.code == 53 && !working { onClose(); return true }; return false } }
        .onDisappear { InputCenter.shared.overlayHandler = nil }
    }

    private func sourceButton(title: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 28, weight: .bold))
                Text(title).font(UI.font(17))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 16)
        }
        .buttonStyle(MDButtonStyle(accent: nil, selected: selected))
    }

    private func field(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(UI.font(12)).foregroundStyle(.black.opacity(0.45))
            TextField("", text: text)
                .textFieldStyle(.plain).font(UI.font(18, .bold))
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.96)).overlay(RoundedRectangle(cornerRadius: 12).stroke(.black, lineWidth: 3)))
        }
    }

    private func stepper(_ label: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(UI.font(12)).foregroundStyle(.black.opacity(0.45))
            HStack(spacing: 10) {
                Button { value.wrappedValue = max(range.lowerBound, value.wrappedValue - 8) } label: { Image(systemName: "minus") }.buttonStyle(MDButtonStyle(compact: true))
                Text("\(value.wrappedValue)").font(UI.font(20)).monospacedDigit().frame(width: 48)
                Button { value.wrappedValue = min(range.upperBound, value.wrappedValue + 8) } label: { Image(systemName: "plus") }.buttonStyle(MDButtonStyle(compact: true))
            }
        }
    }

    private func pickFile() {
        FilePicker.open(types: [.audio]) { url in
            guard let url else { return }
            blank = false
            sourceURL = url
            if title.isEmpty { title = url.deletingPathExtension().lastPathComponent }
            analysis = nil
            analyzing = true
            error = nil
            Task.detached {
                let result = try? Autocharter.analyze(url: url)
                await MainActor.run {
                    analysis = result
                    analyzing = false
                    if let r = result { bpmText = String(format: "%.1f", r.bpm) }
                    else { error = "Couldn't analyse that file — you can still set the BPM manually." }
                }
            }
        }
    }

    private func create() {
        working = true
        error = nil
        let id = "custom." + UUID().uuidString.prefix(8).lowercased()
        let dest = AppPaths.songDir(id).appendingPathComponent("audio.wav")
        let bpmValue = Double(bpmText) ?? 120
        let src = sourceURL
        let isBlank = blank
        let nBars = bars
        let k = keys
        let wantAuto = autoChart
        let an = analysis
        let t = title.trimmingCharacters(in: .whitespaces)
        let a = artist.trimmingCharacters(in: .whitespaces)
        status = isBlank ? "Rendering metronome…" : "Converting audio…"
        Task {
            do {
                let duration: Double = try await Task.detached(priority: .userInitiated) {
                    if isBlank {
                        try SongSynth.renderBlank(bpm: bpmValue, bars: nBars, to: dest)
                        return Double(nBars) * 4 * 60 / bpmValue + 1
                    } else {
                        return try AudioImporter.convert(from: src!, to: dest)
                    }
                }.value
                var notes: [Note] = []
                var offset = 0.0
                if let an, !isBlank {
                    offset = an.offset
                    if wantAuto {
                        var adj = an
                        adj.bpm = bpmValue
                        notes = Autocharter.buildNotes(adj, keyCount: k, diff: .normal)
                    }
                }
                var chart = Chart(name: "Custom", level: 1, notes: notes)
                chart.level = max(1, min(15, Int((Double(chart.objectCount) / max(10, duration) * 2.1).rounded())))
                let song = Song(id: id, title: t, artist: a.isEmpty ? "Unknown artist" : a, bpm: bpmValue, offset: offset, keyCount: k,
                                duration: duration, audioFile: "audio.wav", builtinKey: nil, hue: Double.random(in: 0...1), charts: [chart])
                app.library.save(song)
                app.selectedSongID = id
                app.editorSongID = id
                working = false
                onClose()
                app.go(.editor)
            } catch {
                working = false
                self.error = error.localizedDescription
            }
        }
    }
}
