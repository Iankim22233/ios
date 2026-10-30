import UIKit
import CoreGraphics

struct KeyEvent {
    let code: UInt16
    let isDown: Bool
    let time: Double          // seconds, system uptime base (UITouch.timestamp)
    let chars: String
    let isRepeat: Bool
    let isModifier: Bool
}

struct ScrollInfo {
    var deltaX: Double
    var deltaY: Double
    var zoom: Bool
    var x: Double
}

/// Central input hub. On iOS there is no hardware keyboard; the touch layer (and any attached
/// keyboard) feeds synthetic `KeyEvent`s through here so the game logic is unchanged.
final class InputCenter {
    static let shared = InputCenter()

    var handler: ((KeyEvent) -> Bool)?
    var captureHandler: ((KeyEvent) -> Bool)?
    var scrollHandler: ((ScrollInfo) -> Bool)?
    var overlayHandler: ((KeyEvent) -> Bool)?
    var lockKeys = false
    private(set) var swallowed = 0
    private(set) var down = Set<UInt16>()
    private(set) var pollingReliable: Bool? = false

    func install() {}
    func reclaimKeyboard() {}
    func physicallyDown(_ code: UInt16) -> Bool { down.contains(code) }
    func isReallyDown(_ code: UInt16) -> Bool { down.contains(code) }

    /// Entry point for touches / hardware keys.
    @discardableResult
    func dispatch(_ ke: KeyEvent) -> Bool {
        if ke.isDown { down.insert(ke.code) } else { down.remove(ke.code) }
        if let cap = captureHandler { return cap(ke) }
        if overlayHandler?(ke) == true { return true }
        if handler?(ke) == true { swallowed += 1; return true }
        return false
    }
}

enum KeyNames {
    static func binding(for ev: KeyEvent) -> KeyBinding {
        KeyBinding(code: ev.code, label: label(code: ev.code, chars: ev.chars))
    }

    static func label(code: UInt16, chars: String) -> String {
        switch code {
        case 49: return "Space"
        case 36: return "Return"
        case 76: return "Enter"
        case 48: return "Tab"
        case 51: return "Delete"
        case 53: return "Esc"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        case 55: return "L ⌘"
        case 54: return "R ⌘"
        case 56: return "L ⇧"
        case 60: return "R ⇧"
        case 58: return "L ⌥"
        case 61: return "R ⌥"
        case 59: return "L ⌃"
        case 62: return "R ⌃"
        case 63: return "fn"
        case 57: return "⇪"
        default:
            let c = chars.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            return c.isEmpty ? "Key \(code)" : String(c.prefix(4))
        }
    }
}

/// Shared monotonic clock helpers (same time base as UITouch.timestamp).
enum Clock {
    static func hostNow() -> Double {
        AudioManagerClock.seconds(mach_absolute_time())
    }
    /// Offset to convert UITouch.timestamp into host seconds.
    static let eventSkew: Double = ProcessInfo.processInfo.systemUptime - hostNow()
    static func fromEvent(_ t: Double) -> Double { t - eventSkew }
}
