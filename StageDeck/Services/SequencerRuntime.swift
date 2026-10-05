import Foundation
import Combine

enum SyncMode: String, CaseIterable, Identifiable {
    case internalClock = "Internal"
    case externalClock = "MIDI Clock In"
    var id: String { rawValue }
}

/// Thread-safe real-time core: owns the engine, the tick clock and the render timer.
/// Not actor-isolated on purpose: it is driven from a high-priority dispatch timer.
final class SequencerCore: @unchecked Sendable {
    let engine: SequencerEngine
    let midi: MIDIService
    private let lock = NSLock()
    private var clock = TickClock(tempo: 120)
    private var lastRenderedTick = 0
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "stagedeck.sequencer", qos: .userInteractive)
    private let lookahead = 0.06 // seconds rendered ahead of real time
    private var syncExternal = false
    private var externalClockCount = 0
    private var lastExternalClockTime: Double = 0
    private var externalSecondsPerClock: Double = 60.0 / 120.0 / 24.0
    private var externalRunning = false
    /// Incremented whenever the engine itself changes the project (live recording).
    private(set) var recordVersion = 0

    init(project: SeqProject, midi: MIDIService) {
        engine = SequencerEngine(project: project)
        self.midi = midi
    }

    // MARK: Project access (always under lock)

    func withEngine<T>(_ body: (SequencerEngine) -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body(engine)
    }

    var project: SeqProject {
        get { withEngine { $0.project } }
        set { withEngine { $0.project = newValue } }
    }

    var tempo: Double {
        lock.lock(); defer { lock.unlock() }
        return clock.tempo
    }

    func setTempo(_ bpm: Double) {
        lock.lock()
        clock.setTempo(bpm, at: HostTime.nowSeconds)
        engine.project.tempo = max(20, min(400, bpm))
        lock.unlock()
    }

    func setSyncExternal(_ external: Bool) {
        lock.lock()
        syncExternal = external
        lock.unlock()
    }

    var isRunning: Bool { withEngine { $0.isRunning } }

    /// Current engine tick according to the clock (for UI).
    var currentTick: Int {
        lock.lock(); defer { lock.unlock() }
        if syncExternal { return max(0, externalClockCount * SeqTiming.ticksPerClock - SeqTiming.ticksPerClock) }
        return Int(clock.tick(at: HostTime.nowSeconds))
    }

    var externalTempo: Double {
        lock.lock(); defer { lock.unlock() }
        return externalSecondsPerClock > 0 ? 60.0 / (externalSecondsPerClock * 24.0) : 0
    }

    // MARK: Transport

    func start(patternIndex: Int? = nil) {
        lock.lock()
        let now = HostTime.nowSeconds
        clock = TickClock(tempo: engine.currentTempo, anchorTick: 0, anchorTime: now + 0.01)
        if let p = patternIndex { engine.selectPattern(p) }
        let events = engine.start(atTick: 0, patternIndex: patternIndex)
        clock.setTempo(engine.currentTempo, at: now + 0.01)
        lastRenderedTick = 0
        externalClockCount = 0
        externalRunning = true
        let c = clock
        lock.unlock()
        dispatch(events, clock: c)
        startTimer()
    }

    func stop() {
        lock.lock()
        let tick = lastRenderedTick
        let events = engine.stop(atTick: tick)
        externalRunning = false
        lock.unlock()
        stopTimer()
        send(now: events)
    }

    func panic() {
        lock.lock()
        let events = engine.allNotesOff(atTick: lastRenderedTick)
        lock.unlock()
        send(now: events)
        midi.panic()
    }

    private func startTimer() {
        stopTimer()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: .milliseconds(5), leeway: .milliseconds(1))
        t.setEventHandler { [weak self] in self?.timerTick() }
        t.resume()
        timer = t
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
    }

    private func timerTick() {
        lock.lock()
        guard engine.isRunning, !syncExternal else { lock.unlock(); return }
        let now = HostTime.nowSeconds
        let target = Int(clock.tick(at: now + lookahead))
        guard target > lastRenderedTick else { lock.unlock(); return }
        var events: [ScheduledEvent] = []
        // After a suspension (screen lock, app switch) catch up silently instead of blasting stale notes.
        let gapLimit = SeqTiming.ppqn * 8
        if target - lastRenderedTick > gapLimit {
            let resume = target - SeqTiming.ppqn / 4
            _ = engine.render(from: lastRenderedTick, to: resume)
            events.append(contentsOf: engine.allNotesOff(atTick: resume))
            lastRenderedTick = resume
        }
        events.append(contentsOf: engine.render(from: lastRenderedTick, to: target))
        lastRenderedTick = target
        let engineTempo = engine.currentTempo
        if abs(engineTempo - clock.tempo) > 0.001 { clock.setTempo(engineTempo, at: now) }
        let c = clock
        lock.unlock()
        dispatch(events, clock: c)
    }

    // MARK: External MIDI clock

    func externalMessage(_ message: MIDIMessage) {
        lock.lock()
        guard syncExternal else { lock.unlock(); return }
        let now = HostTime.nowSeconds
        switch message {
        case .start:
            let events = engine.isRunning ? engine.stop(atTick: lastRenderedTick) : []
            lock.unlock()
            send(now: events)
            lock.lock()
            let startEvents = engine.start(atTick: 0)
            lastRenderedTick = 0
            externalClockCount = 0
            externalRunning = true
            lastExternalClockTime = 0
            lock.unlock()
            send(now: startEvents)
        case .continue:
            externalRunning = true
            lock.unlock()
        case .stop:
            externalRunning = false
            let events = engine.isRunning ? engine.stop(atTick: lastRenderedTick) : []
            lock.unlock()
            send(now: events)
        case .clock:
            guard externalRunning, engine.isRunning else { lock.unlock(); return }
            if lastExternalClockTime > 0 {
                let interval = now - lastExternalClockTime
                if interval > 0.002 && interval < 0.5 {
                    externalSecondsPerClock = externalSecondsPerClock * 0.9 + interval * 0.1
                }
            }
            lastExternalClockTime = now
            let from = externalClockCount * SeqTiming.ticksPerClock
            let to = from + SeqTiming.ticksPerClock
            externalClockCount += 1
            let events = engine.render(from: from, to: to)
            lastRenderedTick = to
            let spc = externalSecondsPerClock / Double(SeqTiming.ticksPerClock)
            let bpm = 60.0 / (externalSecondsPerClock * 24.0)
            if abs(bpm - clock.tempo) > 0.5 { clock = TickClock(tempo: bpm, anchorTick: Double(from), anchorTime: now) }
            lock.unlock()
            let stamped: [(MIDIMessage, UInt64)] = events.map { e in
                (e.message, HostTime.hostTicks(fromSeconds: now + Double(e.tick - from) * spc))
            }
            sendGrouped(events: events, stamps: stamped)
        default:
            lock.unlock()
        }
    }

    // MARK: Output

    private func dispatch(_ events: [ScheduledEvent], clock: TickClock) {
        guard !events.isEmpty else { return }
        let stamped: [(MIDIMessage, UInt64)] = events.map { e in
            (e.message, HostTime.hostTicks(fromSeconds: clock.time(ofTick: Double(e.tick))))
        }
        sendGrouped(events: events, stamps: stamped)
    }

    private func sendGrouped(events: [ScheduledEvent], stamps: [(MIDIMessage, UInt64)]) {
        var byPort: [MIDIPortID: [(MIDIMessage, UInt64)]] = [:]
        for (i, e) in events.enumerated() {
            byPort[e.port, default: []].append(stamps[i])
        }
        for (port, msgs) in byPort { midi.send(msgs, to: port) }
    }

    private func send(now events: [ScheduledEvent]) {
        guard !events.isEmpty else { return }
        var byPort: [MIDIPortID: [(MIDIMessage, UInt64)]] = [:]
        for e in events { byPort[e.port, default: []].append((e.message, 0)) }
        for (port, msgs) in byPort { midi.send(msgs, to: port) }
    }

    // MARK: Live input

    func playNote(_ note: Int, velocity: Int, track: Int, on: Bool, record: Bool) {
        lock.lock()
        let tick = syncExternal ? lastRenderedTick : Int(clock.tick(at: HostTime.nowSeconds))
        let event = engine.playNote(note, velocity: velocity, track: track, on: on, atTick: tick)
        if on && record && engine.isRunning {
            engine.record(note: note, velocity: velocity, track: track, atTick: tick)
            recordVersion += 1
        }
        lock.unlock()
        if let e = event { send(now: [e]) }
    }
}

/// Main-thread facade for the sequencer used by the UI.
@MainActor
final class SequencerRuntime: ObservableObject {
    @Published var project: SeqProject {
        didSet { if !suppressPush { core.project = project } }
    }
    @Published private(set) var isRunning = false
    @Published private(set) var position = SeqPosition(patternIndex: 0, cycleTick: 0, cycleLengthTicks: 384, stepsPerTrack: [], bar: 0, beat: 0)
    @Published private(set) var tempo: Double = 124
    @Published var syncMode: SyncMode = .internalClock {
        didSet { core.setSyncExternal(syncMode == .externalClock) }
    }
    @Published var fillActive = false {
        didSet { core.withEngine { $0.fillActive = fillActive } }
    }
    @Published var recordEnabled = false
    @Published private(set) var flashes: [Int: Int] = [:] // track → last flashed step
    @Published private(set) var externalTempo: Double = 0
    @Published private(set) var currentPatternIndex = 0
    @Published private(set) var queuedPatternIndex: Int? = nil
    @Published var selectedTrack = 0
    @Published var selectedStep: Int? = nil
    @Published var stepPage = 0

    let core: SequencerCore
    let midi: MIDIService
    private var uiTimer: Timer?
    private var suppressPush = false
    private var lastRecordVersion = 0

    init(project: SeqProject, midi: MIDIService) {
        self.project = project
        self.midi = midi
        self.core = SequencerCore(project: project, midi: midi)
        self.tempo = project.tempo
        core.setTempo(project.tempo)
        let realtimeCore = core
        midi.onMessage = { message, _ in
            guard message.isRealtime else { return }
            realtimeCore.externalMessage(message)
        }
        uiTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshUI() }
        }
    }

    private func refreshUI() {
        let running = core.isRunning
        if running != isRunning { isRunning = running }
        let tick = core.currentTick
        let pos = core.withEngine { $0.position(atTick: tick) }
        if pos.stepsPerTrack != position.stepsPerTrack || pos.patternIndex != position.patternIndex || pos.bar != position.bar || pos.beat != position.beat {
            position = pos
        }
        let p = core.withEngine { $0.currentPatternIndex }
        if p != currentPatternIndex { currentPatternIndex = p }
        let q = core.withEngine { $0.queuedPatternIndex }
        if q != queuedPatternIndex { queuedPatternIndex = q }
        let triggers = core.withEngine { $0.drainStepTriggers() }
        if !triggers.isEmpty {
            for t in triggers { flashes[t.track] = t.step }
        }
        if syncMode == .externalClock {
            let et = core.externalTempo
            if abs(et - externalTempo) > 0.1 { externalTempo = et }
        }
        let version = core.recordVersion
        if version != lastRecordVersion {
            lastRecordVersion = version
            suppressPush = true
            project = core.project
            suppressPush = false
        }
    }

    // MARK: Transport

    func play() {
        core.start(patternIndex: nil)
        isRunning = true
    }

    func stop() {
        core.stop()
        isRunning = false
        flashes.removeAll()
    }

    func toggle() { isRunning ? stop() : play() }

    func panic() { core.panic() }

    func setTempo(_ bpm: Double) {
        let v = max(20, min(400, bpm))
        tempo = v
        core.setTempo(v)
        suppressPush = true
        project.tempo = v
        suppressPush = false
    }

    func selectPattern(_ index: Int) {
        guard index >= 0, index < project.patterns.count else { return }
        core.withEngine { $0.selectPattern(index) }
        if !isRunning { currentPatternIndex = index }
    }

    func playNote(_ note: Int, velocity: Int = 100, on: Bool) {
        core.playNote(note, velocity: velocity, track: selectedTrack, on: on, record: recordEnabled)
    }

    // MARK: Editing helpers (operate on `project`, which is pushed to the engine)

    var pattern: Pattern {
        get { project.patterns[min(max(0, currentPatternIndex), project.patterns.count - 1)] }
        set { project.patterns[min(max(0, currentPatternIndex), project.patterns.count - 1)] = newValue }
    }

    var track: SeqTrack {
        get { pattern.tracks[min(max(0, selectedTrack), pattern.tracks.count - 1)] }
        set { pattern.tracks[min(max(0, selectedTrack), pattern.tracks.count - 1)] = newValue }
    }

    func toggleStep(_ index: Int) {
        var t = track
        var s = t.step(index)
        if s.isOn && s.notes.isEmpty && s.locks.isEmpty && s.condition == .always && s.retrig.count == 1 {
            s = Step()
        } else if s.isOn {
            s.isOn = false
        } else {
            s.isOn = true
        }
        t.setStep(index, s)
        track = t
    }

    func updateStep(_ index: Int, _ body: (inout Step) -> Void) {
        var t = track
        var s = t.step(index)
        body(&s)
        t.setStep(index, s)
        track = t
    }

    func updateTrack(_ body: (inout SeqTrack) -> Void) {
        var t = track
        body(&t)
        track = t
    }

    func clearTrack() {
        updateTrack { t in t.steps = Array(repeating: Step(), count: SeqTiming.maxSteps) }
    }

    func applyEuclid(pulses: Int, rotation: Int) {
        updateTrack { t in
            let pattern = Euclid.pattern(steps: t.length, pulses: pulses, rotation: rotation)
            for i in 0..<t.length {
                var s = t.steps[i]
                s.isOn = pattern[i]
                t.steps[i] = s
            }
        }
    }

    func randomizeTrack(density: Int) {
        updateTrack { t in
            for i in 0..<t.length {
                var s = t.steps[i]
                s.isOn = Int.random(in: 0..<100) < density
                if s.isOn && !t.isDrum {
                    let scale = project.scale
                    let candidates = scale.notes(root: project.rootNote, from: t.defaultNote - 12, to: t.defaultNote + 12)
                    s.notes = [candidates.randomElement() ?? t.defaultNote]
                    s.velocity = Int.random(in: 70...120)
                } else if s.isOn {
                    s.velocity = Int.random(in: 80...127)
                }
                t.steps[i] = s
            }
        }
    }

    func copyPattern() {
        var p = pattern
        p.id = UUID()
        p.name = pattern.name + " copy"
        project.patterns.append(p)
    }

    func addPattern() {
        guard project.patterns.count < 64 else { return }
        var p = Pattern.empty(name: "P\(project.patterns.count + 1)", trackCount: pattern.tracks.count)
        for (i, t) in pattern.tracks.enumerated() where i < p.tracks.count {
            p.tracks[i].name = t.name
            p.tracks[i].colorHex = t.colorHex
            p.tracks[i].channel = t.channel
            p.tracks[i].port = t.port
            p.tracks[i].defaultNote = t.defaultNote
            p.tracks[i].isDrum = t.isDrum
            p.tracks[i].ccLanes = t.ccLanes
        }
        project.patterns.append(p)
    }

    func deletePattern(_ index: Int) {
        guard project.patterns.count > 1, index < project.patterns.count else { return }
        project.patterns.remove(at: index)
        project.chain = project.chain.filter { $0 < project.patterns.count }
        if project.chain.isEmpty { project.chain = [0] }
        project.song = project.song.filter { $0.patternIndex < project.patterns.count }
        if project.song.isEmpty { project.song = [SongEntry(patternIndex: 0)] }
        if currentPatternIndex >= project.patterns.count { selectPattern(project.patterns.count - 1) }
    }
}
