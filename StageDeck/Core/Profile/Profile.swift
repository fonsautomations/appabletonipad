import Foundation

/// Everything the performer customises. Persisted as JSON in the app's documents folder.
public struct PerformerProfile: Equatable, Codable {
    public var name: String = "Default"

    // Connection
    public var liveHost: String = "" // empty = not configured; broadcast discovery fills it in
    public var livePort: Int = 11000
    public var replyPort: Int = 11001
    public var autoReconnect: Bool = true
    public var meterRefreshEnabled: Bool = true

    // Launcher layout
    public var decks: [DeckDefinition] = []
    public var launchGroups: [LaunchGroup] = []
    public var clipHeight: Double = 54
    public var clipFontSize: Double = 12
    public var showClipProgress: Bool = true
    public var showTrackMeters: Bool = true
    public var showClipNotes: Bool = true
    public var showSceneButtons: Bool = true
    public var showStopButtons: Bool = true
    public var showCueButtons: Bool = true
    public var showSections: Bool = true
    public var followPlayingScene: Bool = true
    public var bigTextMode: Bool = false
    public var dimStoppedClips: Bool = true
    public var hideEmptyScenes: Bool = false

    // Safety
    public var confirmSceneLaunch: Bool = false
    public var confirmStopAll: Bool = true
    public var performanceLock: Bool = false // disables destructive controls (stop all, tempo)
    public var hapticsEnabled: Bool = true
    public var clipTapRequiresLongPress: Bool = false

    // Mixer
    public var showSends: Bool = true
    public var showPan: Bool = false
    public var filterParameterName: String = "Frequency"
    public var macroNames: [String] = ["LPF"]

    // Per-clip notes (lyrics, cues, reminders). Key: "<track name>|<clip name>".
    public var clipNotes: [String: String] = [:]
    /// Per-scene notes. Key: scene name.
    public var sceneNotes: [String: String] = [:]
    /// Custom display labels per track name.
    public var trackAliases: [String: String] = [:]

    // Sequencer defaults
    public var sequencerSendsClock: Bool = true
    public var sequencerFollowsLiveTransport: Bool = true
    public var sequencerSyncsTempoFromLive: Bool = true
    public var keyboardOctave: Int = 3

    // Theme
    public var accentHex: String = "#F28C28"
    public var secondaryHex: String = "#8FB4DD"

    public init() {}

    public static func clipNoteKey(track: String, clip: String) -> String { "\(track)|\(clip)" }

    public func clipNote(track: String, clip: String) -> String? {
        let v = clipNotes[PerformerProfile.clipNoteKey(track: track, clip: clip)]
        return (v?.isEmpty ?? true) ? nil : v
    }

    public mutating func setClipNote(track: String, clip: String, note: String) {
        let key = PerformerProfile.clipNoteKey(track: track, clip: clip)
        if note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { clipNotes.removeValue(forKey: key) } else { clipNotes[key] = note }
    }

    public func displayName(forTrack name: String) -> String {
        trackAliases[name].flatMap { $0.isEmpty ? nil : $0 } ?? name
    }
}

/// Persistent container for everything saved on disk.
public struct AppDocument: Equatable, Codable {
    public var profile: PerformerProfile = PerformerProfile()
    public var project: SeqProject = SeqProject()
    public var version: Int = 1

    public init() {}

    public func encodeJSON() throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try enc.encode(self)
    }

    public static func decodeJSON(_ data: Data) throws -> AppDocument {
        try JSONDecoder().decode(AppDocument.self, from: data)
    }
}
