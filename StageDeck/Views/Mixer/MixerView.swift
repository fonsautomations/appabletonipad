import SwiftUI

/// Stem mixer. Everything stays on screen: sections (decks, buses) are packed into rows that fit the
/// width, strips adapt to the row height, and the master column is always visible on the right.
/// Tap a deck tab to see it alone at full size.
struct MixerView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var live: LiveSession
    @State private var editing = false
    @State private var showAddBus = false
    /// -1 = all sections; otherwise an index into `sections`.
    @State private var focus: Int = -1

    enum Section: Equatable { case deck(Int), buses }

    private var sections: [Section] {
        var out: [Section] = store.decks.indices.map { .deck($0) }
        if !store.profile.mixerBuses.isEmpty || editing { out.append(.buses) }
        return out
    }

    private func stripCount(_ section: Section) -> Int {
        switch section {
        case .deck(let i):
            let deck = store.decks[i]
            let group = store.profile.showGroupStrips && deck.groupTrackName != nil ? 1 : 0
            return deck.resolveTracks(in: live.song).count + group
        case .buses:
            return max(1, store.profile.mixerBuses.count)
        }
    }

    private var sendCount: Int { store.profile.showSends ? store.profile.sendIndices(in: live.song).count : 0 }

    var body: some View {
        let sections = self.sections
        let focusIndex: Int? = (focus >= 0 && focus < sections.count) ? focus : nil
        VStack(spacing: 6) {
            header(sections: sections)
            HStack(alignment: .top, spacing: 10) {
                GeometryReader { geo in
                    let plan = MixerLayoutPlan.plan(width: geo.size.width, height: geo.size.height,
                                                    counts: sections.map { stripCount($0) }, sends: sendCount,
                                                    showPan: store.profile.showPan, focus: focusIndex)
                    VStack(spacing: MixerLayoutPlan.rowGap) {
                        ForEach(Array(plan.rows.enumerated()), id: \.offset) { (_, row) in
                            let overflowing = row.contains(where: { plan.overflowingSections.contains($0) })
                            Group {
                                if overflowing {
                                    ScrollView(.horizontal, showsIndicators: false) { rowView(row, sections: sections, plan: plan) }
                                } else {
                                    rowView(row, sections: sections, plan: plan)
                                }
                            }
                            .frame(height: plan.rowHeight, alignment: .top)
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                }
                MasterColumn()
                    .frame(width: 186)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
        .sheet(isPresented: $showAddBus) { AddBusSheet().environmentObject(store).environmentObject(live) }
        .onChange(of: sections.count) { n in if focus >= n { focus = -1 } }
    }

    private func rowView(_ row: [Int], sections: [Section], plan: MixerLayoutPlan) -> some View {
        HStack(alignment: .top, spacing: MixerLayoutPlan.sectionGap) {
            ForEach(row, id: \.self) { s in
                switch sections[s] {
                case .deck(let i):
                    DeckMixer(deck: store.decks[i], deckIndex: i, metrics: plan.metrics)
                case .buses:
                    BusesSection(editing: editing, metrics: plan.metrics, onAdd: { showAddBus = true })
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func header(sections: [Section]) -> some View {
        HStack(spacing: 8) {
            if editing {
                CapsLabel("SENDS", size: 9)
                if live.song.returnTracks.isEmpty {
                    Text("no return tracks in this set").font(.system(size: 10)).foregroundColor(Theme.textSecondary)
                }
                ForEach(live.song.returnTracks) { r in
                    let on = store.profile.sendIndices(in: live.song).contains(r.index)
                    PadButton(title: r.name, color: Color(r.color), active: on, height: 30, fontSize: 10) { toggleSend(r.index) }
                        .frame(width: 76)
                }
                Spacer()
                PadButton(title: "GROUP STRIPS", color: Theme.secondary, active: store.profile.showGroupStrips, height: 30, fontSize: 10) {
                    store.profile.showGroupStrips.toggle()
                }.frame(width: 110)
                PadButton(title: "MASTER FILTER", color: Theme.green, active: store.profile.showMasterFilter, height: 30, fontSize: 10) {
                    store.profile.showMasterFilter.toggle()
                }.frame(width: 110)
                PadButton(title: "+ BUS", color: Theme.accent, active: true, height: 30, fontSize: 10) { showAddBus = true }.frame(width: 70)
            } else {
                let options: [(Int, String)] = [(-1, "ALL")] + sections.enumerated().map { (i, s) in
                    switch s {
                    case .deck(let d): return (i, store.decks[d].name)
                    case .buses: return (i, "BUSES")
                    }
                }
                Segmented(options: options, selection: $focus, height: 30)
                    .frame(width: CGFloat(options.count) * 86)
                Spacer()
                Text(mixerSummary).font(.system(size: 10)).foregroundColor(Theme.textSecondary).lineLimit(1)
            }
            PadButton(title: editing ? "DONE" : "EDIT", color: Theme.yellow, active: editing, height: 30, fontSize: 11) { editing.toggle() }.frame(width: 70)
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
    }

    private var mixerSummary: String {
        let sends = store.profile.sendIndices(in: live.song).count
        let buses = store.profile.mixerBuses.count
        return "\(sends) send\(sends == 1 ? "" : "s")" + (buses > 0 ? " · \(buses) bus\(buses == 1 ? "" : "es")" : "") + (store.profile.showGroupStrips ? " · group strips" : "")
    }

    private func toggleSend(_ index: Int) {
        let names = live.song.returnTrackNames
        guard index < names.count else { return }
        var current = store.profile.sendIndices(in: live.song)
        if current.contains(index) { current.removeAll(where: { $0 == index }) } else { current.append(index) }
        store.profile.visibleSends = current.sorted().map { names[$0] }
    }
}

/// Always-visible master section: filter (if the master has an Auto Filter), master fader with meter, cue.
struct MasterColumn: View {
    @EnvironmentObject var live: LiveSession
    @EnvironmentObject var store: AppStore

    var body: some View {
        VStack(spacing: 6) {
            CapsLabel("MASTER", size: 9).frame(height: MixerLayoutPlan.sectionHeaderHeight - 6)
            HStack(alignment: .bottom, spacing: 8) {
                if store.profile.showMasterFilter, live.song.masterAutoFilter != nil {
                    VStack(spacing: 4) {
                        FilterFader(trackIndex: LiveSongState.masterTrackIndex, filter: live.song.masterAutoFilter, color: Theme.green)
                            .frame(width: 48).frame(maxHeight: .infinity)
                        CapsLabel("Filter", size: 8)
                    }
                }
                VStack(spacing: 4) {
                    Text(LiveVolume.label(fader: live.song.masterVolume))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundColor(Theme.textSecondary)
                    MasterFaderView(meters: live.meters)
                        .frame(width: 64).frame(maxHeight: .infinity)
                    CapsLabel("Master", size: 8)
                }
                VStack(spacing: 4) {
                    Text(LiveVolume.label(fader: live.song.cueVolume))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundColor(Theme.textSecondary)
                    VerticalFader(value: Binding(get: { live.song.cueVolume }, set: { live.setCueVolume($0) }), color: Theme.yellow, meter: nil, label: nil)
                        .frame(width: 44).frame(maxHeight: .infinity)
                    CapsLabel("Cue", size: 8)
                }
            }
        }
        .padding(8)
        .frame(maxHeight: .infinity)
        .background(Theme.panel)
        .cornerRadius(10)
    }
}

struct DeckMixer: View {
    let deck: DeckDefinition
    let deckIndex: Int
    let metrics: MixerLayoutPlan.Metrics
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var live: LiveSession

    private var tracks: [LiveTrack] { deck.resolveTracks(in: live.song) }
    private var color: Color { Color(hex: deck.colorHex) }
    private var groupTrack: LiveTrack? {
        guard let g = deck.groupTrackName else { return nil }
        return live.song.tracks.first(where: { $0.isGroup && $0.name.caseInsensitiveCompare(g) == .orderedSame })
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                let muted = !tracks.isEmpty && tracks.allSatisfy { $0.mute }
                PadButton(title: deck.name, color: color, active: !muted, height: 34, fontSize: 15) {
                    live.setMute(tracks: tracks.map { $0.index }, on: !muted)
                }
                .frame(width: min(120, max(70, metrics.stripWidth * 1.6)))
                if let g = groupTrack {
                    DeckFilterControl(track: g, label: "HPF", color: color)
                        .frame(width: min(160, max(90, metrics.stripWidth * 2)), height: 34)
                }
                Spacer(minLength: 0)
            }
            .frame(height: MixerLayoutPlan.sectionHeaderHeight - 6)
            HStack(alignment: .top, spacing: MixerLayoutPlan.stripGap) {
                if store.profile.showGroupStrips, let g = groupTrack {
                    ChannelStrip(track: g, deckColor: color, metrics: metrics, isGroupStrip: true)
                }
                ForEach(tracks) { track in
                    ChannelStrip(track: track, deckColor: color, metrics: metrics)
                }
            }
        }
    }
}

/// Filter macro for a whole deck (its group track's Auto Filter).
struct DeckFilterControl: View {
    let track: LiveTrack
    let label: String
    let color: Color
    @EnvironmentObject var live: LiveSession

    var body: some View {
        if let filter = track.autoFilter, let f = filter.parameterIndex(named: "Frequency") {
            let param = filter.parameters[f]
            HorizontalSlider(value: Binding(get: { param.normalized }, set: { v in
                live.setDeviceParameter(track: track.index, device: filter.index, parameter: f, normalized: v)
            }), color: color, label: label)
        } else {
            Text("Add an Auto Filter to '\(track.name)'")
                .font(.system(size: 9)).foregroundColor(Theme.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.panelRaised).cornerRadius(6)
                .onAppear {
                    if let d = track.autoFilter { live.requestDeviceParameters(track: track.index, device: d.index) }
                }
        }
    }
}

// MARK: - Generic strip

/// Everything a strip needs to draw and act, whatever the channel behind it (track, group, return or master).
struct StripModel {
    var name: String
    var color: Color
    var volume: Double
    var mute: Bool
    var solo: Bool? = nil
    var arm: Bool? = nil
    var panning: Double = 0
    var sends: [Double] = []
    /// Pseudo track index used to address devices (track index, `masterTrackIndex` or a return pseudo index).
    var deviceTrackIndex: Int
    var autoFilter: LiveDevice? = nil
    /// Reads the live meter of this channel (observed by the strip so it animates).
    var meter: (LiveMeters) -> Double? = { _ in nil }
    var setVolume: (Double) -> Void
    var setMute: (Bool) -> Void
    var setSolo: ((Bool) -> Void)? = nil
    var setArm: ((Bool) -> Void)? = nil
    var setPanning: (Double) -> Void = { _ in }
    var setSend: (Int, Double) -> Void = { _, _ in }
}

struct StripOptions {
    var sendIndices: [Int] = []
    var showFilter = true
    var showPan = false
    var nameBackground: Color? = nil
}

/// The strip body shared by stems, group strips, buses and returns. Sizes come from the layout plan.
struct StripBody: View {
    let model: StripModel
    let options: StripOptions
    let metrics: MixerLayoutPlan.Metrics
    @ObservedObject var meters: LiveMeters
    var onNameLongPress: (() -> Void)? = nil
    @EnvironmentObject var live: LiveSession
    @EnvironmentObject var store: AppStore

    private var w: CGFloat { CGFloat(metrics.stripWidth) }
    private var gap: CGFloat { metrics.density == .full ? 5 : 4 }

    var body: some View {
        VStack(spacing: gap) {
            Text(model.name)
                .font(.system(size: 10 * metrics.fontScale, weight: .bold, design: .rounded))
                .foregroundColor(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 2)
                .frame(width: w, height: 22)
                .background(options.nameBackground ?? Theme.panelRaised)
                .cornerRadius(6)
                .onLongPressGesture(minimumDuration: 0.5) { onNameLongPress?() }

            if metrics.showSends {
                ForEach(options.sendIndices, id: \.self) { s in
                    let name = live.song.returnTrackNames[safe: s] ?? "S\(s + 1)"
                    SendBar(value: model.sends[safe: s] ?? 0, name: name, color: model.color, height: CGFloat(metrics.sendHeight)) { model.setSend(s, $0) }
                        .frame(width: w, height: CGFloat(metrics.sendHeight))
                }
            }

            if options.showFilter && metrics.showFilter {
                FilterFader(trackIndex: model.deviceTrackIndex, filter: model.autoFilter, color: model.color)
                    .frame(width: w, height: CGFloat(metrics.filterHeight))
            }

            if metrics.showDB {
                Text(LiveVolume.label(fader: model.volume))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(Theme.textSecondary)
                    .frame(width: w, height: 16)
                    .background(Theme.panelRaised)
                    .cornerRadius(4)
            }

            VerticalFader(value: Binding(get: { model.volume }, set: { model.setVolume($0) }), color: model.color, meter: model.meter(meters),
                          label: metrics.showDB ? nil : LiveVolume.label(fader: model.volume))
                .frame(width: w, height: CGFloat(metrics.faderHeight))

            if options.showPan && metrics.density == .full {
                HorizontalSlider(value: Binding(get: { (model.panning + 1) / 2 }, set: { model.setPanning($0 * 2 - 1) }),
                                 color: Theme.textSecondary, label: panLabel)
                    .frame(width: w, height: 18)
            }

            HStack(spacing: 3) {
                PadButton(title: "M", color: Theme.red, active: model.mute, height: 28, fontSize: 11) { model.setMute(!model.mute) }
                if metrics.density != .compact, let solo = model.solo, let setSolo = model.setSolo {
                    PadButton(title: "CUE", color: Theme.yellow, active: solo, height: 28, fontSize: 9) { setSolo(!solo) }
                }
            }
            .frame(width: w)
            if metrics.density == .full, let arm = model.arm, let setArm = model.setArm {
                PadButton(title: "ARM", color: Theme.red, active: arm, height: 24, fontSize: 9) { setArm(!arm) }
                    .frame(width: w)
            }
        }
        .frame(width: w)
    }

    private var panLabel: String {
        let p = model.panning
        if abs(p) < 0.02 { return "C" }
        return p < 0 ? "\(Int(abs(p) * 50))L" : "\(Int(p * 50))R"
    }
}

/// A Live track (stem or group) as a strip.
struct ChannelStrip: View {
    let track: LiveTrack
    let deckColor: Color
    let metrics: MixerLayoutPlan.Metrics
    var isGroupStrip = false
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var live: LiveSession
    @State private var renameRequest: RenameRequest? = nil

    var body: some View {
        StripBody(model: MixerChannels.model(track: track, live: live, store: store),
                  options: StripOptions(sendIndices: store.profile.showSends ? store.profile.sendIndices(in: live.song) : [],
                                        showFilter: true, showPan: store.profile.showPan,
                                        nameBackground: isGroupStrip ? deckColor.opacity(0.45) : nil),
                  metrics: metrics,
                  meters: live.meters,
                  onNameLongPress: { Haptics.heavy(); renameRequest = RenameRequest(liveName: track.name) })
            .sheet(item: $renameRequest) { r in RenameTrackSheet(liveName: r.liveName).environmentObject(store) }
    }
}

/// Builds strip models for every kind of channel.
@MainActor
enum MixerChannels {
    static func model(track: LiveTrack, live: LiveSession, store: AppStore) -> StripModel {
        StripModel(name: store.profile.displayName(forTrack: track.name), color: Color(track.color), volume: track.volume, mute: track.mute,
                   solo: track.solo, arm: track.canBeArmed && track.hasMIDIInput ? track.arm : nil, panning: track.panning, sends: track.sends,
                   deviceTrackIndex: track.index, autoFilter: track.autoFilter, meter: { $0.trackMeters[track.index] ?? 0 },
                   setVolume: { live.setVolume(track: track.index, value: $0) },
                   setMute: { live.setMute(track: track.index, on: $0) },
                   setSolo: { live.setSolo(track: track.index, on: $0) },
                   setArm: { live.setArm(track: track.index, on: $0) },
                   setPanning: { live.setPanning(track: track.index, value: $0) },
                   setSend: { live.setSend(track: track.index, send: $0, value: $1) })
    }

    static func model(returnTrack r: LiveReturnTrack, live: LiveSession) -> StripModel {
        StripModel(name: r.name, color: Color(r.color), volume: r.volume, mute: r.mute, solo: nil, arm: nil, panning: r.panning, sends: r.sends,
                   deviceTrackIndex: LiveSongState.trackIndex(forReturn: r.index), autoFilter: r.autoFilter, meter: { _ in nil },
                   setVolume: { live.setReturnVolume(r.index, value: $0) },
                   setMute: { live.setReturnMute(r.index, on: $0) },
                   setPanning: { live.setReturnPanning(r.index, value: $0) },
                   setSend: { live.setReturnSend(r.index, send: $0, value: $1) })
    }

    static func master(live: LiveSession) -> StripModel {
        StripModel(name: "MASTER", color: Theme.green, volume: live.song.masterVolume, mute: false, solo: nil, arm: nil, panning: 0, sends: [],
                   deviceTrackIndex: LiveSongState.masterTrackIndex, autoFilter: live.song.masterAutoFilter, meter: { $0.masterMeter },
                   setVolume: { live.setMasterVolume($0) },
                   setMute: { _ in })
    }

    /// Resolves a bus to its model; nil when the named channel is not in the current set.
    static func model(bus: MixerBus, live: LiveSession, store: AppStore) -> StripModel? {
        switch bus.kind {
        case .master:
            var m = master(live: live); m.name = bus.displayName; return m
        case .returnTrack:
            guard let r = live.song.returnTracks.first(where: { $0.name.caseInsensitiveCompare(bus.name) == .orderedSame }) else { return nil }
            var m = model(returnTrack: r, live: live); m.name = bus.displayName; return m
        case .group, .track:
            guard let t = live.song.tracks.first(where: { $0.name.caseInsensitiveCompare(bus.name) == .orderedSame }) else { return nil }
            var m = model(track: t, live: live, store: store)
            if let l = bus.label, !l.isEmpty { m.name = l }
            return m
        }
    }
}

/// Fader-shaped meter of one send, named after its return track.
struct SendBar: View {
    let value: Double
    let name: String
    let color: Color
    var height: CGFloat = 34
    let onChange: (Double) -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 6).fill(color.opacity(0.18))
            RoundedRectangle(cornerRadius: 6).fill(color.opacity(0.8))
                .frame(height: max(3, height * CGFloat(value)))
            Text(name)
                .font(.system(size: 8, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.textPrimary)
                .lineLimit(1)
                .padding(.bottom, height < 24 ? 1 : 3)
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { g in
            onChange(max(0, min(1, 1 - Double(g.location.y / height))))
        })
        .onTapGesture(count: 2) { onChange(0) }
    }
}

/// Low-pass macro bound to a channel's Auto Filter (track, group, return or master).
struct FilterFader: View {
    let trackIndex: Int
    let filter: LiveDevice?
    let color: Color
    @EnvironmentObject var live: LiveSession
    @EnvironmentObject var store: AppStore

    var body: some View {
        if let filter, let f = filter.parameterIndex(named: store.profile.filterParameterName) {
            let param = filter.parameters[f]
            VerticalFader(value: Binding(get: { param.normalized }, set: { v in
                live.setDeviceParameter(track: trackIndex, device: filter.index, parameter: f, normalized: v)
            }), color: color.opacity(0.9), meter: nil, label: store.profile.macroNames.first ?? "LPF")
        } else {
            VStack(spacing: 4) {
                Image(systemName: "slider.vertical.3").foregroundColor(Theme.textSecondary.opacity(0.5))
                Text("no filter").font(.system(size: 8)).foregroundColor(Theme.textSecondary.opacity(0.6))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.panel)
            .cornerRadius(6)
            .onAppear {
                if let d = filter { live.requestDeviceParameters(track: trackIndex, device: d.index) }
            }
        }
    }
}

// MARK: - Buses

/// Editable extra strips: groups, returns, master or single tracks, in the order the performer wants.
struct BusesSection: View {
    let editing: Bool
    let metrics: MixerLayoutPlan.Metrics
    let onAdd: () -> Void
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var live: LiveSession
    @State private var editingBus: MixerBus? = nil

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                CapsLabel("BUSES", size: 9)
                if editing {
                    PadButton(title: "+ BUS", color: Theme.accent, active: true, height: 30, fontSize: 10) { onAdd() }.frame(width: 70)
                }
                Spacer(minLength: 0)
            }
            .frame(height: MixerLayoutPlan.sectionHeaderHeight - 6)
            HStack(alignment: .top, spacing: MixerLayoutPlan.stripGap) {
                ForEach(store.profile.mixerBuses) { bus in
                    BusStrip(bus: bus, editing: editing, metrics: metrics, onEdit: { editingBus = bus })
                }
                if store.profile.mixerBuses.isEmpty {
                    Text("Add a group, a return, the master or any track as its own strip.")
                        .font(.system(size: 10, design: .rounded)).foregroundColor(Theme.textSecondary)
                        .frame(width: 120)
                }
            }
        }
        .sheet(item: $editingBus) { bus in
            BusEditor(bus: bus).environmentObject(store).environmentObject(live)
        }
    }
}

struct BusStrip: View {
    let bus: MixerBus
    let editing: Bool
    let metrics: MixerLayoutPlan.Metrics
    let onEdit: () -> Void
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var live: LiveSession

    var body: some View {
        let w = CGFloat(metrics.stripWidth)
        var m = metrics
        if editing { m.faderHeight = max(60, m.faderHeight - 28) } // room for the EDIT / × toolbar
        return VStack(spacing: 4) {
            if editing {
                HStack(spacing: 3) {
                    PadButton(title: "EDIT", color: Theme.yellow, active: true, height: 24, fontSize: 9) { onEdit() }
                    PadButton(title: "×", color: Theme.red, active: false, height: 24, fontSize: 12) { remove() }.frame(width: 24)
                }
                .frame(width: w)
            }
            if let model = MixerChannels.model(bus: bus, live: live, store: store) {
                StripBody(model: model,
                          options: StripOptions(sendIndices: bus.showSends && store.profile.showSends ? store.profile.sendIndices(in: live.song) : [],
                                                showFilter: bus.showFilter, showPan: bus.showPan,
                                                nameBackground: nameBackground(model.color)),
                          metrics: m,
                          meters: live.meters,
                          onNameLongPress: { Haptics.heavy(); onEdit() })
            } else {
                VStack(spacing: 6) {
                    Text(bus.displayName).font(.system(size: 10, weight: .bold, design: .rounded)).foregroundColor(Theme.yellow).lineLimit(1)
                        .frame(width: w, height: 22).background(Theme.panelRaised).cornerRadius(6)
                    Text("\(bus.kind.label.lowercased()) not in this set")
                        .font(.system(size: 9, design: .rounded)).foregroundColor(Theme.yellow).multilineTextAlignment(.center)
                        .frame(width: w, height: 60)
                }
            }
        }
    }

    private func nameBackground(_ color: Color) -> Color? {
        switch bus.kind {
        case .group: return color.opacity(0.45)
        case .returnTrack: return color.opacity(0.3)
        case .master: return Theme.green.opacity(0.35)
        case .track: return nil
        }
    }

    private func remove() {
        store.profile.mixerBuses.removeAll(where: { $0.id == bus.id })
    }
}

/// Options of one bus strip.
struct BusEditor: View {
    let bus: MixerBus
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var live: LiveSession
    @Environment(\.dismiss) private var dismiss
    @State private var label = ""
    @State private var showSends = true
    @State private var showFilter = true
    @State private var showPan = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Bus") {
                    HStack { Text("Channel"); Spacer(); Text(bus.kind == .master ? "Master" : "\(bus.kind.label) · \(bus.name)").foregroundColor(.secondary) }
                    TextField("Label (optional)", text: $label)
                }
                Section("Shows") {
                    Toggle("Sends", isOn: $showSends).disabled(bus.kind == .master)
                    Toggle("Filter (Auto Filter on this channel)", isOn: $showFilter)
                    Toggle("Pan", isOn: $showPan).disabled(bus.kind == .master)
                    if bus.kind == .master {
                        Text("Live's master has no sends. Put an Auto Filter (or a rack) on the master to get a master filter here.")
                            .font(.footnote).foregroundColor(.secondary)
                    }
                }
                Section("Order") {
                    HStack {
                        Button("Move left") { move(-1) }.disabled(index <= 0)
                        Spacer()
                        Button("Move right") { move(1) }.disabled(index < 0 || index >= store.profile.mixerBuses.count - 1)
                    }
                }
                Section {
                    Button("Remove bus", role: .destructive) {
                        store.profile.mixerBuses.removeAll(where: { $0.id == bus.id }); dismiss()
                    }
                }
            }
            .navigationTitle("Edit bus")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save(); dismiss() } }
            }
        }
        .onAppear { label = bus.label ?? ""; showSends = bus.showSends; showFilter = bus.showFilter; showPan = bus.showPan }
    }

    private var index: Int { store.profile.mixerBuses.firstIndex(where: { $0.id == bus.id }) ?? -1 }

    private func move(_ d: Int) {
        let i = index; let j = i + d
        guard i >= 0, j >= 0, j < store.profile.mixerBuses.count else { return }
        store.profile.mixerBuses.swapAt(i, j)
    }

    private func save() {
        guard let i = store.profile.mixerBuses.firstIndex(where: { $0.id == bus.id }) else { return }
        store.profile.mixerBuses[i].label = label.trimmingCharacters(in: .whitespaces).isEmpty ? nil : label
        store.profile.mixerBuses[i].showSends = showSends
        store.profile.mixerBuses[i].showFilter = showFilter
        store.profile.mixerBuses[i].showPan = showPan
    }
}

/// Pick what to add as a bus: a group, a return, the master or any track of the set.
struct AddBusSheet: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var live: LiveSession
    @Environment(\.dismiss) private var dismiss
    @State private var filter = ""

    private var deckTrackNames: Set<String> {
        Set(store.decks.flatMap { $0.resolveTracks(in: live.song).map { $0.name.lowercased() } })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Filter by name", text: $filter)
                    row(kind: .master, name: "", title: "Master", subtitle: live.song.masterAutoFilter != nil ? "fader + Auto Filter" : "fader (no Auto Filter on master)", color: Theme.green)
                }
                Section("Groups") {
                    ForEach(matching(live.song.groupTracks)) { t in
                        row(kind: .group, name: t.name, title: t.name, subtitle: "\(live.song.members(ofGroup: t.index).count) tracks · sends + filter + fader", color: Color(t.color))
                    }
                    if live.song.groupTracks.isEmpty { Text("No group tracks in this set.").foregroundColor(.secondary) }
                }
                Section("Return tracks") {
                    ForEach(live.song.returnTracks.filter { filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter) }) { r in
                        row(kind: .returnTrack, name: r.name, title: r.name, subtitle: "return · volume, sends to other returns" + (r.autoFilter != nil ? ", filter" : ""), color: Color(r.color))
                    }
                    if live.song.returnTracks.isEmpty { Text("No return tracks in this set.").foregroundColor(.secondary) }
                }
                Section("Other tracks") {
                    ForEach(matching(live.song.tracks.filter { !$0.isGroup })) { t in
                        row(kind: .track, name: t.name, title: store.profile.displayName(forTrack: t.name),
                            subtitle: deckTrackNames.contains(t.name.lowercased()) ? "already in a deck" : "track", color: Color(t.color))
                    }
                }
            }
            .navigationTitle("Add bus")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func matching(_ tracks: [LiveTrack]) -> [LiveTrack] {
        filter.isEmpty ? tracks : tracks.filter { $0.name.localizedCaseInsensitiveContains(filter) }
    }

    private func isAdded(kind: MixerBus.Kind, name: String) -> Bool {
        store.profile.mixerBuses.contains(where: { $0.kind == kind && (kind == .master || $0.name.caseInsensitiveCompare(name) == .orderedSame) })
    }

    private func row(kind: MixerBus.Kind, name: String, title: String, subtitle: String, color: Color) -> some View {
        let added = isAdded(kind: kind, name: name)
        return Button(action: {
            Haptics.tap()
            if added { store.profile.mixerBuses.removeAll(where: { $0.kind == kind && (kind == .master || $0.name.caseInsensitiveCompare(name) == .orderedSame) }) }
            else { store.profile.mixerBuses.append(MixerBus(kind: kind, name: name)) }
        }) {
            HStack {
                RoundedRectangle(cornerRadius: 4).fill(color).frame(width: 12, height: 12)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundColor(.primary)
                    Text(subtitle).font(.footnote).foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: added ? "checkmark.circle.fill" : "plus.circle").foregroundColor(added ? .green : .secondary)
            }
        }
    }
}

// MARK: - Master

struct MasterFaderView: View {
    @ObservedObject var meters: LiveMeters
    @EnvironmentObject var live: LiveSession

    var body: some View {
        VerticalFader(value: Binding(get: { live.song.masterVolume }, set: { live.setMasterVolume($0) }),
                      color: Theme.green, meter: meters.masterMeter, label: nil)
    }
}
