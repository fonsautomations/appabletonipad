import Foundation

/// What we read from an Ableton Live Set (.als, gzipped XML) without Live running.
public struct AbletonSetSnapshot: Equatable {
    public enum TrackKind: String { case audio, midi, group, `return` }

    public struct Device: Equatable {
        public var className: String      // XML tag = Live Object Model class_name for stock devices
        public var userName: String       // "" when the device keeps its default name
        public var macroNames: [String]   // racks only, in order
        public var displayName: String {
            if !userName.isEmpty { return userName }
            return AbletonSetSnapshot.defaultDeviceNames[className] ?? className
        }
        public var isRack: Bool { className == "AudioEffectGroupDevice" || className == "InstrumentGroupDevice" || className == "MidiEffectGroupDevice" || className == "DrumGroupDevice" }
        /// Macro names the author actually set (not "Macro N").
        public var namedMacros: [String] { macroNames.filter { !AbletonSetSnapshot.isDefaultMacroName($0) } }
    }

    public struct Clip: Equatable {
        public var sceneIndex: Int
        public var name: String
        public var colorIndex: Int
        public var length: Double
        public var isMIDI: Bool
    }

    public struct Track: Equatable {
        public var id: Int
        public var kind: TrackKind
        public var name: String
        public var colorIndex: Int
        public var groupId: Int          // -1 at top level
        public var devices: [Device]
        public var clips: [Clip]
    }

    public var name: String = ""
    public var creator: String = ""
    public var tempo: Double = 120
    public var tracks: [Track] = []
    public var scenes: [String] = []
    /// Devices on the master (main) track.
    public var masterDevices: [Device] = []

    public var sessionTracks: [Track] { tracks.filter { $0.kind != .return } }
    public var returnTracks: [Track] { tracks.filter { $0.kind == .return } }
    public var topLevelGroups: [Track] { tracks.filter { $0.kind == .group && $0.groupId == -1 } }
    public func children(of group: Track) -> [Track] { tracks.filter { $0.groupId == group.id && $0.kind != .return } }

    public static func isDefaultMacroName(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("Macro ") else { return false }
        return Int(t.dropFirst(6)) != nil
    }

    public static let defaultDeviceNames: [String: String] = [
        "AudioEffectGroupDevice": "Audio Effect Rack", "InstrumentGroupDevice": "Instrument Rack", "MidiEffectGroupDevice": "MIDI Effect Rack",
        "DrumGroupDevice": "Drum Rack", "AutoFilter": "Auto Filter", "Eq8": "EQ Eight", "FilterEQ3": "EQ Three", "StereoGain": "Utility",
        "MxDeviceAudioEffect": "Max Audio Effect", "MxDeviceInstrument": "Max Instrument", "MxDeviceMidiEffect": "Max MIDI Effect",
        "PluginDevice": "Plug-in", "AuPluginDevice": "AU Plug-in", "Compressor2": "Compressor", "GlueCompressor": "Glue Compressor",
        "Reverb": "Reverb", "Delay": "Delay", "Echo": "Echo", "Saturator": "Saturator", "Limiter": "Limiter", "AutoPan": "Auto Pan",
        "Chorus2": "Chorus-Ensemble", "Phaser": "Phaser-Flanger", "Redux2": "Redux", "Roar": "Roar", "Operator": "Operator", "Wavetable": "Wavetable",
        "OriginalSimpler": "Simpler", "MultiSampler": "Sampler", "Drift": "Drift", "Meld": "Meld", "Hybrid": "Hybrid Reverb", "Shifter": "Shifter",
    ]

    /// Live's 70-colour palette (colour index → RGB), rows of 14.
    public static let palette: [Int] = [
        0xFF94A6, 0xFFA529, 0xCC9927, 0xF7F47C, 0xBFFB00, 0x1AFF2F, 0x25FFA8, 0x5CFFE8, 0x8BC5FF, 0x5480E4, 0x92A7FF, 0xD86CE4, 0xE553A0, 0xFFFFFF,
        0xFF3636, 0xF66C03, 0x99724B, 0xFFF034, 0x87FF67, 0x3DC300, 0x00BFAF, 0x19E9FF, 0x10A4EE, 0x007DC0, 0x886CE4, 0xB677C6, 0xFF39D4, 0xD0D0D0,
        0xE2675A, 0xFFA374, 0xD3AD71, 0xEDFFAE, 0xD2E498, 0xBAD074, 0x9BC48D, 0xD4FDE1, 0xCDF1F8, 0xB9C1E3, 0xCDBBE4, 0xAE98E5, 0xE5DCE1, 0xA9A9A9,
        0xC6928B, 0xB78256, 0x99836A, 0xBFBA69, 0xA6BE00, 0x7DB04D, 0x88C2BA, 0x9BB3C4, 0x85A5C2, 0x8393CC, 0xA595B5, 0xBF9FBE, 0xBC7196, 0x7B7B7B,
        0xAF3333, 0xA95131, 0x724F41, 0xDBC300, 0x85961F, 0x539F31, 0x0A9C8E, 0x236384, 0x1A2F96, 0x2F52A2, 0x624BAD, 0xA34BAD, 0xCC2E6E, 0x3C3C3C,
    ]

    public static func color(_ index: Int) -> LiveColor {
        guard index >= 0, index < palette.count else { return .gray }
        return LiveColor(rgb: palette[index])
    }

    /// Converts the snapshot to the same model the app uses when connected (for the offline set).
    public func toSong() -> LiveSongState {
        var song = LiveSongState()
        song.tempo = tempo
        song.liveVersion = "offline · " + creator
        song.scenes = scenes.enumerated().map { LiveScene(index: $0.offset, name: $0.element, color: LiveColor(rgb: 0x3A3A3A)) }
        let session = sessionTracks
        let indexById: [Int: Int] = Dictionary(uniqueKeysWithValues: session.enumerated().map { ($0.element.id, $0.offset) })
        for (i, t) in session.enumerated() {
            var lt = LiveTrack(index: i, name: t.name, color: AbletonSetSnapshot.color(t.colorIndex))
            lt.isGroup = t.kind == .group
            lt.groupTrackIndex = t.groupId >= 0 ? indexById[t.groupId] : nil
            lt.hasMIDIInput = t.kind == .midi
            lt.canBeArmed = t.kind != .group
            lt.sends = returnTracks.map { _ in 0.0 }
            lt.devices = AbletonSetSnapshot.liveDevices(t.devices, trackIndex: i)
            for c in t.clips {
                lt.clips[c.sceneIndex] = LiveClip(trackIndex: i, sceneIndex: c.sceneIndex, name: c.name, color: AbletonSetSnapshot.color(c.colorIndex), length: c.length, isMIDI: c.isMIDI)
            }
            song.tracks.append(lt)
        }
        song.returnTrackNames = returnTracks.map { $0.name }
        for (r, t) in returnTracks.enumerated() {
            song.returnTracks[r].color = AbletonSetSnapshot.color(t.colorIndex)
            song.returnTracks[r].sends = returnTracks.map { _ in 0.0 }
            song.returnTracks[r].devices = AbletonSetSnapshot.liveDevices(t.devices, trackIndex: LiveSongState.trackIndex(forReturn: r))
        }
        song.masterDevices = AbletonSetSnapshot.liveDevices(masterDevices, trackIndex: LiveSongState.masterTrackIndex)
        return song
    }

    static func liveDevices(_ devices: [Device], trackIndex: Int) -> [LiveDevice] {
        devices.enumerated().map { (di, d) in
            var params: [LiveDeviceParameter] = [LiveDeviceParameter(index: 0, name: "Device On", value: 1, min: 0, max: 1)]
            if d.isRack {
                for (mi, m) in d.macroNames.enumerated() { params.append(LiveDeviceParameter(index: mi + 1, name: m, value: 0.5, min: 0, max: 1)) }
            } else if d.className == "AutoFilter" {
                params.append(LiveDeviceParameter(index: 1, name: "Frequency", value: 1, min: 0, max: 1))
            }
            return LiveDevice(trackIndex: trackIndex, index: di, name: d.displayName, className: d.className, parameters: params)
        }
    }

    /// Builds a StageDeck template from the set structure.
    public struct TemplateOptions: Equatable {
        public var decksFromGroups = true
        public var controlPagesFromRacks = true
        public var maxMacrosPerTrack = 4
        public init() {}
    }

    public func makeTemplate(options: TemplateOptions) -> StageDeckTemplate {
        var t = StageDeckTemplate(name: name.isEmpty ? "Ableton set" : name)
        t.author = "Imported from Ableton Live Set"
        t.description = "Structure of \(name): \(sessionTracks.filter { $0.kind != .group }.count) tracks, \(topLevelGroups.count) groups, \(scenes.count) scenes."
        let palette = ["#F28C28", "#8FB4DD", "#7ED957", "#E05A9A", "#F2D33C", "#9A6BFF", "#3CC8E6", "#B16AF0"]
        if options.decksFromGroups {
            let groups = topLevelGroups
            if groups.isEmpty {
                t.decks = [DeckDefinition(name: "ALL", trackNames: [], colorHex: palette[0])]
            } else {
                t.decks = groups.enumerated().map { (i, g) in
                    DeckDefinition(name: g.name, trackNames: [], groupTrackName: g.name, colorHex: AbletonSetSnapshot.color(g.colorIndex).hexString)
                }
            }
        }
        if options.controlPagesFromRacks {
            var pages: [ControlPage] = []
            let containers: [Track] = topLevelGroups.isEmpty ? [] : topLevelGroups
            func widgets(for track: Track, limit: Int?, colorHex: String) -> [ControlWidget] {
                var out: [ControlWidget] = []
                for (di, d) in track.devices.enumerated() where d.isRack {
                    let macros = d.namedMacros
                    guard !macros.isEmpty else { continue }
                    for m in (limit.map { Array(macros.prefix($0)) } ?? macros) {
                        guard let pi = d.macroNames.firstIndex(of: m) else { continue }
                        var w = ControlWidget(name: m, kind: .knob, colorHex: colorHex)
                        w.target = .liveParameter(track: track.name, trackIndex: -1, device: d.displayName, deviceIndex: di, parameter: m, parameterIndex: pi + 1)
                        w.value = 0.5
                        out.append(w)
                    }
                    if limit != nil { break } // first rack only for member tracks
                }
                return out
            }
            for g in containers {
                var page = ControlPage(name: g.name)
                page.widgets = widgets(for: g, limit: nil, colorHex: AbletonSetSnapshot.color(g.colorIndex).hexString)
                for child in children(of: g) where child.kind != .group {
                    page.widgets.append(contentsOf: widgets(for: child, limit: options.maxMacrosPerTrack, colorHex: AbletonSetSnapshot.color(child.colorIndex).hexString))
                }
                if !page.widgets.isEmpty { pages.append(page) }
            }
            if containers.isEmpty {
                var page = ControlPage(name: "Racks")
                for tr in sessionTracks { page.widgets.append(contentsOf: widgets(for: tr, limit: options.maxMacrosPerTrack, colorHex: AbletonSetSnapshot.color(tr.colorIndex).hexString)) }
                if !page.widgets.isEmpty { pages.append(page) }
            }
            if !pages.isEmpty { t.controlPages = pages }
        }
        let tracks = t.referencedTracks
        let devices = t.referencedDevices.map { "\($0.track)/\($0.device)" }
        if !tracks.isEmpty || !devices.isEmpty { t.requires = StageDeckTemplate.Requirements(tracks: tracks, devices: devices) }
        return t
    }
}

/// Minimal, fast XML tag scanner for machine-generated XML (Live sets): start/end tags with
/// attributes, self-closing tags, comments, processing instructions. Text content is skipped.
/// Avoids libxml2 size limits and platform differences; a 70 MB set scans in a few seconds.
public final class SimpleXMLScanner {
    public struct Handler {
        public var didStart: (String, [String: String]) -> Void
        public var didEnd: (String) -> Void
        public init(didStart: @escaping (String, [String: String]) -> Void, didEnd: @escaping (String) -> Void) {
            self.didStart = didStart; self.didEnd = didEnd
        }
    }

    public enum ScanError: Error { case malformed(Int) }

    public static func scan(_ data: Data, handler: Handler) throws {
        try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return }
            let n = raw.count
            var i = 0
            var sawElement = false
            while i < n {
                guard base[i] == 0x3C else { i += 1; continue } // '<'
                guard i + 1 < n else { break }
                let c = base[i + 1]
                if c == 0x3F { // <? ... ?>
                    guard let end = find(base, n, from: i + 2, bytes: [0x3F, 0x3E]) else { throw ScanError.malformed(i) }
                    i = end + 2; continue
                }
                if c == 0x21 { // <!-- --> or <!DOCTYPE
                    if i + 3 < n, base[i + 2] == 0x2D, base[i + 3] == 0x2D {
                        guard let end = find(base, n, from: i + 4, bytes: [0x2D, 0x2D, 0x3E]) else { throw ScanError.malformed(i) }
                        i = end + 3
                    } else {
                        guard let end = find(base, n, from: i + 2, bytes: [0x3E]) else { throw ScanError.malformed(i) }
                        i = end + 1
                    }
                    continue
                }
                if c == 0x2F { // </name>
                    var j = i + 2
                    let nameStart = j
                    while j < n, base[j] != 0x3E, !isSpace(base[j]) { j += 1 }
                    let name = String(decoding: UnsafeBufferPointer(start: base + nameStart, count: j - nameStart), as: UTF8.self)
                    guard let end = find(base, n, from: j, bytes: [0x3E]) else { throw ScanError.malformed(i) }
                    handler.didEnd(name)
                    i = end + 1; continue
                }
                // <name attr="v" ... > or />
                var j = i + 1
                let nameStart = j
                while j < n, base[j] != 0x3E, base[j] != 0x2F, !isSpace(base[j]) { j += 1 }
                let name = String(decoding: UnsafeBufferPointer(start: base + nameStart, count: j - nameStart), as: UTF8.self)
                var attrs: [String: String] = [:]
                var selfClosing = false
                while j < n {
                    while j < n, isSpace(base[j]) { j += 1 }
                    guard j < n else { throw ScanError.malformed(i) }
                    if base[j] == 0x3E { j += 1; break }
                    if base[j] == 0x2F { selfClosing = true; j += 1; continue }
                    let keyStart = j
                    while j < n, base[j] != 0x3D, !isSpace(base[j]), base[j] != 0x3E { j += 1 }
                    let key = String(decoding: UnsafeBufferPointer(start: base + keyStart, count: j - keyStart), as: UTF8.self)
                    while j < n, isSpace(base[j]) { j += 1 }
                    guard j < n, base[j] == 0x3D else { throw ScanError.malformed(i) }
                    j += 1
                    while j < n, isSpace(base[j]) { j += 1 }
                    guard j < n, base[j] == 0x22 || base[j] == 0x27 else { throw ScanError.malformed(i) }
                    let quote = base[j]
                    j += 1
                    let valueStart = j
                    while j < n, base[j] != quote { j += 1 }
                    guard j < n else { throw ScanError.malformed(i) }
                    attrs[key] = decodeEntities(UnsafeBufferPointer(start: base + valueStart, count: j - valueStart))
                    j += 1
                }
                sawElement = true
                handler.didStart(name, attrs)
                if selfClosing { handler.didEnd(name) }
                i = j
            }
            if !sawElement { throw ScanError.malformed(0) }
        }
    }

    @inline(__always) private static func isSpace(_ b: UInt8) -> Bool { b == 0x20 || b == 0x0A || b == 0x0D || b == 0x09 }

    private static func find(_ base: UnsafePointer<UInt8>, _ n: Int, from: Int, bytes: [UInt8]) -> Int? {
        var i = from
        let m = bytes.count
        while i + m <= n {
            var ok = true
            for k in 0..<m where base[i + k] != bytes[k] { ok = false; break }
            if ok { return i }
            i += 1
        }
        return nil
    }

    private static func decodeEntities(_ buf: UnsafeBufferPointer<UInt8>) -> String {
        let s = String(decoding: buf, as: UTF8.self)
        guard s.contains("&") else { return s }
        var out = ""
        var rest = Substring(s)
        while let amp = rest.firstIndex(of: "&") {
            out += rest[..<amp]
            rest = rest[amp...]
            guard let semi = rest.firstIndex(of: ";") else { out += rest; return out }
            let entity = rest[rest.index(after: rest.startIndex)..<semi]
            switch entity {
            case "amp": out += "&"
            case "lt": out += "<"
            case "gt": out += ">"
            case "quot": out += "\""
            case "apos": out += "'"
            default:
                if entity.hasPrefix("#x"), let v = UInt32(entity.dropFirst(2), radix: 16), let u = Unicode.Scalar(v) { out.unicodeScalars.append(u) }
                else if entity.hasPrefix("#"), let v = UInt32(entity.dropFirst(1)), let u = Unicode.Scalar(v) { out.unicodeScalars.append(u) }
                else { out += rest[rest.startIndex...semi] }
            }
            rest = rest[rest.index(after: semi)...]
        }
        out += rest
        return out
    }
}

/// Parser for the XML inside an .als file (already gunzipped).
public final class AbletonSetParser {
    public enum ParseError: Error, CustomStringConvertible {
        case notALiveSet
        case xml(String)
        public var description: String {
            switch self {
            case .notALiveSet: return "This file is not an Ableton Live Set."
            case .xml(let m): return "Could not read the Live Set: \(m)"
            }
        }
    }

    public static func parse(xml data: Data, name: String = "") throws -> AbletonSetSnapshot {
        let p = AbletonSetParser()
        p.snapshot.name = name
        do {
            try SimpleXMLScanner.scan(data, handler: SimpleXMLScanner.Handler(didStart: { p.start($0, $1) }, didEnd: { p.end($0) }))
        } catch {
            if p.tracks.isEmpty { throw ParseError.xml("\(error)") }
        }
        guard p.sawLiveSet else { throw ParseError.notALiveSet }
        p.snapshot.tracks = p.tracks
        p.snapshot.masterDevices = p.masterDevices
        return p.snapshot
    }

    private var snapshot = AbletonSetSnapshot()
    private var tracks: [AbletonSetSnapshot.Track] = []
    private var masterDevices: [AbletonSetSnapshot.Device] = []
    private var path: [String] = []
    private var sawLiveSet = false
    private var currentTrack: AbletonSetSnapshot.Track?
    private var trackDepth = 0
    private var inScenes = false
    private var currentDevice: AbletonSetSnapshot.Device?
    private var deviceDepth = 0
    private var currentClip: AbletonSetSnapshot.Clip?
    private var clipDepth = 0
    private var currentSlotIndex = -1
    private var clipLoopStart: Double?
    private var clipLoopEnd: Double?
    private var clipStart: Double?
    private var clipEnd: Double?
    private var clipIsLooping = true
    private var inMasterTrack = false

    private static let trackTags: [String: AbletonSetSnapshot.TrackKind] = ["AudioTrack": .audio, "MidiTrack": .midi, "GroupTrack": .group, "ReturnTrack": .return]

    private func start(_ elementName: String, _ attributeDict: [String: String]) {
        path.append(elementName)
        let depth = path.count
        if elementName == "Ableton", let creator = attributeDict["Creator"] { snapshot.creator = creator }
        if elementName == "LiveSet" { sawLiveSet = true }
        if elementName == "Scenes", depth == 3 { inScenes = true }
        if elementName == "MainTrack" || elementName == "MasterTrack", depth == 3 { inMasterTrack = true }

        if currentTrack == nil, depth == 4, path[2] == "Tracks", let kind = AbletonSetParser.trackTags[elementName] {
            currentTrack = AbletonSetSnapshot.Track(id: Int(attributeDict["Id"] ?? "") ?? -1, kind: kind, name: "", colorIndex: 0, groupId: -1, devices: [], clips: [])
            trackDepth = depth
            return
        }
        if currentDevice != nil {
            let drel = depth - deviceDepth
            if drel == 1, elementName == "UserName", let v = attributeDict["Value"] { currentDevice?.userName = v }
            if drel == 1, elementName.hasPrefix("MacroDisplayNames."), let v = attributeDict["Value"] { currentDevice?.macroNames.append(v) }
            return
        }
        guard let _ = currentTrack else {
            if inScenes, elementName == "Name", depth == 5, path[3] == "Scene", let v = attributeDict["Value"] { snapshot.scenes.append(v) }
            if inMasterTrack, elementName == "Manual", depth >= 5, path[depth - 2] == "Tempo", let v = attributeDict["Value"], let d = Double(v) { snapshot.tempo = d }
            // Master devices: MainTrack/DeviceChain/DeviceChain/Devices/<Device>
            if inMasterTrack, depth == 7, path[5] == "Devices", path[4] == "DeviceChain", path[3] == "DeviceChain" {
                currentDevice = AbletonSetSnapshot.Device(className: elementName, userName: "", macroNames: [])
                deviceDepth = depth
            }
            return
        }
        let rel = depth - trackDepth // 1 = direct child of the track element
        // Track name / colour / group
        if rel == 2, elementName == "EffectiveName", path[depth - 2] == "Name", let v = attributeDict["Value"] { currentTrack?.name = v }
        if rel == 1, elementName == "Color", let v = attributeDict["Value"], let i = Int(v) { currentTrack?.colorIndex = i }
        if rel == 1, elementName == "TrackGroupId", let v = attributeDict["Value"], let i = Int(v) { currentTrack?.groupId = i }
        // Devices: Track/DeviceChain/DeviceChain/Devices/<Device>
        if currentDevice == nil, rel == 4, path[depth - 2] == "Devices", path[depth - 3] == "DeviceChain", path[depth - 4] == "DeviceChain" {
            currentDevice = AbletonSetSnapshot.Device(className: elementName, userName: "", macroNames: [])
            deviceDepth = depth
            return
        }
        // Clip slots: Track/DeviceChain/MainSequencer/ClipSlotList/ClipSlot(Id)/ClipSlot/Value/<AudioClip|MidiClip>
        if rel == 4, elementName == "ClipSlot", path[depth - 2] == "ClipSlotList", let id = attributeDict["Id"], let i = Int(id) { currentSlotIndex = i }
        if currentClip == nil, rel == 7, elementName == "AudioClip" || elementName == "MidiClip", path[depth - 2] == "Value", path[depth - 3] == "ClipSlot" {
            currentClip = AbletonSetSnapshot.Clip(sceneIndex: currentSlotIndex, name: "", colorIndex: currentTrack?.colorIndex ?? 0, length: 0, isMIDI: elementName == "MidiClip")
            clipDepth = depth
            clipLoopStart = nil; clipLoopEnd = nil; clipStart = nil; clipEnd = nil; clipIsLooping = true
            return
        }
        if currentClip != nil {
            let crel = depth - clipDepth
            let v = attributeDict["Value"]
            if crel == 1, elementName == "Name", let v { currentClip?.name = v }
            if crel == 1, elementName == "Color", let v, let i = Int(v) { currentClip?.colorIndex = i }
            if crel == 1, elementName == "CurrentStart", let v, let d = Double(v) { clipStart = d }
            if crel == 1, elementName == "CurrentEnd", let v, let d = Double(v) { clipEnd = d }
            if crel == 2, path[depth - 2] == "Loop" {
                if elementName == "LoopStart", let v, let d = Double(v) { clipLoopStart = d }
                if elementName == "LoopEnd", let v, let d = Double(v) { clipLoopEnd = d }
                if elementName == "LoopOn", let v { clipIsLooping = v == "true" }
            }
        }
    }

    private func end(_ elementName: String) {
        let depth = path.count
        if currentClip != nil, depth == clipDepth {
            var c = currentClip!
            if clipIsLooping, let s = clipLoopStart, let e = clipLoopEnd, e > s { c.length = e - s }
            else if let s = clipStart, let e = clipEnd, e > s { c.length = e - s }
            if c.sceneIndex >= 0 { currentTrack?.clips.append(c) }
            currentClip = nil
        } else if currentDevice != nil, depth == deviceDepth {
            if let d = currentDevice {
                if currentTrack != nil { currentTrack?.devices.append(d) } else { masterDevices.append(d) }
            }
            currentDevice = nil
        } else if currentTrack != nil, depth == trackDepth {
            if let t = currentTrack { tracks.append(t) }
            currentTrack = nil
        }
        if elementName == "Scenes", depth == 3 { inScenes = false }
        if (elementName == "MainTrack" || elementName == "MasterTrack"), depth == 3 { inMasterTrack = false }
        path.removeLast()
    }
}
