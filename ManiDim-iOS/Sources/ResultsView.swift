import SwiftUI

struct ResultsView: View {
    @Environment(AppModel.self) private var app
    let result: ResultData
    @State private var appear = false
    @State private var shownScore = 0
    @State private var barProgress = 0.0

    private var gradeColor: Color {
        switch result.grade {
        case "SS": return Color(red: 1.0, green: 0.84, blue: 0.2)
        case "S": return Color(red: 1.0, green: 0.7, blue: 0.25)
        case "A": return Color(red: 0.45, green: 0.9, blue: 0.5)
        case "B": return Color(red: 0.45, green: 0.72, blue: 1.0)
        case "C": return Color(red: 0.8, green: 0.55, blue: 1.0)
        default: return Color(white: 0.7)
        }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 26) {
                    // Grade
                    Panel(radius: 28, fill: .white) {
                        VStack(spacing: 6) {
                            Text("RESULT").font(UI.font(15)).foregroundStyle(.black.opacity(0.4))
                            Text(result.grade)
                                .font(.system(size: 170, weight: .black, design: .rounded))
                                .foregroundStyle(gradeColor)
                                .shadow(color: .black, radius: 0, x: 0, y: 8)
                                .scaleEffect(appear ? 1 : 2.4)
                                .opacity(appear ? 1 : 0)
                                .rotationEffect(.degrees(appear ? 0 : -14))
                            if result.failed {
                                badge("FAILED", Color(red: 1, green: 0.45, blue: 0.45))
                            } else if result.allPerfect {
                                badge("ALL PERFECT", Color(red: 1, green: 0.84, blue: 0.2))
                            } else if result.fullCombo {
                                badge("FULL COMBO", Color(red: 0.5, green: 0.9, blue: 0.6))
                            } else {
                                badge(" ", .clear).opacity(0)
                            }
                        }
                        .padding(28)
                        .frame(width: 330)
                    }

                    VStack(alignment: .leading, spacing: 18) {
                        Panel(radius: 28) {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack(alignment: .firstTextBaseline) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(result.songTitle).font(UI.font(34))
                                        Text("\(result.artist)  ·  \(result.chartName)  ·  Lv.\(result.chartLevel)")
                                            .font(UI.font(15, .bold)).foregroundStyle(.black.opacity(0.55))
                                    }
                                    Spacer()
                                    if result.newBest {
                                        Text("NEW BEST").font(UI.font(16)).padding(.horizontal, 12).padding(.vertical, 6)
                                            .background(Capsule().fill(UI.accent(0.13)).overlay(Capsule().stroke(.black, lineWidth: 3)))
                                            .rotationEffect(.degrees(-4))
                                    }
                                    if result.autoplay {
                                        Text("AUTOPLAY").font(UI.font(16)).padding(.horizontal, 12).padding(.vertical, 6)
                                            .background(Capsule().fill(Color(white: 0.9)).overlay(Capsule().stroke(.black, lineWidth: 3)))
                                    }
                                }
                                if result.failed {
                                    Text(result.failReason).font(UI.font(15, .bold)).foregroundStyle(Color(red: 0.85, green: 0.25, blue: 0.25))
                                }
                                if !result.modLabel.isEmpty {
                                    Text("Mods  \(result.modLabel)   ×\(String(format: "%.2f", result.multiplier))   ·   base score \(result.baseScore)")
                                        .font(UI.font(14, .bold)).foregroundStyle(.black.opacity(0.55))
                                }
                                HStack(alignment: .lastTextBaseline, spacing: 30) {
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text("SCORE").font(UI.font(13)).foregroundStyle(.black.opacity(0.4))
                                        Text(String(format: "%07d", shownScore)).font(.system(size: 64, weight: .black, design: .rounded)).monospacedDigit()
                                    }
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text("ACCURACY").font(UI.font(13)).foregroundStyle(.black.opacity(0.4))
                                        Text(String(format: "%.2f%%", result.accuracy * 100 * barProgress)).font(UI.font(36)).monospacedDigit()
                                    }
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text("MAX COMBO").font(UI.font(13)).foregroundStyle(.black.opacity(0.4))
                                        Text("\(Int(Double(result.maxCombo) * barProgress))").font(UI.font(36)).monospacedDigit()
                                    }
                                }
                                // Judgement bars
                                VStack(spacing: 8) {
                                    ForEach(Judgment.allCases, id: \.rawValue) { j in
                                        let c = result.counts[j.rawValue]
                                        HStack(spacing: 12) {
                                            Text(j.title).font(UI.font(14)).frame(width: 84, alignment: .leading)
                                            GeometryReader { g in
                                                ZStack(alignment: .leading) {
                                                    Capsule().fill(Color(white: 0.92))
                                                    Capsule().fill(j.color)
                                                        .frame(width: max(c > 0 ? 14 : 0, g.size.width * Double(c) / Double(max(1, result.totalObjects)) * barProgress))
                                                }
                                                .overlay(Capsule().stroke(.black, lineWidth: 2.5))
                                            }
                                            .frame(height: 16)
                                            Text("\(c)").font(UI.font(16)).monospacedDigit().frame(width: 52, alignment: .trailing)
                                        }
                                    }
                                }
                            }
                            .padding(26)
                        }
                        Panel(radius: 22) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("TIMING").font(UI.font(13)).foregroundStyle(.black.opacity(0.4))
                                    Spacer()
                                    Text(meanText).font(UI.font(13, .bold)).foregroundStyle(.black.opacity(0.55))
                                }
                                TimingHistogram(offsets: result.offsets, progress: barProgress).frame(height: 70)
                            }
                            .padding(.horizontal, 22).padding(.vertical, 16)
                        }
                    }
                }
                .frame(maxWidth: 1060)

                HStack(spacing: 16) {
                    Button { app.retryFromResults() } label: { Label("Retry", systemImage: "arrow.counterclockwise") }
                        .buttonStyle(MDButtonStyle(accent: UI.accent(0.33)))
                    Button { app.go(result.fromEditor ? .editor : .songSelect) } label: {
                        Label(result.fromEditor ? "Back to Editor" : "Songs", systemImage: "list.bullet")
                    }
                    .buttonStyle(MDButtonStyle())
                    Button { app.go(.home) } label: { Label("Home", systemImage: "house.fill") }
                        .buttonStyle(MDButtonStyle())
                }
                .padding(.top, 26)
            }
            .padding(40)
            .offset(y: appear ? 0 : 60)
            .opacity(appear ? 1 : 0)
        }
        .onAppear {
            AudioManager.shared.play(.go)
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) { appear = true }
            withAnimation(.easeOut(duration: 1.4).delay(0.3)) { barProgress = 1 }
            animateScore()
            InputCenter.shared.handler = { ev in
                guard ev.isDown else { return true }
                if ev.code == 36 || ev.code == 15 { app.retryFromResults() }
                else if ev.code == 53 { app.go(result.fromEditor ? .editor : .songSelect) }
                else { return false }
                return true
            }
        }
    }

    private var meanText: String {
        guard !result.offsets.isEmpty else { return "" }
        let mean = result.offsets.reduce(0, +) / Double(result.offsets.count) * 1000
        return String(format: "average %+.0f ms  (%@)", mean, abs(mean) < 4 ? "on time" : (mean < 0 ? "early" : "late"))
    }

    private func badge(_ t: String, _ c: Color) -> some View {
        Text(t).font(UI.font(18)).padding(.horizontal, 16).padding(.vertical, 6)
            .background(Capsule().fill(c).overlay(Capsule().stroke(.black, lineWidth: 3)))
    }

    private func animateScore() {
        let target = result.score
        let start = Date()
        Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { t in
            let p = min(1, (Date().timeIntervalSince(start) - 0.3) / 1.4)
            if p >= 0 { shownScore = Int(Double(target) * (1 - pow(1 - p, 3))) }
            if p >= 1 { t.invalidate() }
        }
    }
}

struct TimingHistogram: View {
    let offsets: [Double]
    var progress: Double
    var body: some View {
        Canvas { ctx, size in
            let bins = 41
            var counts = [Int](repeating: 0, count: bins)
            for o in offsets {
                let b = Int(((clamp(o, -0.15, 0.15) + 0.15) / 0.3 * Double(bins - 1)).rounded())
                counts[b] += 1
            }
            let peak = max(1, counts.max() ?? 1)
            let w = size.width / Double(bins)
            for (i, c) in counts.enumerated() {
                let h = (size.height - 6) * Double(c) / Double(peak) * progress
                let ms = (Double(i) / Double(bins - 1) * 0.3 - 0.15)
                let col: Color = abs(ms) <= 0.045 ? Judgment.perfect.color : (abs(ms) <= 0.09 ? Judgment.great.color : Judgment.good.color)
                let r = CGRect(x: Double(i) * w + 1.5, y: size.height - 3 - h, width: w - 3, height: max(c > 0 ? 3 : 0, h))
                ctx.fill(Path(roundedRect: r, cornerRadius: 3), with: .color(col))
                ctx.stroke(Path(roundedRect: r, cornerRadius: 3), with: .color(.black), style: StrokeStyle(lineWidth: 2))
            }
            ctx.fill(Path(CGRect(x: size.width / 2 - 1.5, y: 0, width: 3, height: size.height)), with: .color(.black.opacity(0.25)))
        }
    }
}
