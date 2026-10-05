import Foundation

/// Identifier of a MIDI output "port" as seen by the sequencer.
/// The platform layer maps this to real CoreMIDI destinations.
public struct MIDIPortID: Hashable, Codable, Equatable, CustomStringConvertible {
    public var rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
    /// Sends to every enabled destination.
    public static let all = MIDIPortID("all")
    public var description: String { rawValue }
}

/// A plain MIDI 1.0 message, expressed as bytes.
public enum MIDIMessage: Equatable, Hashable, CustomStringConvertible {
    case noteOn(channel: UInt8, note: UInt8, velocity: UInt8)
    case noteOff(channel: UInt8, note: UInt8, velocity: UInt8)
    case controlChange(channel: UInt8, controller: UInt8, value: UInt8)
    case programChange(channel: UInt8, program: UInt8)
    case pitchBend(channel: UInt8, value: UInt16) // 0...16383, 8192 = center
    case channelPressure(channel: UInt8, value: UInt8)
    case clock
    case start
    case stop
    case `continue`
    case songPosition(UInt16)
    case raw([UInt8])

    public var bytes: [UInt8] {
        switch self {
        case .noteOn(let ch, let n, let v): return [0x90 | (ch & 0x0F), n & 0x7F, v & 0x7F]
        case .noteOff(let ch, let n, let v): return [0x80 | (ch & 0x0F), n & 0x7F, v & 0x7F]
        case .controlChange(let ch, let c, let v): return [0xB0 | (ch & 0x0F), c & 0x7F, v & 0x7F]
        case .programChange(let ch, let p): return [0xC0 | (ch & 0x0F), p & 0x7F]
        case .pitchBend(let ch, let value):
            let v = min(value, 16383)
            return [0xE0 | (ch & 0x0F), UInt8(v & 0x7F), UInt8((v >> 7) & 0x7F)]
        case .channelPressure(let ch, let v): return [0xD0 | (ch & 0x0F), v & 0x7F]
        case .clock: return [0xF8]
        case .start: return [0xFA]
        case .stop: return [0xFC]
        case .continue: return [0xFB]
        case .songPosition(let pos):
            let p = min(pos, 16383)
            return [0xF2, UInt8(p & 0x7F), UInt8((p >> 7) & 0x7F)]
        case .raw(let b): return b
        }
    }

    public var isRealtime: Bool {
        switch self {
        case .clock, .start, .stop, .continue: return true
        default: return false
        }
    }

    public var description: String {
        switch self {
        case .noteOn(let ch, let n, let v): return "NoteOn ch\(ch + 1) \(MIDINote.name(n)) v\(v)"
        case .noteOff(let ch, let n, _): return "NoteOff ch\(ch + 1) \(MIDINote.name(n))"
        case .controlChange(let ch, let c, let v): return "CC\(c)=\(v) ch\(ch + 1)"
        case .programChange(let ch, let p): return "PC\(p) ch\(ch + 1)"
        case .pitchBend(let ch, let v): return "Bend \(v) ch\(ch + 1)"
        case .channelPressure(let ch, let v): return "AT \(v) ch\(ch + 1)"
        case .clock: return "Clock"
        case .start: return "Start"
        case .stop: return "Stop"
        case .continue: return "Continue"
        case .songPosition(let p): return "SPP \(p)"
        case .raw(let b): return "Raw \(b)"
        }
    }

    /// Parses a complete MIDI message (channel voice or realtime) from bytes.
    public static func parse(_ bytes: [UInt8]) -> MIDIMessage? {
        guard let status = bytes.first else { return nil }
        switch status {
        case 0xF8: return .clock
        case 0xFA: return .start
        case 0xFB: return .continue
        case 0xFC: return .stop
        case 0xF2:
            guard bytes.count >= 3 else { return nil }
            return .songPosition(UInt16(bytes[1] & 0x7F) | (UInt16(bytes[2] & 0x7F) << 7))
        default: break
        }
        let kind = status & 0xF0
        let ch = status & 0x0F
        switch kind {
        case 0x90:
            guard bytes.count >= 3 else { return nil }
            if bytes[2] == 0 { return .noteOff(channel: ch, note: bytes[1], velocity: 0) }
            return .noteOn(channel: ch, note: bytes[1], velocity: bytes[2])
        case 0x80:
            guard bytes.count >= 3 else { return nil }
            return .noteOff(channel: ch, note: bytes[1], velocity: bytes[2])
        case 0xB0:
            guard bytes.count >= 3 else { return nil }
            return .controlChange(channel: ch, controller: bytes[1], value: bytes[2])
        case 0xC0:
            guard bytes.count >= 2 else { return nil }
            return .programChange(channel: ch, program: bytes[1])
        case 0xD0:
            guard bytes.count >= 2 else { return nil }
            return .channelPressure(channel: ch, value: bytes[1])
        case 0xE0:
            guard bytes.count >= 3 else { return nil }
            return .pitchBend(channel: ch, value: UInt16(bytes[1] & 0x7F) | (UInt16(bytes[2] & 0x7F) << 7))
        default:
            return .raw(bytes)
        }
    }
}

/// Note-number helpers.
public enum MIDINote {
    public static let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    /// Middle C (60) is "C3" (Ableton / Elektron convention).
    public static func name(_ note: UInt8) -> String {
        let n = Int(note)
        return "\(names[n % 12])\(n / 12 - 2)"
    }

    public static func name(_ note: Int) -> String {
        name(UInt8(clamping: max(0, min(127, note))))
    }
}
