import SwiftUI
import AVFoundation

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask { .landscape }
}

@main
struct ManiDimApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .preferredColorScheme(.light)
                .statusBarHidden()
                .persistentSystemOverlays(.hidden)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        GeometryReader { geo in
            let k: CGFloat = app.screen == .game ? 1 : max(0.5, min(geo.size.height / 700, geo.size.width / 1100))
            let ins = app.screen == .game ? UIEdgeInsets.zero : Self.safeInsets
            let isGame = app.screen == .game
            let padH = max(ins.left, ins.right) / k, padT = CGFloat(0), padB = CGFloat(0)
            content
                .padding(.horizontal, padH).padding(.top, padT).padding(.bottom, padB)
                .frame(width: geo.size.width / k, height: geo.size.height / k)
                .scaleEffect(k, anchor: .topLeading)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .background(Color.black)
        .ignoresSafeArea()
    }

    private static var safeInsets: UIEdgeInsets {
        let w = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.windows.first
        return w?.safeAreaInsets ?? .zero
    }

    private var content: some View {
        ZStack {
            if app.screen != .game {
                AttractView(showFan: app.screen == .home, centerX: 0.73,
                            hue: app.screen == .songSelect ? app.library.song(id: app.selectedSongID)?.hue : nil)
                    .transition(.opacity)
            }

            switch app.screen {
            case .home:
                HomeView().transition(.opacity.combined(with: .move(edge: .leading)))
            case .songSelect:
                SongSelectView().transition(.opacity.combined(with: .scale(scale: 0.98)))
            case .settings:
                SettingsView().transition(.opacity.combined(with: .scale(scale: 0.98)))
            case .editor:
                EditorHost().transition(.opacity)
            case .game:
                if let s = app.session { GameView(session: s).id(ObjectIdentifier(s)).transition(.opacity) }
            case .results:
                if let r = app.result { ResultsView(result: r).transition(.opacity) }
            }

            if app.showHowTo {
                HowToPlayView { withAnimation(.easeOut(duration: 0.25)) { app.showHowTo = false } }
            }
            if app.showMods {
                ModsView(song: app.library.song(id: app.selectedSongID)) { withAnimation(.easeOut(duration: 0.25)) { app.showMods = false } }
            }
            if app.showNewSong {
                NewSongView { withAnimation(.easeOut(duration: 0.25)) { app.showNewSong = false } }
            }
        }
        .overlay(alignment: .bottom) {
            if let t = app.toast {
                Text(t).font(UI.font(17)).foregroundStyle(.black)
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(Capsule().fill(.white).overlay(Capsule().stroke(.black, lineWidth: 4)))
                    .shadow(color: .black.opacity(0.8), radius: 0, y: 5)
                    .padding(.bottom, 36)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onOpenURL { app.importMadim($0) }
        .background(Color.black)
        .ignoresSafeArea()
        .onAppear {
            DemoRunner.shared.setMusic(true)
        }
        .animation(.easeInOut(duration: 0.3), value: app.showHowTo)
        .animation(.easeInOut(duration: 0.3), value: app.showNewSong)
        .animation(.easeInOut(duration: 0.3), value: app.showMods)
    }
}

