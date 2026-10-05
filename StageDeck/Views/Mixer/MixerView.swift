import SwiftUI

/// Stem mixer: every track of each deck with sends, filter, fader, meter and buttons.
struct MixerView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var live: LiveSession

    var body: some View {
        GeometryReader { geo in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(Array(store.decks.enumerated()), id: \.offset) { (i, deck) in
                        DeckMixer(deck: deck, deckIndex: i)
                        if i < store.decks.count - 1 { Divider().background(Theme.line) }
                    }
                    ReturnsAndMaster()
                }
                .padding(10)
                .frame(minWidth: geo.size.width, alignment: .leading)
            }
        }
    }
}

struct DeckMixer: View {
    let deck: DeckDefinition
    let deckIndex: Int
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
                PadButton(title: deck.name, color: color, active: !muted, height: 40, fontSize: 16) {
                    live.setMute(tracks: tracks.map { $0.index }, on: !muted)
                }
                .frame(width: 120)
                if let g = groupTrack {
                    DeckFilterControl(track: g, label: "HPF", color: color)
                        .frame(width: 160, height: 40)
                }
            }
            HStack(alignment: .top, spacing: 6) {
                ForEach(tracks) { track in
                    ChannelStrip(track: track, deckColor: color)
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

struct ChannelStrip: View {
    let track: LiveTrack
    let deckColor: Color
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var live: LiveSession

    private var color: Color { Color(track.color) }

    var body: some View {
        VStack(spacing: 5) {
            Text(store.profile.displayName(forTrack: track.name))
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: 64, height: 22)
                .background(Theme.panelRaised)
                .cornerRadius(6)

            if store.profile.showSends {
                ForEach(0..<min(4, live.song.numSends), id: \.self) { s in
                    SendControl(track: track, send: s, color: color)
                        .frame(width: 64, height: 34)
                }
            }

            TrackFilterControl(track: track, color: color)
                .frame(width: 64, height: 110)

            Text(LiveVolume.label(fader: track.volume))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(Theme.textSecondary)
                .frame(width: 64, height: 16)
                .background(Theme.panelRaised)
                .cornerRadius(4)

            ChannelFader(track: track, color: color, meters: live.meters)
                .frame(width: 64, height: 180)

            if store.profile.showPan {
                HorizontalSlider(value: Binding(get: { (track.panning + 1) / 2 }, set: { live.setPanning(track: track.index, value: $0 * 2 - 1) }),
                                 color: Theme.textSecondary, label: panLabel)
                    .frame(width: 64, height: 18)
            }

            HStack(spacing: 3) {
                PadButton(title: "M", color: Theme.red, active: track.mute, height: 28, fontSize: 11) {
                    live.setMute(track: track.index, on: !track.mute)
                }
                PadButton(title: "CUE", color: Theme.yellow, active: track.solo, height: 28, fontSize: 9) {
                    live.setSolo(track: track.index, on: !track.solo)
                }
            }
            .frame(width: 64)
            if track.canBeArmed && track.hasMIDIInput {
                PadButton(title: "ARM", color: Theme.red, active: track.arm, height: 24, fontSize: 9) {
                    live.setArm(track: track.index, on: !track.arm)
                }
                .frame(width: 64)
            }
        }
    }

    private var panLabel: String {
        let p = track.panning
        if abs(p) < 0.02 { return "C" }
        return p < 0 ? "\(Int(abs(p) * 50))L" : "\(Int(p * 50))R"
    }
}

struct ChannelFader: View {
    let track: LiveTrack
    let color: Color
    @ObservedObject var meters: LiveMeters
    @EnvironmentObject var live: LiveSession

    var body: some View {
        VerticalFader(value: Binding(get: { track.volume }, set: { live.setVolume(track: track.index, value: $0) }),
                      color: color, meter: meters.trackMeters[track.index] ?? 0, label: nil)
    }
}

struct SendControl: View {
    let track: LiveTrack
    let send: Int
    let color: Color
    @EnvironmentObject var live: LiveSession

    var body: some View {
        let value = send < track.sends.count ? track.sends[send] : 0
        let name = send < live.song.returnTrackNames.count ? live.song.returnTrackNames[send] : "S\(send + 1)"
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 6).fill(color.opacity(0.18))
            RoundedRectangle(cornerRadius: 6).fill(color.opacity(0.8))
                .frame(height: max(3, 34 * CGFloat(value)))
            Text(name)
                .font(.system(size: 8, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.textPrimary)
                .lineLimit(1)
                .padding(.bottom, 3)
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { g in
            let v = max(0, min(1, 1 - Double(g.location.y / 34)))
            live.setSend(track: track.index, send: send, value: v)
        })
        .onTapGesture(count: 2) { live.setSend(track: track.index, send: send, value: 0) }
    }
}

/// Per-track low-pass macro bound to the track's Auto Filter frequency.
struct TrackFilterControl: View {
    let track: LiveTrack
    let color: Color
    @EnvironmentObject var live: LiveSession
    @EnvironmentObject var store: AppStore

    var body: some View {
        if let filter = track.autoFilter, let f = filter.parameterIndex(named: store.profile.filterParameterName) {
            let param = filter.parameters[f]
            VerticalFader(value: Binding(get: { param.normalized }, set: { v in
                live.setDeviceParameter(track: track.index, device: filter.index, parameter: f, normalized: v)
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
                if let d = track.autoFilter { live.requestDeviceParameters(track: track.index, device: d.index) }
            }
        }
    }
}

struct ReturnsAndMaster: View {
    @EnvironmentObject var live: LiveSession

    var body: some View {
        VStack(spacing: 6) {
            CapsLabel("Master / Cue", size: 9)
            HStack(spacing: 8) {
                VStack(spacing: 4) {
                    Text(LiveVolume.label(fader: live.song.masterVolume))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundColor(Theme.textSecondary)
                    MasterFaderView(meters: live.meters)
                        .frame(width: 64, height: 300)
                    CapsLabel("Master", size: 8)
                }
                VStack(spacing: 4) {
                    Text(LiveVolume.label(fader: live.song.cueVolume))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundColor(Theme.textSecondary)
                    VerticalFader(value: Binding(get: { live.song.cueVolume }, set: { live.setCueVolume($0) }), color: Theme.yellow, meter: nil, label: nil)
                        .frame(width: 48, height: 300)
                    CapsLabel("Cue", size: 8)
                }
            }
        }
        .padding(8)
        .background(Theme.panel)
        .cornerRadius(10)
    }
}

struct MasterFaderView: View {
    @ObservedObject var meters: LiveMeters
    @EnvironmentObject var live: LiveSession

    var body: some View {
        VerticalFader(value: Binding(get: { live.song.masterVolume }, set: { live.setMasterVolume($0) }),
                      color: Theme.green, meter: meters.masterMeter, label: nil)
    }
}
