import Foundation

/// A contiguous run of scenes that share a name prefix (e.g. PERPEN_1…PERPEN_8 → "PERPEN").
public struct SceneSection: Equatable, Hashable, Identifiable {
    public var name: String
    public var firstScene: Int
    public var lastScene: Int
    public var color: LiveColor

    public var id: Int { firstScene }
    public var sceneRange: ClosedRange<Int> { firstScene...lastScene }
    public var count: Int { lastScene - firstScene + 1 }

    public init(name: String, firstScene: Int, lastScene: Int, color: LiveColor) {
        self.name = name; self.firstScene = firstScene; self.lastScene = lastScene; self.color = color
    }
}

public enum SetLayout {
    /// Strips a trailing separator + number ("BASIL_5", "BASIL 5", "BASIL-05", "BASIL5") to get the section key.
    public static func sectionKey(forSceneName name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "" }
        var chars = Array(trimmed)
        // drop trailing digits
        var end = chars.count
        while end > 0, chars[end - 1].isNumber { end -= 1 }
        if end == chars.count { return trimmed } // no trailing number → whole name is the key
        chars = Array(chars[0..<end])
        // drop trailing separators
        while let last = chars.last, last == "_" || last == "-" || last == " " || last == "." || last == "#" {
            chars.removeLast()
        }
        let key = String(chars)
        return key.isEmpty ? trimmed : key
    }

    /// Groups consecutive scenes with the same section key.
    public static func sections(from scenes: [LiveScene]) -> [SceneSection] {
        var result: [SceneSection] = []
        for scene in scenes {
            let key = sectionKey(forSceneName: scene.name)
            if var last = result.last, last.name == key, last.lastScene == scene.index - 1 {
                last.lastScene = scene.index
                result[result.count - 1] = last
            } else {
                result.append(SceneSection(name: key.isEmpty ? "Scene \(scene.index + 1)" : key,
                                           firstScene: scene.index, lastScene: scene.index, color: scene.color))
            }
        }
        return result
    }

    /// Section that contains the given scene.
    public static func section(containing scene: Int, in sections: [SceneSection]) -> SceneSection? {
        sections.first(where: { $0.sceneRange.contains(scene) })
    }
}

/// A user-defined deck: a named subset of tracks shown together (like BWX's deck A / deck B).
public struct DeckDefinition: Equatable, Hashable, Codable, Identifiable {
    public var id: UUID
    public var name: String
    /// Track names (matched case-insensitively) – names survive track re-ordering in Live.
    public var trackNames: [String]
    /// Optional: name of the Live group track this deck mirrors. When set, members are resolved from the group.
    public var groupTrackName: String?
    public var colorHex: String

    public init(id: UUID = UUID(), name: String, trackNames: [String] = [], groupTrackName: String? = nil, colorHex: String = "#F28C28") {
        self.id = id; self.name = name; self.trackNames = trackNames; self.groupTrackName = groupTrackName; self.colorHex = colorHex
    }

    /// Resolves the deck to concrete track indices in the current set.
    public func resolveTracks(in song: LiveSongState) -> [LiveTrack] {
        if let g = groupTrackName,
           let group = song.tracks.first(where: { $0.isGroup && $0.name.caseInsensitiveCompare(g) == .orderedSame }) {
            return song.members(ofGroup: group.index)
        }
        if trackNames.isEmpty { return song.launchableTracks }
        return trackNames.compactMap { n in song.tracks.first(where: { !$0.isGroup && $0.name.caseInsensitiveCompare(n) == .orderedSame }) }
    }

    /// Default decks: one per Live group track, or a single deck with everything.
    public static func automatic(from song: LiveSongState) -> [DeckDefinition] {
        let groups = song.groupTracks
        if groups.isEmpty {
            return [DeckDefinition(name: "ALL", trackNames: [], colorHex: "#F28C28")]
        }
        let palette = ["#F28C28", "#8FB4DD", "#7ED957", "#E05A9A", "#F2D33C", "#9A6BFF"]
        return groups.enumerated().map { (i, g) in
            DeckDefinition(name: g.name, trackNames: [], groupTrackName: g.name, colorHex: palette[i % palette.count])
        }
    }
}

/// A launch group fires the clips of one scene row on a subset of tracks ("K" = kicks & bass, "R" = rest).
public struct LaunchGroup: Equatable, Hashable, Codable, Identifiable {
    public var id: UUID
    public var label: String // short label shown on the button, e.g. "K"
    public var trackNames: [String]
    public var colorHex: String

    public init(id: UUID = UUID(), label: String, trackNames: [String], colorHex: String = "#F28C28") {
        self.id = id; self.label = label; self.trackNames = trackNames; self.colorHex = colorHex
    }

    public func resolveTracks(in deckTracks: [LiveTrack]) -> [LiveTrack] {
        deckTracks.filter { t in trackNames.contains(where: { $0.caseInsensitiveCompare(t.name) == .orderedSame }) }
    }
}

public extension String {
    /// Parses "#RRGGBB" / "RRGGBB" into a LiveColor.
    var liveColorFromHex: LiveColor? {
        var s = trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = Int(s, radix: 16) else { return nil }
        return LiveColor(rgb: v)
    }
}

public extension LiveColor {
    var hexString: String {
        let r = Int((red * 255).rounded()), g = Int((green * 255).rounded()), b = Int((blue * 255).rounded())
        return String(format: "#%02X%02X%02X", max(0, min(255, r)), max(0, min(255, g)), max(0, min(255, b)))
    }
}
