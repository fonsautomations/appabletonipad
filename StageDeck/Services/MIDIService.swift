import Foundation
import CoreMIDI
import Combine

/// A CoreMIDI endpoint (destination or source) as shown in Settings.
struct MIDIEndpointInfo: Identifiable, Hashable {
    let id: Int32 // kMIDIPropertyUniqueID
    let name: String
    let isNetwork: Bool
    let isBluetooth: Bool
    let isVirtual: Bool
}

/// Host-time helpers (mach_absolute_time ↔ seconds).
enum HostTime {
    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    static var now: UInt64 { mach_absolute_time() }

    static var nowSeconds: Double { seconds(fromHostTicks: mach_absolute_time()) }

    static func seconds(fromHostTicks ticks: UInt64) -> Double {
        Double(ticks) * Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000.0
    }

    static func hostTicks(fromSeconds seconds: Double) -> UInt64 {
        guard seconds > 0 else { return 0 }
        return UInt64(seconds * 1_000_000_000.0 * Double(timebase.denom) / Double(timebase.numer))
    }
}

/// Owns the CoreMIDI client: enumerates destinations/sources, sends timestamped messages
/// (USB, Bluetooth MIDI, Network/RTP-MIDI, IDAM and our own virtual port) and parses input.
final class MIDIService: ObservableObject, @unchecked Sendable {
    @Published private(set) var destinations: [MIDIEndpointInfo] = []
    @Published private(set) var sources: [MIDIEndpointInfo] = []
    /// Unique IDs of destinations the sequencer sends to. Empty → only the virtual source.
    @Published var enabledDestinationIDs: Set<Int32> = [] {
        didSet { rebuildDestinationCache() }
    }
    /// Unique IDs of sources we listen to (for external MIDI clock).
    @Published var enabledSourceIDs: Set<Int32> = [] {
        didSet { reconnectSources() }
    }
    @Published var networkSessionEnabled: Bool = true {
        didSet { configureNetworkSession() }
    }
    @Published private(set) var lastSentDescription: String = ""
    @Published private(set) var inputActivity: Int = 0
    /// Per-destination timing offset in milliseconds (negative = send earlier, e.g. -20 for Bluetooth MIDI).
    @Published var portOffsetsMs: [Int32: Double] = [:] {
        didSet { rebuildOffsetCache() }
    }
    private var offsetTicksByRef: [MIDIEndpointRef: Int64] = [:]

    /// Called on the MIDI thread for every incoming message.
    var onMessage: (@Sendable (MIDIMessage, UInt64) -> Void)?

    private var client = MIDIClientRef()
    private var outputPort = MIDIPortRef()
    private var inputPort = MIDIPortRef()
    private var virtualSource = MIDIEndpointRef()
    private var virtualDestination = MIDIEndpointRef()
    private var destinationRefs: [Int32: MIDIEndpointRef] = [:]
    private var activeDestinationRefs: [MIDIEndpointRef] = []
    private var connectedSources: [MIDIEndpointRef] = []
    private let lock = NSLock()
    private var sendCounter = 0

    init() {
        setup()
    }

    private func setup() {
        let status = MIDIClientCreateWithBlock("StageDeck" as CFString, &client) { [weak self] _ in
            DispatchQueue.main.async { self?.refreshEndpoints() }
        }
        guard status == noErr else { return }
        MIDIOutputPortCreate(client, "StageDeck Out" as CFString, &outputPort)
        MIDIInputPortCreateWithProtocol(client, "StageDeck In" as CFString, ._1_0, &inputPort) { [weak self] eventList, _ in
            self?.handle(eventList: eventList)
        }
        MIDISourceCreateWithProtocol(client, "StageDeck" as CFString, ._1_0, &virtualSource)
        MIDIDestinationCreateWithProtocol(client, "StageDeck" as CFString, ._1_0, &virtualDestination) { [weak self] eventList, _ in
            self?.handle(eventList: eventList)
        }
        configureNetworkSession()
        refreshEndpoints()
    }

    private func configureNetworkSession() {
        let session = MIDINetworkSession.default()
        session.isEnabled = networkSessionEnabled
        session.connectionPolicy = networkSessionEnabled ? .anyone : .noOne
    }

    /// Re-reads the list of destinations and sources (called when devices appear/disappear).
    func refreshEndpoints() {
        var dests: [MIDIEndpointInfo] = []
        var refs: [Int32: MIDIEndpointRef] = [:]
        for i in 0..<MIDIGetNumberOfDestinations() {
            let ref = MIDIGetDestination(i)
            guard ref != 0, ref != virtualDestination else { continue }
            let info = endpointInfo(ref)
            if info.name == "StageDeck" { continue } // our own virtual destination
            dests.append(info)
            refs[info.id] = ref
        }
        var srcs: [MIDIEndpointInfo] = []
        for i in 0..<MIDIGetNumberOfSources() {
            let ref = MIDIGetSource(i)
            guard ref != 0, ref != virtualSource else { continue }
            let info = endpointInfo(ref)
            if info.name == "StageDeck" { continue }
            srcs.append(info)
        }
        lock.lock()
        destinationRefs = refs
        lock.unlock()
        destinations = dests
        sources = srcs
        rebuildDestinationCache()
        reconnectSources()
    }

    private func endpointInfo(_ ref: MIDIEndpointRef) -> MIDIEndpointInfo {
        var uid: Int32 = 0
        MIDIObjectGetIntegerProperty(ref, kMIDIPropertyUniqueID, &uid)
        var nameRef: Unmanaged<CFString>?
        var name = "MIDI \(uid)"
        if MIDIObjectGetStringProperty(ref, kMIDIPropertyDisplayName, &nameRef) == noErr, let cf = nameRef?.takeRetainedValue() {
            name = cf as String
        }
        var driverRef: Unmanaged<CFString>?
        var driver = ""
        if MIDIObjectGetStringProperty(ref, kMIDIPropertyDriverOwner, &driverRef) == noErr, let cf = driverRef?.takeRetainedValue() {
            driver = cf as String
        }
        let lower = (name + " " + driver).lowercased()
        return MIDIEndpointInfo(id: uid, name: name,
                                isNetwork: lower.contains("network") || lower.contains("rtp"),
                                isBluetooth: lower.contains("bluetooth") || lower.contains("widi") || lower.contains("ble"),
                                isVirtual: lower.contains("idam") || lower.contains("virtual"))
    }

    private func rebuildDestinationCache() {
        lock.lock()
        activeDestinationRefs = enabledDestinationIDs.compactMap { destinationRefs[$0] }
        lock.unlock()
        rebuildOffsetCache()
    }

    private func rebuildOffsetCache() {
        lock.lock()
        var map: [MIDIEndpointRef: Int64] = [:]
        for (uid, ms) in portOffsetsMs {
            if let ref = destinationRefs[uid], abs(ms) > 0.01 {
                let ticks = HostTime.hostTicks(fromSeconds: abs(ms) / 1000.0)
                map[ref] = ms < 0 ? -Int64(ticks) : Int64(ticks)
            }
        }
        offsetTicksByRef = map
        lock.unlock()
    }

    /// Applies a destination's latency offset to a timestamp (0 = "now" stays 0).
    private func shifted(_ ts: UInt64, by offset: Int64) -> UInt64 {
        guard ts != 0, offset != 0 else { return ts }
        let v = Int64(bitPattern: ts) &+ offset
        return v > 0 ? UInt64(v) : 1
    }

    private func reconnectSources() {
        for ref in connectedSources { MIDIPortDisconnectSource(inputPort, ref) }
        connectedSources.removeAll()
        for i in 0..<MIDIGetNumberOfSources() {
            let ref = MIDIGetSource(i)
            var uid: Int32 = 0
            MIDIObjectGetIntegerProperty(ref, kMIDIPropertyUniqueID, &uid)
            if enabledSourceIDs.contains(uid) {
                if MIDIPortConnectSource(inputPort, ref, nil) == noErr { connectedSources.append(ref) }
            }
        }
    }

    // MARK: - Sending

    /// Sends a message now.
    func send(_ message: MIDIMessage, to port: MIDIPortID = .all) {
        send([(message, HostTime.now)], to: port)
    }

    /// Sends messages with absolute host-time timestamps (0 = now).
    func send(_ messages: [(MIDIMessage, UInt64)], to port: MIDIPortID = .all) {
        guard !messages.isEmpty else { return }
        lock.lock()
        let targets = activeDestinationRefs
        let offsets = offsetTicksByRef
        lock.unlock()
        let specific: MIDIEndpointRef? = {
            if port == .all { return nil }
            guard let uid = Int32(port.rawValue) else { return nil }
            lock.lock(); defer { lock.unlock() }
            return destinationRefs[uid]
        }()
        let words: [(UInt64, UInt32)] = messages.compactMap { m, ts in MIDIService.umpWord(for: m).map { (ts, $0) } }
        guard !words.isEmpty else { return }
        let destinations: [MIDIEndpointRef] = specific.map { [$0] } ?? targets
        for dest in destinations {
            sendWords(words, to: dest, offset: offsets[dest] ?? 0)
        }
        sendWords(words, to: nil, offset: 0) // virtual source for other apps / IDAM
        sendCounter += 1
        if sendCounter % 32 == 0, let last = messages.last {
            let text = last.0.description
            DispatchQueue.main.async { [weak self] in self?.lastSentDescription = text }
        }
    }

    /// Builds one event list (ascending timestamps, offset applied) and sends it to a destination,
    /// or publishes it on the virtual source when `dest` is nil.
    private func sendWords(_ words: [(UInt64, UInt32)], to dest: MIDIEndpointRef?, offset: Int64) {
        var groups: [(UInt64, [UInt32])] = []
        for (ts, word) in words {
            let stamped = shifted(ts, by: offset)
            if let last = groups.last, last.0 == stamped, last.1.count < 60 {
                groups[groups.count - 1].1.append(word)
            } else {
                groups.append((stamped, [word]))
            }
        }
        let bufferSize = 4096
        let raw = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: MemoryLayout<MIDIEventList>.alignment)
        defer { raw.deallocate() }
        let listPtr = raw.bindMemory(to: MIDIEventList.self, capacity: 1)
        var packet = MIDIEventListInit(listPtr, ._1_0)
        var added = 0
        for (ts, ws) in groups {
            var w = ws
            let next = MIDIEventListAdd(listPtr, bufferSize, packet, ts, w.count, &w)
            if let p = next as UnsafeMutablePointer<MIDIEventPacket>? {
                packet = p
                added += 1
            } else {
                break
            }
        }
        guard added > 0 else { return }
        if let dest {
            MIDISendEventList(outputPort, dest, listPtr)
        } else {
            MIDIReceivedEventList(virtualSource, listPtr)
        }
    }

    /// Universal MIDI Packet (MIDI 1.0 protocol) word for a classic message.
    static func umpWord(for message: MIDIMessage) -> UInt32? {
        let bytes = message.bytes
        guard let status = bytes.first else { return nil }
        let d1 = UInt32(bytes.count > 1 ? bytes[1] : 0)
        let d2 = UInt32(bytes.count > 2 ? bytes[2] : 0)
        if status >= 0xF0 {
            // System common / realtime → message type 1
            return 0x1000_0000 | (UInt32(status) << 16) | (d1 << 8) | d2
        }
        // Channel voice → message type 2
        return 0x2000_0000 | (UInt32(status) << 16) | (d1 << 8) | d2
    }

    // MARK: - Receiving

    private func handle(eventList: UnsafePointer<MIDIEventList>) {
        var count = 0
        for packet in eventList.unsafeSequence() {
            let timestamp = packet.pointee.timeStamp
            let wordCount = Int(packet.pointee.wordCount)
            // `words` is a fixed 64-element tuple; read the first `wordCount` entries.
            let words: [UInt32] = withUnsafeBytes(of: packet.pointee.words) { raw in
                Array(raw.bindMemory(to: UInt32.self).prefix(min(64, wordCount)))
            }
            for word in words {
                let type = (word >> 28) & 0xF
                guard type == 1 || type == 2 else { continue }
                let status = UInt8((word >> 16) & 0xFF)
                let d1 = UInt8((word >> 8) & 0x7F)
                let d2 = UInt8(word & 0x7F)
                let bytes: [UInt8]
                switch status & 0xF0 {
                case 0xC0, 0xD0: bytes = [status, d1]
                default:
                    if status >= 0xF8 { bytes = [status] } else { bytes = [status, d1, d2] }
                }
                if let m = MIDIMessage.parse(bytes) {
                    onMessage?(m, timestamp)
                    if !m.isRealtime { count += 1 }
                }
            }
        }
        if count > 0 {
            DispatchQueue.main.async { [weak self] in self?.inputActivity += count }
        }
    }

    /// Sends note-off for everything on all channels (panic).
    func panic() {
        var msgs: [(MIDIMessage, UInt64)] = []
        for ch in 0..<16 {
            msgs.append((.controlChange(channel: UInt8(ch), controller: 123, value: 0), 0))
            msgs.append((.controlChange(channel: UInt8(ch), controller: 120, value: 0), 0))
        }
        send(msgs)
    }
}
