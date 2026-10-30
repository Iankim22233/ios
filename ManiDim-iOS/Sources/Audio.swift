import AVFoundation
import Foundation

enum AudioManagerClock {
    static func seconds(_ host: UInt64) -> Double { AVAudioTime.seconds(forHostTime: host) }
    static func host(_ seconds: Double) -> UInt64 { AVAudioTime.hostTime(forSeconds: seconds) }
}

enum SFX: CaseIterable {
    case tap, hold, slide, miss, select, move, back, beep, go, metronome
}

final class AudioManager {
    static let shared = AudioManager()

    let engine = AVAudioEngine()
    let music = AVAudioPlayerNode()
    let varispeed = AVAudioUnitVarispeed()
    let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!

    private var pool: [AVAudioPlayerNode] = []
    private var poolIndex = 0
    private var buffers: [SFX: AVAudioPCMBuffer] = [:]

    private(set) var file: AVAudioFile?
    private(set) var fileURL: URL?
    private(set) var duration: Double = 0
    /// Host time (seconds) at which the song position equals `startPos`.
    private(set) var startHost: Double = 0
    private(set) var startPos: Double = 0
    /// Constant playback speed of the current run (speed mods). Song time advances this fast per second.
    private(set) var playRate: Double = 1
    private(set) var isPlaying = false
    /// Gameplay claims the music node; previews and stray cleanups must not touch it.
    weak var owner: AnyObject?
    private(set) var isPreview = false

    var musicVolume: Float = 0.8 { didSet { music.volume = musicVolume * fadeScale } }
    var sfxVolume: Float = 0.6
    private var fadeScale: Float = 1
    private var fadeTimer: Timer?

    init() {
        engine.attach(music)
        engine.attach(varispeed)
        engine.connect(music, to: varispeed, format: format)
        engine.connect(varispeed, to: engine.mainMixerNode, format: format)
        for _ in 0..<12 {
            let n = AVAudioPlayerNode()
            engine.attach(n)
            engine.connect(n, to: engine.mainMixerNode, format: format)
            pool.append(n)
        }
        for s in SFX.allCases { buffers[s] = Self.makeSFX(s, format: format) }
        engine.prepare()
        startEngine()
    }

    func startEngine() {
        if !engine.isRunning { try? engine.start() }
    }

    func applyVolumes(_ s: GameSettings) {
        musicVolume = Float(s.musicVolume)
        sfxVolume = Float(s.sfxVolume)
    }

    // MARK: Music

    @discardableResult
    func load(url: URL) -> Bool {
        if fileURL == url, file != nil { return true }
        stop()
        guard let f = try? AVAudioFile(forReading: url) else { file = nil; fileURL = nil; duration = 0; return false }
        file = f
        fileURL = url
        duration = Double(f.length) / f.processingFormat.sampleRate
        return true
    }

    func unload() { stop(); file = nil; fileURL = nil; duration = 0 }

    /// Start playing from `pos` seconds; the audio begins after `delay` seconds.
    func play(from pos: Double, delay: Double = 0.05) {
        guard let f = file else { return }
        startEngine()
        music.stop()
        let sr = f.processingFormat.sampleRate
        let frame = AVAudioFramePosition(max(0, pos) * sr)
        let frames = AVAudioFrameCount(max(0, f.length - frame))
        guard frames > 0 else { return }
        music.scheduleSegment(f, startingFrame: frame, frameCount: frames, at: nil, completionHandler: nil)
        // The varispeed unit scales the player's timeline, so a start scheduled `d` seconds ahead really
        // happens `d / rate` seconds ahead. Schedule `delay × rate` to get a start exactly `delay` from now.
        let rate = Double(varispeed.rate)
        let now = mach_absolute_time()
        music.play(at: AVAudioTime(hostTime: now + AudioManagerClock.host(delay * rate)))
        startHost = AudioManagerClock.seconds(now) + delay
        startPos = max(0, pos)
        isPlaying = true
    }

    /// Playback speed of the music (tape-style: pitch follows). Reset to 1 whenever playback stops.
    func setRate(_ r: Float) { varispeed.rate = min(4, max(0.25, r)) }

    /// Fades the music out and then stops it (used when a level ends early).
    func fadeOut(_ seconds: Double) {
        guard isPlaying else { return }
        fadeTimer?.invalidate()
        let start = fadeScale
        var elapsed = 0.0
        let t = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            elapsed += 1.0 / 30
            let p = min(1, elapsed / seconds)
            self.fadeScale = start * Float(1 - p)
            self.music.volume = self.musicVolume * self.fadeScale
            if p >= 1 { timer.invalidate(); self.stop() }
        }
        RunLoop.main.add(t, forMode: .common)
        fadeTimer = t
    }

    func stopPreview() { if isPreview { stop() } }

    func stop(ifOwner o: AnyObject) {
        if owner === o { owner = nil; stop() }
    }

    func stop() {
        music.stop()
        varispeed.rate = 1
        playRate = 1
        isPlaying = false
        isPreview = false
        fadeTimer?.invalidate()
        fadeScale = 1
        music.volume = musicVolume
    }

    /// Song position (seconds) for a given host time.
    func position(atHost h: Double) -> Double { (h - startHost) * playRate + startPos }

    /// Speed mods: varispeed changes tempo and pitch together (nightcore / daycore style).
    func setPlayRate(_ r: Double) { playRate = r; varispeed.rate = Float(min(4, max(0.25, r))) }
    func position() -> Double { position(atHost: Clock.hostNow()) }

    func playPreview(url: URL, from pos: Double) {
        guard owner == nil, load(url: url) else { return }
        let p = min(pos, max(0, duration - 12))
        fadeScale = 0
        music.volume = 0
        play(from: p, delay: 0.05)
        isPreview = true
        fadeTimer?.invalidate()
        var step = 0
        fadeTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            step += 1
            self.fadeScale = Float(min(1, Double(step) / 45))
            self.music.volume = self.musicVolume * self.fadeScale * 0.8
            if step >= 45 { t.invalidate() }
        }
    }

    // MARK: SFX

    func play(_ sfx: SFX, volume: Float = 1) {
        guard let buf = buffers[sfx] else { return }
        startEngine()
        let node = pool[poolIndex]
        poolIndex = (poolIndex + 1) % pool.count
        node.volume = sfxVolume * volume
        node.scheduleBuffer(buf, at: nil, options: .interrupts, completionHandler: nil)
        if !node.isPlaying { node.play() }
    }

    /// Schedule an SFX at an exact host time (used for calibration).
    func schedule(_ sfx: SFX, atHost seconds: Double, volume: Float = 1) {
        guard let buf = buffers[sfx] else { return }
        startEngine()
        let node = pool[poolIndex]
        poolIndex = (poolIndex + 1) % pool.count
        node.volume = sfxVolume * volume
        node.scheduleBuffer(buf, at: AVAudioTime(hostTime: AudioManagerClock.host(seconds)), options: [], completionHandler: nil)
        if !node.isPlaying { node.play() }
    }

    func stopSFX() { for n in pool { n.stop() } }

    // MARK: SFX synthesis

    private static func synth(_ duration: Double, format: AVAudioFormat, _ gen: (Double, inout UInt32) -> Double) -> AVAudioPCMBuffer {
        let sr = format.sampleRate
        let n = AVAudioFrameCount(duration * sr)
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: n)!
        buf.frameLength = n
        var noise: UInt32 = 0x1234ABCD
        let l = buf.floatChannelData![0], r = buf.floatChannelData![1]
        for i in 0..<Int(n) {
            let t = Double(i) / sr
            let v = Float(max(-1, min(1, gen(t, &noise))))
            l[i] = v
            r[i] = v
        }
        return buf
    }

    private static func white(_ s: inout UInt32) -> Double {
        s ^= s << 13; s ^= s >> 17; s ^= s << 5
        return Double(s) / Double(UInt32.max) * 2 - 1
    }

    static func makeSFX(_ s: SFX, format: AVAudioFormat) -> AVAudioPCMBuffer {
        let tau = 2 * Double.pi
        switch s {
        case .tap:
            return synth(0.09, format: format) { t, n in
                (sin(tau * 1500 * t) * 0.45 + sin(tau * 3000 * t) * 0.15) * exp(-t * 75) + white(&n) * 0.25 * exp(-t * 260)
            }
        case .hold:
            return synth(0.14, format: format) { t, n in
                sin(tau * 260 * t) * exp(-t * 28) * 0.7 + sin(tau * 1100 * t) * exp(-t * 90) * 0.3 + white(&n) * 0.2 * exp(-t * 300)
            }
        case .slide:
            return synth(0.18, format: format) { t, n in
                let f = 500 + 2200 * t
                return sin(tau * f * t) * sin(Double.pi * min(1, t / 0.18)) * 0.5 + white(&n) * 0.1 * sin(Double.pi * min(1, t / 0.18))
            }
        case .miss:
            return synth(0.18, format: format) { t, n in
                sin(tau * (110 - 200 * t) * t) * exp(-t * 16) * 0.55 + white(&n) * 0.08 * exp(-t * 60)
            }
        case .select:
            return synth(0.16, format: format) { t, _ in
                let f = t < 0.06 ? 880.0 : 1320.0
                return sin(tau * f * t) * exp(-t * 22) * 0.4
            }
        case .move:
            return synth(0.05, format: format) { t, _ in sin(tau * 700 * t) * exp(-t * 70) * 0.35 }
        case .back:
            return synth(0.14, format: format) { t, _ in
                let f = t < 0.05 ? 700.0 : 480.0
                return sin(tau * f * t) * exp(-t * 24) * 0.4
            }
        case .beep:
            return synth(0.12, format: format) { t, _ in sin(tau * 880 * t) * exp(-t * 14) * 0.45 }
        case .go:
            return synth(0.3, format: format) { t, _ in (sin(tau * 1320 * t) + 0.4 * sin(tau * 1980 * t)) * exp(-t * 9) * 0.4 }
        case .metronome:
            return synth(0.06, format: format) { t, _ in sin(tau * 1000 * t) * exp(-t * 80) * 0.7 }
        }
    }
}
