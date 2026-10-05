import SwiftUI

enum SeqPanel: String, CaseIterable, Identifiable {
    case step = "STEP"
    case track = "TRACK"
    case lfo = "MOD"
    case keys = "KEYS"
    case arrange = "PATTERNS"
    case tools = "TOOLS"
    var id: String { rawValue }
}

/// Elektron / Oxi-style step sequencer screen.
struct SequencerView: View {
    @EnvironmentObject var sequencer: SequencerRuntime
    @EnvironmentObject var store: AppStore
    @State private var panel: SeqPanel = .step

    var body: some View {
        HStack(spacing: 8) {
            TrackList()
                .frame(width: 150)
            VStack(spacing: 8) {
                PatternBar()
                StepGrid()
                Segmented(options: SeqPanel.allCases.map { ($0, $0.rawValue) }, selection: $panel, height: 30)
                Group {
                    switch panel {
                    case .step: StepEditor()
                    case .track: TrackEditor()
                    case .lfo: LFOEditor()
                    case .keys: KeyboardView()
                    case .arrange: ArrangeView()
                    case .tools: ToolsView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .panel()
            }
        }
        .padding(8)
    }
}

struct TrackList: View {
    @EnvironmentObject var sequencer: SequencerRuntime

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 3) {
                ForEach(Array(sequencer.pattern.tracks.enumerated()), id: \.element.id) { (i, track) in
                    TrackRow(index: i, track: track)
                }
            }
        }
    }
}

struct TrackRow: View {
    let index: Int
    let track: SeqTrack
    @EnvironmentObject var sequencer: SequencerRuntime

    var body: some View {
        let selected = sequencer.selectedTrack == index
        let color = Color(hex: track.colorHex)
        HStack(spacing: 4) {
            Button(action: {
                Haptics.tap()
                sequencer.selectedTrack = index
            }) {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 4, height: 26)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(track.name)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(selected ? .black : Theme.textPrimary)
                            .lineLimit(1)
                        Text("ch\(track.channel + 1) · \(track.length)·\(track.speed.rawValue)")
                            .font(.system(size: 9, design: .rounded))
                            .foregroundColor(selected ? .black.opacity(0.7) : Theme.textSecondary)
                    }
                    Spacer(minLength: 0)
                    if let step = sequencer.position.stepsPerTrack[safe: index], sequencer.isRunning {
                        Text("\(step + 1)").font(.system(size: 9, design: .monospaced)).foregroundColor(selected ? .black : Theme.textSecondary)
                    }
                }
                .padding(.horizontal, 6)
                .frame(height: 36)
                .frame(maxWidth: .infinity)
                .background(selected ? color : Theme.panelRaised)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            VStack(spacing: 2) {
                Button(action: { sequencer.project.patterns[sequencer.currentPatternIndex].tracks[index].mute.toggle(); Haptics.tap() }) {
                    Text("M").font(.system(size: 9, weight: .bold)).frame(width: 20, height: 16)
                        .background(track.mute ? Theme.red : Theme.panelRaised).foregroundColor(track.mute ? .black : Theme.textSecondary).cornerRadius(3)
                }
                .buttonStyle(.plain)
                Button(action: { sequencer.project.patterns[sequencer.currentPatternIndex].tracks[index].solo.toggle(); Haptics.tap() }) {
                    Text("S").font(.system(size: 9, weight: .bold)).frame(width: 20, height: 16)
                        .background(track.solo ? Theme.yellow : Theme.panelRaised).foregroundColor(track.solo ? .black : Theme.textSecondary).cornerRadius(3)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct PatternBar: View {
    @EnvironmentObject var sequencer: SequencerRuntime

    var body: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(sequencer.project.patterns.enumerated()), id: \.element.id) { (i, p) in
                        let current = i == sequencer.currentPatternIndex
                        let queued = sequencer.queuedPatternIndex == i
                        Button(action: {
                            Haptics.tap()
                            sequencer.selectPattern(i)
                        }) {
                            Text(p.name)
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(current ? .black : Theme.textPrimary)
                                .padding(.horizontal, 10)
                                .frame(height: 28)
                                .background(current ? Theme.accent : (queued ? Theme.yellow.opacity(0.4) : Theme.panelRaised))
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                    Button(action: { sequencer.addPattern(); Haptics.tap() }) {
                        Image(systemName: "plus").frame(width: 28, height: 28).background(Theme.panelRaised).cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(Theme.textSecondary)
                }
            }
            Spacer()
            PadButton(title: sequencer.isRunning ? "STOP" : "PLAY", color: Theme.green, active: sequencer.isRunning, height: 28, fontSize: 11) {
                sequencer.toggle()
            }
            .frame(width: 70)
            PadButton(title: "REC", color: Theme.red, active: sequencer.recordEnabled, height: 28, fontSize: 11) {
                sequencer.recordEnabled.toggle()
            }
            .frame(width: 56)
            Segmented(options: SyncMode.allCases.map { ($0, $0.rawValue) }, selection: $sequencer.syncMode, height: 28)
                .frame(width: 200)
        }
    }
}

/// 16-step page with page selector; tap toggles, long press selects for editing.
struct StepGrid: View {
    @EnvironmentObject var sequencer: SequencerRuntime

    private var track: SeqTrack { sequencer.track }
    private var pages: Int { max(1, Int(ceil(Double(track.length) / 16.0))) }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(0..<4, id: \.self) { p in
                    let enabled = p < pages
                    let playing = sequencer.isRunning && (sequencer.position.stepsPerTrack[safe: sequencer.selectedTrack] ?? -1) / 16 == p
                    Button(action: { if enabled { sequencer.stepPage = p; Haptics.tap() } }) {
                        Text("\(p * 16 + 1)-\(p * 16 + 16)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(sequencer.stepPage == p ? .black : (enabled ? Theme.textPrimary : Theme.textSecondary.opacity(0.3)))
                            .frame(width: 60, height: 22)
                            .background(sequencer.stepPage == p ? Theme.textPrimary : (playing ? Theme.green.opacity(0.4) : Theme.panelRaised))
                            .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Text(track.name).font(.system(size: 12, weight: .bold, design: .rounded)).foregroundColor(Color(hex: track.colorHex))
                Text("\(MIDINote.name(track.defaultNote)) · \(track.length) steps · swing \(track.swing ?? sequencer.pattern.swing)")
                    .font(.system(size: 10, design: .rounded)).foregroundColor(Theme.textSecondary)
            }
            let page = min(sequencer.stepPage, pages - 1)
            HStack(spacing: 4) {
                ForEach(0..<16, id: \.self) { i in
                    let index = page * 16 + i
                    StepPad(index: index, step: track.step(index), inRange: index < track.length,
                            isPlayhead: sequencer.isRunning && (sequencer.position.stepsPerTrack[safe: sequencer.selectedTrack] ?? -1) == index,
                            isSelected: sequencer.selectedStep == index, isDrum: track.isDrum, color: Color(hex: track.colorHex))
                }
            }
            .frame(height: 76)
        }
    }
}

struct StepPad: View {
    let index: Int
    let step: Step
    let inRange: Bool
    let isPlayhead: Bool
    let isSelected: Bool
    let isDrum: Bool
    let color: Color
    @EnvironmentObject var sequencer: SequencerRuntime

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(step.isOn ? color.opacity(inRange ? 1 : 0.4) : (inRange ? Theme.panelRaised : Theme.panel))
            if isPlayhead {
                RoundedRectangle(cornerRadius: 8).stroke(Color.white, lineWidth: 3)
            } else if isSelected {
                RoundedRectangle(cornerRadius: 8).stroke(Theme.yellow, lineWidth: 2)
            } else if (index % 4) == 0 {
                RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.18), lineWidth: 1)
            }
            VStack(spacing: 2) {
                Text("\(index + 1)")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundColor(step.isOn ? .black.opacity(0.7) : Theme.textSecondary)
                if step.isOn {
                    Text(stepLabel)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.black)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    HStack(spacing: 2) {
                        if step.condition != .always { Tag(step.condition.label) }
                        if step.probability < 100 { Tag("\(step.probability)%") }
                        if step.retrig.count > 1 { Tag("x\(step.retrig.count)") }
                        if !step.locks.isEmpty { Tag("PL") }
                        if step.slide { Tag("SL") }
                        if step.accent { Tag("AC") }
                        if step.micro != 0 { Tag(step.micro > 0 ? "+\(step.micro)" : "\(step.micro)") }
                    }
                }
            }
            .padding(2)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            Haptics.tap()
            if sequencer.selectedStep == index && step.isOn {
                sequencer.toggleStep(index)
                sequencer.selectedStep = nil
            } else if !step.isOn {
                sequencer.toggleStep(index)
                sequencer.selectedStep = index
            } else {
                sequencer.selectedStep = index
            }
        }
        .onLongPressGesture(minimumDuration: 0.4) {
            Haptics.heavy()
            sequencer.toggleStep(index)
            if sequencer.selectedStep == index { sequencer.selectedStep = nil }
        }
    }

    private var stepLabel: String {
        if step.notes.isEmpty { return isDrum ? "•" : "—" }
        if step.notes.count == 1 { return MIDINote.name(step.notes[0]) }
        return MIDINote.name(step.notes[0]) + "+\(step.notes.count - 1)"
    }

    private struct Tag: View {
        let text: String
        init(_ text: String) { self.text = text }
        var body: some View {
            Text(text).font(.system(size: 7, weight: .bold, design: .rounded))
                .foregroundColor(.white).padding(.horizontal, 2).padding(.vertical, 1)
                .background(Color.black.opacity(0.45)).cornerRadius(3)
        }
    }
}
