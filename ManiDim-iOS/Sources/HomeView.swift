import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var app
    @State private var selected = 0
    @State private var appeared = false

    private struct Item { let title: String; let icon: String; let hue: Double }
    private let items = [
        Item(title: "Play", icon: "play.fill", hue: 0.33),
        Item(title: "Create", icon: "wand.and.stars", hue: 0.84),
        Item(title: "Settings", icon: "slider.horizontal.3", hue: 0.55),
        Item(title: "How to Play", icon: "questionmark", hue: 0.13),
    ]

    var body: some View {
        ZStack(alignment: .leading) {
        LinearGradient(colors: [.black.opacity(0.62), .black.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing)
            .frame(width: 780).ignoresSafeArea().allowsHitTesting(false)
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 20)
                logo
                    .padding(.bottom, 34)
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                        Button { selected = i; activate(i) } label: {
                            MenuRow(title: item.title, icon: item.icon, hue: item.hue, selected: selected == i)
                        }
                        .buttonStyle(PressFeedbackStyle())
                        .opacity(appeared ? 1 : 0)
                        .offset(x: appeared ? 0 : -80)
                        .animation(.spring(response: 0.55, dampingFraction: 0.78).delay(0.08 * Double(i) + 0.15), value: appeared)
                    }
                }
                Spacer(minLength: 20)
            }
            .padding(.leading, 70)
            .frame(width: 560)
            Spacer()
        }
        }
        .onAppear {
            appeared = true
            InputCenter.shared.handler = { ev in
                guard ev.isDown else { return true }
                switch ev.code {
                case 126: selected = (selected + items.count - 1) % items.count; AudioManager.shared.play(.move)
                case 125: selected = (selected + 1) % items.count; AudioManager.shared.play(.move)
                case 36, 76, 49: activate(selected)
                default: return false
                }
                return true
            }
        }
    }

    private var logo: some View {
        HStack(alignment: .center, spacing: 18) {
            FanIcon(lanes: 4, animate: true)
                .frame(width: 110, height: 110)
            VStack(alignment: .leading, spacing: -6) {
                Text("Mani")
                    .font(.system(size: 78, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black, radius: 0, x: 0, y: 7)
                Text("Dim")
                    .font(.system(size: 78, weight: .black, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: (0..<4).map { Palette.lane($0, of: 4) }, startPoint: .leading, endPoint: .trailing))
                    .shadow(color: .black, radius: 0, x: 0, y: 7)
            }
        }
        .scaleEffect(appeared ? 1 : 0.8, anchor: .leading)
        .opacity(appeared ? 1 : 0)
        .animation(.spring(response: 0.7, dampingFraction: 0.7), value: appeared)
    }

    private func activate(_ i: Int) {
        AudioManager.shared.play(.select)
        switch i {
        case 0: app.go(.songSelect)
        case 1: app.showNewSong = true
        case 2: app.go(.settings)
        case 3: app.showHowTo = true
        default: break
        }
    }
}

private struct MenuRow: View {
    let title: String
    let icon: String
    let hue: Double
    let selected: Bool

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().fill(UI.accent(hue)).overlay(Circle().stroke(.black, lineWidth: 4))
                Image(systemName: icon).font(.system(size: 17, weight: .black)).foregroundStyle(.black)
            }
            .frame(width: 44, height: 44)
            Text(title).font(UI.font(26)).foregroundStyle(.black)
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 16, weight: .black)).foregroundStyle(.black)
                .opacity(selected ? 1 : 0).offset(x: selected ? 0 : -8)
        }
        .padding(.horizontal, 18)
        .frame(width: 400, height: 66)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(selected ? Color.white : Color.white.opacity(0.9))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.black, lineWidth: 4))
                .shadow(color: .black.opacity(0.85), radius: 0, x: 0, y: selected ? 7 : 4)
        )
        .offset(x: selected ? 18 : 0, y: selected ? -2 : 0)
        .animation(.spring(response: 0.3, dampingFraction: 0.65), value: selected)
        .contentShape(Rectangle())
    }
}

// MARK: - How to play

struct HowToPlayView: View {
    @Environment(AppModel.self) private var app
    var onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea().onTapGesture { onClose() }
            Panel(radius: 28) {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Text("How to Play").font(UI.font(38))
                        Spacer()
                        Button { onClose() } label: { Image(systemName: "xmark") }.buttonStyle(MDButtonStyle(compact: true))
                    }
                    HStack(alignment: .top, spacing: 18) {
                        card(title: "Tap", color: Palette.lane(0, of: 4),
                             text: "Notes fly out of the fan toward the circle. When one reaches the circle, tap the big pad for its lane at the bottom of the screen.",
                             keys: ["1", "2", "3", "4"].map { ($0, false) }, extra: nil)
                        card(title: "Hold", color: Palette.lane(1, of: 4),
                             text: "Long notes: touch the pad on the head and keep your finger down until the tail reaches the circle.",
                             keys: [("2", true)], extra: "keep holding")
                        card(title: "Slide", color: Palette.lane(2, of: 4),
                             text: "While holding a slide note, tap a SLIDE pad (or swipe sideways) when the arrow arrives. It points the way the note moves.",
                             keys: [("2", true), ("◀", false), ("▶", false)], extra: "tap a slide pad")
                    }
                    Text("Use several fingers at once. The pause button is top-right. Timing windows: Perfect ±45 ms · Great ±90 ms · Good ±135 ms.")
                        .font(UI.font(15, .semibold)).foregroundStyle(.black.opacity(0.6))
                }
                .padding(32)
            }
            .frame(maxWidth: 1000)
            .padding(40)
        }
        .transition(.opacity)
    }

    private func card(title: String, color: Color, text: String, keys: [(String, Bool)], extra: String?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Capsule().fill(color).frame(width: 34, height: 14).overlay(Capsule().stroke(.black, lineWidth: 3))
                Text(title).font(UI.font(26))
            }
            Text(text).font(UI.font(15, .semibold)).foregroundStyle(.black.opacity(0.75)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            HStack(spacing: 8) {
                ForEach(Array(keys.enumerated()), id: \.offset) { _, k in Keycap(label: k.0, color: color, width: 52, active: k.1) }
                if let e = extra { Text(e).font(UI.font(14)).foregroundStyle(.black.opacity(0.7)) }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 230, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(white: 0.96)).overlay(RoundedRectangle(cornerRadius: 18).stroke(.black, lineWidth: 3)))
    }
}
