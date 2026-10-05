import SwiftUI

/// Bottom bar: tempo, transport, quantization, sequencer sync and master level.
struct TransportBar: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var live: LiveSession
    @EnvironmentObject var sequencer: SequencerRuntime
    @State private var showQuantization = false

    var body: some View {
        HStack(spacing: 10) {
            tempoControl
            Divider().frame(height: 28).background(Theme.line)
            transportButtons
            Divider().frame(height: 28).background(Theme.line)
            quantizationButton
            Spacer()
            if store.activeTab == .sequencer {
                sequencerStatus
            } else {
                sectionStatus
            }
            Spacer()
            masterMeter
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
        .background(Theme.panel)
    }

    private var tempoControl: some View {
        HStack(spacing: 4) {
            Button(action: { nudgeTempo(-1) }) {
                Image(systemName: "minus").frame(width: 30, height: 36)
            }
            .buttonStyle(.plain)
            .disabled(store.profile.performanceLock)
            VStack(spacing: 0) {
                Text(String(format: "%.1f", tempoValue))
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.textPrimary)
                CapsLabel(tempoLabel, size: 8)
            }
            .frame(width: 70)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                if live.state == .connected { live.tapTempo() }
            }
            Button(action: { nudgeTempo(1) }) {
                Image(systemName: "plus").frame(width: 30, height: 36)
            }
            .buttonStyle(.plain)
            .disabled(store.profile.performanceLock)
        }
        .foregroundColor(Theme.textSecondary)
        .background(Theme.panelRaised)
        .cornerRadius(8)
    }

    private var tempoValue: Double {
        if store.activeTab == .sequencer && (live.state == .disconnected) { return sequencer.tempo }
        if store.activeTab == .sequencer && sequencer.syncMode == .externalClock { return sequencer.externalTempo }
        return live.state == .disconnected ? sequencer.tempo : live.song.tempo
    }

    private var tempoLabel: String {
        if store.activeTab == .sequencer && sequencer.syncMode == .externalClock { return "EXT BPM" }
        return "BPM"
    }

    private func nudgeTempo(_ delta: Double) {
        Haptics.tap()
        if live.state == .connected || live.state.isSimulated {
            live.setTempo(live.song.tempo + delta)
        } else {
            sequencer.setTempo(sequencer.tempo + delta)
        }
    }

    private var transportButtons: some View {
        HStack(spacing: 6) {
            Button(action: {
                Haptics.launch()
                if store.activeTab == .sequencer && live.state == .disconnected {
                    sequencer.toggle()
                } else if live.song.isPlaying {
                    live.stop()
                } else {
                    live.play()
                }
            }) {
                Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(isPlaying ? .black : Theme.textPrimary)
                    .frame(width: 54, height: 36)
                    .background(isPlaying ? Theme.green : Theme.panelRaised)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
            if store.activeTab != .sequencer {
                ConfirmButton(title: "STOP ALL", message: "Stop all clips?", color: Theme.red,
                              requireConfirm: store.profile.confirmStopAll, height: 36) {
                    live.stopAll()
                }
                .frame(width: 84)
                .disabled(store.profile.performanceLock)
            }
        }
    }

    private var isPlaying: Bool {
        if store.activeTab == .sequencer && live.state == .disconnected { return sequencer.isRunning }
        return live.song.isPlaying
    }

    private var quantizationButton: some View {
        Button(action: { showQuantization = true }) {
            VStack(spacing: 0) {
                Text(live.song.quantization.label)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.textPrimary)
                CapsLabel("Quant", size: 8)
            }
            .frame(width: 64, height: 36)
            .background(Theme.panelRaised)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showQuantization) {
            VStack(spacing: 4) {
                ForEach(LiveQuantization.allCases) { q in
                    Button(action: {
                        live.setQuantization(q)
                        showQuantization = false
                    }) {
                        Text(q.label)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(q == live.song.quantization ? .black : Theme.textPrimary)
                            .frame(width: 120, height: 32)
                            .background(q == live.song.quantization ? Theme.accent : Theme.panelRaised)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(Theme.panel)
        }
    }

    private var sequencerStatus: some View {
        HStack(spacing: 8) {
            Text("P\(sequencer.currentPatternIndex + 1)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(Theme.accent)
            if let q = sequencer.queuedPatternIndex {
                Text("→ P\(q + 1)").font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundColor(Theme.yellow)
            }
            Text(String(format: "%d.%d", sequencer.position.bar + 1, sequencer.position.beat + 1))
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(Theme.textSecondary)
            CapsLabel(sequencer.syncMode == .externalClock ? "EXT CLOCK" : (store.profile.sequencerFollowsLiveTransport && live.state != .disconnected ? "FOLLOWS LIVE" : "INTERNAL"), size: 9)
            PadButton(title: "FILL", color: Theme.yellow, active: sequencer.fillActive, height: 32, fontSize: 11) {
                sequencer.fillActive.toggle()
            }
            .frame(width: 60)
            PadButton(title: "PANIC", color: Theme.red, active: false, height: 32, fontSize: 11) {
                sequencer.panic()
            }
            .frame(width: 64)
        }
    }

    private var sectionStatus: some View {
        HStack(spacing: 10) {
            if live.song.isPlaying {
                Text("Beat \(live.song.beat)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(Theme.textSecondary)
            }
            if let name = currentSectionName {
                CapsLabel("Section", size: 8)
                Text(name).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundColor(Theme.textPrimary)
            }
            if live.state == .connected || live.state.isSimulated {
                let seqText = sequencer.isRunning ? "SEQ ▶" : "SEQ ■"
                Text(seqText).font(.system(size: 11, weight: .bold, design: .rounded)).foregroundColor(sequencer.isRunning ? Theme.green : Theme.textSecondary)
            }
        }
    }

    private var currentSectionName: String? {
        let playing = live.song.tracks.compactMap { $0.playingSceneIndex }
        guard let scene = playing.max() else { return nil }
        return SetLayout.section(containing: scene, in: live.sections)?.name
    }

    private var masterMeter: some View {
        MasterMeterView()
    }
}

struct MasterMeterView: View {
    @EnvironmentObject var live: LiveSession

    var body: some View {
        MasterMeterContent(meters: live.meters)
    }
}

private struct MasterMeterContent: View {
    @EnvironmentObject var live: LiveSession
    @ObservedObject var meters: LiveMeters

    var body: some View {
        HStack(spacing: 8) {
            CapsLabel("Master", size: 8)
            VStack(spacing: 3) {
                MeterBar(level: meters.masterMeter).frame(width: 120, height: 6)
                HorizontalSlider(value: Binding(get: { live.song.masterVolume }, set: { live.setMasterVolume($0) }),
                                 color: Theme.green.opacity(0.8), label: "")
                    .frame(width: 120, height: 10)
            }
            Text(LiveVolume.label(fader: live.song.masterVolume))
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(Theme.textPrimary)
                .frame(width: 44, alignment: .trailing)
        }
    }
}
