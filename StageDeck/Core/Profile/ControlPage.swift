import Foundation

/// Kind of control widget on a CONTROL page.
public enum ControlWidgetKind: String, Codable, CaseIterable, Identifiable {
    case fader, knob, button, toggle, xy
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .fader: return "Fader"
        case .knob: return "Knob"
        case .button: return "Button"
        case .toggle: return "Toggle"
        case .xy: return "XY pad"
        }
    }
    /// Default width in grid units (page is 8 units wide).
    public var defaultWidth: Int {
        switch self {
        case .fader: return 1
        case .knob: return 1
        case .button, .toggle: return 1
        case .xy: return 2
        }
    }
    public var isTall: Bool { self == .fader || self == .xy }
}

/// What a widget drives. Live targets are stored by name (with index fallback) so they survive re-ordering.
public enum ControlTarget: Equatable, Hashable, Codable {
    case none
    case liveParameter(track: String, trackIndex: Int, device: String, deviceIndex: Int, parameter: String, parameterIndex: Int)
    case midiCC(channel: Int, controller: Int, port: MIDIPortID)
    case midiNote(channel: Int, note: Int, port: MIDIPortID)

    public var label: String {
        switch self {
        case .none: return "Not assigned"
        case .liveParameter(let t, _, let d, _, let p, _): return "\(t) · \(d) · \(p)"
        case .midiCC(let ch, let cc, _): return "CC \(cc) ch \(ch + 1)"
        case .midiNote(let ch, let n, _): return "Note \(MIDINote.name(n)) ch \(ch + 1)"
        }
    }

    public var isLive: Bool { if case .liveParameter = self { return true } else { return false } }
    public var isMIDI: Bool { !isLive && self != .none }
}

public struct ControlWidget: Equatable, Hashable, Codable, Identifiable {
    public var id: UUID = UUID()
    public var name: String
    public var kind: ControlWidgetKind
    public var colorHex: String = "#F28C28"
    public var width: Int = 1
    public var target: ControlTarget = .none
    /// Second target for the Y axis of an XY pad.
    public var targetY: ControlTarget = .none
    /// Output range (normalized 0...1 of the parameter or 0...127 of the CC).
    public var minimum: Double = 0
    public var maximum: Double = 1
    /// Stored value 0...1 (used for MIDI targets; Live targets read back from Live).
    public var value: Double = 0
    public var valueY: Double = 0

    public init(name: String, kind: ControlWidgetKind, colorHex: String = "#F28C28", target: ControlTarget = .none) {
        self.name = name; self.kind = kind; self.colorHex = colorHex; self.target = target; self.width = kind.defaultWidth
    }

    /// Maps a normalized position 0...1 to the configured output range.
    public func scaled(_ v: Double) -> Double {
        let lo = min(minimum, maximum), hi = max(minimum, maximum)
        return lo + (hi - lo) * max(0, min(1, v))
    }

    public func unscaled(_ out: Double) -> Double {
        let lo = min(minimum, maximum), hi = max(minimum, maximum)
        guard hi > lo else { return 0 }
        return max(0, min(1, (out - lo) / (hi - lo)))
    }
}

public struct ControlPage: Equatable, Hashable, Codable, Identifiable {
    public var id: UUID = UUID()
    public var name: String
    public var widgets: [ControlWidget] = []
    public static let columns = 8

    public init(name: String, widgets: [ControlWidget] = []) {
        self.name = name; self.widgets = widgets
    }

    /// A ready-to-use first page: 8 macro knobs, 4 send faders, an XY pad and two buttons.
    public static func starter() -> ControlPage {
        var page = ControlPage(name: "Macros")
        let palette = ["#F28C28", "#F2D33C", "#7ED957", "#3CC8E6", "#8FB4DD", "#9A6BFF", "#E05A9A", "#B16AF0"]
        for i in 0..<8 {
            var w = ControlWidget(name: "Macro \(i + 1)", kind: .knob, colorHex: palette[i])
            w.target = .midiCC(channel: 0, controller: 20 + i, port: .all)
            w.value = 0.5
            page.widgets.append(w)
        }
        var xy = ControlWidget(name: "FX XY", kind: .xy, colorHex: "#E05A9A")
        xy.target = .midiCC(channel: 0, controller: 30, port: .all)
        xy.targetY = .midiCC(channel: 0, controller: 31, port: .all)
        page.widgets.append(xy)
        for i in 0..<4 {
            var f = ControlWidget(name: "Send \(["A", "B", "C", "D"][i])", kind: .fader, colorHex: palette[i + 2])
            f.target = .midiCC(channel: 0, controller: 40 + i, port: .all)
            page.widgets.append(f)
        }
        var b = ControlWidget(name: "Build", kind: .button, colorHex: "#F2D33C")
        b.target = .midiNote(channel: 0, note: 60, port: .all)
        var t = ControlWidget(name: "Delay", kind: .toggle, colorHex: "#3CC8E6")
        t.target = .midiCC(channel: 0, controller: 50, port: .all)
        page.widgets.append(contentsOf: [b, t])
        return page
    }
}

/// Packs widgets into rows of `columns` units, in order (greedy). Pure, for the grid layout.
public enum ControlLayout {
    public static func rows(_ widgets: [ControlWidget], columns: Int = ControlPage.columns) -> [[ControlWidget]] {
        var rows: [[ControlWidget]] = []
        var current: [ControlWidget] = []
        var used = 0
        for w in widgets {
            let width = max(1, min(columns, w.width))
            if used + width > columns, !current.isEmpty {
                rows.append(current)
                current = []
                used = 0
            }
            current.append(w)
            used += width
        }
        if !current.isEmpty { rows.append(current) }
        return rows
    }
}

/// Resolves a Live target against the current set (by name first, index as fallback).
public enum ControlResolver {
    public struct Resolved: Equatable {
        public var track: Int
        public var device: Int
        public var parameter: Int
    }

    public static func resolve(_ target: ControlTarget, in song: LiveSongState) -> Resolved? {
        guard case .liveParameter(let tName, let tIdx, let dName, let dIdx, let pName, let pIdx) = target else { return nil }
        let track: LiveTrack? = song.tracks.first(where: { $0.name.caseInsensitiveCompare(tName) == .orderedSame }) ?? song.track(tIdx)
        guard let t = track else { return nil }
        let device: LiveDevice? = t.devices.first(where: { $0.name.caseInsensitiveCompare(dName) == .orderedSame }) ?? t.devices[safeIndex: dIdx]
        guard let d = device else { return nil }
        let p = d.parameterIndex(named: pName) ?? (pIdx >= 0 && pIdx < d.parameters.count ? pIdx : nil)
        guard let pi = p else {
            // Parameters not loaded yet (or the name is unknown): -1 tells the caller to request them.
            return Resolved(track: t.index, device: d.index, parameter: -1)
        }
        return Resolved(track: t.index, device: d.index, parameter: pi)
    }
}

extension Array {
    subscript(safeIndex index: Int) -> Element? {
        (index >= 0 && index < count) ? self[index] : nil
    }
}
