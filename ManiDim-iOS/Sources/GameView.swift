import SwiftUI

struct GameView: View {
    @Environment(AppModel.self) private var app
    let session: GameSession
    @State private var introShown = true

    var body: some View {
        ZStack {
            GameCanvas(session: session)
                .ignoresSafeArea()

            if session.phase == .running || session.phase == .countdown {
                TouchLayer(session: session).ignoresSafeArea()
                PadsView(session: session).ignoresSafeArea().allowsHitTesting(false)
                VStack {
                    HStack {
                        Button { session.pause() } label: {
                            Image(systemName: "pause.fill").font(.system(size: 22, weight: .black)).foregroundStyle(.white)
                                .frame(width: 68, height: 52).background(Capsule().fill(.black.opacity(0.4)))
                        }
                        .padding(.trailing, 18).padding(.top, 14)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    Spacer()
                }
            }

            overlay
        }
        .onAppear {
            InputCenter.shared.lockKeys = true
            InputCenter.shared.handler = { [session] ev in session.handleKey(ev) }
            Task { await session.prepare() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.6) { withAnimation(.easeOut(duration: 0.6)) { introShown = false } }
        }
        .onDisappear {
            InputCenter.shared.lockKeys = false
            session.shutdown()
        }
    }

    @ViewBuilder private var overlay: some View {
        switch session.phase {
        case .loading:
            VStack(spacing: 18) {
                ProgressView().controlSize(.large).tint(.white)
                Text("Preparing \(session.song.title)…").font(UI.font(22)).foregroundStyle(.white)
                    .shadow(color: .black, radius: 0, x: 0, y: 2)
            }
            .transition(.opacity)
        case .failed:
            Panel {
                VStack(spacing: 16) {
                    Text("Can't play this song").font(UI.font(28))
                    Text(session.errorText).font(UI.font(16, .medium))
                    Button("Back") { session.quit() }.buttonStyle(MDButtonStyle())
                }
                .padding(32)
            }
            .fixedSize()
        case .running:
            ZStack {
                if introShown && session.activeLesson == nil {
                    IntroCard(song: session.song, chart: session.chart)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
                if let L = session.activeLesson {
                    LessonCard(session: session, lesson: L)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: session.activeLesson)
            .allowsHitTesting(false)
        case .countdown:
            Text("\(max(1, session.countdown))")
                .font(.system(size: 190, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black, radius: 0, x: 0, y: 8)
                .id(session.countdown)
                .transition(.scale(scale: 1.6).combined(with: .opacity))
                .animation(.spring(response: 0.35, dampingFraction: 0.6), value: session.countdown)
        case .paused:
            PauseMenu(session: session)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
        case .finished:
            EmptyView()
        }
    }
}

struct GameCanvas: View {
    let session: GameSession

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                _ = tl.date
                let wall = Clock.hostNow()
                var rs = RenderState(
                    engine: session.engine, fx: session.fx, time: session.time(wall: wall), wall: wall,
                    settings: session.settings, bpm: session.song.bpm, offset: session.song.offset, hue: session.song.hue,
                    title: session.song.title, artist: session.song.artist, chartName: session.chart.name,
                    duration: session.song.duration, keyLabels: session.keyLabels,
                    events: session.chart.events, classic: session.mods.classic, visibility: session.mods.visibility,
                    scoreMult: session.scoreMultiplier, modLabel: session.mods.label)
                rs.centerY = PadLayout.centerY(size: size, classic: session.mods.classic)
                rs.uScale = PadLayout.uScale
                rs.touchPads = true
                GameRenderer.draw(&ctx, size: size, rs: rs)
            }
        }
    }
}

private struct IntroCard: View {
    let song: Song
    let chart: Chart
    @State private var appear = false
    var body: some View {
        VStack(spacing: 6) {
            Text(song.title).font(.system(size: 54, weight: .black, design: .rounded)).foregroundStyle(.white)
                .shadow(color: .black, radius: 0, x: 0, y: 5)
            Text("\(song.artist)  ·  \(chart.name)  ·  Lv.\(chart.level)").font(UI.font(20, .bold)).foregroundStyle(.white.opacity(0.9))
                .shadow(color: .black.opacity(0.6), radius: 0, x: 0, y: 2)
        }
        .offset(y: appear ? -190 : -160)
        .opacity(appear ? 1 : 0)
        .onAppear { withAnimation(.spring(response: 0.7, dampingFraction: 0.8)) { appear = true } }
    }
}

private struct PauseMenu: View {
    let session: GameSession
    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            Panel(radius: 26) {
                VStack(spacing: 18) {
                    Text("PAUSED").font(UI.font(44)).foregroundStyle(.black)
                    VStack(spacing: 12) {
                        ForEach(Array(["Resume", "Restart", "Quit to Songs"].enumerated()), id: \.offset) { i, title in
                            Button(title) {
                                switch i {
                                case 0: session.resume()
                                case 1: session.restart()
                                default: session.quit()
                                }
                            }
                            .buttonStyle(MDButtonStyle(accent: i == 0 ? UI.accent(0.33) : nil, selected: false))
                            .frame(width: 260)
                            .overlay(alignment: .leading) {
                                if session.pauseIndex == i {
                                    Image(systemName: "arrowtriangle.right.fill").font(.system(size: 18)).offset(x: -34)
                                        .foregroundStyle(.black)
                                }
                            }
                        }
                    }
                    Text("Tap an option").font(UI.font(13, .bold)).foregroundStyle(.black.opacity(0.45))
                }
                .padding(.horizontal, 44).padding(.vertical, 34)
            }
            .fixedSize()
        }
    }
}

struct LessonCard: View {
    let session: GameSession
    let lesson: Lesson
    @State private var pulse = false

    var body: some View {
        VStack {
            Panel(radius: 26) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("LESSON \(session.lessonNumber) OF \(session.lessonTotal)").font(UI.font(12)).tracking(2).foregroundStyle(.black.opacity(0.4))
                        Spacer()
                        Image(systemName: "pause.fill").font(.system(size: 12, weight: .black)).foregroundStyle(.black.opacity(0.35))
                    }
                    Text(lesson.title).font(UI.font(34))
                    Text(session.lessonText(lesson))
                        .font(UI.font(18, .semibold)).foregroundStyle(.black.opacity(0.78))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Tap anywhere to continue").font(UI.font(16)).foregroundStyle(.black.opacity(pulse ? 0.8 : 0.35))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.top, 4)
                }
                .padding(26)
                .frame(width: 560)
            }
            .padding(.top, 70)
            Spacer()
        }
        .onAppear { withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { pulse = true } }
    }
}
