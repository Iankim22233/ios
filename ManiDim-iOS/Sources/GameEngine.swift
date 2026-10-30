import Foundation

enum HitKind { case tap, holdHead, holdTail, slide }

enum GameEvent {
    case keyDown(lane: Int)
    case keyUp(lane: Int)
    case hit(lane: Int, judgment: Judgment, offset: Double, kind: HitKind)
    case miss(lane: Int, kind: HitKind)
    case holdBegin(lane: Int)
    case holdEnd(lane: Int, success: Bool)
    case slide(from: Int, to: Int, judgment: Judgment)
    /// Too many keys pressed at once for the notes that were due — counted as a miss.
    case mash(lane: Int)
}

final class RNote {
    enum State { case waiting, holding, done, missed, dropped }
    let note: Note
    var state: State = .waiting
    var headJudgment: Judgment?
    var nextSlide = 0
    var changedAt: Double = -100
    var holdKey: Int

    init(_ n: Note) { note = n; holdKey = n.lane }
}

/// Pure game logic: judgments, holds, slides, scoring. Time is song time (seconds).
final class GameEngine {
    let laneCount: Int
    let notes: [RNote]
    private var laneQueues: [[Int]]
    private var laneCursor: [Int]
    private(set) var holding: [Int] = []
    private(set) var keyDown: [Bool]

    private(set) var counts = [0, 0, 0, 0]
    private(set) var earned = 0.0
    private(set) var judged = 0
    private(set) var combo = 0
    private(set) var maxCombo = 0
    private(set) var offsets: [Double] = []
    let totalObjects: Int
    var onEvent: ((GameEvent) -> Void)?
    private func emit(_ e: GameEvent) { onEvent?(e) }

    let windowScale: Double
    var hitWindow: Double { 0.135 * windowScale }
    var slideWindow: Double { 0.16 * windowScale }
    let grace = 0.03
    var bot = false
    private var botCursor = 0
    private var botReleases: [(lane: Int, time: Double)] = []
    // Anti-mash: lane presses in the last 50 ms
    private var recentPresses: [Double] = []
    private var burstDue = 0
    let mashWindow = 0.05
    let lastTime: Double

    var score: Int { Int((1_000_000 * earned / Double(max(1, totalObjects))).rounded()) }
    var accuracy: Double { judged == 0 ? 1 : earned / Double(judged) }
    var progressObjects: Double { Double(judged) / Double(max(1, totalObjects)) }

    init(chart: Chart, laneCount: Int, startTime: Double = 0, windowScale: Double = 1) {
        self.laneCount = laneCount
        self.windowScale = windowScale
        var list = chart.notes
            .filter { $0.time >= startTime - 0.001 && $0.lane >= 0 && $0.lane < laneCount }
            .sorted { ($0.time, $0.lane) < ($1.time, $1.lane) }
        // Make sure slides never leave the lane range and are in order.
        for i in list.indices {
            list[i].slides.sort { $0.time < $1.time }
            list[i].slides = list[i].slides.filter { $0.time > list[i].time && $0.time < list[i].endTime }
        }
        notes = list.map { RNote($0) }
        laneQueues = Array(repeating: [], count: laneCount)
        for (i, n) in notes.enumerated() { laneQueues[n.note.lane].append(i) }
        laneCursor = Array(repeating: 0, count: laneCount)
        keyDown = Array(repeating: false, count: laneCount)
        totalObjects = list.reduce(0) { $0 + ($1.isHold ? 2 + $1.slides.count : 1) }
        lastTime = list.map(\.endTime).max() ?? 0
    }

    var isFinished: Bool {
        !notes.contains { $0.state == .waiting || $0.state == .holding }
    }

    // MARK: Judging

    private func judge(_ dt: Double, windows: (Double, Double, Double) = (0.045, 0.09, 0.135)) -> Judgment {
        let d = abs(dt) / windowScale
        if d <= windows.0 { return .perfect }
        if d <= windows.1 { return .great }
        return .good
    }

    private func account(_ j: Judgment) {
        counts[j.rawValue] += 1
        earned += j.weight
        judged += 1
        if j == .miss { combo = 0 } else { combo += 1; maxCombo = max(maxCombo, combo) }
    }

    private func nextWaiting(_ lane: Int) -> Int? {
        var c = laneCursor[lane]
        let q = laneQueues[lane]
        while c < q.count, notes[q[c]].state != .waiting { c += 1 }
        laneCursor[lane] = c
        return c < q.count ? q[c] : nil
    }

    // MARK: Input

    /// `pendingDown` = other lane keys that are physically down but whose key events haven't been processed yet
    /// (the game passes this so a mash of keys pressed in the same instant is seen as a whole).
    func press(lane: Int, at t: Double, pendingDown: Int = 0) {
        guard lane >= 0, lane < laneCount else { return }
        keyDown[lane] = true
        emit(.keyDown(lane: lane))

        // Anti-mash: pressing more keys than there are notes due (and more than 2) is a miss, not a hit.
        recentPresses.removeAll { abs(t - $0) > mashWindow }
        if recentPresses.isEmpty { burstDue = 0 }
        recentPresses.append(t)
        var due = 0
        for l in 0..<laneCount {
            if let i = nextWaiting(l), abs(notes[i].note.time - t) <= 0.08 { due += 1 }
        }
        burstDue = max(burstDue, due)
        if recentPresses.count + pendingDown > max(2, burstDue) {
            if let idx = nextWaiting(lane), abs(t - notes[idx].note.time) <= hitWindow + grace {
                missHead(idx, now: t)
                emit(.mash(lane: lane))
            }
            return
        }

        guard let idx = nextWaiting(lane) else { return }
        let rn = notes[idx]
        let dt = t - rn.note.time
        guard dt >= -hitWindow, dt <= hitWindow else { return }
        let j = judge(dt)
        account(j)
        offsets.append(dt)
        rn.headJudgment = j
        rn.changedAt = t
        if rn.note.isHold {
            rn.state = .holding
            rn.holdKey = lane
            holding.append(idx)
            emit(.hit(lane: lane, judgment: j, offset: dt, kind: .holdHead))
            emit(.holdBegin(lane: lane))
        } else {
            rn.state = .done
            emit(.hit(lane: lane, judgment: j, offset: dt, kind: .tap))
        }
    }

    func release(lane: Int, at t: Double) {
        guard lane >= 0, lane < laneCount else { return }
        if keyDown[lane] { emit(.keyUp(lane: lane)) }
        keyDown[lane] = false
        for idx in holding where notes[idx].holdKey == lane {
            let rn = notes[idx]
            if t >= rn.note.endTime - 0.12 { completeHold(idx, at: t) } else { dropHold(idx, at: t) }
        }
    }

    func slide(dir: Int, at t: Double) {
        var best: (idx: Int, dt: Double)?
        for idx in holding {
            let rn = notes[idx]
            guard rn.nextSlide < rn.note.slides.count else { continue }
            let s = rn.note.slides[rn.nextSlide]
            guard s.dir == dir else { continue }
            let dt = t - s.time
            guard abs(dt) <= slideWindow else { continue }
            if best == nil || abs(dt) < abs(best!.dt) { best = (idx, dt) }
        }
        guard let b = best else { return }
        let rn = notes[b.idx]
        let s = rn.note.slides[rn.nextSlide]
        let j = judge(b.dt, windows: (0.07, 0.115, 0.16))
        account(j)
        offsets.append(b.dt)
        rn.nextSlide += 1
        let from = rn.note.lane(at: s.time - 1e-6, count: laneCount)
        let to = rn.note.lane(at: s.time, count: laneCount)
        emit(.slide(from: from, to: to, judgment: j))
        emit(.hit(lane: to, judgment: j, offset: b.dt, kind: .slide))
    }

    // MARK: Updating

    func update(now: Double) {
        if bot { runBot(now: now) }

        for lane in 0..<laneCount {
            while let idx = nextWaiting(lane) {
                let rn = notes[idx]
                if now - rn.note.time > hitWindow + grace { missHead(idx, now: now) } else { break }
            }
        }

        for idx in holding {
            let rn = notes[idx]
            while rn.nextSlide < rn.note.slides.count,
                  now - rn.note.slides[rn.nextSlide].time > slideWindow + grace {
                let s = rn.note.slides[rn.nextSlide]
                rn.nextSlide += 1
                account(.miss)
                emit(.miss(lane: rn.note.lane(at: s.time, count: laneCount), kind: .slide))
            }
            if now >= rn.note.endTime { completeHold(idx, at: now) }
        }
    }

    private func missHead(_ idx: Int, now: Double) {
        let rn = notes[idx]
        rn.state = .missed
        rn.changedAt = now
        account(.miss)
        emit(.miss(lane: rn.note.lane, kind: rn.note.isHold ? .holdHead : .tap))
        if rn.note.isHold {
            for _ in 0..<(1 + rn.note.slides.count) { account(.miss) }
        }
    }

    private func completeHold(_ idx: Int, at t: Double) {
        let rn = notes[idx]
        guard rn.state == .holding else { return }
        rn.state = .done
        rn.changedAt = t
        holding.removeAll { $0 == idx }
        // Any slides not judged by now count as misses.
        while rn.nextSlide < rn.note.slides.count { rn.nextSlide += 1; account(.miss) }
        account(.perfect)
        let lane = rn.note.finalLane(count: laneCount)
        emit(.hit(lane: lane, judgment: .perfect, offset: 0, kind: .holdTail))
        emit(.holdEnd(lane: lane, success: true))
    }

    private func dropHold(_ idx: Int, at t: Double) {
        let rn = notes[idx]
        guard rn.state == .holding else { return }
        rn.state = .dropped
        rn.changedAt = t
        holding.removeAll { $0 == idx }
        account(.miss)
        while rn.nextSlide < rn.note.slides.count { rn.nextSlide += 1; account(.miss) }
        let lane = rn.note.lane(at: t, count: laneCount)
        emit(.miss(lane: lane, kind: .holdTail))
        emit(.holdEnd(lane: lane, success: false))
    }

    // MARK: Autoplay

    private func runBot(now: Double) {
        while botCursor < notes.count, notes[botCursor].note.time <= now {
            let rn = notes[botCursor]
            botCursor += 1
            guard rn.state == .waiting else { continue }
            press(lane: rn.note.lane, at: rn.note.time)
            let rel = rn.note.isHold ? rn.note.endTime : rn.note.time + 0.07
            botReleases.append((rn.note.lane, rel))
        }
        for idx in holding {
            let rn = notes[idx]
            while rn.nextSlide < rn.note.slides.count, rn.note.slides[rn.nextSlide].time <= now {
                let s = rn.note.slides[rn.nextSlide]
                let before = rn.nextSlide
                slide(dir: s.dir, at: s.time)
                if rn.nextSlide == before { rn.nextSlide += 1 }
            }
        }
        var remaining: [(lane: Int, time: Double)] = []
        for r in botReleases {
            if r.time <= now { release(lane: r.lane, at: r.time) } else { remaining.append(r) }
        }
        botReleases = remaining
    }

    func result(song: Song, chart: Chart, autoplay: Bool, fromEditor: Bool) -> ResultData {
        ResultData(songID: song.id, songTitle: song.title, artist: song.artist, chartName: chart.name,
                   chartLevel: chart.level, hue: song.hue, score: score, accuracy: accuracy, maxCombo: maxCombo,
                   counts: counts, offsets: offsets, totalObjects: totalObjects, autoplay: autoplay, fromEditor: fromEditor)
    }
}
