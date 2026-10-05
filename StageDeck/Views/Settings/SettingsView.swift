import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var live: LiveSession
    @EnvironmentObject var midi: MIDIService
    @EnvironmentObject var sequencer: SequencerRuntime
    @Environment(\.dismiss) private var dismiss
    @State private var showBluetooth = false
    @State private var showAdvertise = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Undo / redo last change")
                        Spacer()
                        Button("Undo") { store.undo() }.disabled(!store.canUndo)
                        Button("Redo") { store.redo() }.disabled(!store.canRedo).padding(.leading, 12)
                    }
                }
                Group {
                    connectionSection
                    TemplatesSection()
                    SetCheckSection()
                    ChannelNamesSection()
                    midiSection
                }
                Group {
                    launcherSection
                    sizesSection
                    mixerSection
                    decksSection
                    groupsSection
                }
                Group {
                    safetySection
                    sequencerSection
                    aboutSection
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: $showBluetooth) { BluetoothMIDICentralView() }
            .sheet(isPresented: $showAdvertise) { BluetoothMIDIPeripheralView() }
        }
    }

    // MARK: Sections

    private var connectionSection: some View {
        Section("Ableton Live (AbletonOSC)") {
            HStack {
                Text("Status")
                Spacer()
                Text(live.state.label + (live.liveHost.isEmpty ? "" : " · \(live.liveHost)")).foregroundColor(.secondary)
            }
            TextField("Mac IP (empty = find automatically)", text: $store.profile.liveHost)
                .keyboardType(.decimalPad)
                .autocorrectionDisabled()
            HStack {
                Text("Port"); Spacer()
                TextField("11000", value: $store.profile.livePort, format: .number).multilineTextAlignment(.trailing).frame(width: 80)
            }
            HStack {
                Text("Reply port"); Spacer()
                TextField("11001", value: $store.profile.replyPort, format: .number).multilineTextAlignment(.trailing).frame(width: 80)
            }
            Toggle("Reconnect automatically", isOn: $store.profile.autoReconnect)
            Toggle("Live meters (more network traffic)", isOn: $store.profile.meterRefreshEnabled)
            HStack {
                Button("Connect") { store.connect() }
                Spacer()
                Button("Reload set") { live.reloadSession() }.disabled(live.state != .connected)
                Spacer()
                Button("Demo mode") { live.enterDemo() }
                Spacer()
                Button("Disconnect", role: .destructive) { live.disconnect() }
            }
            Text("iPad: " + OSCClient.localIPAddresses().joined(separator: ", "))
                .font(.footnote).foregroundColor(.secondary)
            if !live.listenerError.isEmpty { Text(live.listenerError).font(.footnote).foregroundColor(.red) }
            Text("Messages received: \(live.messagesReceived)").font(.footnote).foregroundColor(.secondary)
        }
    }

    private var midiSection: some View {
        Section("MIDI (sequencer output, clock)") {
            Group {
            Toggle("Network MIDI session (Wi‑Fi / Ethernet to the Mac)", isOn: $midi.networkSessionEnabled)
            HStack {
                Button("Bluetooth MIDI devices…") { showBluetooth = true }
                Spacer()
                Button("Advertise this iPad…") { showAdvertise = true }
            }
            Button("Rescan ports") { midi.refreshEndpoints() }
            if midi.destinations.isEmpty {
                Text("No MIDI outputs yet. Connect a USB interface, pair Bluetooth MIDI, or create a network session in Audio MIDI Setup on the Mac. The virtual port “StageDeck” is always available to other apps and IDAM.")
                    .font(.footnote).foregroundColor(.secondary)
            }
            ForEach(midi.destinations) { d in
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(isOn: Binding(get: { midi.enabledDestinationIDs.contains(d.id) }, set: { on in
                        if on { midi.enabledDestinationIDs.insert(d.id) } else { midi.enabledDestinationIDs.remove(d.id) }
                    })) {
                        HStack {
                            Image(systemName: d.isBluetooth ? "wave.3.right" : (d.isNetwork ? "network" : "cable.connector"))
                            Text(d.name)
                        }
                    }
                    if midi.enabledDestinationIDs.contains(d.id) {
                        HStack {
                            Text("Timing offset").font(.footnote).foregroundColor(.secondary)
                            Spacer()
                            Stepper("\(Int(midi.portOffsetsMs[d.id] ?? 0)) ms", value: Binding(get: { midi.portOffsetsMs[d.id] ?? 0 },
                                                                                         set: { midi.portOffsetsMs[d.id] = $0 }), in: -50...50, step: 1)
                                .font(.footnote)
                                .frame(width: 170)
                        }
                    }
                }
            }
            Text("Negative offset sends earlier to compensate a slow link (Bluetooth MIDI is typically 10–20 ms late).").font(.footnote).foregroundColor(.secondary)
            }
            Group {
            if !midi.sources.isEmpty {
                Text("Clock input (sync the sequencer to external MIDI clock)").font(.footnote).foregroundColor(.secondary)
                ForEach(midi.sources) { s in
                    Toggle(isOn: Binding(get: { midi.enabledSourceIDs.contains(s.id) }, set: { on in
                        if on { midi.enabledSourceIDs.insert(s.id) } else { midi.enabledSourceIDs.remove(s.id) }
                    })) {
                        Text("In: \(s.name)")
                    }
                }
            }
            Toggle("Send MIDI clock from the sequencer", isOn: $store.profile.sequencerSendsClock)
            Toggle("Send MIDI Start/Stop with the clock", isOn: $sequencer.project.sendTransport)
            Picker("Clock goes to", selection: $sequencer.project.clockPort) {
                Text("All enabled outputs").tag(MIDIPortID.all)
                ForEach(midi.destinations) { d in Text(d.name).tag(MIDIPortID(String(d.id))) }
            }
            Button("MIDI panic (all notes off)", role: .destructive) { sequencer.panic() }
            }
        }
    }

    private var launcherSection: some View {
        Section("Launcher layout") {
            Toggle("Show section bar", isOn: $store.profile.showSections)
            Toggle("Show scene buttons", isOn: $store.profile.showSceneButtons)
            Toggle("Show stop row", isOn: $store.profile.showStopButtons)
            Toggle("Show CUE row", isOn: $store.profile.showCueButtons)
            Toggle("Show track meters", isOn: $store.profile.showTrackMeters)
            Toggle("Show clip progress", isOn: $store.profile.showClipProgress)
            Toggle("Show clip notes", isOn: $store.profile.showClipNotes)
            Toggle("Dim stopped clips", isOn: $store.profile.dimStoppedClips)
            Toggle("Hide scenes without clips in the deck", isOn: $store.profile.hideEmptyScenes)
            Toggle("Follow playing scene", isOn: $store.profile.followPlayingScene)
        }
    }

    private var sizesSection: some View {
        Section("Text and sizes") {
            Toggle("Big text mode", isOn: $store.profile.bigTextMode)
            HStack {
                Text("Clip height"); Slider(value: $store.profile.clipHeight, in: 36...110, step: 2); Text("\(Int(store.profile.clipHeight))").frame(width: 32)
            }
            HStack {
                Text("Clip font"); Slider(value: $store.profile.clipFontSize, in: 9...20, step: 1); Text("\(Int(store.profile.clipFontSize))").frame(width: 32)
            }
        }
    }

    private var mixerSection: some View {
        Section("Mixer") {
            Toggle("Show sends", isOn: $store.profile.showSends)
            Toggle("Show pan", isOn: $store.profile.showPan)
            Toggle("Fit everything on screen (off = full-size strips, scroll sideways)", isOn: $store.profile.mixerFitToScreen)
            Toggle("Group strips (each deck's group as a full strip)", isOn: $store.profile.showGroupStrips)
            Toggle("Master filter (Auto Filter on the master)", isOn: $store.profile.showMasterFilter)
            HStack {
                Text("Filter parameter name"); Spacer()
                TextField("Frequency", text: $store.profile.filterParameterName).multilineTextAlignment(.trailing).frame(width: 140)
            }
            Text("Put an Auto Filter on any channel you want to filter: tracks, group tracks, returns or the master. StageDeck finds it by class name and drives its Frequency parameter. Which sends are shown, and extra bus strips (groups, returns, master, single tracks), are edited in the mixer with EDIT.")
                .font(.footnote).foregroundColor(.secondary)
        }
    }

    private var decksSection: some View {
        Section("Decks") {
            Text("A deck is a set of tracks shown together. By default one deck per Live group track. Tracks are matched by name.")
                .font(.footnote).foregroundColor(.secondary)
            ForEach(Array(store.profile.decks.enumerated()), id: \.element.id) { (i, deck) in
                NavigationLink {
                    DeckEditor(deck: Binding(get: { store.profile.decks[safe: i] ?? deck }, set: { v in if i < store.profile.decks.count { store.profile.decks[i] = v } }))
                } label: {
                    HStack {
                        RoundedRectangle(cornerRadius: 4).fill(Color(hex: deck.colorHex)).frame(width: 16, height: 16)
                        Text(deck.name)
                        Spacer()
                        Text(deck.groupTrackName.map { "group \($0)" } ?? "\(deck.trackNames.count) tracks").foregroundColor(.secondary)
                    }
                }
            }
            .onDelete { idx in store.profile.decks.remove(atOffsets: idx) }
            HStack {
                Button("Add deck") { store.profile.decks.append(DeckDefinition(name: "Deck \(store.profile.decks.count + 1)")) }
                Spacer()
                Button("Reset to Live groups") { store.profile.decks = DeckDefinition.automatic(from: live.song) }
            }
        }
    }

    private var groupsSection: some View {
        Section("Launch groups (K / R buttons)") {
            Text("A launch group fires one scene row only on the listed tracks: build a drop without hunting for clips.")
                .font(.footnote).foregroundColor(.secondary)
            ForEach(Array(store.profile.launchGroups.enumerated()), id: \.element.id) { (i, g) in
                NavigationLink {
                    LaunchGroupEditor(group: Binding(get: { store.profile.launchGroups[safe: i] ?? g }, set: { v in if i < store.profile.launchGroups.count { store.profile.launchGroups[i] = v } }))
                } label: {
                    HStack {
                        RoundedRectangle(cornerRadius: 4).fill(Color(hex: g.colorHex)).frame(width: 16, height: 16)
                        Text(g.label)
                        Spacer()
                        Text(g.trackNames.joined(separator: ", ")).foregroundColor(.secondary).lineLimit(1)
                    }
                }
            }
            .onDelete { idx in store.profile.launchGroups.remove(atOffsets: idx) }
            Button("Add group") { store.profile.launchGroups.append(LaunchGroup(label: "G\(store.profile.launchGroups.count + 1)", trackNames: [])) }
        }
    }

    private var safetySection: some View {
        Section("Stage safety") {
            Toggle("Performance lock (no tempo changes, no stop-all)", isOn: $store.profile.performanceLock)
            Toggle("Confirm STOP ALL", isOn: $store.profile.confirmStopAll)
            Toggle("Confirm scene launch", isOn: $store.profile.confirmSceneLaunch)
            Toggle("Clips need a long press to launch", isOn: $store.profile.clipTapRequiresLongPress)
            Toggle("Haptic feedback", isOn: $store.profile.hapticsEnabled)
        }
    }

    private var sequencerSection: some View {
        Section("Sequencer") {
            Toggle("Follow Live transport (play/stop)", isOn: $store.profile.sequencerFollowsLiveTransport)
            Toggle("Take tempo from Live", isOn: $store.profile.sequencerSyncsTempoFromLive)
            HStack {
                Text("Keyboard octave"); Spacer()
                Stepper("\(store.profile.keyboardOctave)", value: $store.profile.keyboardOctave, in: -1...7).frame(width: 140)
            }
            HStack {
                Text("Project name"); Spacer()
                TextField("Project", text: $sequencer.project.name).multilineTextAlignment(.trailing).frame(width: 180)
            }
            Button("Save now") { store.saveNow() }
        }
    }

    private var aboutSection: some View {
        Section("About") {
            Text("StageDeck — clip launcher, stem mixer and step sequencer for Ableton Live on iPad. Live side: AbletonOSC remote script (MIT) with the StageDeck master/returns extension; see ableton/README.md in the project.")
                .font(.footnote).foregroundColor(.secondary)
            Text("Live \(live.song.liveVersion.isEmpty ? "—" : live.song.liveVersion) · \(live.song.tracks.count) tracks · \(live.song.scenes.count) scenes")
                .font(.footnote).foregroundColor(.secondary)
        }
    }
}

struct DeckEditor: View {
    @Binding var deck: DeckDefinition
    @EnvironmentObject var live: LiveSession

    var body: some View {
        Form {
            Section("Deck") {
                TextField("Name", text: $deck.name)
                TextField("Colour (hex)", text: $deck.colorHex)
                Picker("Mirror a Live group", selection: Binding(get: { deck.groupTrackName ?? "" }, set: { deck.groupTrackName = $0.isEmpty ? nil : $0 })) {
                    Text("None (pick tracks)").tag("")
                    ForEach(live.song.groupTracks) { g in Text(g.name).tag(g.name) }
                }
            }
            if deck.groupTrackName == nil {
                Section("Tracks in this deck") {
                    ForEach(live.song.launchableTracks) { t in
                        Toggle(t.name, isOn: Binding(get: { deck.trackNames.contains(where: { $0.caseInsensitiveCompare(t.name) == .orderedSame }) },
                                                     set: { on in
                            if on { deck.trackNames.append(t.name) } else { deck.trackNames.removeAll(where: { $0.caseInsensitiveCompare(t.name) == .orderedSame }) }
                        }))
                    }
                }
            }
        }
        .navigationTitle(deck.name)
    }
}

struct LaunchGroupEditor: View {
    @Binding var group: LaunchGroup
    @EnvironmentObject var live: LiveSession

    var body: some View {
        Form {
            Section("Group") {
                TextField("Label (short)", text: $group.label)
                TextField("Colour (hex)", text: $group.colorHex)
            }
            Section("Tracks (by name, in any deck)") {
                ForEach(uniqueTrackNames, id: \.self) { name in
                    Toggle(name, isOn: Binding(get: { group.trackNames.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) },
                                               set: { on in
                        if on { group.trackNames.append(name) } else { group.trackNames.removeAll(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) }
                    }))
                }
            }
        }
        .navigationTitle(group.label)
    }

    private var uniqueTrackNames: [String] {
        var seen: Set<String> = []
        var out: [String] = []
        for t in live.song.launchableTracks where !seen.contains(t.name.lowercased()) {
            seen.insert(t.name.lowercased())
            out.append(t.name)
        }
        return out
    }
}
