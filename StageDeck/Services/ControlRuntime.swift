import Foundation
import Combine

/// Drives CONTROL page widgets: Live device parameters over OSC (with feedback) or plain MIDI.
@MainActor
final class ControlRuntime: ObservableObject {
    /// Current normalized values (0...1) for MIDI-targeted widgets, keyed by widget id ("id" and "id:y").
    @Published private(set) var values: [String: Double] = [:]
    @Published private(set) var lastSent: String = ""
    /// Widgets whose Live target could not be found in the current set.
    @Published private(set) var unresolved: Set<UUID> = []

    private let live: LiveSession
    private let midi: MIDIService
    /// Name → index resolution cache, rebuilt when the set's devices or parameters change.
    private var resolvedCache: [String: ControlResolver.Resolved?] = [:]
    private var cacheSignature: Int = -1

    private func resolve(_ target: ControlTarget, key: String) -> ControlResolver.Resolved? {
        let sig = live.song.deviceSignature &+ live.song.tracks.count &* 7919
        if sig != cacheSignature { resolvedCache.removeAll(); cacheSignature = sig }
        if let cached = resolvedCache[key] { return cached }
        let r = ControlResolver.resolve(target, in: live.song)
        if r == nil || r!.parameter >= 0 { resolvedCache[key] = r } // keep re-trying while parameters load
        return r
    }
    private var lastCC: [String: Int] = [:]
    private var heldNotes: Set<String> = []

    init(live: LiveSession, midi: MIDIService) {
        self.live = live
        self.midi = midi
    }

    /// Seeds stored values from the profile (called when pages change).
    func seed(from pages: [ControlPage]) {
        for page in pages {
            for w in page.widgets {
                if values[w.id.uuidString] == nil { values[w.id.uuidString] = w.value }
                if values[w.id.uuidString + ":y"] == nil { values[w.id.uuidString + ":y"] = w.valueY }
            }
        }
    }

    /// Makes sure Live parameter targets are loaded and listened to (feedback).
    func prepare(page: ControlPage) {
        var missing: Set<UUID> = []
        for w in page.widgets {
            for target in [w.target, w.targetY] where target.isLive {
                if let r = ControlResolver.resolve(target, in: live.song) {
                    live.requestDeviceParameters(track: r.track, device: r.device)
                    if r.parameter >= 0 {
                        live.listenParameter(track: r.track, device: r.device, parameter: r.parameter)
                    } else if live.state == .connected, live.song.devices(ofTrack: r.track)[safe: r.device].map({ $0.parameters.count > 1 }) == true {
                        missing.insert(w.id) // parameters loaded but no such name
                    }
                } else if live.state == .connected {
                    missing.insert(w.id)
                }
            }
        }
        unresolved = missing
    }

    /// Normalized value shown by a widget (Live targets read back from Live).
    func value(for widget: ControlWidget, axisY: Bool = false) -> Double {
        let target = axisY ? widget.targetY : widget.target
        if case .liveParameter = target, let r = resolve(target, key: widget.id.uuidString + (axisY ? ":y" : "")), r.parameter >= 0,
           let p = live.song.devices(ofTrack: r.track)[safe: r.device]?.parameters[safe: r.parameter] {
            return widget.unscaled(p.normalized)
        }
        return values[widget.id.uuidString + (axisY ? ":y" : "")] ?? (axisY ? widget.valueY : widget.value)
    }

    /// Sets a continuous value 0...1.
    func set(_ widget: ControlWidget, value v: Double, axisY: Bool = false) {
        let key = widget.id.uuidString + (axisY ? ":y" : "")
        let clamped = max(0, min(1, v))
        values[key] = clamped
        let target = axisY ? widget.targetY : widget.target
        send(target: target, normalized: widget.scaled(clamped), widgetKey: key)
    }

    /// Momentary / toggle button press.
    func press(_ widget: ControlWidget, down: Bool) {
        let key = widget.id.uuidString
        let on: Bool
        if widget.kind == .toggle {
            guard down else { return }
            on = (values[key] ?? 0) < 0.5
        } else {
            on = down
        }
        values[key] = on ? 1 : 0
        switch widget.target {
        case .midiNote(let ch, let note, let port):
            let msg: MIDIMessage = on ? .noteOn(channel: UInt8(ch & 0x0F), note: UInt8(note & 0x7F), velocity: 127)
                                      : .noteOff(channel: UInt8(ch & 0x0F), note: UInt8(note & 0x7F), velocity: 0)
            midi.send(msg, to: port)
            lastSent = msg.description
        default:
            send(target: widget.target, normalized: on ? widget.scaled(1) : widget.scaled(0), widgetKey: key)
        }
    }

    private func send(target: ControlTarget, normalized: Double, widgetKey: String) {
        switch target {
        case .none:
            break
        case .liveParameter:
            guard let r = ControlResolver.resolve(target, in: live.song), r.parameter >= 0 else { return }
            live.setDeviceParameter(track: r.track, device: r.device, parameter: r.parameter, normalized: normalized)
            lastSent = "\(target.label) = \(Int((normalized * 100).rounded()))%"
        case .midiCC(let ch, let cc, let port):
            let v = Int((max(0, min(1, normalized)) * 127).rounded())
            if lastCC[widgetKey] == v { return }
            lastCC[widgetKey] = v
            let msg = MIDIMessage.controlChange(channel: UInt8(ch & 0x0F), controller: UInt8(cc & 0x7F), value: UInt8(v))
            midi.send(msg, to: port)
            lastSent = msg.description
        case .midiNote(let ch, let note, let port):
            let on = normalized >= 0.5
            let msg: MIDIMessage = on ? .noteOn(channel: UInt8(ch & 0x0F), note: UInt8(note & 0x7F), velocity: UInt8(max(1, min(127, Int(normalized * 127)))))
                                      : .noteOff(channel: UInt8(ch & 0x0F), note: UInt8(note & 0x7F), velocity: 0)
            midi.send(msg, to: port)
            lastSent = msg.description
        }
    }
}
