import Foundation
import Combine
import SwiftUI

/// Root object: wires the Live session, the sequencer and persistence together.
@MainActor
final class AppStore: ObservableObject {
    @Published var profile: PerformerProfile {
        didSet { scheduleSave(); applyProfile() }
    }
    @Published var activeTab: AppTab = .launcher
    @Published var launcherMode: LauncherMode = .dual
    @Published var selectedDeckIndex: Int = 0
    @Published var showSettings = false

    let live = LiveSession()
    let midi = MIDIService()
    let sequencer: SequencerRuntime
    let control: ControlRuntime

    private var saveTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []
    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return dir.appendingPathComponent("stagedeck.json")
    }()

    enum AppTab: String, CaseIterable, Identifiable {
        case launcher = "LAUNCH"
        case mixer = "MIXER"
        case control = "CTRL"
        case sequencer = "SEQ"
        var id: String { rawValue }
    }

    enum LauncherMode: String, CaseIterable, Identifiable {
        case single = "INDIV."
        case dual = "DUAL"
        var id: String { rawValue }
    }

    init() {
        var document = AppDocument()
        if let data = try? Data(contentsOf: fileURL), let loaded = try? AppDocument.decodeJSON(data) {
            document = loaded
        }
        profile = document.profile
        sequencer = SequencerRuntime(project: document.project, midi: midi)
        control = ControlRuntime(live: live, midi: midi)

        sequencer.$project
            .dropFirst()
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.scheduleSave() }
            .store(in: &cancellables)

        live.onSessionLoaded = { [weak self] in
            self?.sessionLoaded()
        }
        live.onTempo = { [weak self] bpm in
            guard let self, self.profile.sequencerSyncsTempoFromLive else { return }
            self.sequencer.setTempo(bpm)
        }
        live.onTransport = { [weak self] playing in
            guard let self, self.profile.sequencerFollowsLiveTransport, self.sequencer.syncMode == .internalClock else { return }
            if playing && !self.sequencer.isRunning { self.sequencer.play() }
            if !playing && self.sequencer.isRunning { self.sequencer.stop() }
        }
        applyProfile()
    }

    private func applyProfile() {
        live.configure(host: profile.liveHost, port: profile.livePort, replyPort: profile.replyPort, autoReconnect: profile.autoReconnect)
        live.meterRefreshEnabled = profile.meterRefreshEnabled
        if sequencer.project.sendMIDIClock != profile.sequencerSendsClock {
            sequencer.project.sendMIDIClock = profile.sequencerSendsClock
        }
    }

    func connect() { live.connect() }

    private func sessionLoaded() {
        if profile.decks.isEmpty || profile.decks.allSatisfy({ $0.resolveTracks(in: live.song).isEmpty }) {
            profile.decks = DeckDefinition.automatic(from: live.song)
        }
        if profile.launchGroups.isEmpty {
            let names = live.song.launchableTracks.map { $0.name }
            let kicks = names.filter { n in ["kick", "bass", "lo", "sub", "k"].contains(where: { n.lowercased().contains($0) }) }
            if !kicks.isEmpty {
                let rest = names.filter { !kicks.contains($0) }
                profile.launchGroups = [LaunchGroup(label: "K", trackNames: Array(Set(kicks)), colorHex: "#F28C28"),
                                        LaunchGroup(label: "R", trackNames: Array(Set(rest)), colorHex: "#C8762A")]
            }
        }
        if selectedDeckIndex >= profile.decks.count { selectedDeckIndex = 0 }
    }

    // MARK: Persistence

    private func scheduleSave() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.saveNow() }
        }
    }

    func saveNow() {
        var doc = AppDocument()
        doc.profile = profile
        doc.project = sequencer.project
        do {
            let data = try doc.encodeJSON()
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Saving is best-effort; the UI keeps working from memory.
        }
    }

    // MARK: Derived helpers

    var decks: [DeckDefinition] {
        profile.decks.isEmpty ? DeckDefinition.automatic(from: live.song) : profile.decks
    }

    func tracks(forDeck index: Int) -> [LiveTrack] {
        let d = decks
        guard !d.isEmpty else { return live.song.launchableTracks }
        return d[min(max(0, index), d.count - 1)].resolveTracks(in: live.song)
    }

    func accentColor(forDeck index: Int) -> Color {
        let d = decks
        guard !d.isEmpty else { return Color(hex: profile.accentHex) }
        return Color(hex: d[min(max(0, index), d.count - 1)].colorHex)
    }
}

extension Color {
    init(hex: String) {
        let c = hex.liveColorFromHex ?? LiveColor.gray
        self.init(red: c.red, green: c.green, blue: c.blue)
    }

    init(_ live: LiveColor) {
        self.init(red: live.red, green: live.green, blue: live.blue)
    }
}
