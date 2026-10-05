import Foundation

/// Musical scales as semitone offsets from the root.
public struct Scale: Equatable, Hashable, Codable, Identifiable {
    public var name: String
    public var intervals: [Int]

    public var id: String { name }

    public init(name: String, intervals: [Int]) {
        self.name = name; self.intervals = intervals
    }

    public static let chromatic = Scale(name: "Chromatic", intervals: Array(0..<12))
    public static let major = Scale(name: "Major", intervals: [0, 2, 4, 5, 7, 9, 11])
    public static let minor = Scale(name: "Minor", intervals: [0, 2, 3, 5, 7, 8, 10])
    public static let harmonicMinor = Scale(name: "Harmonic Minor", intervals: [0, 2, 3, 5, 7, 8, 11])
    public static let melodicMinor = Scale(name: "Melodic Minor", intervals: [0, 2, 3, 5, 7, 9, 11])
    public static let dorian = Scale(name: "Dorian", intervals: [0, 2, 3, 5, 7, 9, 10])
    public static let phrygian = Scale(name: "Phrygian", intervals: [0, 1, 3, 5, 7, 8, 10])
    public static let lydian = Scale(name: "Lydian", intervals: [0, 2, 4, 6, 7, 9, 11])
    public static let mixolydian = Scale(name: "Mixolydian", intervals: [0, 2, 4, 5, 7, 9, 10])
    public static let locrian = Scale(name: "Locrian", intervals: [0, 1, 3, 5, 6, 8, 10])
    public static let majorPentatonic = Scale(name: "Major Pentatonic", intervals: [0, 2, 4, 7, 9])
    public static let minorPentatonic = Scale(name: "Minor Pentatonic", intervals: [0, 3, 5, 7, 10])
    public static let blues = Scale(name: "Blues", intervals: [0, 3, 5, 6, 7, 10])
    public static let wholeTone = Scale(name: "Whole Tone", intervals: [0, 2, 4, 6, 8, 10])
    public static let phrygianDominant = Scale(name: "Phrygian Dominant", intervals: [0, 1, 4, 5, 7, 8, 10])
    public static let hungarianMinor = Scale(name: "Hungarian Minor", intervals: [0, 2, 3, 6, 7, 8, 11])
    public static let japanese = Scale(name: "Japanese (In)", intervals: [0, 1, 5, 7, 8])
    public static let diminished = Scale(name: "Diminished", intervals: [0, 2, 3, 5, 6, 8, 9, 11])

    public static let all: [Scale] = [
        chromatic, major, minor, harmonicMinor, melodicMinor, dorian, phrygian, lydian, mixolydian, locrian,
        majorPentatonic, minorPentatonic, blues, wholeTone, phrygianDominant, hungarianMinor, japanese, diminished,
    ]

    public static func named(_ name: String) -> Scale {
        all.first(where: { $0.name == name }) ?? .chromatic
    }

    /// True if the note belongs to the scale with the given root (0...11).
    public func contains(note: Int, root: Int) -> Bool {
        let pc = ((note - root) % 12 + 12) % 12
        return intervals.contains(pc)
    }

    /// Nearest scale note (ties resolve downwards).
    public func quantize(note: Int, root: Int) -> Int {
        if contains(note: note, root: root) { return note }
        for distance in 1...6 {
            if contains(note: note - distance, root: root) { return note - distance }
            if contains(note: note + distance, root: root) { return note + distance }
        }
        return note
    }

    /// Note at `degree` (0-based, may be negative / beyond one octave) above `root` in the given octave.
    public func note(degree: Int, root: Int, octave: Int) -> Int {
        let n = intervals.count
        let oct = Int(floor(Double(degree) / Double(n)))
        let idx = ((degree % n) + n) % n
        return (octave + 2) * 12 + root + intervals[idx] + oct * 12
    }

    /// All notes in the scale between lo and hi inclusive.
    public func notes(root: Int, from lo: Int, to hi: Int) -> [Int] {
        (lo...hi).filter { contains(note: $0, root: root) }
    }
}

/// Euclidean rhythm generator (Bjorklund).
public enum Euclid {
    /// Returns `steps` booleans with `pulses` evenly spread, rotated by `rotation`.
    public static func pattern(steps: Int, pulses: Int, rotation: Int = 0) -> [Bool] {
        guard steps > 0 else { return [] }
        let k = max(0, min(steps, pulses))
        if k == 0 { return Array(repeating: false, count: steps) }
        if k == steps { return Array(repeating: true, count: steps) }
        // Classic Euclidean distribution: a hit wherever floor(i*k/n) advances. Yields the
        // canonical Bjorklund patterns, e.g. E(3,8) = x..x..x. and E(5,8) = x.x.xx.x (a rotation).
        var result: [Bool] = []
        for i in 0..<steps {
            result.append((i * k) % steps < k)
        }
        let r = ((rotation % steps) + steps) % steps
        if r != 0 {
            result = Array(result[(steps - r)...] + result[..<(steps - r)])
        }
        return result
    }
}
