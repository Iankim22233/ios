import Foundation
import SwiftUI
import Observation
import ImageIO

struct KeyBinding: Codable, Hashable {
    var code: UInt16
    var label: String
}

enum Skin: String, Codable, CaseIterable, Identifiable {
    case original, highContrast, classic
    var id: String { rawValue }
    var title: String {
        switch self {
        case .original: return "Original"
        case .highContrast: return "High Contrast"
        case .classic: return "Classic"
        }
    }
    var blurb: String {
        switch self {
        case .original: return "The fan with light wedges"
        case .highContrast: return "Black wedges, white outlines"
        case .classic: return "Vertical lanes, mania-style"
        }
    }
}

struct RGBA: Codable, Equatable, Hashable {
    var r: Double, g: Double, b: Double
    init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }
    init(color: Color) {
        (r, g, b) = color.rgbTuple()
    }
    var color: Color { Color(red: r, green: g, blue: b) }
}

struct BackgroundSetting: Codable, Equatable {
    enum Mode: String, Codable, CaseIterable { case skin, preset, custom, image }
    var mode: Mode = .skin
    var preset = "slate"
    var top = RGBA(0.50, 0.50, 0.50)
    var bottom = RGBA(0.40, 0.40, 0.40)
    var imageFile: String?
    var dim = 0.45

    static let presets: [(id: String, name: String, top: RGBA, bottom: RGBA)] = [
        ("slate", "Slate", RGBA(0.50, 0.50, 0.50), RGBA(0.40, 0.40, 0.40)),
        ("midnight", "Midnight", RGBA(0.11, 0.11, 0.20), RGBA(0.04, 0.04, 0.09)),
        ("sunset", "Sunset", RGBA(0.98, 0.62, 0.48), RGBA(0.42, 0.22, 0.52)),
        ("ocean", "Ocean", RGBA(0.23, 0.48, 0.84), RGBA(0.04, 0.16, 0.29)),
        ("forest", "Forest", RGBA(0.37, 0.64, 0.42), RGBA(0.09, 0.20, 0.12)),
        ("rose", "Rose", RGBA(0.94, 0.56, 0.69), RGBA(0.42, 0.16, 0.33)),
        ("paper", "Paper", RGBA(0.95, 0.95, 0.95), RGBA(0.80, 0.80, 0.80)),
        ("black", "Black", RGBA(0, 0, 0), RGBA(0, 0, 0)),
    ]

    func spec(for skin: Skin, classic: Bool = false) -> BackdropSpec {
        switch mode {
        case .skin:
            if classic { return BackdropSpec(top: .black, bottom: .black, image: nil, dim: 0, decor: false) }
            switch skin {
            case .original: return BackdropSpec(top: RGBA(0.50, 0.50, 0.50).color, bottom: RGBA(0.40, 0.40, 0.40).color, image: nil, dim: 0, decor: true)
            case .highContrast: return BackdropSpec(top: RGBA(0.47, 0.47, 0.47).color, bottom: RGBA(0.47, 0.47, 0.47).color, image: nil, dim: 0, decor: false)
            case .classic: return BackdropSpec(top: .black, bottom: .black, image: nil, dim: 0, decor: false)
            }
        case .preset:
            let p = Self.presets.first { $0.id == preset } ?? Self.presets[0]
            return BackdropSpec(top: p.top.color, bottom: p.bottom.color, image: nil, dim: 0, decor: skin == .original && !classic)
        case .custom:
            return BackdropSpec(top: top.color, bottom: bottom.color, image: nil, dim: 0, decor: skin == .original && !classic)
        case .image:
            if let img = BackgroundImages.image(named: imageFile) {
                return BackdropSpec(top: .black, bottom: .black, image: img, dim: dim, decor: false)
            }
            return BackgroundSetting().spec(for: skin, classic: classic)
        }
    }
}

struct BackdropSpec {
    var top: Color
    var bottom: Color
    var image: UIImage?
    var dim: Double
    var decor: Bool
}

enum BackgroundImages {
    private static var cached: (name: String, image: UIImage)?

    static func image(named name: String?) -> UIImage? {
        guard let name else { return nil }
        if let c = cached, c.name == name { return c.image }
        let url = AppPaths.support.appendingPathComponent(name)
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceThumbnailMaxPixelSize: 2560]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        let img = UIImage(cgImage: cg)
        cached = (name, img)
        return img
    }

    /// Copies the picked image into the app's support folder; returns the stored file name.
    static func importImage(from url: URL, replacing old: String?) throws -> String {
        let name = "background-\(UUID().uuidString.prefix(8)).\(url.pathExtension.lowercased())"
        try FileManager.default.copyItem(at: url, to: AppPaths.support.appendingPathComponent(name))
        if let old { try? FileManager.default.removeItem(at: AppPaths.support.appendingPathComponent(old)) }
        cached = nil
        return name
    }
}

struct GameSettings: Codable, Equatable {
    var keymaps: [String: [KeyBinding]] = GameSettings.defaultKeymaps()
    var slideLeft = KeyBinding(code: 55, label: "L ⌘")
    var slideRight = KeyBinding(code: 54, label: "R ⌘")
    var scrollSpeed: Double = 7
    var audioOffsetMs: Double = 0
    var musicVolume: Double = 0.8
    var sfxVolume: Double = 0.6
    var hitSounds = true
    var particles = true
    var screenShake = true
    var beatPulse = true
    var showFPS = false
    var autoplay = false
    var chartEffects = true
    var mods: [String] = []
    var skin: Skin = .original
    var background = BackgroundSetting()

    init() {}

    enum CodingKeys: String, CodingKey {
        case keymaps, slideLeft, slideRight, scrollSpeed, audioOffsetMs, musicVolume, sfxVolume, hitSounds
        case particles, screenShake, beatPulse, showFPS, autoplay, skin, background, chartEffects, mods
    }

    // Lenient: settings saved by older versions keep working when new options are added.
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        keymaps = (try? c.decode([String: [KeyBinding]].self, forKey: .keymaps)) ?? keymaps
        slideLeft = (try? c.decode(KeyBinding.self, forKey: .slideLeft)) ?? slideLeft
        slideRight = (try? c.decode(KeyBinding.self, forKey: .slideRight)) ?? slideRight
        scrollSpeed = (try? c.decode(Double.self, forKey: .scrollSpeed)) ?? scrollSpeed
        audioOffsetMs = (try? c.decode(Double.self, forKey: .audioOffsetMs)) ?? audioOffsetMs
        musicVolume = (try? c.decode(Double.self, forKey: .musicVolume)) ?? musicVolume
        sfxVolume = (try? c.decode(Double.self, forKey: .sfxVolume)) ?? sfxVolume
        hitSounds = (try? c.decode(Bool.self, forKey: .hitSounds)) ?? hitSounds
        particles = (try? c.decode(Bool.self, forKey: .particles)) ?? particles
        screenShake = (try? c.decode(Bool.self, forKey: .screenShake)) ?? screenShake
        beatPulse = (try? c.decode(Bool.self, forKey: .beatPulse)) ?? beatPulse
        showFPS = (try? c.decode(Bool.self, forKey: .showFPS)) ?? showFPS
        autoplay = (try? c.decode(Bool.self, forKey: .autoplay)) ?? autoplay
        chartEffects = (try? c.decode(Bool.self, forKey: .chartEffects)) ?? chartEffects
        skin = (try? c.decode(Skin.self, forKey: .skin)) ?? skin
        background = (try? c.decode(BackgroundSetting.self, forKey: .background)) ?? background
        mods = (try? c.decode([String].self, forKey: .mods)) ?? mods
        // Classic used to be a skin; it is now the "Classic Layout" easy mod.
        if skin == .classic {
            skin = .original
            if !mods.contains(Mod.classic.rawValue) { mods.append(Mod.classic.rawValue) }
        }
    }

    static let keyCounts = [1, 2, 3, 4, 5, 6, 7, 8]
    /// Lane counts offered when authoring songs.
    static let songKeyCounts = [3, 4, 5, 6, 7, 8]
    var modSet: ModSet { ModSet(raw: mods) }

    static func defaultKeymaps() -> [String: [KeyBinding]] {
        func k(_ c: UInt16, _ l: String) -> KeyBinding { KeyBinding(code: c, label: l) }
        let A = k(0, "A"), S = k(1, "S"), D = k(2, "D"), F = k(3, "F"), J = k(38, "J"), K = k(40, "K"),
            L = k(37, "L"), semi = k(41, ";"), space = k(49, "Space")
        return [
            "1": [space],
            "2": [F, J],
            "3": [F, space, J],
            "4": [D, F, J, K],
            "5": [D, F, space, J, K],
            "6": [S, D, F, J, K, L],
            "7": [S, D, F, space, J, K, L],
            "8": [A, S, D, F, J, K, L, semi],
        ]
    }

    func keys(for count: Int) -> [KeyBinding] {
        keymaps[String(count)] ?? GameSettings.defaultKeymaps()[String(count)] ?? []
    }

    var audioOffset: Double { audioOffsetMs / 1000 }
}

@Observable
final class SettingsStore {
    static let shared = SettingsStore()
    var value: GameSettings { didSet { if !suppressSave { save() } } }
    /// Debug launch flags (`--skin`, `--mods`, …) change settings for that run only.
    var suppressSave = false

    private let key = "ManiDim.settings.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let v = try? JSONDecoder().decode(GameSettings.self, from: data) {
            value = v
        } else {
            value = GameSettings()
        }
        value.autoplay = false     // never carry autoplay across launches
    }

    private func save() {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
        AudioManager.shared.applyVolumes(value)
    }

    func resetKeys() {
        value.keymaps = GameSettings.defaultKeymaps()
        value.slideLeft = KeyBinding(code: 55, label: "L ⌘")
        value.slideRight = KeyBinding(code: 54, label: "R ⌘")
    }

    /// Assign a key to a lane. If another lane/slide already uses the key, swap.
    func bind(lane: Int, count: Int, to binding: KeyBinding) {
        var keys = value.keys(for: count)
        guard lane < keys.count else { return }
        let old = keys[lane]
        if let other = keys.firstIndex(where: { $0.code == binding.code }), other != lane {
            keys[other] = old
        }
        if value.slideLeft.code == binding.code { value.slideLeft = old }
        else if value.slideRight.code == binding.code { value.slideRight = old }
        keys[lane] = binding
        value.keymaps[String(count)] = keys
    }

    func bindSlide(left: Bool, to binding: KeyBinding, count: Int) {
        let old = left ? value.slideLeft : value.slideRight
        var keys = value.keys(for: count)
        if let idx = keys.firstIndex(where: { $0.code == binding.code }) {
            keys[idx] = old
            value.keymaps[String(count)] = keys
        }
        if left {
            if value.slideRight.code == binding.code { value.slideRight = old }
            value.slideLeft = binding
        } else {
            if value.slideLeft.code == binding.code { value.slideLeft = old }
            value.slideRight = binding
        }
    }
}

// MARK: - Theme & palette

struct Theme {
    var wedge: Color
    var outline: Color
    var box: Color
    var ink: Color
    var capTop: Color
    var capBottom: Color
    var capText: Color
    var capShadow: Color

    static func make(_ skin: Skin) -> Theme {
        switch skin {
        case .original, .classic:
            return Theme(wedge: .white, outline: .black, box: .white, ink: .black,
                         capTop: .white, capBottom: Color(white: 0.92), capText: .black, capShadow: .black.opacity(0.85))
        case .highContrast:
            return Theme(wedge: .black, outline: .white, box: .black, ink: .white,
                         capTop: Color(white: 0.12), capBottom: .black, capText: .white, capShadow: Color(white: 0.55))
        }
    }
}

enum Palette {
    /// Lane hue: magenta → blue → green → red across the fan (like the prototype).
    static func laneHue(_ i: Int, of n: Int) -> Double {
        let t = n <= 1 ? 0 : Double(i) / Double(n - 1)
        var h = 0.84 - t * 0.86
        if h < 0 { h += 1 }
        return h
    }
    static func lane(_ i: Int, of n: Int, brightness: Double = 1.0, saturation: Double = 0.66) -> Color {
        Color(hue: laneHue(i, of: n), saturation: saturation, brightness: brightness)
    }
    static func rgb(_ i: Int, of n: Int) -> (Double, Double, Double) {
        Color(hue: laneHue(i, of: n), saturation: 0.66, brightness: 1.0).rgbTuple()
    }
    static func mix(_ a: Int, _ b: Int, of n: Int, t: Double) -> Color {
        let x = rgb(a, of: n), y = rgb(b, of: n)
        return Color(red: lerp(x.0, y.0, t), green: lerp(x.1, y.1, t), blue: lerp(x.2, y.2, t))
    }
}
