import Foundation

/// RGB colour as delivered by Live (0xRRGGBB).
public struct LiveColor: Equatable, Hashable, Codable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red; self.green = green; self.blue = blue
    }

    public init(rgb: Int) {
        let v = max(0, rgb)
        red = Double((v >> 16) & 0xFF) / 255.0
        green = Double((v >> 8) & 0xFF) / 255.0
        blue = Double(v & 0xFF) / 255.0
    }

    public static let gray = LiveColor(red: 0.45, green: 0.45, blue: 0.45)

    /// Perceived luminance 0...1, used to pick readable text colour.
    public var luminance: Double { 0.2126 * red + 0.7152 * green + 0.0722 * blue }
    public var prefersDarkText: Bool { luminance > 0.55 }
}

public enum ClipPlayState: Equatable, Hashable {
    case stopped
    case queued
    case playing
    case recording
}

public struct LiveClip: Equatable, Hashable, Identifiable {
    public var trackIndex: Int
    public var sceneIndex: Int
    public var name: String
    public var color: LiveColor
    public var length: Double // beats
    public var isMIDI: Bool = false

    public var id: String { "\(trackIndex):\(sceneIndex)" }

    public init(trackIndex: Int, sceneIndex: Int, name: String, color: LiveColor, length: Double, isMIDI: Bool = false) {
        self.trackIndex = trackIndex
        self.sceneIndex = sceneIndex
        self.name = name
        self.color = color
        self.length = length
        self.isMIDI = isMIDI
    }
}

public struct LiveDeviceParameter: Equatable, Hashable {
    public var index: Int
    public var name: String
    public var value: Double
    public var min: Double
    public var max: Double

    public init(index: Int, name: String, value: Double, min: Double, max: Double) {
        self.index = index; self.name = name; self.value = value; self.min = min; self.max = max
    }

    public var normalized: Double {
        guard max > min else { return 0 }
        return (value - min) / (max - min)
    }
}

public struct LiveDevice: Equatable, Hashable, Identifiable {
    public var trackIndex: Int
    public var index: Int
    public var name: String
    public var className: String
    public var parameters: [LiveDeviceParameter] = []

    public var id: String { "\(trackIndex):\(index)" }

    public init(trackIndex: Int, index: Int, name: String, className: String, parameters: [LiveDeviceParameter] = []) {
        self.trackIndex = trackIndex; self.index = index; self.name = name; self.className = className; self.parameters = parameters
    }

    public var isAutoFilter: Bool { className == "AutoFilter" }

    public func parameterIndex(named needle: String) -> Int? {
        parameters.first(where: { $0.name.caseInsensitiveCompare(needle) == .orderedSame })?.index
    }
}

public struct LiveTrack: Equatable, Hashable, Identifiable {
    public var index: Int
    public var name: String
    public var color: LiveColor
    public var isGroup: Bool = false
    public var groupTrackIndex: Int? = nil
    public var mute: Bool = false
    public var solo: Bool = false
    public var arm: Bool = false
    public var canBeArmed: Bool = true
    public var volume: Double = 0.85
    public var panning: Double = 0
    public var sends: [Double] = []
    public var meter: Double = 0
    public var playingSlotIndex: Int = -1
    public var firedSlotIndex: Int = -1
    public var clips: [Int: LiveClip] = [:] // keyed by scene index
    public var devices: [LiveDevice] = []
    public var hasMIDIInput: Bool = false

    public var id: Int { index }

    public init(index: Int, name: String, color: LiveColor = .gray) {
        self.index = index; self.name = name; self.color = color
    }

    /// Scene index of the clip that is currently playing, if any.
    public var playingSceneIndex: Int? { playingSlotIndex >= 0 ? playingSlotIndex : nil }
    public var queuedSceneIndex: Int? { firedSlotIndex >= 0 ? firedSlotIndex : nil }

    public func playState(forScene scene: Int) -> ClipPlayState {
        if firedSlotIndex == scene { return .queued }
        if playingSlotIndex == scene { return .playing }
        return .stopped
    }

    /// First Auto Filter device on this track.
    public var autoFilter: LiveDevice? { devices.first(where: { $0.isAutoFilter }) }
}

public struct LiveScene: Equatable, Hashable, Identifiable {
    public var index: Int
    public var name: String
    public var color: LiveColor
    public var isTriggered: Bool = false
    public var tempo: Double? = nil

    public var id: Int { index }

    public init(index: Int, name: String, color: LiveColor = .gray) {
        self.index = index; self.name = name; self.color = color
    }
}

/// Live's "Clip Trigger Quantization" enum (song.clip_trigger_quantization).
public enum LiveQuantization: Int, CaseIterable, Codable, Identifiable {
    case none = 0
    case bars8 = 1
    case bars4 = 2
    case bars2 = 3
    case bar = 4
    case half = 5
    case halfTriplet = 6
    case quarter = 7
    case quarterTriplet = 8
    case eighth = 9
    case eighthTriplet = 10
    case sixteenth = 11
    case sixteenthTriplet = 12
    case thirtySecond = 13

    public var id: Int { rawValue }

    public var label: String {
        switch self {
        case .none: return "None"
        case .bars8: return "8 Bars"
        case .bars4: return "4 Bars"
        case .bars2: return "2 Bars"
        case .bar: return "1 Bar"
        case .half: return "1/2"
        case .halfTriplet: return "1/2T"
        case .quarter: return "1/4"
        case .quarterTriplet: return "1/4T"
        case .eighth: return "1/8"
        case .eighthTriplet: return "1/8T"
        case .sixteenth: return "1/16"
        case .sixteenthTriplet: return "1/16T"
        case .thirtySecond: return "1/32"
        }
    }
}

/// Whole-session snapshot of the Live set as the app knows it.
public struct LiveSongState: Equatable {
    public var tracks: [LiveTrack] = []
    public var scenes: [LiveScene] = []
    public var returnTrackNames: [String] = []
    public var tempo: Double = 120
    public var isPlaying: Bool = false
    public var beat: Int = 0
    public var quantization: LiveQuantization = .bar
    public var masterVolume: Double = 0.85
    public var masterMeter: Double = 0
    public var cueVolume: Double = 0.85
    public var liveVersion: String = ""
    /// Playing position (beats) of each playing clip, keyed by "track:scene".
    public var clipPositions: [String: Double] = [:]

    public init() {}

    public var numSends: Int { returnTrackNames.count }

    public func track(_ index: Int) -> LiveTrack? {
        guard index >= 0, index < tracks.count else { return nil }
        return tracks[index]
    }

    public func clip(track: Int, scene: Int) -> LiveClip? {
        self.track(track)?.clips[scene]
    }

    /// Progress 0...1 of a playing clip.
    public func clipProgress(track: Int, scene: Int) -> Double? {
        guard let clip = clip(track: track, scene: scene), clip.length > 0 else { return nil }
        guard let pos = clipPositions["\(track):\(scene)"] else { return nil }
        return max(0, min(1, pos / clip.length))
    }

    /// Tracks that are not group tracks and are visible for launching.
    public var launchableTracks: [LiveTrack] { tracks.filter { !$0.isGroup } }

    /// Member tracks of a group track.
    public func members(ofGroup groupIndex: Int) -> [LiveTrack] {
        tracks.filter { $0.groupTrackIndex == groupIndex && !$0.isGroup }
    }

    public var groupTracks: [LiveTrack] { tracks.filter { $0.isGroup } }
}

/// Live's fader (0...1) ↔ dB mapping.
/// Live's fader is linear in dB between -18 dB (0.4) and +6 dB (1.0) with 0 dB at 0.85,
/// and roughly logarithmic below 0.4. This approximation matches Live's display within ~0.3 dB.
public enum LiveVolume {
    public static func decibels(fromFader v: Double) -> Double {
        let x = max(0, min(1, v))
        if x <= 0.0001 { return -Double.infinity }
        if x >= 0.4 {
            return (x - 0.85) * 40.0
        }
        // Below 0.4: -18 dB at 0.4 falling to -inf; use a log curve that hits -70 dB near 0.02.
        let t = x / 0.4 // 0...1
        return -18.0 + 52.0 * log10(t) * 1.0
    }

    public static func fader(fromDecibels db: Double) -> Double {
        if db == -Double.infinity || db < -90 { return 0 }
        if db >= -18 {
            return max(0, min(1, db / 40.0 + 0.85))
        }
        let t = pow(10.0, (db + 18.0) / 52.0)
        return max(0, min(0.4, t * 0.4))
    }

    public static func label(fader v: Double) -> String {
        let db = decibels(fromFader: v)
        if db == -Double.infinity || db < -70 { return "-inf" }
        return String(format: "%.1f", db)
    }
}
