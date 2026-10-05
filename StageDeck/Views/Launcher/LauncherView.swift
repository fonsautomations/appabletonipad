import SwiftUI

/// Session-view clip launcher: one or two decks side by side.
struct LauncherView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var live: LiveSession
    @State private var deckForPanel: [Int] = [0, 1]

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Segmented(options: AppStore.LauncherMode.allCases.map { ($0, $0.rawValue) }, selection: $store.launcherMode, height: 30)
                    .frame(width: 150)
                Spacer()
                if store.profile.performanceLock {
                    CapsLabel("Performance lock", size: 9, color: Theme.yellow)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)

            if store.launcherMode == .dual && store.decks.count > 1 {
                HStack(spacing: 8) {
                    DeckPanel(panel: 0, deckIndex: binding(for: 0), compact: true)
                    Divider().background(Theme.line)
                    DeckPanel(panel: 1, deckIndex: binding(for: 1), compact: true)
                }
                .padding(.horizontal, 8)
            } else {
                DeckPanel(panel: 0, deckIndex: binding(for: 0), compact: false)
                    .padding(.horizontal, 8)
            }
        }
        .onAppear {
            if store.decks.count > 1 { deckForPanel = [0, 1] }
        }
    }

    private func binding(for panel: Int) -> Binding<Int> {
        Binding(get: {
            let d = deckForPanel.indices.contains(panel) ? deckForPanel[panel] : 0
            return min(d, max(0, store.decks.count - 1))
        }, set: { v in
            while deckForPanel.count <= panel { deckForPanel.append(0) }
            deckForPanel[panel] = v
        })
    }
}

/// One deck: deck tabs, section bar, header, clip grid, stop/cue rows.
struct DeckPanel: View {
    let panel: Int
    @Binding var deckIndex: Int
    let compact: Bool
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var live: LiveSession
    @State private var noteEditorClip: LiveClip? = nil
    @State private var sceneToConfirm: Int? = nil
    @State private var renameRequest: RenameRequest? = nil

    private var tracks: [LiveTrack] { store.tracks(forDeck: deckIndex) }
    private var deckColor: Color { store.accentColor(forDeck: deckIndex) }
    private var groups: [LaunchGroup] { store.profile.launchGroups }
    private var scenes: [LiveScene] {
        if store.profile.hideEmptyScenes {
            let ts = tracks
            return live.song.scenes.filter { s in ts.contains(where: { $0.clips[s.index] != nil }) }
        }
        return live.song.scenes
    }

    var body: some View {
        VStack(spacing: 4) {
            deckTabs
            if store.profile.showSections { SectionBar(deckColor: deckColor, scenes: scenes, onJump: { scrollTarget = $0 }) }
            GeometryReader { geo in
                let layout = GridLayout(width: geo.size.width, tracks: tracks.count, groups: groups.count,
                                        sceneColumn: store.profile.showSceneButtons, profile: store.profile, compact: compact)
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(spacing: 3) {
                        HeaderRow(tracks: tracks, layout: layout, deckColor: deckColor, onRename: { renameRequest = RenameRequest(liveName: $0) })
                        ScrollViewReader { proxy in
                            ScrollView(.vertical, showsIndicators: true) {
                                LazyVStack(spacing: 3) {
                                    ForEach(scenes) { scene in
                                        SceneRow(scene: scene, tracks: tracks, groups: groups, layout: layout, deckColor: deckColor,
                                                 onEditNote: { noteEditorClip = $0 }, onConfirmScene: { sceneToConfirm = $0 })
                                            .id(scene.index)
                                    }
                                }
                            }
                            .onChange(of: scrollTarget) { target in
                                if let t = target {
                                    withAnimation { proxy.scrollTo(t, anchor: .top) }
                                    scrollTarget = nil
                                }
                            }
                            .onChange(of: playingSceneSignature) { _ in
                                guard store.profile.followPlayingScene, let s = lastFiredScene else { return }
                                withAnimation { proxy.scrollTo(s, anchor: .center) }
                            }
                        }
                        if store.profile.showStopButtons { StopRow(tracks: tracks, layout: layout) }
                        if store.profile.showCueButtons { CueRow(tracks: tracks, layout: layout) }
                    }
                    .frame(minWidth: geo.size.width, alignment: .leading)
                }
            }
        }
        .sheet(item: $renameRequest) { r in
            RenameTrackSheet(liveName: r.liveName).environmentObject(store)
        }
        .sheet(item: $noteEditorClip) { clip in
            ClipNoteEditor(clip: clip, trackName: live.song.track(clip.trackIndex)?.name ?? "")
                .environmentObject(store)
        }
        .confirmationDialog("Launch scene?", isPresented: Binding(get: { sceneToConfirm != nil }, set: { if !$0 { sceneToConfirm = nil } }), titleVisibility: .visible) {
            Button("Launch \(sceneToConfirm.map { live.song.scenes[safe: $0]?.name ?? "" } ?? "")") {
                if let s = sceneToConfirm { fireScene(s) }
                sceneToConfirm = nil
            }
            Button("Cancel", role: .cancel) { sceneToConfirm = nil }
        }
    }

    @State private var scrollTarget: Int? = nil

    private var playingSceneSignature: String {
        tracks.map { "\($0.playingSlotIndex)" }.joined(separator: ",")
    }

    private var lastFiredScene: Int? {
        tracks.compactMap { $0.playingSceneIndex }.max()
    }

    private func fireScene(_ scene: Int) {
        Haptics.launch()
        if store.decks.count > 1 {
            live.fireRow(scene: scene, tracks: tracks.map { $0.index })
        } else {
            live.fireScene(scene)
        }
    }

    private var deckTabs: some View {
        HStack(spacing: 4) {
            ForEach(Array(store.decks.enumerated()), id: \.offset) { (i, deck) in
                PadButton(title: deck.name, color: Color(hex: deck.colorHex), active: i == deckIndex, height: 30, fontSize: 12) {
                    deckIndex = i
                }
                .frame(maxWidth: 140)
            }
            Spacer()
            if store.decks.count > 1 {
                let trackIndices = tracks.map { $0.index }
                let muted = !tracks.isEmpty && tracks.allSatisfy { $0.mute }
                PadButton(title: muted ? "DECK MUTED" : "CUT DECK", color: Theme.red, active: muted, height: 30, fontSize: 10) {
                    live.setMute(tracks: trackIndices, on: !muted)
                }
                .frame(width: 110)
            }
        }
    }
}

/// Column sizing shared by header, rows and footers.
struct GridLayout {
    let sceneWidth: CGFloat
    let groupWidth: CGFloat
    let clipWidth: CGFloat
    let rowHeight: CGFloat
    let fontSize: CGFloat
    let sceneColumn: Bool
    let spacing: CGFloat = 3

    init(width: CGFloat, tracks: Int, groups: Int, sceneColumn: Bool, profile: PerformerProfile, compact: Bool) {
        self.sceneColumn = sceneColumn
        let sceneW: CGFloat = sceneColumn ? (compact ? 48 : 72) : 0
        let groupW: CGFloat = compact ? 34 : 44
        sceneWidth = sceneW
        groupWidth = groupW
        let gapCount: CGFloat = CGFloat(groups + (sceneColumn ? 1 : 0))
        let fixed: CGFloat = sceneW + CGFloat(groups) * groupW + gapCount * 3
        let trackGaps: CGFloat = CGFloat(max(0, tracks - 1)) * 3
        let available: CGFloat = width - fixed - trackGaps
        let natural: CGFloat = tracks > 0 ? available / CGFloat(tracks) : 80
        let minW: CGFloat = compact ? 44 : 56
        let maxW: CGFloat = compact ? 110 : 160
        clipWidth = max(minW, min(maxW, natural))
        let baseHeight: CGFloat = CGFloat(profile.clipHeight)
        let bigFactor: CGFloat = profile.bigTextMode ? 1.3 : 1
        let compactFactor: CGFloat = compact ? 1 : 1.15
        rowHeight = baseHeight * bigFactor * compactFactor
        let baseFont: CGFloat = CGFloat(profile.clipFontSize)
        fontSize = baseFont * (profile.bigTextMode ? 1.4 : 1)
    }
}

struct HeaderRow: View {
    let tracks: [LiveTrack]
    let layout: GridLayout
    let deckColor: Color
    let onRename: (String) -> Void
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var live: LiveSession

    var body: some View {
        HStack(spacing: layout.spacing) {
            if layout.sceneColumn {
                CapsLabel("Scene", size: 8).frame(width: layout.sceneWidth)
            }
            ForEach(store.profile.launchGroups) { g in
                CapsLabel(g.label, size: 9, color: Color(hex: g.colorHex)).frame(width: layout.groupWidth)
            }
            ForEach(tracks) { track in
                TrackHeaderCell(track: track, width: layout.clipWidth, showMeter: store.profile.showTrackMeters, onRename: onRename)
            }
        }
        .frame(height: 30)
    }
}

struct TrackHeaderCell: View {
    let track: LiveTrack
    let width: CGFloat
    let showMeter: Bool
    let onRename: (String) -> Void
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var live: LiveSession

    var body: some View {
        VStack(spacing: 3) {
            Text(store.profile.displayName(forTrack: track.name))
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(track.mute ? Theme.textSecondary.opacity(0.5) : Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if showMeter {
                TrackMeterStrip(trackIndex: track.index, color: Color(track.color), meters: live.meters)
                    .frame(height: 4)
            }
        }
        .frame(width: width)
        .contentShape(Rectangle())
        .onTapGesture {
            Haptics.tap()
            live.setMute(track: track.index, on: !track.mute)
        }
        .onLongPressGesture(minimumDuration: 0.5) {
            Haptics.heavy()
            onRename(track.name)
        }
    }
}

struct TrackMeterStrip: View {
    let trackIndex: Int
    let color: Color
    @ObservedObject var meters: LiveMeters

    var body: some View {
        MeterBar(level: meters.trackMeters[trackIndex] ?? 0, color: color)
    }
}

struct SceneRow: View {
    let scene: LiveScene
    let tracks: [LiveTrack]
    let groups: [LaunchGroup]
    let layout: GridLayout
    let deckColor: Color
    let onEditNote: (LiveClip) -> Void
    let onConfirmScene: (Int) -> Void
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var live: LiveSession

    var body: some View {
        HStack(spacing: layout.spacing) {
            if layout.sceneColumn {
                SceneButton(scene: scene, tracks: tracks, width: layout.sceneWidth, height: layout.rowHeight, deckColor: deckColor, onConfirm: onConfirmScene)
            }
            ForEach(groups) { g in
                GroupButton(group: g, scene: scene, deckTracks: tracks, width: layout.groupWidth, height: layout.rowHeight)
            }
            ForEach(tracks) { track in
                ClipCell(track: track, scene: scene, width: layout.clipWidth, height: layout.rowHeight, fontSize: layout.fontSize, onEditNote: onEditNote)
            }
        }
    }
}

struct SceneButton: View {
    let scene: LiveScene
    let tracks: [LiveTrack]
    let width: CGFloat
    let height: CGFloat
    let deckColor: Color
    let onConfirm: (Int) -> Void
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var live: LiveSession

    private var isActive: Bool {
        !tracks.isEmpty && tracks.contains(where: { $0.playingSlotIndex == scene.index })
    }

    var body: some View {
        Button(action: {
            if store.profile.confirmSceneLaunch { onConfirm(scene.index); return }
            Haptics.launch()
            if store.decks.count > 1 {
                live.fireRow(scene: scene.index, tracks: tracks.map { $0.index })
            } else {
                live.fireScene(scene.index)
            }
        }) {
            Text(scene.name)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundColor(isActive ? .black : Theme.textSecondary)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .multilineTextAlignment(.center)
                .padding(2)
                .frame(width: width, height: height)
                .background(isActive ? Color.white : Theme.panelRaised)
                .cornerRadius(Theme.corner)
        }
        .buttonStyle(.plain)
    }
}

struct GroupButton: View {
    let group: LaunchGroup
    let scene: LiveScene
    let deckTracks: [LiveTrack]
    let width: CGFloat
    let height: CGFloat
    @EnvironmentObject var live: LiveSession

    private var members: [LiveTrack] { group.resolveTracks(in: deckTracks) }
    private var isActive: Bool {
        let withClips = members.filter { $0.clips[scene.index] != nil }
        return !withClips.isEmpty && withClips.allSatisfy { $0.playingSlotIndex == scene.index }
    }
    private var hasClips: Bool { members.contains(where: { $0.clips[scene.index] != nil }) }

    var body: some View {
        Button(action: {
            Haptics.launch()
            live.fireRow(scene: scene.index, tracks: members.map { $0.index })
        }) {
            Text(group.label)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundColor(isActive ? .black : (hasClips ? Theme.textPrimary : Theme.textSecondary.opacity(0.4)))
                .frame(width: width, height: height)
                .background(Color(hex: group.colorHex).opacity(isActive ? 1 : (hasClips ? 0.45 : 0.15)))
                .cornerRadius(Theme.corner)
        }
        .buttonStyle(.plain)
    }
}

/// One clip slot.
struct ClipCell: View {
    let track: LiveTrack
    let scene: LiveScene
    let width: CGFloat
    let height: CGFloat
    let fontSize: CGFloat
    let onEditNote: (LiveClip) -> Void
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var live: LiveSession
    @State private var blink = false

    private var clip: LiveClip? { track.clips[scene.index] }
    private var state: ClipPlayState { track.playState(forScene: scene.index) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: Theme.corner)
                .fill(backgroundColor)
            if let clip {
                VStack(alignment: .leading, spacing: 1) {
                    let parts = ClipNaming.split(clip.name)
                    if !parts.prefix.isEmpty {
                        Text(parts.prefix)
                            .font(.system(size: fontSize * 0.75, weight: .medium, design: .rounded))
                            .foregroundColor(textColor.opacity(0.7))
                            .lineLimit(1)
                    }
                    Text(parts.label)
                        .font(.system(size: fontSize, weight: .bold, design: .rounded))
                        .foregroundColor(textColor)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    if store.profile.showClipNotes, let note = store.profile.clipNote(track: track.name, clip: clip.name) {
                        Text(note)
                            .font(.system(size: fontSize * 0.75, weight: .semibold, design: .rounded))
                            .foregroundColor(textColor.opacity(0.85))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 5)
                .padding(.top, 4)
                .padding(.bottom, store.profile.showClipProgress ? 9 : 4)
                if state == .playing && store.profile.showClipProgress {
                    VStack {
                        Spacer()
                        ClipProgressBar(trackIndex: track.index, sceneIndex: scene.index, length: clip.length, meters: live.meters)
                            .frame(height: 5)
                            .padding(.horizontal, 5)
                            .padding(.bottom, 4)
                    }
                }
            }
            if state == .queued {
                RoundedRectangle(cornerRadius: Theme.corner)
                    .stroke(Color.white, lineWidth: 2)
                    .opacity(blink ? 0.2 : 1)
                    .animation(.easeInOut(duration: 0.35).repeatForever(autoreverses: true), value: blink)
                    .onAppear { blink = true }
                    .onDisappear { blink = false }
            }
        }
        .frame(width: width, height: height)
        .contentShape(Rectangle())
        .onTapGesture { if !store.profile.clipTapRequiresLongPress { trigger() } }
        .onLongPressGesture(minimumDuration: 0.45) {
            if store.profile.clipTapRequiresLongPress { trigger() } else if let clip { onEditNote(clip) }
        }
    }

    private func trigger() {
        if clip != nil {
            Haptics.launch()
            live.fireClip(track: track.index, scene: scene.index)
        } else {
            Haptics.tap()
            live.stopTrack(track.index)
        }
    }

    private var backgroundColor: Color {
        guard let clip else { return Theme.panel }
        let c = Color(clip.color)
        switch state {
        case .playing, .recording: return c
        case .queued: return c.opacity(0.5)
        case .stopped: return c.opacity(store.profile.dimStoppedClips ? 0.32 : 0.7)
        }
    }

    private var textColor: Color {
        guard let clip else { return Theme.textSecondary }
        if state == .playing { return clip.color.prefersDarkText ? .black : .white }
        return Theme.textPrimary
    }
}

struct ClipProgressBar: View {
    let trackIndex: Int
    let sceneIndex: Int
    let length: Double
    @ObservedObject var meters: LiveMeters

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.black.opacity(0.25))
                Capsule().fill(Color.black.opacity(0.75))
                    .frame(width: max(4, geo.size.width * CGFloat(meters.progress(track: trackIndex, scene: sceneIndex, length: length) ?? 0)))
            }
        }
    }
}

struct StopRow: View {
    let tracks: [LiveTrack]
    let layout: GridLayout
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var live: LiveSession

    var body: some View {
        HStack(spacing: layout.spacing) {
            if layout.sceneColumn {
                Button(action: {
                    Haptics.heavy()
                    for t in tracks { live.stopTrack(t.index) }
                }) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                        .frame(width: layout.sceneWidth, height: 30)
                        .background(Theme.red.opacity(0.8))
                        .cornerRadius(Theme.corner)
                }
                .buttonStyle(.plain)
            }
            ForEach(store.profile.launchGroups) { _ in
                Color.clear.frame(width: layout.groupWidth, height: 30)
            }
            ForEach(tracks) { track in
                Button(action: {
                    Haptics.tap()
                    live.stopTrack(track.index)
                }) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 9))
                        .foregroundColor(track.playingSlotIndex >= 0 ? Theme.red : Theme.textSecondary.opacity(0.5))
                        .frame(width: layout.clipWidth, height: 30)
                        .background(Theme.panelRaised)
                        .cornerRadius(Theme.corner)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct CueRow: View {
    let tracks: [LiveTrack]
    let layout: GridLayout
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var live: LiveSession

    var body: some View {
        HStack(spacing: layout.spacing) {
            if layout.sceneColumn { Color.clear.frame(width: layout.sceneWidth, height: 30) }
            ForEach(store.profile.launchGroups) { _ in
                Color.clear.frame(width: layout.groupWidth, height: 30)
            }
            ForEach(tracks) { track in
                Button(action: {
                    Haptics.tap()
                    live.setSolo(track: track.index, on: !track.solo)
                }) {
                    Text("CUE")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(track.solo ? .black : Theme.textSecondary)
                        .frame(width: layout.clipWidth, height: 30)
                        .background(track.solo ? Theme.yellow : Theme.panelRaised)
                        .cornerRadius(Theme.corner)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Horizontal list of sections (consecutive scenes sharing a name).
struct SectionBar: View {
    let deckColor: Color
    let scenes: [LiveScene]
    let onJump: (Int) -> Void
    @EnvironmentObject var live: LiveSession

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(live.sections) { section in
                    let active = isActive(section)
                    Button(action: {
                        Haptics.tap()
                        onJump(section.firstScene)
                    }) {
                        Text(section.name)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(active ? .black : Theme.textSecondary)
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .frame(height: 26)
                            .background(active ? deckColor : Theme.panelRaised)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(height: 28)
    }

    private func isActive(_ section: SceneSection) -> Bool {
        live.song.tracks.contains { t in
            guard let s = t.playingSceneIndex else { return false }
            return section.sceneRange.contains(s)
        }
    }
}

enum ClipNaming {
    /// "basilar_5-HI PERC" → prefix "basilar_5-", label "HI PERC".
    static func split(_ name: String) -> (prefix: String, label: String) {
        if let idx = name.lastIndex(where: { $0 == "-" || $0 == "–" }) , idx != name.startIndex {
            let label = name[name.index(after: idx)...].trimmingCharacters(in: .whitespaces)
            let prefix = String(name[...idx])
            if !label.isEmpty { return (prefix, label) }
        }
        return ("", name)
    }
}
