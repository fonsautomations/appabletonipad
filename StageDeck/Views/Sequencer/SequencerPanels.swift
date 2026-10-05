import SwiftUI

/// Per-step parameters (note, velocity, length, micro, probability, condition, retrig, locks).
struct StepEditor: View {
    @EnvironmentObject var sequencer: SequencerRuntime

    var body: some View {
        if let index = sequencer.selectedStep {
            let step = sequencer.track.step(index)
            ScrollView([.vertical, .horizontal], showsIndicators: true) {
                VStack(alignment: .leading, spacing: 10) {
                    CapsLabel("Step \(index + 1) · \(sequencer.track.name)", size: 10, color: Theme.textPrimary)
                    HStack(alignment: .bottom, spacing: 8) {
                        ValueDial(title: "Note", value: noteBinding(step), range: 0...127, format: { MIDINote.name($0) }).frame(width: 110)
                        ValueDial(title: "Vel", value: binding(\.velocity, step), range: 1...127).frame(width: 90)
                        ValueDial(title: "Len /16", value: lengthBinding(step), range: 1...64, format: { String(format: "%.2g", Double($0) / 4) }).frame(width: 90)
                        ValueDial(title: "Micro", value: binding(\.micro, step), range: -11...11, format: { $0 > 0 ? "+\($0)" : "\($0)" }).frame(width: 90)
                        ValueDial(title: "Prob %", value: binding(\.probability, step), range: 0...100, step: 5).frame(width: 90)
                        ToggleButton(title: "ACCENT", isOn: boolBinding(\.accent, step), color: Theme.yellow, height: 34).frame(width: 84)
                        ToggleButton(title: "SLIDE", isOn: boolBinding(\.slide, step), color: Theme.secondary, height: 34).frame(width: 84)
                        Spacer(minLength: 0)
                    }
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            CapsLabel("Retrig", size: 10, color: Theme.textPrimary)
                            HStack(spacing: 8) {
                                ValueDial(title: "Retrig", value: binding(\.retrig.count, step), range: 1...16, format: { $0 == 1 ? "off" : "x\($0)" }).frame(width: 90)
                                ValueDial(title: "Rate", value: retrigRateBinding(step), range: 0...(Retrig.rates.count - 1), format: { Retrig.rates[$0].label }).frame(width: 90)
                                ValueDial(title: "Ramp %", value: binding(\.retrig.velocityRamp, step), range: -100...100, step: 10).frame(width: 90)
                                ValueDial(title: "Prog chg", value: binding(\.programChange, step), range: -1...127, format: { $0 < 0 ? "—" : "\($0)" }).frame(width: 90)
                            }
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            CapsLabel("Chord", size: 10, color: Theme.textPrimary)
                            ChordEditor(step: step, index: index)
                        }
                        Spacer(minLength: 0)
                    }
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            CapsLabel("Condition", size: 10, color: Theme.textPrimary)
                            ConditionPicker(step: step, index: index)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            CapsLabel("Parameter locks", size: 10, color: Theme.textPrimary)
                            LockEditor(step: step, index: index)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .padding(4)
            }
        } else {
            VStack(spacing: 8) {
                Text("Tap a step to add it, tap again to edit. Long-press clears.")
                Text("Press PLAY, enable REC and play the KEYS panel to record live.")
            }
            .font(.system(size: 13, design: .rounded))
            .foregroundColor(Theme.textSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func binding(_ kp: WritableKeyPath<Step, Int>, _ step: Step) -> Binding<Int> {
        Binding(get: { sequencer.selectedStep.map { sequencer.track.step($0)[keyPath: kp] } ?? step[keyPath: kp] },
                set: { v in if let i = sequencer.selectedStep { sequencer.updateStep(i) { $0[keyPath: kp] = v } } })
    }

    private func boolBinding(_ kp: WritableKeyPath<Step, Bool>, _ step: Step) -> Binding<Bool> {
        Binding(get: { sequencer.selectedStep.map { sequencer.track.step($0)[keyPath: kp] } ?? step[keyPath: kp] },
                set: { v in if let i = sequencer.selectedStep { sequencer.updateStep(i) { $0[keyPath: kp] = v } } })
    }

    private func noteBinding(_ step: Step) -> Binding<Int> {
        Binding(get: {
            let s = sequencer.selectedStep.map { sequencer.track.step($0) } ?? step
            return s.notes.first ?? sequencer.track.defaultNote
        }, set: { v in
            if let i = sequencer.selectedStep {
                sequencer.updateStep(i) { s in
                    if s.notes.isEmpty { s.notes = [v] } else { s.notes[0] = v }
                }
            }
        })
    }

    private func lengthBinding(_ step: Step) -> Binding<Int> {
        Binding(get: {
            let s = sequencer.selectedStep.map { sequencer.track.step($0) } ?? step
            return max(1, Int((s.length * 4).rounded()))
        }, set: { v in
            if let i = sequencer.selectedStep { sequencer.updateStep(i) { $0.length = Double(v) / 4 } }
        })
    }

    private func retrigRateBinding(_ step: Step) -> Binding<Int> {
        Binding(get: {
            let s = sequencer.selectedStep.map { sequencer.track.step($0) } ?? step
            return Retrig.rates.firstIndex(where: { $0.ticks == s.retrig.rateTicks }) ?? 6
        }, set: { v in
            if let i = sequencer.selectedStep { sequencer.updateStep(i) { $0.retrig.rateTicks = Retrig.rates[max(0, min(Retrig.rates.count - 1, v))].ticks } }
        })
    }
}

struct ConditionPicker: View {
    let step: Step
    let index: Int
    @EnvironmentObject var sequencer: SequencerRuntime

    var body: some View {
        let columns = Array(repeating: GridItem(.fixed(44), spacing: 3), count: 8)
        LazyVGrid(columns: columns, spacing: 3) {
            ForEach(Array(TrigCondition.presets.enumerated()), id: \.offset) { (_, c) in
                Button(action: {
                    Haptics.tap()
                    sequencer.updateStep(index) { $0.condition = c }
                }) {
                    Text(c.label)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(step.condition == c ? .black : Theme.textPrimary)
                        .frame(width: 44, height: 22)
                        .background(step.condition == c ? Theme.accent : Theme.panelRaised)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 8 * 47)
    }
}

struct LockEditor: View {
    let step: Step
    let index: Int
    @EnvironmentObject var sequencer: SequencerRuntime
    @State private var customCC: Int = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(sequencer.track.ccLanes) { lane in
                HStack(spacing: 6) {
                    Text("\(lane.name) (CC\(lane.controller))")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.textPrimary)
                        .frame(width: 110, alignment: .leading)
                    let locked = step.locks[lane.controller]
                    HorizontalSlider(value: Binding(get: { Double(locked ?? lane.defaultValue) / 127 },
                                                    set: { v in sequencer.updateStep(index) { $0.locks[lane.controller] = Int((v * 127).rounded()) } }),
                                     color: locked == nil ? Theme.textSecondary.opacity(0.5) : Theme.accent,
                                     label: locked.map { "\($0)" } ?? "—")
                        .frame(width: 140, height: 22)
                    Button(action: { sequencer.updateStep(index) { $0.locks.removeValue(forKey: lane.controller) } }) {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).frame(width: 22, height: 22)
                            .background(Theme.panelRaised).cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(Theme.textSecondary)
                    .opacity(locked == nil ? 0.3 : 1)
                }
            }
            if sequencer.track.ccLanes.count < 8 {
                HStack(spacing: 6) {
                    ValueDial(title: "Add CC lane", value: $customCC, range: 0...127).frame(width: 120)
                    PadButton(title: "ADD", color: Theme.secondary, active: false, height: 30, fontSize: 10) {
                        sequencer.updateTrack { $0.ccLanes.append(CCLane(name: "CC\(customCC)", controller: customCC)) }
                    }
                    .frame(width: 60)
                }
            }
        }
    }
}

struct ChordEditor: View {
    let step: Step
    let index: Int
    @EnvironmentObject var sequencer: SequencerRuntime

    private static let chords: [(String, [Int])] = [
        ("Single", []), ("min", [0, 3, 7]), ("maj", [0, 4, 7]), ("min7", [0, 3, 7, 10]), ("maj7", [0, 4, 7, 11]),
        ("7", [0, 4, 7, 10]), ("sus2", [0, 2, 7]), ("sus4", [0, 5, 7]), ("dim", [0, 3, 6]), ("5", [0, 7]), ("oct", [0, 12]),
    ]

    var body: some View {
        let root = step.notes.first ?? sequencer.track.defaultNote
        let columns = Array(repeating: GridItem(.fixed(56), spacing: 3), count: 4)
        LazyVGrid(columns: columns, spacing: 3) {
            ForEach(Array(ChordEditor.chords.enumerated()), id: \.offset) { (_, chord) in
                let notes = chord.1.isEmpty ? [root] : chord.1.map { root + $0 }
                let active = step.notes == notes || (chord.1.isEmpty && step.notes.count <= 1)
                Button(action: {
                    Haptics.tap()
                    sequencer.updateStep(index) { $0.notes = notes.filter { $0 >= 0 && $0 <= 127 } }
                }) {
                    Text(chord.0)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(active ? .black : Theme.textPrimary)
                        .frame(width: 56, height: 24)
                        .background(active ? Theme.secondary : Theme.panelRaised)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 4 * 59)
    }
}

/// Track-level parameters (MIDI routing, length, speed, direction, swing, defaults, scale lock…).
struct TrackEditor: View {
    @EnvironmentObject var sequencer: SequencerRuntime
    @EnvironmentObject var midi: MIDIService

    var body: some View {
        ScrollView([.vertical, .horizontal], showsIndicators: true) {
            VStack(alignment: .leading, spacing: 10) {
                CapsLabel("Track", size: 10, color: Theme.textPrimary)
                HStack(alignment: .bottom, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        CapsLabel("Name", size: 9)
                        TextField("Name", text: Binding(get: { sequencer.track.name }, set: { v in sequencer.updateTrack { $0.name = v } }))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 130, height: 34)
                    }
                    ValueDial(title: "Channel", value: Binding(get: { sequencer.track.channel + 1 }, set: { v in sequencer.updateTrack { $0.channel = v - 1 } }), range: 1...16).frame(width: 90)
                    ValueDial(title: "Length", value: Binding(get: { sequencer.track.length }, set: { v in sequencer.updateTrack { $0.length = v } }), range: 1...64).frame(width: 90)
                    ValueDial(title: "Speed", value: speedBinding, range: 0...(TrackSpeed.allCases.count - 1), format: { TrackSpeed.allCases[$0].rawValue }).frame(width: 90)
                    ValueDial(title: "Dir", value: dirBinding, range: 0...(PlayDirection.allCases.count - 1), format: { PlayDirection.allCases[$0].label }).frame(width: 90)
                    ToggleButton(title: "DRUM", isOn: Binding(get: { sequencer.track.isDrum }, set: { v in sequencer.updateTrack { $0.isDrum = v } }), color: Theme.secondary, height: 34).frame(width: 80)
                    ToggleButton(title: "SCALE LOCK", isOn: Binding(get: { sequencer.track.scaleLock }, set: { v in sequencer.updateTrack { $0.scaleLock = v } }), color: Theme.secondary, height: 34).frame(width: 110)
                    ToggleButton(title: "MUTE", isOn: Binding(get: { sequencer.track.mute }, set: { v in sequencer.updateTrack { $0.mute = v } }), color: Theme.red, height: 34).frame(width: 70)
                    ToggleButton(title: "SOLO", isOn: Binding(get: { sequencer.track.solo }, set: { v in sequencer.updateTrack { $0.solo = v } }), color: Theme.yellow, height: 34).frame(width: 70)
                    Spacer(minLength: 0)
                }
                HStack(spacing: 8) {
                    ValueDial(title: "Def note", value: Binding(get: { sequencer.track.defaultNote }, set: { v in sequencer.updateTrack { $0.defaultNote = v } }), range: 0...127, format: { MIDINote.name($0) }).frame(width: 100)
                    ValueDial(title: "Def vel", value: Binding(get: { sequencer.track.defaultVelocity }, set: { v in sequencer.updateTrack { $0.defaultVelocity = v } }), range: 1...127).frame(width: 90)
                    ValueDial(title: "Accent vel", value: Binding(get: { sequencer.track.accentVelocity }, set: { v in sequencer.updateTrack { $0.accentVelocity = v } }), range: 1...127).frame(width: 90)
                    ValueDial(title: "Transpose", value: Binding(get: { sequencer.track.transpose }, set: { v in sequencer.updateTrack { $0.transpose = v } }), range: -36...36).frame(width: 90)
                    ValueDial(title: "Chance %", value: Binding(get: { sequencer.track.chance }, set: { v in sequencer.updateTrack { $0.chance = v } }), range: 0...100, step: 5).frame(width: 90)
                    ValueDial(title: "Swing", value: Binding(get: { sequencer.track.swing ?? sequencer.pattern.swing }, set: { v in sequencer.updateTrack { $0.swing = v } }), range: 50...80).frame(width: 90)
                    ValueDial(title: "Prog chg", value: Binding(get: { sequencer.track.programChange }, set: { v in sequencer.updateTrack { $0.programChange = v } }), range: -1...127, format: { $0 < 0 ? "—" : "\($0 + 1)" }).frame(width: 90)
                    Spacer(minLength: 0)
                }
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        CapsLabel("MIDI output", size: 10, color: Theme.textPrimary)
                        PortPicker(selection: Binding(get: { sequencer.track.port }, set: { v in sequencer.updateTrack { $0.port = v } }))
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        CapsLabel("Pattern", size: 10, color: Theme.textPrimary)
                        HStack(alignment: .bottom, spacing: 8) {
                            VStack(alignment: .leading, spacing: 3) {
                                CapsLabel("Name", size: 9)
                                TextField("Pattern name", text: Binding(get: { sequencer.pattern.name }, set: { v in sequencer.pattern.name = v }))
                                    .textFieldStyle(.roundedBorder).frame(width: 110, height: 34)
                            }
                            ValueDial(title: "Master len", value: Binding(get: { sequencer.pattern.masterLength }, set: { v in sequencer.pattern.masterLength = v }), range: 1...64).frame(width: 100)
                            ValueDial(title: "Pat swing", value: Binding(get: { sequencer.pattern.swing }, set: { v in sequencer.pattern.swing = v }), range: 50...80).frame(width: 100)
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        CapsLabel("Key / scale", size: 10, color: Theme.textPrimary)
                        HStack(alignment: .bottom, spacing: 8) {
                            ValueDial(title: "Root", value: $sequencer.project.rootNote, range: 0...11, format: { MIDINote.names[$0] }).frame(width: 90)
                            ValueDial(title: "Scale", value: scaleBinding, range: 0...(Scale.all.count - 1), format: { Scale.all[$0].name }).frame(width: 150)
                            ValueDial(title: "Global transp", value: $sequencer.project.globalTranspose, range: -24...24).frame(width: 110)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(4)
        }
    }

    private var speedBinding: Binding<Int> {
        Binding(get: { TrackSpeed.allCases.firstIndex(of: sequencer.track.speed) ?? 2 },
                set: { v in sequencer.updateTrack { $0.speed = TrackSpeed.allCases[max(0, min(TrackSpeed.allCases.count - 1, v))] } })
    }

    private var dirBinding: Binding<Int> {
        Binding(get: { PlayDirection.allCases.firstIndex(of: sequencer.track.direction) ?? 0 },
                set: { v in sequencer.updateTrack { $0.direction = PlayDirection.allCases[max(0, min(PlayDirection.allCases.count - 1, v))] } })
    }

    private var scaleBinding: Binding<Int> {
        Binding(get: { Scale.all.firstIndex(where: { $0.name == sequencer.project.scaleName }) ?? 0 },
                set: { v in sequencer.project.scaleName = Scale.all[max(0, min(Scale.all.count - 1, v))].name })
    }
}

/// Picks "all enabled outputs" or a specific CoreMIDI destination.
struct PortPicker: View {
    @Binding var selection: MIDIPortID
    @EnvironmentObject var midi: MIDIService

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            portButton(title: "All enabled", id: .all)
            ForEach(midi.destinations) { d in
                portButton(title: d.name, id: MIDIPortID(String(d.id)))
            }
        }
        .frame(width: 180)
    }

    private func portButton(title: String, id: MIDIPortID) -> some View {
        Button(action: { selection = id; Haptics.tap() }) {
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .foregroundColor(selection == id ? .black : Theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(selection == id ? Theme.accent : Theme.panelRaised)
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }
}

/// Two modulation lanes per track.
struct LFOEditor: View {
    @EnvironmentObject var sequencer: SequencerRuntime

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(0..<2, id: \.self) { i in
                LFOLane(index: i)
            }
            VStack(alignment: .leading, spacing: 6) {
                CapsLabel("CC lanes", size: 10, color: Theme.textPrimary)
                ForEach(Array(sequencer.track.ccLanes.enumerated()), id: \.element.id) { (li, lane) in
                    HStack(spacing: 6) {
                        TextField("Name", text: Binding(get: { lane.name }, set: { v in sequencer.updateTrack { $0.ccLanes[li].name = v } }))
                            .textFieldStyle(.roundedBorder).frame(width: 90)
                        ValueDial(title: "CC", value: Binding(get: { lane.controller }, set: { v in sequencer.updateTrack { $0.ccLanes[li].controller = v } }), range: 0...127).frame(width: 80)
                        ValueDial(title: "Default", value: Binding(get: { lane.defaultValue }, set: { v in sequencer.updateTrack { $0.ccLanes[li].defaultValue = v } }), range: 0...127).frame(width: 80)
                        Button(action: { sequencer.updateTrack { $0.ccLanes.remove(at: li) } }) {
                            Image(systemName: "trash").font(.system(size: 11)).foregroundColor(Theme.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                ToggleButton(title: "SEND DEFAULTS ON PATTERN START", isOn: $sequencer.project.sendDefaultsOnPatternStart, color: Theme.secondary, height: 28)
                    .frame(width: 270)
            }
        }
        .padding(4)
    }
}

struct LFOLane: View {
    let index: Int
    @EnvironmentObject var sequencer: SequencerRuntime

    private var lfo: LFO { sequencer.track.lfos[safe: index] ?? LFO() }

    private func update(_ body: @escaping (inout LFO) -> Void) {
        sequencer.updateTrack { t in
            while t.lfos.count <= index { t.lfos.append(LFO()) }
            body(&t.lfos[index])
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                CapsLabel("LFO \(index + 1)", size: 10, color: Theme.textPrimary)
                ToggleButton(title: lfo.enabled ? "ON" : "OFF", isOn: Binding(get: { lfo.enabled }, set: { v in update { $0.enabled = v } }), color: Theme.green, height: 26).frame(width: 60)
            }
            HStack(spacing: 6) {
                ValueDial(title: "Shape", value: Binding(get: { LFOShape.allCases.firstIndex(of: lfo.shape) ?? 0 }, set: { v in update { $0.shape = LFOShape.allCases[max(0, min(LFOShape.allCases.count - 1, v))] } }), range: 0...(LFOShape.allCases.count - 1), format: { LFOShape.allCases[$0].label }).frame(width: 80)
                ValueDial(title: "Rate", value: Binding(get: { LFO.periods.firstIndex(where: { $0.ticks == lfo.periodTicks }) ?? 3 }, set: { v in update { $0.periodTicks = LFO.periods[max(0, min(LFO.periods.count - 1, v))].ticks } }), range: 0...(LFO.periods.count - 1), format: { LFO.periods[$0].label }).frame(width: 90)
                ValueDial(title: "Mode", value: Binding(get: { LFOMode.allCases.firstIndex(of: lfo.mode) ?? 0 }, set: { v in update { $0.mode = LFOMode.allCases[max(0, min(LFOMode.allCases.count - 1, v))] } }), range: 0...(LFOMode.allCases.count - 1), format: { LFOMode.allCases[$0].label }).frame(width: 80)
            }
            HStack(spacing: 6) {
                ValueDial(title: "Depth", value: Binding(get: { lfo.depth }, set: { v in update { $0.depth = v } }), range: -100...100, step: 5).frame(width: 80)
                ValueDial(title: "Center", value: Binding(get: { lfo.center }, set: { v in update { $0.center = v } }), range: 0...127).frame(width: 80)
                ValueDial(title: "Phase", value: Binding(get: { lfo.phase }, set: { v in update { $0.phase = v } }), range: 0...127).frame(width: 80)
            }
            HStack(spacing: 6) {
                ValueDial(title: "Dest", value: destBinding, range: 0...(destinations.count - 1), format: { self.destinations[$0].label }).frame(width: 140)
            }
        }
        .padding(6)
        .background(Theme.panelRaised.opacity(0.5))
        .cornerRadius(8)
    }

    private var destinations: [LFODestination] {
        var list: [LFODestination] = [.none, .pitchBend, .velocity]
        for lane in sequencer.track.ccLanes { list.append(.cc(lane.controller)) }
        for cc in [1, 2, 7, 10, 11, 71, 74] where !sequencer.track.ccLanes.contains(where: { $0.controller == cc }) { list.append(.cc(cc)) }
        return list
    }

    private var destBinding: Binding<Int> {
        Binding(get: { destinations.firstIndex(of: lfo.destination) ?? 0 },
                set: { v in let d = destinations; update { $0.destination = d[max(0, min(d.count - 1, v))] } })
    }
}

/// Playable keyboard (scale-aware) for auditioning and recording.
struct KeyboardView: View {
    @EnvironmentObject var sequencer: SequencerRuntime
    @EnvironmentObject var store: AppStore
    @State private var octave: Int = 3
    @State private var held: Set<Int> = []

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                CapsLabel("\(sequencer.track.name) · \(MIDINote.names[sequencer.project.rootNote]) \(sequencer.project.scaleName)", size: 10, color: Theme.textPrimary)
                Spacer()
                ValueDial(title: "Octave", value: $octave, range: -1...7).frame(width: 90)
                ToggleButton(title: "REC", isOn: $sequencer.recordEnabled, color: Theme.red, height: 30).frame(width: 60)
            }
            let notes = sequencer.track.isDrum ? Array((36 + (octave - 3) * 12)..<(52 + (octave - 3) * 12)) : scaleNotes
            HStack(spacing: 3) {
                ForEach(notes, id: \.self) { n in
                    KeyPad(note: n, isRoot: (n - sequencer.project.rootNote) % 12 == 0, held: held.contains(n)) { on in
                        if on { held.insert(n) } else { held.remove(n) }
                        sequencer.playNote(n, velocity: 100, on: on)
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(4)
        .onAppear { octave = store.profile.keyboardOctave }
    }

    private var scaleNotes: [Int] {
        let scale = sequencer.project.scale
        let root = sequencer.project.rootNote
        return (0..<16).map { scale.note(degree: $0, root: root, octave: octave) }.filter { $0 >= 0 && $0 <= 127 }
    }
}

struct KeyPad: View {
    let note: Int
    let isRoot: Bool
    let held: Bool
    let onPress: (Bool) -> Void

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(held ? Theme.accent : (isRoot ? Theme.panelRaised : Theme.panel))
            .overlay(
                VStack {
                    Spacer()
                    Text(MIDINote.name(note)).font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(held ? .black : Theme.textSecondary).padding(.bottom, 6)
                }
            )
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.line, lineWidth: 1))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in if !held { onPress(true); Haptics.tap() } }
                    .onEnded { _ in onPress(false) }
            )
    }
}

/// Chain / song arrangement.
struct ArrangeView: View {
    @EnvironmentObject var sequencer: SequencerRuntime
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var live: LiveSession
    @State private var showLibrary = false
    @State private var showSaveName = false
    @State private var saveName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Segmented(options: [(ArrangeMode.pattern, "LOOP PATTERN"), (.chain, "CHAIN"), (.song, "SONG")], selection: $sequencer.project.arrangeMode, height: 30)
                    .frame(width: 320)
                Spacer()
                PadButton(title: "COPY PATTERN", color: Theme.secondary, active: false, height: 30, fontSize: 10) { sequencer.copyPattern() }.frame(width: 120)
                PadButton(title: "DELETE PATTERN", color: Theme.red, active: false, height: 30, fontSize: 10) { sequencer.deletePattern(sequencer.currentPatternIndex) }.frame(width: 130)
                PadButton(title: "SAVE PROJECT", color: Theme.green, active: false, height: 30, fontSize: 10) { saveName = sequencer.project.name; showSaveName = true }.frame(width: 110)
                PadButton(title: "LOAD…", color: Theme.panelRaised, active: false, height: 30, fontSize: 10) { showLibrary = true }.frame(width: 70)
            }
            .alert("Save sequencer project", isPresented: $showSaveName) {
                TextField("Name", text: $saveName)
                Button("Save") {
                    sequencer.project.name = saveName
                    store.library.save(LibrarySnapshots.sequence(name: saveName, profile: store.profile, project: sequencer.project, song: live.song), name: saveName, category: .sequence)
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $showLibrary) {
                LibraryView(only: .sequence).environmentObject(store).environmentObject(live).environmentObject(store.library)
            }
            switch sequencer.project.arrangeMode {
            case .pattern:
                Text("The current pattern loops. Tap another pattern while playing to queue it for the next cycle.")
                    .font(.system(size: 12, design: .rounded)).foregroundColor(Theme.textSecondary)
            case .chain:
                CapsLabel("Chain (tap a pattern to append, tap an entry to remove)", size: 9)
                HStack(spacing: 4) {
                    ForEach(Array(sequencer.project.chain.enumerated()), id: \.offset) { (i, p) in
                        PadButton(title: sequencer.project.patterns[safe: p]?.name ?? "?", color: Theme.accent, active: true, height: 30, fontSize: 10) {
                            if sequencer.project.chain.count > 1 { sequencer.project.chain.remove(at: i) }
                        }
                        .frame(width: 60)
                    }
                    Spacer()
                }
                patternPalette { sequencer.project.chain.append($0) }
            case .song:
                CapsLabel("Song (pattern × repeats; tap entry to remove)", size: 9)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(sequencer.project.song.enumerated()), id: \.element.id) { (i, entry) in
                            VStack(spacing: 3) {
                                PadButton(title: sequencer.project.patterns[safe: entry.patternIndex]?.name ?? "?", color: Theme.accent, active: true, height: 30, fontSize: 10) {
                                    if sequencer.project.song.count > 1 { sequencer.project.song.remove(at: i) }
                                }
                                .frame(width: 70)
                                ValueDial(title: "×", value: Binding(get: { entry.repeats }, set: { v in sequencer.project.song[i].repeats = v }), range: 1...64).frame(width: 70)
                            }
                        }
                    }
                }
                patternPalette { sequencer.project.song.append(SongEntry(patternIndex: $0, repeats: 1)) }
            }
            Spacer()
        }
        .padding(4)
    }

    private func patternPalette(_ add: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(sequencer.project.patterns.enumerated()), id: \.element.id) { (i, p) in
                PadButton(title: "+ \(p.name)", color: Theme.panelRaised, active: false, height: 26, fontSize: 10) { add(i) }
                    .frame(width: 70)
            }
            Spacer()
        }
    }
}

/// Generative helpers: euclid, randomize, clear, copy track, send to Live.
struct ToolsView: View {
    @EnvironmentObject var sequencer: SequencerRuntime
    @EnvironmentObject var live: LiveSession
    @EnvironmentObject var store: AppStore
    @State private var pulses = 4
    @State private var rotation = 0
    @State private var density = 40
    @State private var liveTrack: Int = -1
    @State private var liveScene: Int = 0
    @State private var bars: Int = 2
    @State private var sendResult = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            generativeTools
            sendToLive
        }
        .padding(4)
    }

    private var sendToLive: some View {
        VStack(alignment: .leading, spacing: 6) {
            CapsLabel("Send pattern to a Live MIDI clip (conditions, probability, retrigs, swing and micro-timing get baked in)", size: 10, color: Theme.textPrimary)
            if live.midiTracks.isEmpty {
                Text(live.state == .connected || live.state.isSimulated ? "No MIDI tracks in the set. Add a MIDI track in Live (with an instrument) and reload." : "Connect to Live to send patterns as clips.")
                    .font(.system(size: 12, design: .rounded)).foregroundColor(Theme.textSecondary)
            } else {
                HStack(spacing: 8) {
                    ValueDial(title: "Live track", value: Binding(get: { max(0, live.midiTracks.firstIndex(where: { $0.index == liveTrack }) ?? 0) },
                                                                 set: { liveTrack = live.midiTracks[max(0, min(live.midiTracks.count - 1, $0))].index }),
                              range: 0...max(0, live.midiTracks.count - 1), format: { i in live.midiTracks[safeIndex: i]?.name ?? "?" }).frame(width: 170)
                    ValueDial(title: "Scene", value: $liveScene, range: 0...max(0, live.song.scenes.count - 1), format: { i in live.song.scenes[safeIndex: i]?.name ?? "\(i + 1)" }).frame(width: 150)
                    ValueDial(title: "Bars", value: $bars, range: 1...16, format: { "\($0)" }).frame(width: 80)
                    PadButton(title: "SEND \(sequencer.track.name.uppercased())", color: Theme.green, active: true, height: 34, fontSize: 11) { send(all: false) }.frame(width: 150)
                    PadButton(title: "SEND ALL (BY NAME)", color: Theme.secondary, active: false, height: 34, fontSize: 10) { send(all: true) }.frame(width: 150)
                }
                if !sendResult.isEmpty {
                    Text(sendResult).font(.system(size: 11, design: .rounded)).foregroundColor(Theme.textSecondary)
                }
            }
        }
        .onAppear { if liveTrack < 0, let first = live.midiTracks.first { liveTrack = first.index } }
    }

    private func send(all: Bool) {
        let notes = PatternBounce.render(project: sequencer.project, patternIndex: sequencer.currentPatternIndex, bars: bars, seed: UInt64(Date().timeIntervalSince1970))
        let length = Double(bars) * PatternBounce.beatsPerBar
        var results: [String] = []
        if all {
            for (i, t) in sequencer.pattern.tracks.enumerated() {
                guard let target = live.midiTracks.first(where: { $0.name.caseInsensitiveCompare(t.name) == .orderedSame || store.profile.displayName(forTrack: $0.name).caseInsensitiveCompare(t.name) == .orderedSame }) else { continue }
                results.append(live.writeClip(track: target.index, scene: liveScene, lengthBeats: length, name: "\(sequencer.pattern.name) \(t.name)", notes: notes[i] ?? []))
            }
            if results.isEmpty { results.append("No Live MIDI track names match the sequencer tracks (\(sequencer.pattern.tracks.map { $0.name }.joined(separator: ", "))).") }
        } else {
            let target = liveTrack >= 0 ? liveTrack : (live.midiTracks.first?.index ?? 0)
            results.append(live.writeClip(track: target, scene: liveScene, lengthBeats: length, name: "\(sequencer.pattern.name) \(sequencer.track.name)", notes: notes[sequencer.selectedTrack] ?? []))
        }
        sendResult = results.joined(separator: " · ")
        store.lastImportSummary = sendResult
        Haptics.launch()
    }

    private var generativeTools: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                CapsLabel("Euclid", size: 10, color: Theme.textPrimary)
                HStack(spacing: 6) {
                    ValueDial(title: "Pulses", value: $pulses, range: 0...64).frame(width: 90)
                    ValueDial(title: "Rotate", value: $rotation, range: 0...63).frame(width: 90)
                    PadButton(title: "APPLY", color: Theme.accent, active: true, height: 34) { sequencer.applyEuclid(pulses: pulses, rotation: rotation) }.frame(width: 80)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                CapsLabel("Random", size: 10, color: Theme.textPrimary)
                HStack(spacing: 6) {
                    ValueDial(title: "Density %", value: $density, range: 0...100, step: 5).frame(width: 100)
                    PadButton(title: "RANDOMIZE", color: Theme.secondary, active: true, height: 34) { sequencer.randomizeTrack(density: density) }.frame(width: 110)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                CapsLabel("Track", size: 10, color: Theme.textPrimary)
                HStack(spacing: 6) {
                    PadButton(title: "CLEAR", color: Theme.red, active: false, height: 34) { sequencer.clearTrack() }.frame(width: 80)
                    PadButton(title: "SHIFT ←", color: Theme.panelRaised, active: false, height: 34) { shift(-1) }.frame(width: 80)
                    PadButton(title: "SHIFT →", color: Theme.panelRaised, active: false, height: 34) { shift(1) }.frame(width: 80)
                    PadButton(title: "VEL ±", color: Theme.panelRaised, active: false, height: 34) { humanize() }.frame(width: 80)
                }
            }
        }
    }

    private func shift(_ by: Int) {
        sequencer.updateTrack { t in
            let n = t.length
            guard n > 1 else { return }
            let slice = Array(t.steps[0..<n])
            for i in 0..<n { t.steps[(i + by + n) % n] = slice[i] }
        }
    }

    private func humanize() {
        sequencer.updateTrack { t in
            for i in 0..<t.length where t.steps[i].isOn {
                t.steps[i].velocity = max(1, min(127, t.steps[i].velocity + Int.random(in: -12...12)))
                t.steps[i].micro = max(-3, min(3, Int.random(in: -2...2)))
            }
        }
    }
}
