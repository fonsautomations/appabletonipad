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
    @Published var controlDual: Bool = false
    @Published var selectedDeckIndex: Int = 0
    @Published var showSettings = false
    @Published var pendingTemplate: PendingTemplate? = nil
    @Published var pendingAbletonSet: PendingAbletonSet? = nil
    @Published var importBusy: String = ""
    @Published var lastImportSummary: String = ""

    let live = LiveSession()
    let midi = MIDIService()
    let sequencer: SequencerRuntime
    let control: ControlRuntime
    let library = TemplateLibrary()

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

        // MIDI hardware choices live in the profile so they survive relaunches.
        midi.enabledDestinationIDs = Set(profile.midiEnabledDestinations.compactMap { Int32($0) })
        midi.enabledSourceIDs = Set(profile.midiEnabledSources.compactMap { Int32($0) })
        midi.portOffsetsMs = Dictionary(uniqueKeysWithValues: profile.midiPortOffsetsMs.compactMap { k, v in Int32(k).map { ($0, v) } })
        midi.networkSessionEnabled = profile.midiNetworkSession
        midi.$enabledDestinationIDs.dropFirst().sink { [weak self] ids in
            guard let self else { return }
            let list = ids.map { String($0) }.sorted()
            if list != self.profile.midiEnabledDestinations { self.profile.midiEnabledDestinations = list }
        }.store(in: &cancellables)
        midi.$enabledSourceIDs.dropFirst().sink { [weak self] ids in
            guard let self else { return }
            let list = ids.map { String($0) }.sorted()
            if list != self.profile.midiEnabledSources { self.profile.midiEnabledSources = list }
        }.store(in: &cancellables)
        midi.$portOffsetsMs.dropFirst().sink { [weak self] offsets in
            guard let self else { return }
            let map = Dictionary(uniqueKeysWithValues: offsets.map { (String($0.key), $0.value) })
            if map != self.profile.midiPortOffsetsMs { self.profile.midiPortOffsetsMs = map }
        }.store(in: &cancellables)
        midi.$networkSessionEnabled.dropFirst().sink { [weak self] on in
            guard let self else { return }
            if on != self.profile.midiNetworkSession { self.profile.midiNetworkSession = on }
        }.store(in: &cancellables)

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

    // MARK: Channel names

    func setAlias(_ alias: String, forTrack liveName: String) {
        let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == liveName { profile.trackAliases.removeValue(forKey: liveName) } else { profile.trackAliases[liveName] = trimmed }
    }

    // MARK: Templates

    /// Reads an Ableton Live Set in the background and presents the import sheet.
    func openAbletonSet(url: URL) {
        importBusy = "Reading \(url.lastPathComponent)…"
        Task.detached(priority: .userInitiated) { [weak self] in
            #if canImport(Darwin)
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            #endif
            let result: Result<AbletonSetSnapshot, Error> = Result { try AbletonSetImport.load(url: url) }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.importBusy = ""
                switch result {
                case .success(let snap):
                    self.pendingAbletonSet = PendingAbletonSet(snapshot: snap, fileName: url.lastPathComponent)
                    self.showSettings = false
                case .failure(let e):
                    self.lastImportSummary = "Live Set: \((e as? CustomStringConvertible)?.description ?? e.localizedDescription)"
                }
            }
        }
    }

    /// Reads a .stagedeck / .json file (Files, AirDrop, share sheet). Returns an error message or nil.
    @discardableResult
    func openTemplate(url: URL) -> String? {
        if url.pathExtension.lowercased() == "als" {
            openAbletonSet(url: url)
            return nil
        }
        #if canImport(Darwin)
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        #endif
        do {
            let data = try Data(contentsOf: url)
            let t = try StageDeckTemplate.parse(data)
            pendingTemplate = PendingTemplate(template: t, source: url.lastPathComponent)
            showSettings = false
            return nil
        } catch let e as StageDeckTemplate.ParseError {
            return e.description
        } catch {
            return "Could not read \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    func importTemplate(_ t: StageDeckTemplate, mode: TemplateImportMode) {
        var p = profile
        var project = sequencer.project
        TemplateImporter.apply(t, mode: mode, to: &p, project: &project)
        profile = p
        if project != sequencer.project { sequencer.project = project }
        control.seed(from: profile.controlPages)
        if selectedDeckIndex >= decks.count { selectedDeckIndex = 0 }
        lastImportSummary = "Imported \"\(t.name)\": " + t.contents.joined(separator: "; ")
        saveNow()
    }

    func makeTemplate(name: String, author: String, description: String, sections: TemplateSections) -> StageDeckTemplate {
        TemplateExporter.make(name: name.isEmpty ? "StageDeck template" : name, author: author.isEmpty ? nil : author,
                              description: description.isEmpty ? nil : description, sections: sections,
                              profile: profile, project: sequencer.project, song: live.song)
    }

    /// Writes the template to a temporary .stagedeck file for the share sheet.
    func exportTemplateFile(name: String, author: String, description: String, sections: TemplateSections) -> URL? {
        let t = makeTemplate(name: name, author: author, description: description, sections: sections)
        guard let data = try? t.encodeJSON() else { return nil }
        let safe = t.name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safe).\(StageDeckTemplate.fileExtension)")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
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
