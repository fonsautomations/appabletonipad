import Foundation

/// Outgoing requests understood by AbletonOSC (plus the StageDeck master-track extension).
/// All addresses verified against the AbletonOSC source.
public enum LiveCommand {
    public static let listenPort = 11000
    public static let replyPort = 11001

    // MARK: Session

    public static func test() -> OSCMessage { OSCMessage("/live/test") }
    public static func version() -> OSCMessage { OSCMessage("/live/application/get/version") }
    public static func numTracks() -> OSCMessage { OSCMessage("/live/song/get/num_tracks") }
    public static func numScenes() -> OSCMessage { OSCMessage("/live/song/get/num_scenes") }
    public static func sceneNames() -> OSCMessage { OSCMessage("/live/song/get/scenes/name") }
    public static func tempo() -> OSCMessage { OSCMessage("/live/song/get/tempo") }
    public static func setTempo(_ bpm: Double) -> OSCMessage { OSCMessage("/live/song/set/tempo", [.float(Float(bpm))]) }
    public static func isPlaying() -> OSCMessage { OSCMessage("/live/song/get/is_playing") }
    public static func startPlaying() -> OSCMessage { OSCMessage("/live/song/start_playing") }
    public static func continuePlaying() -> OSCMessage { OSCMessage("/live/song/continue_playing") }
    public static func stopPlaying() -> OSCMessage { OSCMessage("/live/song/stop_playing") }
    public static func stopAllClips() -> OSCMessage { OSCMessage("/live/song/stop_all_clips") }
    public static func tapTempo() -> OSCMessage { OSCMessage("/live/song/tap_tempo") }
    public static func metronome(_ on: Bool) -> OSCMessage { OSCMessage("/live/song/set/metronome", [.int32(on ? 1 : 0)]) }
    public static func quantization() -> OSCMessage { OSCMessage("/live/song/get/clip_trigger_quantization") }
    public static func setQuantization(_ q: LiveQuantization) -> OSCMessage {
        OSCMessage("/live/song/set/clip_trigger_quantization", [.int32(Int32(q.rawValue))])
    }
    public static func showMessage(_ text: String) -> OSCMessage { OSCMessage("/live/api/show_message", [.string(text)]) }

    public static func songListen(_ property: String, start: Bool) -> OSCMessage {
        OSCMessage("/live/song/\(start ? "start_listen" : "stop_listen")/\(property)")
    }

    /// Bulk track query. Each property is "track.x" or "clip.x"; values come back flattened
    /// in the order tracks × properties (clip properties expand to one value per scene).
    public static func trackData(from: Int, to: Int, properties: [String]) -> OSCMessage {
        OSCMessage("/live/song/get/track_data", [.int32(Int32(from)), .int32(Int32(to))] + properties.map { .string($0) })
    }

    // MARK: Tracks

    public static func trackGet(_ property: String, track: Int) -> OSCMessage {
        OSCMessage("/live/track/get/\(property)", [.int32(Int32(track))])
    }
    public static func trackSet(_ property: String, track: Int, value: OSCValue) -> OSCMessage {
        OSCMessage("/live/track/set/\(property)", [.int32(Int32(track)), value])
    }
    public static func trackListen(_ property: String, track: Int, start: Bool) -> OSCMessage {
        OSCMessage("/live/track/\(start ? "start_listen" : "stop_listen")/\(property)", [.int32(Int32(track))])
    }
    public static func trackClipNames(track: Int) -> OSCMessage { trackGet("clips/name", track: track) }
    public static func trackClipColors(track: Int) -> OSCMessage { trackGet("clips/color", track: track) }
    public static func trackClipLengths(track: Int) -> OSCMessage { trackGet("clips/length", track: track) }
    public static func trackStopAllClips(track: Int) -> OSCMessage {
        OSCMessage("/live/track/stop_all_clips", [.int32(Int32(track))])
    }
    public static func setVolume(track: Int, value: Double) -> OSCMessage {
        trackSet("volume", track: track, value: .float(Float(max(0, min(1, value)))))
    }
    public static func setPanning(track: Int, value: Double) -> OSCMessage {
        trackSet("panning", track: track, value: .float(Float(max(-1, min(1, value)))))
    }
    public static func setMute(track: Int, on: Bool) -> OSCMessage { trackSet("mute", track: track, value: .int32(on ? 1 : 0)) }
    public static func setSolo(track: Int, on: Bool) -> OSCMessage { trackSet("solo", track: track, value: .int32(on ? 1 : 0)) }
    public static func setArm(track: Int, on: Bool) -> OSCMessage { trackSet("arm", track: track, value: .int32(on ? 1 : 0)) }
    public static func getSend(track: Int, send: Int) -> OSCMessage {
        OSCMessage("/live/track/get/send", [.int32(Int32(track)), .int32(Int32(send))])
    }
    public static func setSend(track: Int, send: Int, value: Double) -> OSCMessage {
        OSCMessage("/live/track/set/send", [.int32(Int32(track)), .int32(Int32(send)), .float(Float(max(0, min(1, value))))])
    }

    // MARK: Clips & scenes

    public static func fireClip(track: Int, scene: Int) -> OSCMessage {
        OSCMessage("/live/clip_slot/fire", [.int32(Int32(track)), .int32(Int32(scene))])
    }
    public static func stopClipSlot(track: Int, scene: Int) -> OSCMessage {
        OSCMessage("/live/clip_slot/stop", [.int32(Int32(track)), .int32(Int32(scene))])
    }
    public static func clipListen(_ property: String, track: Int, scene: Int, start: Bool) -> OSCMessage {
        OSCMessage("/live/clip/\(start ? "start_listen" : "stop_listen")/\(property)", [.int32(Int32(track)), .int32(Int32(scene))])
    }
    public static func clipGet(_ property: String, track: Int, scene: Int) -> OSCMessage {
        OSCMessage("/live/clip/get/\(property)", [.int32(Int32(track)), .int32(Int32(scene))])
    }
    public static func createClip(track: Int, scene: Int, lengthBeats: Double) -> OSCMessage {
        OSCMessage("/live/clip_slot/create_clip", [.int32(Int32(track)), .int32(Int32(scene)), .float(Float(lengthBeats))])
    }
    public static func removeAllNotes(track: Int, scene: Int) -> OSCMessage {
        OSCMessage("/live/clip/remove/notes", [.int32(Int32(track)), .int32(Int32(scene))])
    }
    public static func addNotes(track: Int, scene: Int, args: [OSCValue]) -> OSCMessage {
        OSCMessage("/live/clip/add/notes", [.int32(Int32(track)), .int32(Int32(scene))] + args)
    }
    public static func clipSet(_ property: String, track: Int, scene: Int, value: OSCValue) -> OSCMessage {
        OSCMessage("/live/clip/set/\(property)", [.int32(Int32(track)), .int32(Int32(scene)), value])
    }
    public static func sceneSetName(_ scene: Int, name: String) -> OSCMessage {
        OSCMessage("/live/scene/set/name", [.int32(Int32(scene)), .string(name)])
    }
    public static func fireScene(_ scene: Int) -> OSCMessage { OSCMessage("/live/scene/fire", [.int32(Int32(scene))]) }
    public static func sceneGet(_ property: String, scene: Int) -> OSCMessage {
        OSCMessage("/live/scene/get/\(property)", [.int32(Int32(scene))])
    }
    public static func sceneListen(_ property: String, scene: Int, start: Bool) -> OSCMessage {
        OSCMessage("/live/scene/\(start ? "start_listen" : "stop_listen")/\(property)", [.int32(Int32(scene))])
    }
    public static func selectScene(_ scene: Int) -> OSCMessage { OSCMessage("/live/view/set/selected_scene", [.int32(Int32(scene))]) }
    public static func selectTrack(_ track: Int) -> OSCMessage { OSCMessage("/live/view/set/selected_track", [.int32(Int32(track))]) }
    public static func selectedDevice() -> OSCMessage { OSCMessage("/live/view/get/selected_device") }

    // MARK: Devices
    // Track index >= 0 → AbletonOSC's /live/device/… (track, device, …).
    // Track index LiveSongState.masterTrackIndex → StageDeck extension /live/master/device/… (device, …).
    // Track index for a return (see LiveSongState.trackIndex(forReturn:)) → /live/return/device/… (return, device, …).

    static func deviceAddress(_ suffix: String, track: Int) -> (String, [OSCValue]) {
        if track == LiveSongState.masterTrackIndex { return ("/live/master/device/\(suffix)", []) }
        if let r = LiveSongState.returnIndex(fromTrackIndex: track) { return ("/live/return/device/\(suffix)", [.int32(Int32(r))]) }
        return ("/live/device/\(suffix)", [.int32(Int32(track))])
    }
    static func deviceMessage(_ suffix: String, track: Int, _ rest: [OSCValue]) -> OSCMessage {
        let (address, prefix) = deviceAddress(suffix, track: track)
        return OSCMessage(address, prefix + rest)
    }

    public static func deviceParameterNames(track: Int, device: Int) -> OSCMessage {
        deviceMessage("get/parameters/name", track: track, [.int32(Int32(device))])
    }
    public static func deviceParameterValues(track: Int, device: Int) -> OSCMessage {
        deviceMessage("get/parameters/value", track: track, [.int32(Int32(device))])
    }
    public static func deviceParameterMins(track: Int, device: Int) -> OSCMessage {
        deviceMessage("get/parameters/min", track: track, [.int32(Int32(device))])
    }
    public static func deviceParameterMaxes(track: Int, device: Int) -> OSCMessage {
        deviceMessage("get/parameters/max", track: track, [.int32(Int32(device))])
    }
    public static func setDeviceParameter(track: Int, device: Int, parameter: Int, value: Double) -> OSCMessage {
        deviceMessage("set/parameter/value", track: track, [.int32(Int32(device)), .int32(Int32(parameter)), .float(Float(value))])
    }
    public static func deviceParameterListen(track: Int, device: Int, parameter: Int, start: Bool) -> OSCMessage {
        deviceMessage("\(start ? "start_listen" : "stop_listen")/parameter/value", track: track, [.int32(Int32(device)), .int32(Int32(parameter))])
    }
    /// Device names / class names of a track, the master (`masterTrackIndex`) or a return (`trackIndex(forReturn:)`).
    public static func trackDeviceNames(track: Int) -> OSCMessage {
        if track == LiveSongState.masterTrackIndex { return OSCMessage("/live/master/get/devices/name") }
        if let r = LiveSongState.returnIndex(fromTrackIndex: track) { return OSCMessage("/live/return/get/devices/name", [.int32(Int32(r))]) }
        return OSCMessage("/live/track/get/devices/name", [.int32(Int32(track))])
    }
    public static func trackDeviceClassNames(track: Int) -> OSCMessage {
        if track == LiveSongState.masterTrackIndex { return OSCMessage("/live/master/get/devices/class_name") }
        if let r = LiveSongState.returnIndex(fromTrackIndex: track) { return OSCMessage("/live/return/get/devices/class_name", [.int32(Int32(r))]) }
        return OSCMessage("/live/track/get/devices/class_name", [.int32(Int32(track))])
    }

    // MARK: StageDeck extension (master track / returns), see ableton/AbletonOSC/abletonosc/master.py

    public static func masterGet(_ property: String) -> OSCMessage { OSCMessage("/live/master/get/\(property)") }
    public static func masterSet(_ property: String, value: Double) -> OSCMessage {
        OSCMessage("/live/master/set/\(property)", [.float(Float(value))])
    }
    public static func masterListen(_ property: String, start: Bool) -> OSCMessage {
        OSCMessage("/live/master/\(start ? "start_listen" : "stop_listen")/\(property)")
    }
    public static func numReturnTracks() -> OSCMessage { OSCMessage("/live/song/get/num_return_tracks") }
    public static func returnTrackNames() -> OSCMessage { OSCMessage("/live/song/get/return_tracks/name") }
    public static func returnSet(_ property: String, index: Int, value: OSCValue) -> OSCMessage {
        OSCMessage("/live/return/set/\(property)", [.int32(Int32(index)), value])
    }
    public static func returnGet(_ property: String, index: Int) -> OSCMessage {
        OSCMessage("/live/return/get/\(property)", [.int32(Int32(index))])
    }
    public static func returnListen(_ property: String, index: Int, start: Bool) -> OSCMessage {
        OSCMessage("/live/return/\(start ? "start_listen" : "stop_listen")/\(property)", [.int32(Int32(index))])
    }
    public static func returnGetSend(index: Int, send: Int) -> OSCMessage {
        OSCMessage("/live/return/get/send", [.int32(Int32(index)), .int32(Int32(send))])
    }
    public static func returnSetSend(index: Int, send: Int, value: Double) -> OSCMessage {
        OSCMessage("/live/return/set/send", [.int32(Int32(index)), .int32(Int32(send)), .float(Float(max(0, min(1, value))))])
    }
}

/// Typed events decoded from AbletonOSC replies and listener pushes.
public enum LiveEvent: Equatable {
    case testOK
    case version(String)
    case error(String)
    case tempo(Double)
    case isPlaying(Bool)
    case beat(Int)
    case numTracks(Int)
    case numScenes(Int)
    case quantization(LiveQuantization)
    case sceneNames([String])
    case trackData([OSCValue])
    case trackName(track: Int, String)
    case trackColor(track: Int, LiveColor)
    case trackMute(track: Int, Bool)
    case trackSolo(track: Int, Bool)
    case trackArm(track: Int, Bool)
    case trackCanBeArmed(track: Int, Bool)
    case trackVolume(track: Int, Double)
    case trackPanning(track: Int, Double)
    case trackSend(track: Int, send: Int, Double)
    case trackMeter(track: Int, Double)
    case trackPlayingSlot(track: Int, Int)
    case trackFiredSlot(track: Int, Int)
    case trackIsGroup(track: Int, Bool)
    case trackClipNames(track: Int, [String?])
    case trackClipColors(track: Int, [LiveColor?])
    case trackClipLengths(track: Int, [Double?])
    case trackDeviceNames(track: Int, [String])
    case trackDeviceClassNames(track: Int, [String])
    case clipPlayingPosition(track: Int, scene: Int, Double)
    case clipIsPlaying(track: Int, scene: Int, Bool)
    case clipName(track: Int, scene: Int, String)
    case clipColor(track: Int, scene: Int, LiveColor)
    case clipLength(track: Int, scene: Int, Double)
    case clipIsMIDI(track: Int, scene: Int, Bool)
    case sceneName(scene: Int, String)
    case sceneColor(scene: Int, LiveColor)
    case sceneTriggered(scene: Int, Bool)
    case deviceParameterNames(track: Int, device: Int, [String])
    case deviceParameterValues(track: Int, device: Int, [Double])
    case deviceParameterMins(track: Int, device: Int, [Double])
    case deviceParameterMaxes(track: Int, device: Int, [Double])
    case deviceParameterValue(track: Int, device: Int, parameter: Int, Double)
    case selectedDevice(track: Int, device: Int)
    case masterVolume(Double)
    case masterMeter(Double)
    case cueVolume(Double)
    case numReturnTracks(Int)
    case returnTrackNames([String])
    case returnVolume(index: Int, Double)
    case returnMute(index: Int, Bool)
    case returnPanning(index: Int, Double)
    case returnSend(index: Int, send: Int, Double)
    case masterPanning(Double)
    case unknown(OSCMessage)
}

/// Decodes OSC messages coming from AbletonOSC into `LiveEvent`s.
public enum LiveEventDecoder {
    public static func decode(_ m: OSCMessage) -> LiveEvent {
        let a = m.arguments
        func i(_ n: Int) -> Int? { n < a.count ? a[n].intValue : nil }
        func d(_ n: Int) -> Double? { n < a.count ? a[n].doubleValue : nil }
        func b(_ n: Int) -> Bool? { n < a.count ? a[n].boolValue : nil }
        func s(_ n: Int) -> String? { n < a.count ? a[n].stringValue : nil }
        func strings(from n: Int) -> [String] { a.count > n ? a[n...].compactMap { $0.stringValue } : [] }
        func doubles(from n: Int) -> [Double] { a.count > n ? a[n...].compactMap { $0.doubleValue } : [] }

        switch m.address {
        case "/live/test":
            return .testOK
        case "/live/application/get/version":
            if let major = i(0), let minor = i(1) { return .version("\(major).\(minor)") }
            return .version(s(0) ?? "")
        case "/live/error":
            return .error(s(0) ?? "unknown error")
        case "/live/song/get/tempo":
            if let v = d(0) { return .tempo(v) }
        case "/live/song/get/is_playing":
            if let v = b(0) { return .isPlaying(v) }
        case "/live/song/get/beat":
            if let v = i(0) { return .beat(v) }
        case "/live/song/get/num_tracks":
            if let v = i(0) { return .numTracks(v) }
        case "/live/song/get/num_scenes":
            if let v = i(0) { return .numScenes(v) }
        case "/live/song/get/clip_trigger_quantization":
            if let v = i(0), let q = LiveQuantization(rawValue: v) { return .quantization(q) }
        case "/live/song/get/scenes/name":
            return .sceneNames(strings(from: 0))
        case "/live/song/get/track_data":
            return .trackData(a)
        case "/live/song/get/num_return_tracks":
            if let v = i(0) { return .numReturnTracks(v) }
        case "/live/song/get/return_tracks/name":
            return .returnTrackNames(strings(from: 0))

        case "/live/track/get/name":
            if let t = i(0), let v = s(1) { return .trackName(track: t, v) }
        case "/live/track/get/color":
            if let t = i(0), let v = i(1) { return .trackColor(track: t, LiveColor(rgb: v)) }
        case "/live/track/get/mute":
            if let t = i(0), let v = b(1) { return .trackMute(track: t, v) }
        case "/live/track/get/solo":
            if let t = i(0), let v = b(1) { return .trackSolo(track: t, v) }
        case "/live/track/get/arm":
            if let t = i(0), let v = b(1) { return .trackArm(track: t, v) }
        case "/live/track/get/can_be_armed":
            if let t = i(0), let v = b(1) { return .trackCanBeArmed(track: t, v) }
        case "/live/track/get/volume":
            if let t = i(0), let v = d(1) { return .trackVolume(track: t, v) }
        case "/live/track/get/panning":
            if let t = i(0), let v = d(1) { return .trackPanning(track: t, v) }
        case "/live/track/get/send":
            if let t = i(0), let sendIndex = i(1), let v = d(2) { return .trackSend(track: t, send: sendIndex, v) }
        case "/live/track/get/output_meter_level":
            if let t = i(0), let v = d(1) { return .trackMeter(track: t, v) }
        case "/live/track/get/playing_slot_index":
            if let t = i(0), let v = i(1) { return .trackPlayingSlot(track: t, v) }
        case "/live/track/get/fired_slot_index":
            if let t = i(0), let v = i(1) { return .trackFiredSlot(track: t, v) }
        case "/live/track/get/is_foldable":
            if let t = i(0), let v = b(1) { return .trackIsGroup(track: t, v) }
        case "/live/track/get/clips/name":
            if let t = i(0) { return .trackClipNames(track: t, a.dropFirst().map { $0.isNull ? nil : ($0.stringValue ?? "") }) }
        case "/live/track/get/clips/color":
            if let t = i(0) { return .trackClipColors(track: t, a.dropFirst().map { $0.isNull ? nil : LiveColor(rgb: $0.intValue ?? 0) }) }
        case "/live/track/get/clips/length":
            if let t = i(0) { return .trackClipLengths(track: t, a.dropFirst().map { $0.isNull ? nil : $0.doubleValue }) }
        case "/live/track/get/devices/name":
            if let t = i(0) { return .trackDeviceNames(track: t, strings(from: 1)) }
        case "/live/track/get/devices/class_name":
            if let t = i(0) { return .trackDeviceClassNames(track: t, strings(from: 1)) }

        case "/live/clip/get/playing_position":
            if let t = i(0), let c = i(1), let v = d(2) { return .clipPlayingPosition(track: t, scene: c, v) }
        case "/live/clip/get/is_playing":
            if let t = i(0), let c = i(1), let v = b(2) { return .clipIsPlaying(track: t, scene: c, v) }
        case "/live/clip/get/name":
            if let t = i(0), let c = i(1), let v = s(2) { return .clipName(track: t, scene: c, v) }
        case "/live/clip/get/color":
            if let t = i(0), let c = i(1), let v = i(2) { return .clipColor(track: t, scene: c, LiveColor(rgb: v)) }
        case "/live/clip/get/length":
            if let t = i(0), let c = i(1), let v = d(2) { return .clipLength(track: t, scene: c, v) }
        case "/live/clip/get/is_midi_clip":
            if let t = i(0), let c = i(1), let v = b(2) { return .clipIsMIDI(track: t, scene: c, v) }

        case "/live/scene/get/name":
            if let sc = i(0), let v = s(1) { return .sceneName(scene: sc, v) }
        case "/live/scene/get/color":
            if let sc = i(0), let v = i(1) { return .sceneColor(scene: sc, LiveColor(rgb: v)) }
        case "/live/scene/get/is_triggered":
            if let sc = i(0), let v = b(1) { return .sceneTriggered(scene: sc, v) }

        case "/live/device/get/parameters/name":
            if let t = i(0), let dv = i(1) { return .deviceParameterNames(track: t, device: dv, strings(from: 2)) }
        case "/live/device/get/parameters/value":
            if let t = i(0), let dv = i(1) { return .deviceParameterValues(track: t, device: dv, doubles(from: 2)) }
        case "/live/device/get/parameters/min":
            if let t = i(0), let dv = i(1) { return .deviceParameterMins(track: t, device: dv, doubles(from: 2)) }
        case "/live/device/get/parameters/max":
            if let t = i(0), let dv = i(1) { return .deviceParameterMaxes(track: t, device: dv, doubles(from: 2)) }
        case "/live/device/get/parameter/value":
            if let t = i(0), let dv = i(1), let p = i(2), let v = d(3) { return .deviceParameterValue(track: t, device: dv, parameter: p, v) }

        case "/live/view/get/selected_device":
            if let t = i(0), let dv = i(1) { return .selectedDevice(track: t, device: dv) }
        case "/live/master/get/volume":
            if let v = d(0) { return .masterVolume(v) }
        case "/live/master/get/output_meter_level":
            if let v = d(0) { return .masterMeter(v) }
        case "/live/master/get/cue_volume":
            if let v = d(0) { return .cueVolume(v) }
        case "/live/return/get/volume":
            if let r = i(0), let v = d(1) { return .returnVolume(index: r, v) }
        case "/live/return/get/mute":
            if let r = i(0), let v = b(1) { return .returnMute(index: r, v) }
        case "/live/return/get/panning":
            if let r = i(0), let v = d(1) { return .returnPanning(index: r, v) }
        case "/live/return/get/send":
            if let r = i(0), let sendIndex = i(1), let v = d(2) { return .returnSend(index: r, send: sendIndex, v) }
        case "/live/master/get/panning":
            if let v = d(0) { return .masterPanning(v) }
        // Master / return devices (StageDeck extension): same events as track devices with a pseudo track index.
        case "/live/master/get/devices/name":
            return .trackDeviceNames(track: LiveSongState.masterTrackIndex, strings(from: 0))
        case "/live/master/get/devices/class_name":
            return .trackDeviceClassNames(track: LiveSongState.masterTrackIndex, strings(from: 0))
        case "/live/master/device/get/parameters/name":
            if let dv = i(0) { return .deviceParameterNames(track: LiveSongState.masterTrackIndex, device: dv, strings(from: 1)) }
        case "/live/master/device/get/parameters/value":
            if let dv = i(0) { return .deviceParameterValues(track: LiveSongState.masterTrackIndex, device: dv, doubles(from: 1)) }
        case "/live/master/device/get/parameters/min":
            if let dv = i(0) { return .deviceParameterMins(track: LiveSongState.masterTrackIndex, device: dv, doubles(from: 1)) }
        case "/live/master/device/get/parameters/max":
            if let dv = i(0) { return .deviceParameterMaxes(track: LiveSongState.masterTrackIndex, device: dv, doubles(from: 1)) }
        case "/live/master/device/get/parameter/value":
            if let dv = i(0), let p = i(1), let v = d(2) { return .deviceParameterValue(track: LiveSongState.masterTrackIndex, device: dv, parameter: p, v) }
        case "/live/return/get/devices/name":
            if let r = i(0) { return .trackDeviceNames(track: LiveSongState.trackIndex(forReturn: r), strings(from: 1)) }
        case "/live/return/get/devices/class_name":
            if let r = i(0) { return .trackDeviceClassNames(track: LiveSongState.trackIndex(forReturn: r), strings(from: 1)) }
        case "/live/return/device/get/parameters/name":
            if let r = i(0), let dv = i(1) { return .deviceParameterNames(track: LiveSongState.trackIndex(forReturn: r), device: dv, strings(from: 2)) }
        case "/live/return/device/get/parameters/value":
            if let r = i(0), let dv = i(1) { return .deviceParameterValues(track: LiveSongState.trackIndex(forReturn: r), device: dv, doubles(from: 2)) }
        case "/live/return/device/get/parameters/min":
            if let r = i(0), let dv = i(1) { return .deviceParameterMins(track: LiveSongState.trackIndex(forReturn: r), device: dv, doubles(from: 2)) }
        case "/live/return/device/get/parameters/max":
            if let r = i(0), let dv = i(1) { return .deviceParameterMaxes(track: LiveSongState.trackIndex(forReturn: r), device: dv, doubles(from: 2)) }
        case "/live/return/device/get/parameter/value":
            if let r = i(0), let dv = i(1), let p = i(2), let v = d(3) { return .deviceParameterValue(track: LiveSongState.trackIndex(forReturn: r), device: dv, parameter: p, v) }
        default:
            break
        }
        return .unknown(m)
    }
}
