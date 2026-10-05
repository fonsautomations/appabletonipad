import Foundation

/// Timing constants. Ticks are the engine's unit; 96 ticks per quarter note, 24 per 16th-note step.
public enum SeqTiming {
    public static let ppqn = 96
    public static let ticksPerStep = 24
    public static let ticksPerClock = ppqn / 24 // MIDI clock = 24 PPQN → 4 ticks
    public static let maxSteps = 64
    public static let maxTracks = 16
    public static let microRange = 11 // ± ticks (just under half a step)
    public static let lfoResolutionTicks = 6 // evaluate LFOs every 1/64 note
}

/// Playback speed of a track relative to the pattern (Elektron-style "scale").
public enum TrackSpeed: String, CaseIterable, Codable, Identifiable {
    case x2 = "2x", x3_2 = "3/2x", x1 = "1x", x3_4 = "3/4x", x1_2 = "1/2x", x1_4 = "1/4x", x1_8 = "1/8x"

    public var id: String { rawValue }

    public var ticksPerStep: Int {
        switch self {
        case .x2: return 12
        case .x3_2: return 16
        case .x1: return 24
        case .x3_4: return 32
        case .x1_2: return 48
        case .x1_4: return 96
        case .x1_8: return 192
        }
    }
}

public enum PlayDirection: String, CaseIterable, Codable, Identifiable {
    case forward, reverse, pingpong, random
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .forward: return "→"
        case .reverse: return "←"
        case .pingpong: return "↔"
        case .random: return "?"
        }
    }
}

/// Elektron-style trig conditions.
public enum TrigCondition: Equatable, Hashable, Codable {
    case always
    /// Fires on loop `n` of every `of` loops (1-based), e.g. 1:2, 2:4.
    case ratio(n: Int, of: Int)
    case fill
    case notFill
    case first
    case notFirst
    /// Fires if the previous conditional step on this track fired.
    case pre
    case notPre
    /// Fires if the most recent conditional step on the track above fired.
    case neighbor
    case notNeighbor

    public static let presets: [TrigCondition] = {
        var list: [TrigCondition] = [.always, .fill, .notFill, .first, .notFirst, .pre, .notPre, .neighbor, .notNeighbor]
        for of in [2, 3, 4, 5, 6, 7, 8] {
            for n in 1...of { list.append(.ratio(n: n, of: of)) }
        }
        return list
    }()

    public var label: String {
        switch self {
        case .always: return "—"
        case .ratio(let n, let of): return "\(n):\(of)"
        case .fill: return "FILL"
        case .notFill: return "!FILL"
        case .first: return "1ST"
        case .notFirst: return "!1ST"
        case .pre: return "PRE"
        case .notPre: return "!PRE"
        case .neighbor: return "NEI"
        case .notNeighbor: return "!NEI"
        }
    }
}

/// Retrig (ratchet) settings for a step.
public struct Retrig: Equatable, Hashable, Codable {
    public var count: Int = 1 // total hits (1 = no retrig)
    public var rateTicks: Int = 6 // spacing between hits (6 = 1/64)
    public var velocityRamp: Int = 0 // -100...100 % change from first to last hit

    public init(count: Int = 1, rateTicks: Int = 6, velocityRamp: Int = 0) {
        self.count = count; self.rateTicks = rateTicks; self.velocityRamp = velocityRamp
    }

    public static let rates: [(label: String, ticks: Int)] = [
        ("1/8", 48), ("1/12", 32), ("1/16", 24), ("1/24", 16), ("1/32", 12), ("1/48", 8), ("1/64", 6), ("1/96", 4), ("1/128", 3),
    ]
}

/// One step of a track.
public struct Step: Equatable, Hashable, Codable {
    public var isOn: Bool = false
    /// Notes played by this step (chords allowed). Empty → use the track's default note.
    public var notes: [Int] = []
    public var velocity: Int = 100
    /// Gate length in steps (0.1 ... 16). Ignored when `slide` is set.
    public var length: Double = 0.5
    /// Micro timing offset in ticks (-11...11).
    public var micro: Int = 0
    public var probability: Int = 100 // percent
    public var condition: TrigCondition = .always
    public var retrig: Retrig = Retrig()
    /// Parameter locks: CC number → value (0...127).
    public var locks: [Int: Int] = [:]
    /// 303-style accent.
    public var accent: Bool = false
    /// 303-style slide/legato into the next step.
    public var slide: Bool = false
    /// Program change lock (0...127), -1 = none.
    public var programChange: Int = -1

    public init() {}

    public static func on(note: Int? = nil, velocity: Int = 100) -> Step {
        var s = Step()
        s.isOn = true
        if let n = note { s.notes = [n] }
        s.velocity = velocity
        return s
    }
}

public enum LFOShape: String, CaseIterable, Codable, Identifiable {
    case sine, triangle, sawUp, sawDown, square, random, exp
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .sine: return "SIN"
        case .triangle: return "TRI"
        case .sawUp: return "SAW"
        case .sawDown: return "RMP"
        case .square: return "SQR"
        case .random: return "RND"
        case .exp: return "EXP"
        }
    }
}

public enum LFOMode: String, CaseIterable, Codable, Identifiable {
    case free, trig, oneShot
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .free: return "FREE"
        case .trig: return "TRIG"
        case .oneShot: return "ONE"
        }
    }
}

public enum LFODestination: Equatable, Hashable, Codable {
    case cc(Int)
    case pitchBend
    case velocity
    case none

    public var label: String {
        switch self {
        case .cc(let n): return "CC\(n)"
        case .pitchBend: return "BEND"
        case .velocity: return "VEL"
        case .none: return "OFF"
        }
    }
}

/// A modulation lane (like Elektron LFOs / Oxi mod lanes).
public struct LFO: Equatable, Hashable, Codable, Identifiable {
    public var id: UUID = UUID()
    public var enabled: Bool = false
    public var shape: LFOShape = .sine
    public var mode: LFOMode = .free
    /// Period in ticks (one full cycle).
    public var periodTicks: Int = 384 // 1 bar
    /// Multiplier for fine rate (1 = period as is).
    public var depth: Int = 50 // -100...100 (% of range)
    public var center: Int = 64 // 0...127 output center
    public var phase: Int = 0 // 0...127 start phase
    public var destination: LFODestination = .none

    public init() {}

    public static let periods: [(label: String, ticks: Int)] = [
        ("8 bars", 3072), ("4 bars", 1536), ("2 bars", 768), ("1 bar", 384), ("1/2", 192), ("1/4", 96), ("1/8", 48), ("1/16", 24), ("1/32", 12),
    ]

    /// Raw waveform -1...1 for phase 0...1.
    public func wave(_ p: Double, randomSeed: Int) -> Double {
        let phase = p - floor(p)
        switch shape {
        case .sine: return sin(phase * 2 * Double.pi)
        case .triangle: return phase < 0.5 ? (phase * 4 - 1) : (3 - phase * 4)
        case .sawUp: return phase * 2 - 1
        case .sawDown: return 1 - phase * 2
        case .square: return phase < 0.5 ? 1 : -1
        case .exp: return pow(phase, 3) * 2 - 1
        case .random:
            // Deterministic sample & hold: 8 random values per cycle derived from a hash.
            let slot = Int(phase * 8)
            var h = UInt64(truncatingIfNeeded: randomSeed) &* 0x9E3779B97F4A7C15
            h ^= UInt64(slot &+ 1) &* 0xBF58476D1CE4E5B9
            h ^= h >> 31
            h = h &* 0x94D049BB133111EB
            h ^= h >> 29
            return Double(h % 2001) / 1000.0 - 1
        }
    }

    /// Output 0...127 for a tick position (relative to the LFO's own start).
    public func value(atTick tick: Int, cycleSeed: Int = 0) -> Int {
        let period = max(1, periodTicks)
        let p = Double(tick) / Double(period) + Double(phase) / 128.0
        if mode == .oneShot, tick >= period { return center }
        let w = wave(p, randomSeed: cycleSeed &+ Int(floor(p)))
        let v = Double(center) + w * Double(depth) / 100.0 * 64.0
        return Int(max(0, min(127, v.rounded())))
    }
}

/// A named CC lane with a default value.
public struct CCLane: Equatable, Hashable, Codable, Identifiable {
    public var id: UUID = UUID()
    public var name: String
    public var controller: Int
    public var defaultValue: Int = 64

    public init(name: String, controller: Int, defaultValue: Int = 64) {
        self.name = name; self.controller = controller; self.defaultValue = defaultValue
    }
}

public struct SeqTrack: Equatable, Hashable, Codable, Identifiable {
    public var id: UUID = UUID()
    public var name: String
    public var colorHex: String = "#F28C28"
    public var port: MIDIPortID = .all
    public var channel: Int = 0 // 0-based
    public var defaultNote: Int = 60
    public var defaultVelocity: Int = 100
    public var accentVelocity: Int = 127
    public var length: Int = 16 // steps
    public var speed: TrackSpeed = .x1
    public var direction: PlayDirection = .forward
    public var mute: Bool = false
    public var solo: Bool = false
    public var transpose: Int = 0
    public var scaleLock: Bool = false
    /// Swing 50...80 (%). nil → use the pattern swing.
    public var swing: Int? = nil
    /// Track-level chance 0...100 applied to every step in addition to the step probability.
    public var chance: Int = 100
    public var steps: [Step] = Array(repeating: Step(), count: SeqTiming.maxSteps)
    public var lfos: [LFO] = [LFO(), LFO()]
    public var ccLanes: [CCLane] = []
    public var sendClock: Bool = false
    public var isDrum: Bool = false
    /// MIDI program change sent on the port/channel when the pattern starts (-1 = none).
    public var programChange: Int = -1

    public init(name: String) {
        self.name = name
    }

    /// Tolerant decoding so saved projects survive new fields.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func get<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T { (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback }
        let d = SeqTrack(name: "Track")
        id = get(.id, UUID())
        name = get(.name, d.name)
        colorHex = get(.colorHex, d.colorHex)
        port = get(.port, d.port)
        channel = get(.channel, d.channel)
        defaultNote = get(.defaultNote, d.defaultNote)
        defaultVelocity = get(.defaultVelocity, d.defaultVelocity)
        accentVelocity = get(.accentVelocity, d.accentVelocity)
        length = get(.length, d.length)
        speed = get(.speed, d.speed)
        direction = get(.direction, d.direction)
        mute = get(.mute, d.mute)
        solo = get(.solo, d.solo)
        transpose = get(.transpose, d.transpose)
        scaleLock = get(.scaleLock, d.scaleLock)
        swing = get(.swing, d.swing)
        chance = get(.chance, d.chance)
        var decodedSteps = get(.steps, d.steps)
        if decodedSteps.count < SeqTiming.maxSteps { decodedSteps.append(contentsOf: Array(repeating: Step(), count: SeqTiming.maxSteps - decodedSteps.count)) }
        steps = Array(decodedSteps.prefix(SeqTiming.maxSteps))
        lfos = get(.lfos, d.lfos)
        ccLanes = get(.ccLanes, d.ccLanes)
        sendClock = get(.sendClock, d.sendClock)
        isDrum = get(.isDrum, d.isDrum)
        programChange = get(.programChange, d.programChange)
    }

    public func step(_ i: Int) -> Step {
        (i >= 0 && i < steps.count) ? steps[i] : Step()
    }

    public mutating func setStep(_ i: Int, _ s: Step) {
        guard i >= 0, i < steps.count else { return }
        steps[i] = s
    }

    public var activeStepIndices: [Int] { (0..<length).filter { steps[$0].isOn } }
}

/// Pattern: the collection of all tracks' step data.
public struct Pattern: Equatable, Hashable, Codable, Identifiable {
    public var id: UUID = UUID()
    public var name: String
    public var tracks: [SeqTrack]
    /// Pattern length in 1x steps used for pattern changes (16 = 1 bar).
    public var masterLength: Int = 16
    public var swing: Int = 50
    /// Optional tempo override (nil = project tempo).
    public var tempo: Double? = nil

    public init(name: String, tracks: [SeqTrack]) {
        self.name = name; self.tracks = tracks
    }

    public var masterLengthTicks: Int { max(1, masterLength) * SeqTiming.ticksPerStep }

    public static func empty(name: String, trackCount: Int = 8) -> Pattern {
        let defaults: [(String, String, Int, Bool)] = [
            ("KICK", "#F28C28", 36, true), ("SNARE", "#F2D33C", 38, true), ("HAT", "#7ED957", 42, true), ("PERC", "#E05A9A", 46, true),
            ("BASS", "#8FB4DD", 36, false), ("LEAD", "#9A6BFF", 60, false), ("CHORD", "#3CC8E6", 60, false), ("FX", "#B16AF0", 60, false),
            ("T9", "#F28C28", 60, false), ("T10", "#F2D33C", 60, false), ("T11", "#7ED957", 60, false), ("T12", "#E05A9A", 60, false),
            ("T13", "#8FB4DD", 60, false), ("T14", "#9A6BFF", 60, false), ("T15", "#3CC8E6", 60, false), ("T16", "#B16AF0", 60, false),
        ]
        var tracks: [SeqTrack] = []
        for i in 0..<max(1, min(SeqTiming.maxTracks, trackCount)) {
            let d = defaults[i]
            var t = SeqTrack(name: d.0)
            t.colorHex = d.1
            t.defaultNote = d.2
            t.isDrum = d.3
            t.channel = i < 4 ? 9 : i // drums on channel 10, others on their own channel
            if i >= 4 { t.channel = min(15, i - 4) }
            t.ccLanes = [CCLane(name: "Cutoff", controller: 74), CCLane(name: "Reso", controller: 71), CCLane(name: "Env", controller: 73)]
            tracks.append(t)
        }
        return Pattern(name: name, tracks: tracks)
    }
}

/// Song-mode entry.
public struct SongEntry: Equatable, Hashable, Codable, Identifiable {
    public var id: UUID = UUID()
    public var patternIndex: Int
    public var repeats: Int = 1

    public init(patternIndex: Int, repeats: Int = 1) {
        self.patternIndex = patternIndex; self.repeats = repeats
    }
}

public enum ArrangeMode: String, Codable, CaseIterable, Identifiable {
    case pattern, chain, song
    public var id: String { rawValue }
}

/// A full sequencer project (persisted as JSON).
public struct SeqProject: Equatable, Codable {
    public var name: String = "New Project"
    public var tempo: Double = 124
    public var patterns: [Pattern] = [Pattern.empty(name: "A1")]
    public var chain: [Int] = [0]
    public var song: [SongEntry] = [SongEntry(patternIndex: 0, repeats: 4)]
    public var arrangeMode: ArrangeMode = .pattern
    public var rootNote: Int = 0 // 0 = C
    public var scaleName: String = Scale.minor.name
    public var globalTranspose: Int = 0
    public var sendMIDIClock: Bool = true
    /// Also send MIDI Start/Stop with the clock (some hardware should free-run instead).
    public var sendTransport: Bool = true
    public var clockPort: MIDIPortID = .all
    public var sendDefaultsOnPatternStart: Bool = false

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func get<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T { (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback }
        let d = SeqProject()
        name = get(.name, d.name)
        tempo = get(.tempo, d.tempo)
        patterns = get(.patterns, d.patterns)
        if patterns.isEmpty { patterns = d.patterns }
        chain = get(.chain, d.chain)
        song = get(.song, d.song)
        arrangeMode = get(.arrangeMode, d.arrangeMode)
        rootNote = get(.rootNote, d.rootNote)
        scaleName = get(.scaleName, d.scaleName)
        globalTranspose = get(.globalTranspose, d.globalTranspose)
        sendMIDIClock = get(.sendMIDIClock, d.sendMIDIClock)
        sendTransport = get(.sendTransport, d.sendTransport)
        clockPort = get(.clockPort, d.clockPort)
        sendDefaultsOnPatternStart = get(.sendDefaultsOnPatternStart, d.sendDefaultsOnPatternStart)
    }

    public var scale: Scale { Scale.named(scaleName) }

    public func pattern(_ i: Int) -> Pattern? {
        (i >= 0 && i < patterns.count) ? patterns[i] : nil
    }
}
