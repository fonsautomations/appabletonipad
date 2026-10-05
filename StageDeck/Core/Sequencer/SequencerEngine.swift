import Foundation

/// A MIDI message scheduled at an absolute engine tick.
public struct ScheduledEvent: Equatable, CustomStringConvertible {
    public var tick: Int
    public var port: MIDIPortID
    public var message: MIDIMessage
    /// Sort order inside a tick: clock < note off < control < note on.
    public var order: Int

    public init(tick: Int, port: MIDIPortID, message: MIDIMessage, order: Int) {
        self.tick = tick; self.port = port; self.message = message; self.order = order
    }

    public var description: String { "@\(tick) \(port) \(message)" }
}

/// Deterministic xorshift generator (used for tests and reproducible randomness).
public struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    public init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    public mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

/// Where the engine currently is, for UI display.
public struct SeqPosition: Equatable {
    public var patternIndex: Int
    public var cycleTick: Int // ticks since the cycle started
    public var cycleLengthTicks: Int
    public var stepsPerTrack: [Int] // current step index per track (-1 if unknown)
    public var bar: Int
    public var beat: Int

    public init(patternIndex: Int, cycleTick: Int, cycleLengthTicks: Int, stepsPerTrack: [Int], bar: Int, beat: Int) {
        self.patternIndex = patternIndex; self.cycleTick = cycleTick; self.cycleLengthTicks = cycleLengthTicks
        self.stepsPerTrack = stepsPerTrack; self.bar = bar; self.beat = beat
    }
}

/// Pure, platform-independent step sequencer engine.
///
/// Time is expressed in ticks (96 per quarter note). Call `start(atTick:)`, then repeatedly
/// `render(from:to:)` with contiguous, increasing ranges; the returned events are absolutely
/// timestamped and ready to be converted to host time by the platform layer.
public final class SequencerEngine {
    public var project: SeqProject {
        didSet {
            if currentPatternIndex >= project.patterns.count { currentPatternIndex = max(0, project.patterns.count - 1) }
            trackRuntimes.reserveCapacity(SeqTiming.maxTracks)
        }
    }
    public private(set) var currentPatternIndex: Int = 0
    public var queuedPatternIndex: Int? = nil
    public var fillActive: Bool = false
    public private(set) var isRunning: Bool = false
    public private(set) var playStartTick: Int = 0
    public private(set) var cycleStart: Int = 0
    public private(set) var lifetimeStart: Int = 0
    public private(set) var previousCycleStart: Int = 0
    public private(set) var previousPatternIndex: Int = 0
    public private(set) var cycleCount: Int = 0
    public private(set) var chainPosition: Int = 0
    public private(set) var songPosition: Int = 0
    public private(set) var songRepeat: Int = 0
    public var rng: RandomNumberGenerator

    private var cursor: Int = 0
    private var deferred: [ScheduledEvent] = []
    private var activeNotes: [NoteKey: Int] = [:] // key → count of pending offs
    private var trackRuntimes: [TrackRuntime] = Array(repeating: TrackRuntime(), count: SeqTiming.maxTracks)
    private var lfoLastValues: [String: Int] = [:]
    private var stepTriggerLog: [StepTrigger] = []

    public struct StepTrigger: Equatable {
        public var tick: Int
        public var track: Int
        public var step: Int
    }

    struct NoteKey: Hashable {
        var port: MIDIPortID
        var channel: UInt8
        var note: UInt8
    }

    struct TrackRuntime {
        var lastConditionResult: Bool = true
        var loopOffset: Int = 0
        var lastTrigTick: Int = 0
        var lastStepSlide: Bool = false
        var randomStep: Int = 0
        var randomK: Int = -1
    }

    enum Order {
        static let clock = 0
        static let noteOff = 1
        static let control = 2
        static let noteOn = 3
    }

    public init(project: SeqProject, rng: RandomNumberGenerator = SystemRandomNumberGenerator()) {
        self.project = project
        self.rng = rng
    }

    // MARK: - Public accessors

    public var currentPattern: Pattern {
        project.pattern(currentPatternIndex) ?? Pattern.empty(name: "—")
    }

    public var currentTempo: Double {
        currentPattern.tempo ?? project.tempo
    }

    public var masterLengthTicks: Int { currentPattern.masterLengthTicks }

    /// Triggers rendered so far (since the last call), for UI flashes.
    public func drainStepTriggers() -> [StepTrigger] {
        let out = stepTriggerLog
        stepTriggerLog.removeAll()
        return out
    }

    public func position(atTick tick: Int) -> SeqPosition {
        var cStart = cycleStart
        var pIndex = currentPatternIndex
        if tick < cycleStart {
            cStart = previousCycleStart
            pIndex = previousPatternIndex
        }
        let pattern = project.pattern(pIndex) ?? currentPattern
        let rel = max(0, tick - cStart)
        let steps = pattern.tracks.map { track -> Int in
            let s = track.speed.ticksPerStep
            let k = rel / s
            return stepIndex(forK: k, track: track, trackIndex: 0, useRandomState: false)
        }
        let beatTicks = SeqTiming.ppqn
        return SeqPosition(patternIndex: pIndex, cycleTick: rel, cycleLengthTicks: pattern.masterLengthTicks,
                           stepsPerTrack: steps, bar: rel / (beatTicks * 4), beat: (rel / beatTicks) % 4)
    }

    // MARK: - Transport

    /// Starts playback at the given absolute tick. Returns MIDI start + optional defaults.
    public func start(atTick tick: Int, patternIndex: Int? = nil) -> [ScheduledEvent] {
        if let p = patternIndex, project.pattern(p) != nil { currentPatternIndex = p }
        isRunning = true
        playStartTick = tick
        cursor = tick
        cycleStart = tick
        lifetimeStart = tick
        previousCycleStart = tick
        previousPatternIndex = currentPatternIndex
        cycleCount = 0
        deferred.removeAll()
        activeNotes.removeAll()
        lfoLastValues.removeAll()
        trackRuntimes = Array(repeating: TrackRuntime(), count: SeqTiming.maxTracks)
        for i in 0..<trackRuntimes.count { trackRuntimes[i].lastTrigTick = tick }
        if project.arrangeMode == .chain, let first = project.chain.first, project.pattern(first) != nil, patternIndex == nil {
            chainPosition = 0
            currentPatternIndex = first
        }
        if project.arrangeMode == .song, let first = project.song.first, project.pattern(first.patternIndex) != nil, patternIndex == nil {
            songPosition = 0
            songRepeat = 0
            currentPatternIndex = first.patternIndex
        }
        var events: [ScheduledEvent] = []
        if project.sendMIDIClock {
            events.append(ScheduledEvent(tick: tick, port: project.clockPort, message: .start, order: Order.clock))
        }
        events.append(contentsOf: defaultsEvents(atTick: tick))
        return events
    }

    /// Stops playback. Returns note-offs for every sounding note and the MIDI stop message.
    public func stop(atTick tick: Int) -> [ScheduledEvent] {
        var events: [ScheduledEvent] = []
        for (key, _) in activeNotes {
            events.append(ScheduledEvent(tick: tick, port: key.port, message: .noteOff(channel: key.channel, note: key.note, velocity: 0), order: Order.noteOff))
        }
        activeNotes.removeAll()
        deferred.removeAll()
        if project.sendMIDIClock {
            events.append(ScheduledEvent(tick: tick, port: project.clockPort, message: .stop, order: Order.clock))
        }
        isRunning = false
        return events
    }

    /// Immediately silences everything (panic) without changing the running state.
    public func allNotesOff(atTick tick: Int) -> [ScheduledEvent] {
        var events: [ScheduledEvent] = []
        for (key, _) in activeNotes {
            events.append(ScheduledEvent(tick: tick, port: key.port, message: .noteOff(channel: key.channel, note: key.note, velocity: 0), order: Order.noteOff))
        }
        activeNotes.removeAll()
        deferred.removeAll(where: { if case .noteOff = $0.message { return true } else { return false } })
        return events
    }

    /// Queues a pattern change for the next cycle boundary.
    public func queuePattern(_ index: Int) {
        guard project.pattern(index) != nil else { return }
        queuedPatternIndex = index
    }

    /// Switches pattern immediately (used while stopped).
    public func selectPattern(_ index: Int) {
        guard project.pattern(index) != nil else { return }
        if isRunning { queuePattern(index) } else { currentPatternIndex = index; previousPatternIndex = index }
    }

    // MARK: - Rendering

    /// Renders all events with ticks in [from, to). Ranges must be contiguous and increasing.
    public func render(from: Int, to: Int) -> [ScheduledEvent] {
        guard isRunning, to > from else { return [] }
        let horizon = to + SeqTiming.microRange
        if cursor < from { cursor = from }
        while cursor < horizon {
            // Handle cycle wraps when the processing cursor reaches a boundary.
            let boundary = cycleStart + masterLengthTicks
            if cursor >= boundary {
                wrapCycle(at: boundary)
                continue
            }
            let segmentEnd = min(horizon, boundary)
            processNominal(from: cursor, to: segmentEnd)
            cursor = segmentEnd
        }
        return emitDeferred(from: from, to: to)
    }

    private func emitDeferred(from: Int, to: Int) -> [ScheduledEvent] {
        var out: [ScheduledEvent] = []
        var keep: [ScheduledEvent] = []
        keep.reserveCapacity(deferred.count)
        for e in deferred {
            if e.tick < to { out.append(e) } else { keep.append(e) }
        }
        deferred = keep
        out.sort { a, b in a.tick != b.tick ? a.tick < b.tick : a.order < b.order }
        for e in out {
            switch e.message {
            case .noteOn(let ch, let n, _):
                activeNotes[NoteKey(port: e.port, channel: ch, note: n), default: 0] += 1
            case .noteOff(let ch, let n, _):
                let key = NoteKey(port: e.port, channel: ch, note: n)
                if let c = activeNotes[key] {
                    if c <= 1 { activeNotes.removeValue(forKey: key) } else { activeNotes[key] = c - 1 }
                }
            default: break
            }
        }
        return out
    }

    private func wrapCycle(at boundary: Int) {
        previousCycleStart = cycleStart
        previousPatternIndex = currentPatternIndex
        let oldPattern = currentPattern
        let oldCycleTicks = masterLengthTicks
        var nextIndex: Int? = nil
        if let q = queuedPatternIndex, project.pattern(q) != nil {
            nextIndex = q
            queuedPatternIndex = nil
        } else {
            switch project.arrangeMode {
            case .pattern:
                nextIndex = nil
            case .chain:
                if !project.chain.isEmpty {
                    chainPosition = (chainPosition + 1) % project.chain.count
                    let idx = project.chain[chainPosition]
                    if project.pattern(idx) != nil { nextIndex = idx }
                }
            case .song:
                if !project.song.isEmpty {
                    songRepeat += 1
                    let entry = project.song[min(songPosition, project.song.count - 1)]
                    if songRepeat >= max(1, entry.repeats) {
                        songRepeat = 0
                        songPosition = (songPosition + 1) % project.song.count
                    }
                    let idx = project.song[songPosition].patternIndex
                    if project.pattern(idx) != nil { nextIndex = idx }
                }
            }
        }
        cycleStart = boundary
        cycleCount += 1
        if let n = nextIndex, n != currentPatternIndex {
            currentPatternIndex = n
            lifetimeStart = boundary
            cycleCount = 0
            for i in 0..<trackRuntimes.count {
                trackRuntimes[i].loopOffset = 0
                trackRuntimes[i].lastConditionResult = true
                trackRuntimes[i].randomK = -1
            }
            lfoLastValues.removeAll()
            deferred.append(contentsOf: defaultsEvents(atTick: boundary))
        } else {
            // Same pattern: carry per-track loop counters over the completed cycle.
            for (i, track) in oldPattern.tracks.enumerated() where i < trackRuntimes.count {
                let loopTicks = max(1, track.length) * track.speed.ticksPerStep
                trackRuntimes[i].loopOffset += Int(ceil(Double(oldCycleTicks) / Double(loopTicks)))
                trackRuntimes[i].randomK = -1
            }
        }
    }

    private func defaultsEvents(atTick tick: Int) -> [ScheduledEvent] {
        guard project.sendDefaultsOnPatternStart else { return [] }
        var events: [ScheduledEvent] = []
        for track in currentPattern.tracks {
            for lane in track.ccLanes {
                events.append(ScheduledEvent(tick: tick, port: track.port,
                                             message: .controlChange(channel: UInt8(track.channel & 0x0F), controller: UInt8(lane.controller & 0x7F), value: UInt8(max(0, min(127, lane.defaultValue)))),
                                             order: Order.control))
            }
        }
        return events
    }

    /// Processes nominal ticks [from, to) of the current cycle.
    private func processNominal(from: Int, to: Int) {
        let pattern = currentPattern
        // MIDI clock
        if project.sendMIDIClock {
            var t = from - ((from - cycleStart) % SeqTiming.ticksPerClock + SeqTiming.ticksPerClock) % SeqTiming.ticksPerClock
            if t < from { t += SeqTiming.ticksPerClock }
            while t < to {
                deferred.append(ScheduledEvent(tick: t, port: project.clockPort, message: .clock, order: Order.clock))
                t += SeqTiming.ticksPerClock
            }
        }
        let anySolo = pattern.tracks.contains(where: { $0.solo })
        for (ti, track) in pattern.tracks.enumerated() where ti < SeqTiming.maxTracks {
            let audible = !track.mute && (!anySolo || track.solo)
            processSteps(track: track, trackIndex: ti, from: from, to: to, audible: audible, pattern: pattern)
            processLFOs(track: track, trackIndex: ti, from: from, to: to, audible: audible)
        }
    }

    private func stepIndex(forK k: Int, track: SeqTrack, trackIndex: Int, useRandomState: Bool) -> Int {
        let L = max(1, min(SeqTiming.maxSteps, track.length))
        switch track.direction {
        case .forward:
            return k % L
        case .reverse:
            return L - 1 - (k % L)
        case .pingpong:
            if L == 1 { return 0 }
            let period = 2 * L - 2
            let idx = k % period
            return idx < L ? idx : period - idx
        case .random:
            guard useRandomState else { return k % L }
            if trackRuntimes[trackIndex].randomK != k {
                trackRuntimes[trackIndex].randomK = k
                trackRuntimes[trackIndex].randomStep = Int(rng.next() % UInt64(L))
            }
            return trackRuntimes[trackIndex].randomStep
        }
    }

    private func processSteps(track: SeqTrack, trackIndex ti: Int, from: Int, to: Int, audible: Bool, pattern: Pattern) {
        let s = track.speed.ticksPerStep
        let L = max(1, min(SeqTiming.maxSteps, track.length))
        let swing = track.swing ?? pattern.swing
        let swingClamped: Double = Double(max(50, min(80, swing)))
        let swingFraction: Double = 2.0 * swingClamped / 100.0 - 1.0
        let swingOffset: Int = Int((Double(s) * swingFraction).rounded())
        // Nominal step ticks in [from, to): multiples of s from cycleStart.
        var k = Int(ceil(Double(from - cycleStart) / Double(s)))
        if k < 0 { k = 0 }
        while true {
            let nominal = cycleStart + k * s
            if nominal >= to { break }
            let idx = stepIndex(forK: k, track: track, trackIndex: ti, useRandomState: true)
            let loop = trackRuntimes[ti].loopOffset + k / L
            let step = track.step(idx)
            if step.isOn {
                var trig = nominal + max(-SeqTiming.microRange, min(SeqTiming.microRange, step.micro))
                if k % 2 == 1 { trig += swingOffset }
                if trig < playStartTick { trig = playStartTick }
                if evaluate(step: step, trackIndex: ti, loop: loop) && audible && rollProbability(step: step, track: track) {
                    emitTrig(step: step, stepIndex: idx, track: track, trackIndex: ti, at: trig, stepTicks: s, nominal: nominal)
                }
            }
            k += 1
        }
    }

    private func rollProbability(step: Step, track: SeqTrack) -> Bool {
        let p = max(0, min(100, step.probability))
        let c = max(0, min(100, track.chance))
        if p >= 100 && c >= 100 { return true }
        let roll = Int(rng.next() % 10000) // 0...9999
        return roll < (p * c)
    }

    /// Evaluates the trig condition and updates PRE state.
    private func evaluate(step: Step, trackIndex ti: Int, loop: Int) -> Bool {
        let result: Bool
        switch step.condition {
        case .always:
            return true
        case .ratio(let n, let of):
            let o = max(1, of)
            result = (loop % o) == (max(1, min(o, n)) - 1)
        case .fill: result = fillActive
        case .notFill: result = !fillActive
        case .first: result = loop == 0
        case .notFirst: result = loop != 0
        case .pre: result = trackRuntimes[ti].lastConditionResult
        case .notPre: result = !trackRuntimes[ti].lastConditionResult
        case .neighbor: result = ti > 0 ? trackRuntimes[ti - 1].lastConditionResult : false
        case .notNeighbor: result = ti > 0 ? !trackRuntimes[ti - 1].lastConditionResult : true
        }
        trackRuntimes[ti].lastConditionResult = result
        return result
    }

    private func emitTrig(step: Step, stepIndex: Int, track: SeqTrack, trackIndex ti: Int, at trig: Int, stepTicks s: Int, nominal: Int) {
        let channel = UInt8(track.channel & 0x0F)
        let port = track.port
        stepTriggerLog.append(StepTrigger(tick: trig, track: ti, step: stepIndex))
        // Parameter locks and program change first.
        for (cc, value) in step.locks.sorted(by: { $0.key < $1.key }) {
            deferred.append(ScheduledEvent(tick: trig, port: port,
                                           message: .controlChange(channel: channel, controller: UInt8(cc & 0x7F), value: UInt8(max(0, min(127, value)))),
                                           order: Order.control))
        }
        if step.programChange >= 0 {
            deferred.append(ScheduledEvent(tick: trig, port: port, message: .programChange(channel: channel, program: UInt8(step.programChange & 0x7F)), order: Order.control))
        }
        // Velocity
        var velocity = step.accent ? track.accentVelocity : step.velocity
        for lfo in track.lfos where lfo.enabled && lfo.destination == .velocity {
            let base = lfoBaseTick(lfo: lfo, trackIndex: ti, tick: trig)
            velocity += lfo.value(atTick: base, cycleSeed: ti) - lfo.center
        }
        velocity = max(1, min(127, velocity))
        // Notes
        var notes = step.notes.isEmpty ? [track.defaultNote] : step.notes
        notes = notes.map { n -> Int in
            var v = n + track.transpose + (track.isDrum ? 0 : project.globalTranspose)
            if track.scaleLock && !track.isDrum { v = project.scale.quantize(note: v, root: project.rootNote) }
            return max(0, min(127, v))
        }
        // Gate
        var lengthTicks = max(1, Int((step.length * Double(s)).rounded()))
        if step.slide {
            lengthTicks = max(1, (nominal + s + 2) - trig)
        }
        let count = max(1, min(16, step.retrig.count))
        let rate = max(1, step.retrig.rateTicks)
        let previousSlide = trackRuntimes[ti].lastStepSlide
        for hit in 0..<count {
            let hitTick = trig + hit * rate
            var hitVel = velocity
            if count > 1 {
                let ramp = Double(max(-100, min(100, step.retrig.velocityRamp))) / 100.0
                hitVel = Int((Double(velocity) * (1.0 + ramp * Double(hit) / Double(count - 1))).rounded())
                hitVel = max(1, min(127, hitVel))
            }
            let hitLength = count > 1 ? max(1, min(lengthTicks, rate - 1)) : lengthTicks
            for note in notes {
                let n = UInt8(note)
                let key = NoteKey(port: port, channel: channel, note: n)
                // Close an overlapping pending note-off unless the previous step slides into this one.
                if !(previousSlide && hit == 0) {
                    for i in deferred.indices where deferred[i].port == port && deferred[i].tick > hitTick {
                        if case .noteOff(let ch, let nn, _) = deferred[i].message, ch == channel, nn == n {
                            deferred[i].tick = hitTick
                        }
                    }
                }
                _ = key
                deferred.append(ScheduledEvent(tick: hitTick, port: port, message: .noteOn(channel: channel, note: n, velocity: UInt8(hitVel)), order: Order.noteOn))
                deferred.append(ScheduledEvent(tick: hitTick + hitLength, port: port, message: .noteOff(channel: channel, note: n, velocity: 0), order: Order.noteOff))
            }
        }
        trackRuntimes[ti].lastStepSlide = step.slide
        trackRuntimes[ti].lastTrigTick = trig
    }

    private func lfoBaseTick(lfo: LFO, trackIndex ti: Int, tick: Int) -> Int {
        switch lfo.mode {
        case .free: return tick - lifetimeStart
        case .trig, .oneShot: return tick - trackRuntimes[ti].lastTrigTick
        }
    }

    private func processLFOs(track: SeqTrack, trackIndex ti: Int, from: Int, to: Int, audible: Bool) {
        guard audible else { return }
        for (li, lfo) in track.lfos.enumerated() where lfo.enabled {
            let key = "\(ti):\(li)"
            var t = from - ((from % SeqTiming.lfoResolutionTicks) + SeqTiming.lfoResolutionTicks) % SeqTiming.lfoResolutionTicks
            if t < from { t += SeqTiming.lfoResolutionTicks }
            while t < to {
                let base = lfoBaseTick(lfo: lfo, trackIndex: ti, tick: t)
                let value = lfo.value(atTick: base, cycleSeed: ti &+ li)
                if lfoLastValues[key] != value {
                    lfoLastValues[key] = value
                    let channel = UInt8(track.channel & 0x0F)
                    switch lfo.destination {
                    case .cc(let cc):
                        deferred.append(ScheduledEvent(tick: t, port: track.port, message: .controlChange(channel: channel, controller: UInt8(cc & 0x7F), value: UInt8(value)), order: Order.control))
                    case .pitchBend:
                        deferred.append(ScheduledEvent(tick: t, port: track.port, message: .pitchBend(channel: channel, value: UInt16(value) << 7), order: Order.control))
                    case .velocity, .none:
                        break
                    }
                }
                t += SeqTiming.lfoResolutionTicks
            }
        }
    }

    // MARK: - Live input / recording

    /// Records a note played live into the nearest step of the given track (quantized).
    public func record(note: Int, velocity: Int, track ti: Int, atTick tick: Int) {
        guard let pattern = project.pattern(currentPatternIndex), ti >= 0, ti < pattern.tracks.count else { return }
        var track = pattern.tracks[ti]
        let s = track.speed.ticksPerStep
        let rel = max(0, tick - cycleStart)
        let k = Int((Double(rel) / Double(s)).rounded())
        let idx = k % max(1, track.length)
        var step = track.step(idx)
        step.isOn = true
        if !step.notes.contains(note) { step.notes.append(note) }
        if step.notes.count > 4 { step.notes.removeFirst() }
        step.velocity = max(1, min(127, velocity))
        track.setStep(idx, step)
        project.patterns[currentPatternIndex].tracks[ti] = track
    }

    /// A one-off note from the on-screen keyboard (not recorded).
    public func playNote(_ note: Int, velocity: Int, track ti: Int, on: Bool, atTick tick: Int) -> ScheduledEvent? {
        guard let pattern = project.pattern(currentPatternIndex), ti >= 0, ti < pattern.tracks.count else { return nil }
        let track = pattern.tracks[ti]
        let n = UInt8(max(0, min(127, note + track.transpose)))
        let ch = UInt8(track.channel & 0x0F)
        let key = NoteKey(port: track.port, channel: ch, note: n)
        if on {
            activeNotes[key, default: 0] += 1
            return ScheduledEvent(tick: tick, port: track.port, message: .noteOn(channel: ch, note: n, velocity: UInt8(max(1, min(127, velocity)))), order: Order.noteOn)
        } else {
            if let c = activeNotes[key] { if c <= 1 { activeNotes.removeValue(forKey: key) } else { activeNotes[key] = c - 1 } }
            return ScheduledEvent(tick: tick, port: track.port, message: .noteOff(channel: ch, note: n, velocity: 0), order: Order.noteOff)
        }
    }
}

/// Tick ↔ seconds conversion anchored at a known point, so tempo changes do not jump the position.
public struct TickClock: Equatable {
    public var tempo: Double
    public var anchorTick: Double
    public var anchorTime: Double // seconds

    public init(tempo: Double, anchorTick: Double = 0, anchorTime: Double = 0) {
        self.tempo = max(20, min(400, tempo))
        self.anchorTick = anchorTick
        self.anchorTime = anchorTime
    }

    public var secondsPerTick: Double { 60.0 / tempo / Double(SeqTiming.ppqn) }

    public func tick(at time: Double) -> Double {
        anchorTick + (time - anchorTime) / secondsPerTick
    }

    public func time(ofTick tick: Double) -> Double {
        anchorTime + (tick - anchorTick) * secondsPerTick
    }

    /// Changes tempo while keeping the position continuous at `time`.
    public mutating func setTempo(_ newTempo: Double, at time: Double) {
        let t = tick(at: time)
        anchorTick = t
        anchorTime = time
        tempo = max(20, min(400, newTempo))
    }
}
