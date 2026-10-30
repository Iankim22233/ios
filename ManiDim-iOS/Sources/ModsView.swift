import SwiftUI

struct ModsView: View {
    @Environment(AppModel.self) private var app
    let song: Song?
    var onClose: () -> Void

    private var set: ModSet { app.settings.modSet }
    private var origKeys: Int { song?.keys(app.selectedChart) ?? 4 }

    private func mult(_ m: Mod) -> Double {
        if let k = m.keyCount { return ModSet.keyMultiplier(from: origKeys, to: k) }
        return m.multiplier
    }

    private func toggle(_ m: Mod) {
        var s = app.settingsStore.value.modSet
        s.toggle(m)
        app.settingsStore.value.mods = s.rawValues
        AudioManager.shared.play(s.has(m) ? .select : .back, volume: 0.7)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea().onTapGesture { onClose() }
            Panel(radius: 28) {
                VStack(spacing: 14) {
                    HStack(alignment: .center, spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Mods").font(UI.font(38))
                            Text(song.map { "Applied to \($0.title) and every other song until you change them" } ?? "Applied to every song")
                                .font(UI.font(13, .semibold)).foregroundStyle(.black.opacity(0.5))
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 0) {
                            Text("SCORE MULTIPLIER").font(UI.font(11)).foregroundStyle(.black.opacity(0.4))
                            Text("×" + String(format: "%.2f", set.multiplier(origKeys: origKeys)))
                                .font(UI.font(40)).monospacedDigit()
                                .foregroundStyle(set.multiplier(origKeys: origKeys) >= 1 ? Color(red: 0.85, green: 0.35, blue: 0.3) : Color(red: 0.2, green: 0.55, blue: 0.3))
                        }
                        Button("Reset") {
                            app.settingsStore.value.mods = []
                            AudioManager.shared.play(.back)
                        }
                        .buttonStyle(MDButtonStyle(compact: true)).disabled(set.isEmpty)
                        Button("Done") { onClose() }.buttonStyle(MDButtonStyle(accent: UI.accent(0.33), compact: true))
                    }
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(ModCategory.allCases) { cat in column(cat) }
                    }
                    if !set.isEmpty {
                        Text("Active: \(set.label)").font(UI.font(14)).foregroundStyle(.black.opacity(0.6))
                    }
                }
                .padding(26)
            }
            .frame(maxWidth: 1240)
            .padding(30)
        }
        .transition(.opacity)
        .onAppear { InputCenter.shared.overlayHandler = { ev in if ev.isDown && (ev.code == 53 || ev.code == 46) { onClose() }; return ev.isDown && (ev.code == 53 || ev.code == 46) } }
        .onDisappear { InputCenter.shared.overlayHandler = nil }
    }

    private func column(_ cat: ModCategory) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Capsule().fill(cat.tint).frame(width: 30, height: 14).overlay(Capsule().stroke(.black, lineWidth: 3))
                VStack(alignment: .leading, spacing: 0) {
                    Text(cat.title).font(UI.font(22))
                    Text(cat.blurb).font(UI.font(11, .semibold)).foregroundStyle(.black.opacity(0.45))
                }
            }
            ScrollView(showsIndicators: false) {
                VStack(spacing: 8) {
                    if cat == .conversion { keyGrid(cat) }
                    ForEach(Mod.allCases.filter { $0.category == cat && $0.keyCount == nil }) { m in row(m, cat) }
                }
                .padding(.vertical, 4).padding(.horizontal, 3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: 470)
    }

    private func keyGrid(_ cat: ModCategory) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("KEY COUNT — remap the chart to this many lanes").font(UI.font(11)).foregroundStyle(.black.opacity(0.4))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                ForEach(Mod.allCases.filter { $0.keyCount != nil }) { m in
                    let on = set.has(m)
                    let same = m.keyCount == origKeys
                    Button { toggle(m) } label: {
                        VStack(spacing: 0) {
                            Text(m.title).font(UI.font(18))
                            Text(same ? "as is" : "×" + String(format: "%.2f", mult(m))).font(UI.font(10, .bold)).foregroundStyle(.black.opacity(0.5))
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(MDButtonStyle(accent: on ? cat.tint : nil, compact: true, selected: false))
                }
            }
        }
    }

    private func row(_ m: Mod, _ cat: ModCategory) -> some View {
        let on = set.has(m)
        return Button { toggle(m) } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(cat.tint).overlay(Circle().stroke(.black, lineWidth: 3))
                    Image(systemName: m.icon).font(.system(size: 15, weight: .black))
                }
                .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(m.title).font(UI.font(16))
                        Text(m.acronym).font(UI.font(10)).padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Color(white: 0.9)).overlay(Capsule().stroke(.black, lineWidth: 1.5)))
                    }
                    Text(m.blurb).font(UI.font(11, .semibold)).foregroundStyle(.black.opacity(0.55)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Text("×" + String(format: "%.2f", mult(m))).font(UI.font(13)).monospacedDigit()
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Capsule().fill(m.multiplier >= 1 ? Color(red: 1, green: 0.85, blue: 0.82) : Color(red: 0.84, green: 0.96, blue: 0.84)).overlay(Capsule().stroke(.black, lineWidth: 2)))
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 14).fill(on ? cat.tint.opacity(0.55) : Color(white: 0.97))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(.black, lineWidth: on ? 4 : 2.5))
                .shadow(color: .black.opacity(on ? 0.8 : 0), radius: 0, y: 4))
            .overlay(alignment: .topTrailing) {
                if on { Image(systemName: "checkmark.circle.fill").font(.system(size: 18)).foregroundStyle(.black).background(Circle().fill(.white)).offset(x: 5, y: -6) }
            }
        }
        .buttonStyle(PressFeedbackStyle())
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: on)
    }
}
