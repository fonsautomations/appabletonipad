import Foundation

/// A note rendered from a pattern, in beats (quarter notes) relative to the clip start.
public struct BouncedNote: Equatable {
    public var pitch: Int
    public var start: Double
    public var duration: Double
    public var velocity: Int

    public init(pitch: Int, start: Double, duration: Double, velocity: Int) {
        self.pitch = pitch; self.start = start; self.duration = duration; self.velocity = velocity
    }
}

/// Renders a pattern with the real engine so conditions, probability, retrigs, swing and
/// micro-timing are baked into plain notes (what a Live MIDI clip can hold).
public enum PatternBounce {
    public static let beatsPerBar = 4.0

    /// Notes per sequencer track index for `bars` bars of `patternIndex`.
    public static func render(project: SeqProject, patternIndex: Int, bars: Int, seed: UInt64 = 1, fill: Bool = false) -> [Int: [BouncedNote]] {
        var p = project
        p.arrangeMode = .pattern
        p.sendMIDIClock = false
        p.sendDefaultsOnPatternStart = false
        let engine = SequencerEngine(project: p, rng: SeededGenerator(seed: seed))
        engine.selectPattern(patternIndex)
        engine.fillActive = fill
        let totalTicks = max(1, bars) * SeqTiming.ppqn * 4
        var events = engine.start(atTick: 0)
        events.append(contentsOf: engine.render(from: 0, to: totalTicks))
        events.append(contentsOf: engine.stop(atTick: totalTicks))
        var open: [String: (tick: Int, velocity: Int, track: Int, pitch: Int)] = [:]
        var out: [Int: [BouncedNote]] = [:]
        let ppq = Double(SeqTiming.ppqn)
        for e in events.sorted(by: { $0.tick != $1.tick ? $0.tick < $1.tick : $0.order < $1.order }) {
            switch e.message {
            case .noteOn(let ch, let n, let v):
                let key = "\(e.track):\(ch):\(n)"
                if let o = open[key] {
                    out[o.track, default: []].append(BouncedNote(pitch: o.pitch, start: Double(o.tick) / ppq, duration: Double(max(1, e.tick - o.tick)) / ppq, velocity: o.velocity))
                }
                open[key] = (e.tick, Int(v), e.track, Int(n))
            case .noteOff(let ch, let n, _):
                let key = "\(e.track):\(ch):\(n)"
                if let o = open[key] {
                    let end = min(e.tick, totalTicks)
                    out[o.track, default: []].append(BouncedNote(pitch: o.pitch, start: Double(o.tick) / ppq, duration: Double(max(1, end - o.tick)) / ppq, velocity: o.velocity))
                    open.removeValue(forKey: key)
                }
            default:
                break
            }
        }
        for (_, o) in open {
            out[o.track, default: []].append(BouncedNote(pitch: o.pitch, start: Double(o.tick) / ppq, duration: Double(max(1, totalTicks - o.tick)) / ppq, velocity: o.velocity))
        }
        for k in out.keys { out[k]?.sort { $0.start != $1.start ? $0.start < $1.start : $0.pitch < $1.pitch } }
        return out
    }

    /// AbletonOSC `/live/clip/add/notes` argument list (pitch, start, duration, velocity, mute) per chunk.
    public static func oscChunks(_ notes: [BouncedNote], chunkSize: Int = 48) -> [[OSCValue]] {
        var chunks: [[OSCValue]] = []
        var current: [OSCValue] = []
        for n in notes {
            current.append(contentsOf: [.int32(Int32(max(0, min(127, n.pitch)))), .float(Float(n.start)), .float(Float(max(0.01, n.duration))),
                                        .int32(Int32(max(1, min(127, n.velocity)))), .bool(false)])
            if current.count >= chunkSize * 5 { chunks.append(current); current = [] }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }
}
