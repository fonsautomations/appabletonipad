import Foundation

/// A shareable template: any subset of the performer profile and sequencer project.
/// Stored as readable JSON in a `.stagedeck` file. Every section is optional, so a template
/// may carry just one control page, or a whole rig.
public struct StageDeckTemplate: Codable, Equatable {
    public static let formatIdentifier = "stagedeck-template"
    public static let currentVersion = 1
    public static let fileExtension = "stagedeck"

    public var format: String? = StageDeckTemplate.formatIdentifier
    public var version: Int? = StageDeckTemplate.currentVersion
    public var name: String
    public var author: String? = nil
    public var description: String? = nil
    /// What the template expects to find in the Live set (informational; checked on import).
    public var requires: Requirements? = nil

    public var controlPages: [ControlPage]? = nil
    public var decks: [DeckDefinition]? = nil
    public var launchGroups: [LaunchGroup]? = nil
    /// Display names per Live track name ("KICK" → "BOMBO").
    public var trackAliases: [String: String]? = nil
    public var clipNotes: [String: String]? = nil
    public var layout: LayoutSettings? = nil
    public var patterns: [Pattern]? = nil
    public var sequencer: SequencerSettings? = nil

    public struct Requirements: Codable, Equatable {
        public var tracks: [String] = []
        /// "track/device" pairs.
        public var devices: [String] = []
        public init(tracks: [String] = [], devices: [String] = []) { self.tracks = tracks; self.devices = devices }
    }

    public struct LayoutSettings: Codable, Equatable {
        public var clipHeight: Double? = nil
        public var clipFontSize: Double? = nil
        public var showClipProgress: Bool? = nil
        public var showTrackMeters: Bool? = nil
        public var showClipNotes: Bool? = nil
        public var showSceneButtons: Bool? = nil
        public var showStopButtons: Bool? = nil
        public var showCueButtons: Bool? = nil
        public var showSections: Bool? = nil
        public var bigTextMode: Bool? = nil
        public var dimStoppedClips: Bool? = nil
        public var hideEmptyScenes: Bool? = nil
        public var showSends: Bool? = nil
        public var showPan: Bool? = nil
        public var filterParameterName: String? = nil
        public init() {}
    }

    public struct SequencerSettings: Codable, Equatable {
        public var tempo: Double? = nil
        public var rootNote: Int? = nil
        public var scaleName: String? = nil
        public var chain: [Int]? = nil
        public var song: [SongEntry]? = nil
        public var arrangeMode: ArrangeMode? = nil
        public init() {}
    }

    public init(name: String) { self.name = name }

    // MARK: Serialization

    public func encodeJSON() throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try enc.encode(self)
    }

    public enum ParseError: Error, Equatable, CustomStringConvertible {
        case notJSON(String)
        case wrongFormat
        case newerVersion(Int)
        case empty

        public var description: String {
            switch self {
            case .notJSON(let detail): return "This is not valid JSON: \(detail)"
            case .wrongFormat: return "This JSON is not a StageDeck template (missing \"format\": \"stagedeck-template\")."
            case .newerVersion(let v): return "This template needs a newer StageDeck (format version \(v))."
            case .empty: return "The template has no sections to import."
            }
        }
    }

    /// Parses JSON text or data. Accepts a bare profile export too (format missing but known keys present).
    public static func parse(_ data: Data) throws -> StageDeckTemplate {
        let template: StageDeckTemplate
        do {
            template = try JSONDecoder().decode(StageDeckTemplate.self, from: data)
        } catch let DecodingError.keyNotFound(key, _) {
            throw ParseError.notJSON("missing key \(key.stringValue)")
        } catch let DecodingError.typeMismatch(_, ctx) {
            throw ParseError.notJSON(ctx.debugDescription)
        } catch let DecodingError.dataCorrupted(ctx) {
            throw ParseError.notJSON(ctx.debugDescription)
        } catch {
            throw ParseError.notJSON(error.localizedDescription)
        }
        if let f = template.format, f != formatIdentifier { throw ParseError.wrongFormat }
        if let v = template.version, v > currentVersion { throw ParseError.newerVersion(v) }
        if template.isEmpty { throw ParseError.empty }
        return template
    }

    public static func parse(text: String) throws -> StageDeckTemplate {
        try parse(Data(text.utf8))
    }

    public var isEmpty: Bool {
        (controlPages ?? []).isEmpty && (decks ?? []).isEmpty && (launchGroups ?? []).isEmpty && (trackAliases ?? [:]).isEmpty
            && (clipNotes ?? [:]).isEmpty && layout == nil && (patterns ?? []).isEmpty && sequencer == nil
    }

    /// Human summary of what the template contains.
    public var contents: [String] {
        var out: [String] = []
        if let p = controlPages, !p.isEmpty { out.append("\(p.count) control page\(p.count == 1 ? "" : "s") (\(p.map { $0.name }.joined(separator: ", ")))") }
        if let d = decks, !d.isEmpty { out.append("\(d.count) deck\(d.count == 1 ? "" : "s") (\(d.map { $0.name }.joined(separator: ", ")))") }
        if let g = launchGroups, !g.isEmpty { out.append("\(g.count) launch group\(g.count == 1 ? "" : "s") (\(g.map { $0.label }.joined(separator: ", ")))") }
        if let a = trackAliases, !a.isEmpty { out.append("\(a.count) channel name\(a.count == 1 ? "" : "s")") }
        if let n = clipNotes, !n.isEmpty { out.append("\(n.count) clip note\(n.count == 1 ? "" : "s")") }
        if layout != nil { out.append("launcher / mixer layout settings") }
        if let p = patterns, !p.isEmpty { out.append("\(p.count) sequencer pattern\(p.count == 1 ? "" : "s") (\(p.map { $0.name }.joined(separator: ", ")))") }
        if sequencer != nil { out.append("sequencer settings") }
        return out
    }

    /// Tracks and devices referenced by the template (from decks, groups, aliases and control targets).
    public var referencedTracks: [String] {
        var set: [String] = []
        func add(_ s: String) { if !s.isEmpty, !set.contains(where: { $0.caseInsensitiveCompare(s) == .orderedSame }) { set.append(s) } }
        for d in decks ?? [] { d.trackNames.forEach(add); if let g = d.groupTrackName { add(g) } }
        for g in launchGroups ?? [] { g.trackNames.forEach(add) }
        for (k, _) in trackAliases ?? [:] { add(k) }
        for p in controlPages ?? [] {
            for w in p.widgets {
                for t in [w.target, w.targetY] { if case .liveParameter(let track, _, _, _, _, _) = t { add(track) } }
            }
        }
        for r in requires?.tracks ?? [] { add(r) }
        return set
    }

    public var referencedDevices: [(track: String, device: String)] {
        var out: [(String, String)] = []
        func add(_ t: String, _ d: String) {
            if !t.isEmpty, !d.isEmpty, !out.contains(where: { $0.0.caseInsensitiveCompare(t) == .orderedSame && $0.1.caseInsensitiveCompare(d) == .orderedSame }) { out.append((t, d)) }
        }
        for p in controlPages ?? [] {
            for w in p.widgets {
                for t in [w.target, w.targetY] { if case .liveParameter(let track, _, let device, _, _, _) = t { add(track, device) } }
            }
        }
        for r in requires?.devices ?? [] {
            let parts = r.split(separator: "/", maxSplits: 1).map(String.init)
            if parts.count == 2 { add(parts[0], parts[1]) }
        }
        return out.map { (track: $0.0, device: $0.1) }
    }
}

/// How an imported section is combined with what is already there.
public enum TemplateImportMode: String, CaseIterable, Identifiable {
    case add = "Add"
    case replace = "Replace"
    public var id: String { rawValue }
}

/// Import preview: what matches the loaded set and what does not.
public struct TemplateCheck: Equatable {
    public var missingTracks: [String] = []
    public var missingDevices: [String] = []
    public var setLoaded: Bool = false

    public var isClean: Bool { missingTracks.isEmpty && missingDevices.isEmpty }
}

public enum TemplateImporter {
    public static func check(_ t: StageDeckTemplate, against song: LiveSongState) -> TemplateCheck {
        var c = TemplateCheck()
        c.setLoaded = !song.tracks.isEmpty
        guard c.setLoaded else { return c }
        for name in t.referencedTracks where !song.tracks.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            c.missingTracks.append(name)
        }
        for ref in t.referencedDevices {
            guard let track = song.tracks.first(where: { $0.name.caseInsensitiveCompare(ref.track) == .orderedSame }) else { continue }
            if !track.devices.contains(where: { $0.name.caseInsensitiveCompare(ref.device) == .orderedSame }) {
                c.missingDevices.append("\(ref.track) / \(ref.device)")
            }
        }
        return c
    }

    /// Applies the template. Connection settings are never touched.
    public static func apply(_ t: StageDeckTemplate, mode: TemplateImportMode, to profile: inout PerformerProfile, project: inout SeqProject) {
        if let pages = t.controlPages, !pages.isEmpty {
            let fresh = pages.map { page -> ControlPage in
                var p = page; p.id = UUID(); p.widgets = p.widgets.map { var w = $0; w.id = UUID(); return w }; return p
            }
            profile.controlPages = mode == .replace ? fresh : profile.controlPages + fresh
        }
        if let decks = t.decks, !decks.isEmpty {
            let fresh = decks.map { var d = $0; d.id = UUID(); return d }
            profile.decks = mode == .replace ? fresh : profile.decks + fresh
        }
        if let groups = t.launchGroups, !groups.isEmpty {
            let fresh = groups.map { var g = $0; g.id = UUID(); return g }
            profile.launchGroups = mode == .replace ? fresh : profile.launchGroups + fresh
        }
        if let aliases = t.trackAliases, !aliases.isEmpty {
            if mode == .replace { profile.trackAliases = aliases } else { profile.trackAliases.merge(aliases) { _, new in new } }
        }
        if let notes = t.clipNotes, !notes.isEmpty {
            if mode == .replace { profile.clipNotes = notes } else { profile.clipNotes.merge(notes) { _, new in new } }
        }
        if let l = t.layout {
            if let v = l.clipHeight { profile.clipHeight = v }
            if let v = l.clipFontSize { profile.clipFontSize = v }
            if let v = l.showClipProgress { profile.showClipProgress = v }
            if let v = l.showTrackMeters { profile.showTrackMeters = v }
            if let v = l.showClipNotes { profile.showClipNotes = v }
            if let v = l.showSceneButtons { profile.showSceneButtons = v }
            if let v = l.showStopButtons { profile.showStopButtons = v }
            if let v = l.showCueButtons { profile.showCueButtons = v }
            if let v = l.showSections { profile.showSections = v }
            if let v = l.bigTextMode { profile.bigTextMode = v }
            if let v = l.dimStoppedClips { profile.dimStoppedClips = v }
            if let v = l.hideEmptyScenes { profile.hideEmptyScenes = v }
            if let v = l.showSends { profile.showSends = v }
            if let v = l.showPan { profile.showPan = v }
            if let v = l.filterParameterName { profile.filterParameterName = v }
        }
        if let patterns = t.patterns, !patterns.isEmpty {
            let fresh = patterns.map { p -> Pattern in
                var x = p; x.id = UUID()
                x.tracks = x.tracks.map { var tr = $0; tr.id = UUID(); return tr }
                return x
            }
            project.patterns = mode == .replace ? fresh : project.patterns + fresh
            if project.chain.contains(where: { $0 >= project.patterns.count }) { project.chain = [0] }
            if project.song.contains(where: { $0.patternIndex >= project.patterns.count }) { project.song = [SongEntry(patternIndex: 0)] }
        }
        if let s = t.sequencer {
            if let v = s.tempo { project.tempo = v }
            if let v = s.rootNote { project.rootNote = max(0, min(11, v)) }
            if let v = s.scaleName { project.scaleName = v }
            if let v = s.arrangeMode { project.arrangeMode = v }
            if let v = s.chain, !v.isEmpty, v.allSatisfy({ $0 >= 0 && $0 < project.patterns.count }) { project.chain = v }
            if let v = s.song, !v.isEmpty, v.allSatisfy({ $0.patternIndex >= 0 && $0.patternIndex < project.patterns.count }) { project.song = v }
        }
    }
}

/// Which parts to put in an exported template.
public struct TemplateSections: Equatable {
    public var controlPages = true
    public var decks = true
    public var launchGroups = true
    public var trackAliases = true
    public var clipNotes = false
    public var layout = true
    public var patterns = false
    public var sequencerSettings = false
    public init() {}
    public static let everything: TemplateSections = {
        var s = TemplateSections(); s.clipNotes = true; s.patterns = true; s.sequencerSettings = true; return s
    }()
}

public enum TemplateExporter {
    public static func make(name: String, author: String?, description: String?, sections: TemplateSections,
                            profile: PerformerProfile, project: SeqProject, song: LiveSongState) -> StageDeckTemplate {
        var t = StageDeckTemplate(name: name)
        t.author = author
        t.description = description
        if sections.controlPages { t.controlPages = profile.controlPages }
        if sections.decks { t.decks = profile.decks }
        if sections.launchGroups { t.launchGroups = profile.launchGroups }
        if sections.trackAliases { t.trackAliases = profile.trackAliases }
        if sections.clipNotes { t.clipNotes = profile.clipNotes }
        if sections.layout {
            var l = StageDeckTemplate.LayoutSettings()
            l.clipHeight = profile.clipHeight; l.clipFontSize = profile.clipFontSize
            l.showClipProgress = profile.showClipProgress; l.showTrackMeters = profile.showTrackMeters
            l.showClipNotes = profile.showClipNotes; l.showSceneButtons = profile.showSceneButtons
            l.showStopButtons = profile.showStopButtons; l.showCueButtons = profile.showCueButtons
            l.showSections = profile.showSections; l.bigTextMode = profile.bigTextMode
            l.dimStoppedClips = profile.dimStoppedClips; l.hideEmptyScenes = profile.hideEmptyScenes
            l.showSends = profile.showSends; l.showPan = profile.showPan; l.filterParameterName = profile.filterParameterName
            t.layout = l
        }
        if sections.patterns { t.patterns = project.patterns }
        if sections.sequencerSettings {
            var s = StageDeckTemplate.SequencerSettings()
            s.tempo = project.tempo; s.rootNote = project.rootNote; s.scaleName = project.scaleName
            s.chain = project.chain; s.song = project.song; s.arrangeMode = project.arrangeMode
            t.sequencer = s
        }
        let tracks = t.referencedTracks
        let devices = t.referencedDevices.map { "\($0.track)/\($0.device)" }
        if !tracks.isEmpty || !devices.isEmpty { t.requires = StageDeckTemplate.Requirements(tracks: tracks, devices: devices) }
        _ = song
        return t
    }
}

/// Plain-text description of the loaded set, to paste into an AI prompt or share with a friend.
public enum SetDescriber {
    public static func describe(_ song: LiveSongState, profile: PerformerProfile) -> String {
        guard !song.tracks.isEmpty else { return "No Live set loaded." }
        var lines: [String] = []
        lines.append("StageDeck set description (tempo \(Int(song.tempo.rounded())) BPM, \(song.tracks.count) tracks, \(song.scenes.count) scenes)")
        lines.append("")
        lines.append("TRACKS (Live name → display name, group, devices and parameters):")
        for t in song.tracks {
            let alias = profile.displayName(forTrack: t.name)
            let aliasText = alias == t.name ? "" : " → \"\(alias)\""
            let group = t.groupTrackIndex.flatMap { song.track($0)?.name }.map { ", in group \($0)" } ?? ""
            lines.append("- \(t.isGroup ? "[GROUP] " : "")\(t.name)\(aliasText)\(group)")
            for d in t.devices {
                let params = d.parameters.map { $0.name }.filter { $0 != "Device On" }
                let paramText = params.isEmpty ? "" : ": " + params.prefix(16).joined(separator: ", ") + (params.count > 16 ? ", …" : "")
                lines.append("    · device \"\(d.name)\" (\(d.className))\(paramText)")
            }
        }
        if !song.returnTrackNames.isEmpty { lines.append(""); lines.append("RETURN TRACKS: " + song.returnTrackNames.joined(separator: ", ")) }
        let sections = SetLayout.sections(from: song.scenes)
        if !sections.isEmpty { lines.append(""); lines.append("SCENE SECTIONS: " + sections.map { "\($0.name) (\($0.count))" }.joined(separator: ", ")) }
        if !profile.decks.isEmpty { lines.append(""); lines.append("DECKS: " + profile.decks.map { "\($0.name)=" + ($0.groupTrackName.map { "group \($0)" } ?? $0.trackNames.joined(separator: "+")) }.joined(separator: "; ")) }
        lines.append("")
        lines.append("Template format: see docs/TEMPLATE_FORMAT.md. Control targets use these exact track, device and parameter names.")
        return lines.joined(separator: "\n")
    }
}

/// Templates shipped with the app.
public enum BuiltInTemplates {
    public static var all: [StageDeckTemplate] { [macros8, stemsAB, drumSeq909] }

    public static var macros8: StageDeckTemplate {
        var t = StageDeckTemplate(name: "Macros 8")
        t.author = "StageDeck"
        t.description = "One control page with eight knobs on MIDI CC 20–27, an XY pad and four send faders. Map them in Live with MIDI Map."
        t.controlPages = [ControlPage.starter()]
        return t
    }

    public static var stemsAB: StageDeckTemplate {
        var t = StageDeckTemplate(name: "Stems A/B")
        t.author = "StageDeck"
        t.description = "Two decks mirroring Live group tracks A and B, launch groups K (kicks & bass) and R (rest), channel names in Spanish."
        t.decks = [DeckDefinition(name: "A", trackNames: [], groupTrackName: "A", colorHex: "#F28C28"),
                   DeckDefinition(name: "B", trackNames: [], groupTrackName: "B", colorHex: "#8FB4DD")]
        t.launchGroups = [LaunchGroup(label: "K", trackNames: ["KICK", "KICK2", "LO"], colorHex: "#F28C28"),
                          LaunchGroup(label: "R", trackNames: ["HI PERC", "MID PERC", "SYN-1", "SYN-2", "FX", "FX2-PAD", "ATMOS"], colorHex: "#C8762A")]
        t.trackAliases = ["KICK": "BOMBO", "LO": "BAJO", "HI PERC": "PERC AGUDA", "MID PERC": "PERC MEDIA", "ATMOS": "AMBIENTE"]
        var l = StageDeckTemplate.LayoutSettings(); l.showSections = true; l.showCueButtons = true; l.bigTextMode = false
        t.layout = l
        return t
    }

    public static var drumSeq909: StageDeckTemplate {
        var t = StageDeckTemplate(name: "Drum seq 909")
        t.author = "StageDeck"
        t.description = "Two patterns for a 909-style kit on MIDI channel 10 (kick 36, snare 38, hat 42, open hat 46), with fills and a 1:2 clap."
        var a = Pattern.empty(name: "909 A", trackCount: 4)
        for i in [0, 4, 8, 12] { a.tracks[0].steps[i] = Step.on(note: 36, velocity: 120) }
        for i in [4, 12] { a.tracks[1].steps[i] = Step.on(note: 38, velocity: 110) }
        for i in stride(from: 0, to: 16, by: 2) { a.tracks[2].steps[i] = Step.on(note: 42, velocity: i % 4 == 0 ? 100 : 70) }
        var oh = Step.on(note: 46, velocity: 90); oh.condition = .ratio(n: 2, of: 2); a.tracks[3].steps[14] = oh
        var fill = Step.on(note: 38, velocity: 100); fill.condition = .fill; fill.retrig = Retrig(count: 4, rateTicks: 6, velocityRamp: 40); a.tracks[1].steps[15] = fill
        var b = a; b.id = UUID(); b.name = "909 B"
        b.tracks[0].steps[10] = Step.on(note: 36, velocity: 100)
        b.tracks[2].length = 12
        t.patterns = [a, b]
        var s = StageDeckTemplate.SequencerSettings(); s.tempo = 128; s.arrangeMode = .chain; s.chain = [0, 0, 0, 1]
        t.sequencer = s
        return t
    }
}
