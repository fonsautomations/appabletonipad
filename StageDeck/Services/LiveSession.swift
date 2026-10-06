import Foundation
import Combine
import Network

enum LiveConnectionState: Equatable {
    case disconnected
    case searching
    case connecting
    case connected
    case demo
    /// A real set loaded from an .als file, browsed without Live running.
    case offline

    var label: String {
        switch self {
        case .disconnected: return "Offline"
        case .searching: return "Searching…"
        case .connecting: return "Connecting…"
        case .connected: return "Live"
        case .demo: return "Demo"
        case .offline: return "Offline set"
        }
    }

    /// Demo and offline sets simulate Live locally; nothing is sent over the network.
    var isSimulated: Bool { self == .demo || self == .offline }
}

/// High-rate values (meters, clip positions) published at most 20×/s so the grid stays cheap.
@MainActor
final class LiveMeters: ObservableObject {
    @Published var trackMeters: [Int: Double] = [:]
    @Published var clipPositions: [String: Double] = [:]
    @Published var masterMeter: Double = 0

    func progress(track: Int, scene: Int, length: Double) -> Double? {
        guard length > 0, let pos = clipPositions["\(track):\(scene)"] else { return nil }
        return max(0, min(1, pos / length))
    }
}

/// Thread-safe mailbox: the OSC queue appends, the main actor drains in one hop per burst.
final class OSCInbox: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [(OSCMessage, String)] = []
    private var scheduled = false

    /// Returns true when the caller should schedule a drain.
    func push(_ m: OSCMessage, from sender: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        items.append((m, sender))
        if scheduled { return false }
        scheduled = true
        return true
    }

    func drain() -> [(OSCMessage, String)] {
        lock.lock(); defer { lock.unlock() }
        let out = items
        items.removeAll(keepingCapacity: true)
        scheduled = false
        return out
    }
}

/// Talks to Ableton Live through AbletonOSC and keeps `song` in sync.
/// All published state changes happen on the main thread.
@MainActor
final class LiveSession: ObservableObject {
    /// The set as the app knows it. Changes are published at most once per run-loop turn, so a burst of
    /// OSC replies or a fader drag at 60 Hz costs one re-render, not one per message.
    private(set) var song = LiveSongState() { didSet { publishCoalesced() } }
    @Published private(set) var sections: [SceneSection] = []
    private var publishScheduled = false

    private func publishCoalesced() {
        guard !publishScheduled else { return }
        publishScheduled = true
        objectWillChange.send()
        DispatchQueue.main.async { [weak self] in self?.publishScheduled = false }
    }
    @Published private(set) var state: LiveConnectionState = .disconnected
    @Published private(set) var liveHost: String = ""
    @Published private(set) var lastError: String = ""
    @Published private(set) var listenerError: String = ""
    private(set) var lastMessageAt: Date = .distantPast
    private(set) var messagesReceived: Int = 0
    @Published var meterRefreshEnabled: Bool = true
    @Published private(set) var selectedDeviceInLive: SelectedDevice? = nil
    struct SelectedDevice: Equatable { var track: Int; var device: Int }
    private var selectedDeviceCallbacks: [(Int, Int) -> Void] = []
    private var listenedParameters: Set<String> = []
    let meters = LiveMeters()
    private var pendingMeters: [Int: Double] = [:]
    private var pendingPositions: [String: Double] = [:]
    private var pendingMaster: Double? = nil
    private var meterFlushTimer: Timer?

    /// Fired after a successful (re)load of the whole set.
    var onSessionLoaded: (() -> Void)?
    /// Fired with every tempo change (for the sequencer).
    var onTempo: ((Double) -> Void)?
    /// Fired with transport changes (for the sequencer).
    var onTransport: ((Bool) -> Void)?

    private let client = OSCClient()
    private let inbox = OSCInbox()
    private var heartbeat: Timer?
    private var structurePoll: Timer?
    private var demoTimer: Timer?
    private var throttleTimer: Timer?
    private var pendingThrottled: [String: OSCMessage] = [:]
    private var awaitingTest = false
    private var consecutiveMisses = 0
    private var loadingTracks: Set<Int> = []
    private var listenedClips: [Int: Int] = [:] // track → scene we listen playing_position on
    private var deviceParamsRequested: Set<String> = []
    private var configuredHost = ""
    private var configuredPort = 11000
    private var configuredReplyPort = 11001
    private var autoReconnect = true
    private var demoStart = Date()

    init() {
        let inbox = self.inbox
        client.onMessage = { [weak self] message, sender in
            if inbox.push(message, from: sender) {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    for (m, s) in self.inbox.drain() { self.handle(m, from: s) }
                }
            }
        }
        meterFlushTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.flushMeters() }
        }
        client.onListenerError = { [weak self] text in
            Task { @MainActor [weak self] in self?.listenerError = text }
        }
    }

    private func flushMeters() {
        if !pendingMeters.isEmpty {
            for (k, v) in pendingMeters { meters.trackMeters[k] = v }
            pendingMeters.removeAll()
        }
        if !pendingPositions.isEmpty {
            for (k, v) in pendingPositions { meters.clipPositions[k] = v }
            pendingPositions.removeAll()
        }
        if let m = pendingMaster { meters.masterMeter = m; pendingMaster = nil }
    }

    // MARK: - Connection lifecycle

    func configure(host: String, port: Int, replyPort: Int, autoReconnect: Bool) {
        configuredHost = host.trimmingCharacters(in: .whitespaces)
        configuredPort = port
        configuredReplyPort = replyPort
        self.autoReconnect = autoReconnect
    }

    func connect() {
        stopDemo()
        client.startListening()
        liveHost = configuredHost
        if configuredHost.isEmpty {
            state = .searching
            client.configure(host: "", port: configuredPort, replyPort: configuredReplyPort)
            client.broadcastDiscovery()
        } else {
            state = .connecting
            client.configure(host: configuredHost, port: configuredPort, replyPort: configuredReplyPort)
            send(LiveCommand.test())
        }
        startHeartbeat()
    }

    func disconnect() {
        heartbeat?.invalidate(); heartbeat = nil
        structurePoll?.invalidate(); structurePoll = nil
        throttleTimer?.invalidate(); throttleTimer = nil
        stopDemo()
        client.stop()
        state = .disconnected
        listenedClips.removeAll()
    }

    func retryDiscovery() {
        client.broadcastDiscovery()
    }

    private func startHeartbeat() {
        heartbeat?.invalidate()
        heartbeat = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.heartbeatTick() }
        }
        structurePoll?.invalidate()
        structurePoll = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.pollStructure() }
        }
    }

    private func heartbeatTick() {
        switch state {
        case .demo, .offline, .disconnected:
            return
        case .searching:
            client.broadcastDiscovery()
        case .connecting, .connected:
            if awaitingTest {
                consecutiveMisses += 1
                if consecutiveMisses >= 3 {
                    lastError = "Live stopped answering"
                    awaitingTest = false
                    consecutiveMisses = 0
                    if autoReconnect {
                        state = configuredHost.isEmpty ? .searching : .connecting
                        if configuredHost.isEmpty { client.broadcastDiscovery() }
                    } else {
                        state = .disconnected
                    }
                    return
                }
            }
            awaitingTest = true
            send(LiveCommand.test())
        }
    }

    private func pollStructure() {
        guard state == .connected else { return }
        send(LiveCommand.numTracks())
        send(LiveCommand.numScenes())
    }

    // MARK: - Sending

    func send(_ message: OSCMessage) {
        guard !state.isSimulated else { return }
        client.send(message)
    }

    /// Coalesces rapid fader moves: at most one message per key every 30 ms.
    func sendThrottled(key: String, _ message: OSCMessage) {
        pendingThrottled[key] = message
        if throttleTimer == nil {
            throttleTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in self?.flushThrottled() }
            }
        }
    }

    private func flushThrottled() {
        if pendingThrottled.isEmpty {
            throttleTimer?.invalidate(); throttleTimer = nil
            return
        }
        for (_, m) in pendingThrottled { send(m) }
        pendingThrottled.removeAll()
    }

    // MARK: - Session loading

    private func loadSession() {
        loadingTracks.removeAll()
        listenedClips.removeAll()
        deviceParamsRequested.removeAll()
        listenedParameters.removeAll()
        send(LiveCommand.version())
        send(LiveCommand.numTracks())
        send(LiveCommand.numScenes())
        send(LiveCommand.tempo())
        send(LiveCommand.isPlaying())
        send(LiveCommand.quantization())
        send(LiveCommand.sceneNames())
        send(LiveCommand.returnTrackNames())
        send(LiveCommand.masterGet("volume"))
        send(LiveCommand.masterGet("cue_volume"))
        send(LiveCommand.trackDeviceNames(track: LiveSongState.masterTrackIndex))
        send(LiveCommand.trackDeviceClassNames(track: LiveSongState.masterTrackIndex))
    }

    /// Mixer state, sends, devices and listeners of one return track (StageDeck extension).
    private func requestReturnDetails(_ r: Int) {
        let pseudo = LiveSongState.trackIndex(forReturn: r)
        send(LiveCommand.returnGet("panning", index: r))
        send(LiveCommand.returnListen("volume", index: r, start: true))
        send(LiveCommand.returnListen("mute", index: r, start: true))
        for s in 0..<song.numSends { send(LiveCommand.returnGetSend(index: r, send: s)) }
        send(LiveCommand.trackDeviceNames(track: pseudo))
        send(LiveCommand.trackDeviceClassNames(track: pseudo))
    }

    private func requestTrackData() {
        send(LiveCommand.trackData(from: 0, to: -1, properties: LiveSession.trackDataProperties))
    }

    static let trackDataProperties = ["track.name", "track.color", "track.is_foldable", "track.group_track", "track.mute", "track.solo",
                                      "track.playing_slot_index", "track.fired_slot_index", "track.has_midi_input"]

    private func requestTrackDetails(_ t: Int) {
        send(LiveCommand.trackClipNames(track: t))
        send(LiveCommand.trackClipColors(track: t))
        send(LiveCommand.trackClipLengths(track: t))
        send(LiveCommand.trackGet("volume", track: t))
        send(LiveCommand.trackGet("panning", track: t))
        send(LiveCommand.trackGet("can_be_armed", track: t))
        send(LiveCommand.trackDeviceNames(track: t))
        send(LiveCommand.trackDeviceClassNames(track: t))
        for s in 0..<song.numSends { send(LiveCommand.getSend(track: t, send: s)) }
    }

    private func startListeners() {
        send(LiveCommand.songListen("tempo", start: true))
        send(LiveCommand.songListen("is_playing", start: true))
        send(LiveCommand.songListen("beat", start: true))
        send(LiveCommand.songListen("clip_trigger_quantization", start: true))
        send(LiveCommand.masterListen("volume", start: true))
        send(LiveCommand.masterListen("output_meter_level", start: true))
        for t in song.tracks {
            send(LiveCommand.trackListen("playing_slot_index", track: t.index, start: true))
            send(LiveCommand.trackListen("fired_slot_index", track: t.index, start: true))
            send(LiveCommand.trackListen("volume", track: t.index, start: true))
            send(LiveCommand.trackListen("mute", track: t.index, start: true))
            send(LiveCommand.trackListen("solo", track: t.index, start: true))
            send(LiveCommand.trackListen("name", track: t.index, start: true))
            send(LiveCommand.trackListen("color", track: t.index, start: true))
            if t.canBeArmed { send(LiveCommand.trackListen("arm", track: t.index, start: true)) }
            if meterRefreshEnabled {
                send(LiveCommand.trackListen("output_meter_level", track: t.index, start: true))
            }
        }
        for s in song.scenes {
            send(LiveCommand.sceneGet("color", scene: s.index))
        }
    }

    func reloadSession() {
        guard state == .connected else { return }
        loadSession()
    }

    // MARK: - Incoming

    private func handle(_ message: OSCMessage, from sender: String) {
        messagesReceived += 1
        lastMessageAt = Date()
        let event = LiveEventDecoder.decode(message)
        switch event {
        case .testOK:
            awaitingTest = false
            consecutiveMisses = 0
            if state == .searching || state == .connecting {
                if !sender.isEmpty, configuredHost.isEmpty {
                    liveHost = sender
                    client.configure(host: sender, port: configuredPort, replyPort: configuredReplyPort)
                }
                state = .connected
                lastError = ""
                loadSession()
            }
        case .version(let v):
            song.liveVersion = v
        case .error(let e):
            lastError = e
        case .tempo(let t):
            song.tempo = t
            onTempo?(t)
        case .isPlaying(let p):
            if song.isPlaying != p { onTransport?(p) }
            song.isPlaying = p
            if !p { meters.clipPositions.removeAll(); pendingPositions.removeAll() }
        case .beat(let b):
            song.beat = b
        case .quantization(let q):
            song.quantization = q
        case .numTracks(let n):
            if n != song.tracks.count {
                song.tracks = (0..<n).map { LiveTrack(index: $0, name: "Track \($0 + 1)") }
                listenedClips.removeAll()
                requestTrackData()
            }
        case .numScenes(let n):
            if n != song.scenes.count {
                song.scenes = (0..<n).map { LiveScene(index: $0, name: "Scene \($0 + 1)") }
                send(LiveCommand.sceneNames())
                for s in song.scenes { send(LiveCommand.sceneGet("color", scene: s.index)) }
            }
        case .sceneNames(let names):
            if names.count != song.scenes.count {
                song.scenes = (0..<names.count).map { LiveScene(index: $0, name: names[$0]) }
                for s in song.scenes { send(LiveCommand.sceneGet("color", scene: s.index)) }
            } else {
                for (i, n) in names.enumerated() { song.scenes[i].name = n }
            }
            sections = SetLayout.sections(from: song.scenes)
        case .trackData(let values):
            applyTrackData(values)
        case .numReturnTracks(let n):
            if song.returnTrackNames.count != n {
                song.returnTrackNames = (0..<n).map { "Return \($0 + 1)" }
            }
        case .returnTrackNames(let names):
            song.returnTrackNames = names
            for t in song.tracks {
                for s in 0..<names.count { send(LiveCommand.getSend(track: t.index, send: s)) }
            }
            if state == .connected { for r in 0..<names.count { requestReturnDetails(r) } }
        case .returnVolume(let r, let v): updateReturn(r) { $0.volume = v }
        case .returnMute(let r, let v): updateReturn(r) { $0.mute = v }
        case .returnPanning(let r, let v): updateReturn(r) { $0.panning = v }
        case .returnSend(let r, let s, let v):
            updateReturn(r) { rt in
                while rt.sends.count <= s { rt.sends.append(0) }
                rt.sends[s] = v
            }
        case .masterPanning:
            break
        case .trackName(let t, let v): update(t) { $0.name = v }
        case .trackColor(let t, let v): update(t) { $0.color = v }
        case .trackMute(let t, let v): update(t) { $0.mute = v }
        case .trackSolo(let t, let v): update(t) { $0.solo = v }
        case .trackArm(let t, let v): update(t) { $0.arm = v }
        case .trackCanBeArmed(let t, let v):
            update(t) { $0.canBeArmed = v }
            if v { send(LiveCommand.trackGet("arm", track: t)) }
        case .trackVolume(let t, let v): update(t) { $0.volume = v }
        case .trackPanning(let t, let v): update(t) { $0.panning = v }
        case .trackSend(let t, let s, let v):
            update(t) { tr in
                while tr.sends.count <= s { tr.sends.append(0) }
                tr.sends[s] = v
            }
        case .trackMeter(let t, let v): pendingMeters[t] = v
        case .trackPlayingSlot(let t, let v):
            update(t) { $0.playingSlotIndex = v }
            updateClipListener(track: t, scene: v)
        case .trackFiredSlot(let t, let v): update(t) { $0.firedSlotIndex = v }
        case .trackIsGroup(let t, let v): update(t) { $0.isGroup = v }
        case .trackClipNames(let t, let names):
            update(t) { tr in
                for (scene, name) in names.enumerated() {
                    if let name {
                        var clip = tr.clips[scene] ?? LiveClip(trackIndex: t, sceneIndex: scene, name: name, color: tr.color, length: 0)
                        clip.name = name
                        tr.clips[scene] = clip
                    } else {
                        tr.clips.removeValue(forKey: scene)
                    }
                }
            }
        case .trackClipColors(let t, let colors):
            update(t) { tr in
                for (scene, color) in colors.enumerated() {
                    if let color, tr.clips[scene] != nil { tr.clips[scene]?.color = color }
                }
            }
        case .trackClipLengths(let t, let lengths):
            update(t) { tr in
                for (scene, len) in lengths.enumerated() {
                    if let len, tr.clips[scene] != nil { tr.clips[scene]?.length = len }
                }
            }
        case .trackDeviceNames(let t, let names):
            updateDevices(t) { existing in
                var devices: [LiveDevice] = []
                for (i, n) in names.enumerated() {
                    var d = LiveDevice(trackIndex: t, index: i, name: n, className: i < existing.count ? existing[i].className : "")
                    if i < existing.count { d.parameters = existing[i].parameters }
                    devices.append(d)
                }
                existing = devices
            }
        case .trackDeviceClassNames(let t, let names):
            updateDevices(t) { devices in
                for (i, n) in names.enumerated() {
                    if i < devices.count { devices[i].className = n }
                    else { devices.append(LiveDevice(trackIndex: t, index: i, name: n, className: n)) }
                }
            }
            if let filter = song.devices(ofTrack: t).first(where: { $0.isAutoFilter }) {
                requestDeviceParameters(track: t, device: filter.index)
            }
        case .clipPlayingPosition(let t, let s, let pos):
            pendingPositions["\(t):\(s)"] = pos
        case .clipIsPlaying, .clipName, .clipColor, .clipLength, .clipIsMIDI:
            break
        case .sceneName(let s, let v):
            if s < song.scenes.count { song.scenes[s].name = v; sections = SetLayout.sections(from: song.scenes) }
        case .sceneColor(let s, let v):
            if s < song.scenes.count { song.scenes[s].color = v; sections = SetLayout.sections(from: song.scenes) }
        case .sceneTriggered(let s, let v):
            if s < song.scenes.count { song.scenes[s].isTriggered = v }
        case .deviceParameterNames(let t, let d, let names):
            updateDevices(t) { devices in
                guard d >= 0, d < devices.count else { return }
                var params = devices[d].parameters
                for (i, n) in names.enumerated() {
                    if i < params.count { params[i].name = n } else { params.append(LiveDeviceParameter(index: i, name: n, value: 0, min: 0, max: 1)) }
                }
                devices[d].parameters = params
            }
            if let dev = song.devices(ofTrack: t)[safe: d], let f = dev.parameterIndex(named: "Frequency") {
                send(LiveCommand.deviceParameterListen(track: t, device: d, parameter: f, start: true))
            }
        case .deviceParameterValues(let t, let d, let values):
            updateDevices(t) { devices in
                guard d >= 0, d < devices.count else { return }
                for (i, v) in values.enumerated() where i < devices[d].parameters.count { devices[d].parameters[i].value = v }
            }
        case .deviceParameterMins(let t, let d, let values):
            updateDevices(t) { devices in
                guard d >= 0, d < devices.count else { return }
                for (i, v) in values.enumerated() where i < devices[d].parameters.count { devices[d].parameters[i].min = v }
            }
        case .deviceParameterMaxes(let t, let d, let values):
            updateDevices(t) { devices in
                guard d >= 0, d < devices.count else { return }
                for (i, v) in values.enumerated() where i < devices[d].parameters.count { devices[d].parameters[i].max = v }
            }
        case .deviceParameterValue(let t, let d, let p, let v):
            updateDevices(t) { devices in
                guard d >= 0, p >= 0, d < devices.count, p < devices[d].parameters.count else { return }
                devices[d].parameters[p].value = v
            }
        case .selectedDevice(let t, let d):
            selectedDeviceInLive = SelectedDevice(track: t, device: d)
            let callbacks = selectedDeviceCallbacks
            selectedDeviceCallbacks.removeAll()
            for cb in callbacks { cb(t, d) }
        case .masterVolume(let v): song.masterVolume = v
        case .masterMeter(let v): pendingMaster = v
        case .cueVolume(let v): song.cueVolume = v
        case .unknown:
            break
        }
    }

    private func update(_ index: Int, _ body: (inout LiveTrack) -> Void) {
        guard index >= 0, index < song.tracks.count else { return }
        body(&song.tracks[index])
    }

    private func updateReturn(_ index: Int, _ body: (inout LiveReturnTrack) -> Void) {
        guard index >= 0, index < song.returnTracks.count else { return }
        body(&song.returnTracks[index])
    }

    /// Devices of a track, the master (`masterTrackIndex`) or a return (pseudo index).
    private func updateDevices(_ index: Int, _ body: (inout [LiveDevice]) -> Void) {
        if index == LiveSongState.masterTrackIndex { body(&song.masterDevices); return }
        if let r = LiveSongState.returnIndex(fromTrackIndex: index) { updateReturn(r) { body(&$0.devices) }; return }
        update(index) { body(&$0.devices) }
    }

    private func applyTrackData(_ values: [OSCValue]) {
        let props = LiveSession.trackDataProperties.count
        guard props > 0, values.count % props == 0 else { return }
        let n = values.count / props
        if n != song.tracks.count {
            song.tracks = (0..<n).map { LiveTrack(index: $0, name: "Track \($0 + 1)") }
        }
        for t in 0..<n {
            let base = t * props
            update(t) { tr in
                tr.name = values[base].stringValue ?? tr.name
                tr.color = LiveColor(rgb: values[base + 1].intValue ?? 0)
                tr.isGroup = values[base + 2].boolValue ?? false
                tr.groupTrackIndex = values[base + 3].isNull ? nil : values[base + 3].intValue
                tr.mute = values[base + 4].boolValue ?? false
                tr.solo = values[base + 5].boolValue ?? false
                tr.playingSlotIndex = values[base + 6].intValue ?? -1
                tr.firedSlotIndex = values[base + 7].intValue ?? -1
                tr.hasMIDIInput = values[base + 8].boolValue ?? false
            }
            requestTrackDetails(t)
        }
        startListeners()
        for t in song.tracks where t.playingSlotIndex >= 0 { updateClipListener(track: t.index, scene: t.playingSlotIndex) }
        onSessionLoaded?()
    }

    private func updateClipListener(track: Int, scene: Int) {
        if let old = listenedClips[track], old != scene {
            send(LiveCommand.clipListen("playing_position", track: track, scene: old, start: false))
            meters.clipPositions.removeValue(forKey: "\(track):\(old)")
            pendingPositions.removeValue(forKey: "\(track):\(old)")
            listenedClips.removeValue(forKey: track)
        }
        if scene >= 0, listenedClips[track] != scene {
            listenedClips[track] = scene
            send(LiveCommand.clipListen("playing_position", track: track, scene: scene, start: true))
        }
    }

    /// Subscribes to a device parameter so widgets show Live's value (idempotent).
    func listenParameter(track: Int, device: Int, parameter: Int) {
        let key = "\(track):\(device):\(parameter)"
        guard device >= 0, parameter >= 0, !listenedParameters.contains(key), state == .connected else { return }
        listenedParameters.insert(key)
        send(LiveCommand.deviceParameterListen(track: track, device: device, parameter: parameter, start: true))
    }

    /// Asks Live which device is selected; the callback runs when the answer arrives.
    func requestSelectedDevice(_ completion: @escaping (Int, Int) -> Void) {
        if state.isSimulated {
            completion(1, 0)
            return
        }
        selectedDeviceCallbacks.append(completion)
        send(LiveCommand.selectedDevice())
    }

    /// Loads the parameters of every device of a channel that has not been loaded yet (idempotent).
    func loadDevices(ofTrack track: Int) {
        guard state == .connected else { return }
        for d in song.devices(ofTrack: track) where d.parameters.count <= 1 {
            requestDeviceParameters(track: track, device: d.index)
        }
    }

    func requestDeviceParameters(track: Int, device: Int) {
        guard device >= 0 else { return }
        let key = "\(track):\(device)"
        guard !deviceParamsRequested.contains(key) else { return }
        deviceParamsRequested.insert(key)
        send(LiveCommand.deviceParameterNames(track: track, device: device))
        send(LiveCommand.deviceParameterMins(track: track, device: device))
        send(LiveCommand.deviceParameterMaxes(track: track, device: device))
        send(LiveCommand.deviceParameterValues(track: track, device: device))
    }

    // MARK: - Performer actions

    func fireClip(track: Int, scene: Int) {
        if state.isSimulated { demoFire(track: track, scene: scene); return }
        send(LiveCommand.fireClip(track: track, scene: scene))
    }

    func stopTrack(_ track: Int) {
        if state.isSimulated { update(track) { $0.playingSlotIndex = -1; $0.firedSlotIndex = -1 }; return }
        send(LiveCommand.trackStopAllClips(track: track))
    }

    func fireScene(_ scene: Int) {
        if state.isSimulated {
            for t in song.tracks where !t.isGroup && t.clips[scene] != nil { demoFire(track: t.index, scene: scene) }
            return
        }
        send(LiveCommand.fireScene(scene))
    }

    /// Fires one scene row on a subset of tracks (launch groups).
    func fireRow(scene: Int, tracks: [Int]) {
        for t in tracks {
            if song.clip(track: t, scene: scene) != nil { fireClip(track: t, scene: scene) }
            else { stopTrack(t) }
        }
    }

    func stopAll() {
        if state.isSimulated {
            for i in song.tracks.indices { song.tracks[i].playingSlotIndex = -1; song.tracks[i].firedSlotIndex = -1 }
            meters.clipPositions.removeAll()
            return
        }
        send(LiveCommand.stopAllClips())
    }

    func play() {
        if state.isSimulated { song.isPlaying = true; onTransport?(true); return }
        send(LiveCommand.startPlaying())
    }

    func stop() {
        if state.isSimulated { song.isPlaying = false; onTransport?(false); return }
        send(LiveCommand.stopPlaying())
    }

    func setTempo(_ bpm: Double) {
        let v = max(20, min(999, bpm))
        song.tempo = v
        if state.isSimulated { onTempo?(v); return }
        sendThrottled(key: "tempo", LiveCommand.setTempo(v))
    }

    func tapTempo() { send(LiveCommand.tapTempo()) }

    func setQuantization(_ q: LiveQuantization) {
        song.quantization = q
        send(LiveCommand.setQuantization(q))
    }

    func setVolume(track: Int, value: Double) {
        update(track) { $0.volume = value }
        sendThrottled(key: "vol\(track)", LiveCommand.setVolume(track: track, value: value))
    }

    func setPanning(track: Int, value: Double) {
        update(track) { $0.panning = value }
        sendThrottled(key: "pan\(track)", LiveCommand.setPanning(track: track, value: value))
    }

    func setSend(track: Int, send s: Int, value: Double) {
        update(track) { tr in
            while tr.sends.count <= s { tr.sends.append(0) }
            tr.sends[s] = value
        }
        sendThrottled(key: "send\(track):\(s)", LiveCommand.setSend(track: track, send: s, value: value))
    }

    func setMute(track: Int, on: Bool) {
        update(track) { $0.mute = on }
        send(LiveCommand.setMute(track: track, on: on))
    }

    func setSolo(track: Int, on: Bool) {
        update(track) { $0.solo = on }
        send(LiveCommand.setSolo(track: track, on: on))
    }

    func setArm(track: Int, on: Bool) {
        update(track) { $0.arm = on }
        send(LiveCommand.setArm(track: track, on: on))
    }

    func setMasterVolume(_ value: Double) {
        song.masterVolume = value
        sendThrottled(key: "master", LiveCommand.masterSet("volume", value: value))
    }

    func setCueVolume(_ value: Double) {
        song.cueVolume = value
        sendThrottled(key: "cue", LiveCommand.masterSet("cue_volume", value: value))
    }

    /// Sets a device parameter by normalized value 0...1. Works for tracks, the master and returns (pseudo indices).
    func setDeviceParameter(track: Int, device: Int, parameter: Int, normalized: Double) {
        guard device >= 0, parameter >= 0 else { return }
        updateDevices(track) { devices in
            guard device < devices.count, parameter < devices[device].parameters.count else { return }
            var p = devices[device].parameters[parameter]
            p.value = p.min + (p.max - p.min) * max(0, min(1, normalized))
            devices[device].parameters[parameter] = p
        }
        guard let p = song.devices(ofTrack: track)[safe: device]?.parameters[safe: parameter] else { return }
        sendThrottled(key: "dev\(track):\(device):\(parameter)", LiveCommand.setDeviceParameter(track: track, device: device, parameter: parameter, value: p.value))
    }

    // MARK: - Return tracks (StageDeck extension)

    func setReturnVolume(_ r: Int, value: Double) {
        updateReturn(r) { $0.volume = value }
        sendThrottled(key: "ret\(r)", LiveCommand.returnSet("volume", index: r, value: .float(Float(max(0, min(1, value))))))
    }

    func setReturnMute(_ r: Int, on: Bool) {
        updateReturn(r) { $0.mute = on }
        send(LiveCommand.returnSet("mute", index: r, value: .int32(on ? 1 : 0)))
    }

    func setReturnPanning(_ r: Int, value: Double) {
        updateReturn(r) { $0.panning = value }
        sendThrottled(key: "retpan\(r)", LiveCommand.returnSet("panning", index: r, value: .float(Float(max(-1, min(1, value))))))
    }

    func setReturnSend(_ r: Int, send s: Int, value: Double) {
        updateReturn(r) { rt in
            while rt.sends.count <= s { rt.sends.append(0) }
            rt.sends[s] = value
        }
        sendThrottled(key: "retsend\(r):\(s)", LiveCommand.returnSetSend(index: r, send: s, value: value))
    }

    /// Mutes/unmutes every track in a list (deck cut).
    func setMute(tracks: [Int], on: Bool) {
        for t in tracks { setMute(track: t, on: on) }
    }

    // MARK: - Writing clips (sequencer → Live)

    /// Creates (or clears) the MIDI clip at track/scene and fills it with the given notes.
    /// Returns a user-facing status line.
    @discardableResult
    func writeClip(track: Int, scene: Int, lengthBeats: Double, name: String, notes: [BouncedNote]) -> String {
        guard let t = song.track(track) else { return "Track \(track + 1) not found" }
        guard !t.isGroup else { return "\(t.name) is a group track" }
        guard t.hasMIDIInput else { return "\(t.name) is not a MIDI track" }
        if state.isSimulated {
            update(track) { tr in
                tr.clips[scene] = LiveClip(trackIndex: track, sceneIndex: scene, name: name, color: tr.color, length: lengthBeats, isMIDI: true)
            }
            return "Demo: \(notes.count) notes → \(t.name), scene \(scene + 1)"
        }
        guard state == .connected else { return "Not connected to Live" }
        let length = max(1, lengthBeats)
        if song.clip(track: track, scene: scene) != nil {
            send(LiveCommand.removeAllNotes(track: track, scene: scene))
            send(LiveCommand.clipSet("loop_start", track: track, scene: scene, value: .float(0)))
            send(LiveCommand.clipSet("loop_end", track: track, scene: scene, value: .float(Float(length))))
            send(LiveCommand.clipSet("end_marker", track: track, scene: scene, value: .float(Float(length))))
        } else {
            send(LiveCommand.createClip(track: track, scene: scene, lengthBeats: length))
        }
        for chunk in PatternBounce.oscChunks(notes) {
            send(LiveCommand.addNotes(track: track, scene: scene, args: chunk))
        }
        send(LiveCommand.clipSet("name", track: track, scene: scene, value: .string(name)))
        update(track) { tr in
            tr.clips[scene] = LiveClip(trackIndex: track, sceneIndex: scene, name: name, color: tr.color, length: length, isMIDI: true)
        }
        // Re-read the clip row shortly after so names/colours match Live.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            self?.send(LiveCommand.trackClipNames(track: track))
            self?.send(LiveCommand.trackClipColors(track: track))
            self?.send(LiveCommand.trackClipLengths(track: track))
        }
        return "\(notes.count) notes → \(t.name), scene \(scene + 1) (\(Int(length / 4)) bars)"
    }

    /// MIDI tracks that can receive a clip.
    var midiTracks: [LiveTrack] { song.tracks.filter { $0.hasMIDIInput && !$0.isGroup } }

    // MARK: - Demo mode (no Live needed)

    func enterDemo() {
        disconnect()
        state = .demo
        song = DemoSet.make()
        sections = SetLayout.sections(from: song.scenes)
        demoStart = Date()
        demoTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.demoTick() }
        }
        onSessionLoaded?()
        onTempo?(song.tempo)
    }

    /// Loads a set parsed from an .als file so every screen shows the real tracks without Live.
    func enterOffline(song offlineSong: LiveSongState) {
        disconnect()
        state = .offline
        song = offlineSong
        sections = SetLayout.sections(from: song.scenes)
        meters.trackMeters.removeAll()
        meters.clipPositions.removeAll()
        onSessionLoaded?()
        onTempo?(song.tempo)
    }

    private func stopDemo() {
        demoTimer?.invalidate()
        demoTimer = nil
    }

    private func demoFire(track: Int, scene: Int) {
        update(track) { tr in
            tr.firedSlotIndex = scene
        }
        song.isPlaying = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard let self else { return }
            self.update(track) { tr in
                if tr.firedSlotIndex == scene {
                    tr.firedSlotIndex = -1
                    tr.playingSlotIndex = tr.clips[scene] != nil ? scene : -1
                    self.meters.clipPositions["\(track):\(scene)"] = 0
                }
            }
        }
    }

    private func demoTick() {
        guard state == .demo else { return }
        let beatsPerSecond = song.tempo / 60
        if song.isPlaying {
            song.beat = Int(Date().timeIntervalSince(demoStart) * beatsPerSecond)
        }
        var maxMeter = 0.0
        for t in song.tracks {
            if t.playingSlotIndex >= 0, song.isPlaying, let clip = t.clips[t.playingSlotIndex], clip.length > 0 {
                let key = "\(t.index):\(t.playingSlotIndex)"
                var pos = (meters.clipPositions[key] ?? 0) + 0.1 * beatsPerSecond
                if pos >= clip.length { pos -= clip.length }
                meters.clipPositions[key] = pos
                let m = min(1, 0.3 + 0.5 * abs(sin(pos * 3)) + Double.random(in: 0...0.2))
                meters.trackMeters[t.index] = m
                maxMeter = max(maxMeter, m)
            } else {
                meters.trackMeters[t.index] = max(0, (meters.trackMeters[t.index] ?? 0) - 0.08)
            }
        }
        meters.masterMeter = maxMeter
    }
}


