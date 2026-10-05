import SwiftUI

/// CONTROL: user-built pages of knobs, faders, buttons and XY pads mapped to Live parameters or MIDI.
struct ControlView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var live: LiveSession
    @EnvironmentObject var control: ControlRuntime
    @State private var pageIndex = 0
    @State private var editing = false
    @State private var editingWidget: ControlWidget? = nil
    @State private var showAddMenu = false
    @State private var renamingPage = false
    @State private var pageName = ""

    private var pages: [ControlPage] { store.profile.controlPages }
    private var page: ControlPage? { pages[safeIndex: pageIndex] }

    var body: some View {
        VStack(spacing: 8) {
            header
            if let page {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 10) {
                        ForEach(Array(ControlLayout.rows(page.widgets).enumerated()), id: \.offset) { (_, row) in
                            HStack(alignment: .top, spacing: 10) {
                                ForEach(row) { widget in
                                    ControlWidgetView(widget: widget, editing: editing, onEdit: { editingWidget = widget })
                                        .frame(maxWidth: .infinity)
                                        .frame(width: nil)
                                        .layoutPriority(Double(widget.width))
                                }
                                if ControlLayout.rowUnits(row) < ControlPage.columns {
                                    Spacer(minLength: 0).layoutPriority(Double(ControlPage.columns - ControlLayout.rowUnits(row)))
                                }
                            }
                        }
                        if page.widgets.isEmpty {
                            Text("Empty page. Tap EDIT, then ADD to place knobs, faders, buttons or an XY pad.")
                                .font(.system(size: 13, design: .rounded)).foregroundColor(Theme.textSecondary).padding(30)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onAppear { control.prepare(page: page) }
                .onChange(of: page.widgets) { _ in control.prepare(page: page) }
                .onChange(of: live.song.tracks.count) { _ in control.prepare(page: page) }
            } else {
                Spacer()
                PadButton(title: "CREATE FIRST PAGE", color: Theme.accent, active: true, height: 44) { addPage() }.frame(width: 220)
                Spacer()
            }
        }
        .padding(8)
        .sheet(item: $editingWidget) { w in
            WidgetEditor(widget: w, onSave: { updated in updateWidget(updated) }, onDelete: { deleteWidget(w.id) })
                .environmentObject(store).environmentObject(live).environmentObject(store.midi)
        }
        .confirmationDialog("Add control", isPresented: $showAddMenu, titleVisibility: .visible) {
            ForEach(ControlWidgetKind.allCases) { kind in
                Button(kind.label) { addWidget(kind) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear { control.seed(from: pages) }
    }

    private var header: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(pages.enumerated()), id: \.element.id) { (i, p) in
                        PadButton(title: p.name, color: Theme.accent, active: i == pageIndex, height: 28, fontSize: 11) { pageIndex = i }
                            .frame(width: 110)
                    }
                    if editing {
                        PadButton(title: "+ PAGE", color: Theme.panelRaised, active: false, height: 28, fontSize: 10) { addPage() }.frame(width: 70)
                    }
                }
            }
            Spacer()
            if !control.lastSent.isEmpty {
                Text(control.lastSent).font(.system(size: 10, design: .monospaced)).foregroundColor(Theme.textSecondary).lineLimit(1)
            }
            if !control.unresolved.isEmpty {
                CapsLabel("\(control.unresolved.count) unassigned in this set", size: 9, color: Theme.yellow)
            }
            if editing {
                PadButton(title: "RENAME", color: Theme.panelRaised, active: false, height: 28, fontSize: 10) {
                    pageName = page?.name ?? ""
                    renamingPage = true
                }.frame(width: 76)
                PadButton(title: "DELETE PAGE", color: Theme.red, active: false, height: 28, fontSize: 10) { deletePage() }.frame(width: 100)
                PadButton(title: "ADD", color: Theme.secondary, active: true, height: 28, fontSize: 11) { showAddMenu = true }.frame(width: 70)
            }
            PadButton(title: editing ? "DONE" : "EDIT", color: Theme.yellow, active: editing, height: 28, fontSize: 11) { editing.toggle() }.frame(width: 70)
        }
        .alert("Page name", isPresented: $renamingPage) {
            TextField("Name", text: $pageName)
            Button("Save") { if pageIndex < store.profile.controlPages.count { store.profile.controlPages[pageIndex].name = pageName } }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func addPage() {
        store.profile.controlPages.append(ControlPage(name: "Page \(store.profile.controlPages.count + 1)"))
        pageIndex = store.profile.controlPages.count - 1
    }

    private func deletePage() {
        guard pageIndex < store.profile.controlPages.count else { return }
        store.profile.controlPages.remove(at: pageIndex)
        pageIndex = max(0, min(pageIndex, store.profile.controlPages.count - 1))
    }

    private func addWidget(_ kind: ControlWidgetKind) {
        guard pageIndex < store.profile.controlPages.count else { return }
        let n = store.profile.controlPages[pageIndex].widgets.count + 1
        var w = ControlWidget(name: "\(kind.label) \(n)", kind: kind, colorHex: ["#F28C28", "#F2D33C", "#7ED957", "#3CC8E6", "#8FB4DD", "#9A6BFF", "#E05A9A"][n % 7])
        if kind == .knob || kind == .fader { w.value = 0.5 }
        store.profile.controlPages[pageIndex].widgets.append(w)
        editingWidget = w
    }

    private func updateWidget(_ w: ControlWidget) {
        guard pageIndex < store.profile.controlPages.count,
              let i = store.profile.controlPages[pageIndex].widgets.firstIndex(where: { $0.id == w.id }) else { return }
        store.profile.controlPages[pageIndex].widgets[i] = w
    }

    private func deleteWidget(_ id: UUID) {
        guard pageIndex < store.profile.controlPages.count else { return }
        store.profile.controlPages[pageIndex].widgets.removeAll(where: { $0.id == id })
    }
}

extension ControlLayout {
    static func rowUnits(_ row: [ControlWidget]) -> Int {
        row.reduce(0) { $0 + max(1, min(ControlPage.columns, $1.width)) }
    }
}

/// One widget (fader / knob / button / toggle / XY) with its label.
struct ControlWidgetView: View {
    let widget: ControlWidget
    let editing: Bool
    let onEdit: () -> Void
    @EnvironmentObject var control: ControlRuntime
    @EnvironmentObject var live: LiveSession

    private var color: Color { Color(hex: widget.colorHex) }
    private var height: CGFloat { widget.kind.isTall ? 170 : 96 }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                body(for: widget.kind)
                if editing {
                    RoundedRectangle(cornerRadius: 10).stroke(Theme.yellow, lineWidth: 2)
                    VStack {
                        HStack {
                            Spacer()
                            Button(action: onEdit) {
                                Image(systemName: "slider.horizontal.3").font(.system(size: 12, weight: .bold)).foregroundColor(.black)
                                    .frame(width: 28, height: 28).background(Theme.yellow).cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                    }
                    .padding(4)
                }
            }
            .frame(height: height)
            Text(widget.name)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(Theme.textPrimary)
                .lineLimit(1)
            Text(widget.target.label + (widget.kind == .xy ? " / " + widget.targetY.label : ""))
                .font(.system(size: 8, design: .rounded))
                .foregroundColor(unresolved ? Theme.yellow : Theme.textSecondary)
                .lineLimit(1)
        }
    }

    private var unresolved: Bool { control.unresolved.contains(widget.id) }

    @ViewBuilder
    private func body(for kind: ControlWidgetKind) -> some View {
        switch kind {
        case .fader:
            VerticalFader(value: Binding(get: { control.value(for: widget) }, set: { control.set(widget, value: $0) }), color: color, meter: nil,
                          label: percent(control.value(for: widget)))
                .disabled(editing)
        case .knob:
            KnobView(value: Binding(get: { control.value(for: widget) }, set: { control.set(widget, value: $0) }), color: color)
                .disabled(editing)
        case .button, .toggle:
            let on = control.value(for: widget) >= 0.5
            RoundedRectangle(cornerRadius: 10)
                .fill(on ? color : color.opacity(0.3))
                .overlay(Text(widget.kind == .toggle ? (on ? "ON" : "OFF") : "PUSH")
                            .font(.system(size: 16, weight: .heavy, design: .rounded)).foregroundColor(on ? .black : Theme.textPrimary))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1))
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { _ in if !pressed && !editing { pressed = true; Haptics.tap(); control.press(widget, down: true) } }
                    .onEnded { _ in if pressed { pressed = false; control.press(widget, down: false) } })
        case .xy:
            XYPadView(x: Binding(get: { control.value(for: widget) }, set: { control.set(widget, value: $0) }),
                      y: Binding(get: { control.value(for: widget, axisY: true) }, set: { control.set(widget, value: $0, axisY: true) }), color: color)
                .disabled(editing)
        }
    }

    @State private var pressed = false

    private func percent(_ v: Double) -> String { "\(Int((v * 100).rounded()))" }
}

/// Rotary control: drag up/down.
struct KnobView: View {
    @Binding var value: Double
    var color: Color
    @State private var startValue: Double? = nil

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            ZStack {
                Circle().stroke(color.opacity(0.22), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: CGFloat(max(0.001, min(1, value))) * 0.75)
                    .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(135))
                Text("\(Int((value * 100).rounded()))")
                    .font(.system(size: size * 0.22, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.textPrimary)
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in
                    if startValue == nil { startValue = value }
                    value = max(0, min(1, (startValue ?? value) - Double(g.translation.height) / 150.0))
                }
                .onEnded { _ in startValue = nil })
        }
    }
}

/// Two-axis pad.
struct XYPadView: View {
    @Binding var x: Double
    @Binding var y: Double
    var color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(color.opacity(0.18))
                RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1)
                Path { p in
                    p.move(to: CGPoint(x: geo.size.width / 2, y: 0)); p.addLine(to: CGPoint(x: geo.size.width / 2, y: geo.size.height))
                    p.move(to: CGPoint(x: 0, y: geo.size.height / 2)); p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height / 2))
                }
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                Circle().fill(color).frame(width: 26, height: 26)
                    .position(x: CGFloat(x) * geo.size.width, y: (1 - CGFloat(y)) * geo.size.height)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                x = max(0, min(1, Double(g.location.x / geo.size.width)))
                y = max(0, min(1, 1 - Double(g.location.y / geo.size.height)))
            })
        }
    }
}

/// Edits a widget: name, colour, size, range and target.
struct WidgetEditor: View {
    @State var widget: ControlWidget
    let onSave: (ControlWidget) -> Void
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Control") {
                    TextField("Name", text: $widget.name)
                    Picker("Kind", selection: $widget.kind) {
                        ForEach(ControlWidgetKind.allCases) { k in Text(k.label).tag(k) }
                    }
                    TextField("Colour (hex)", text: $widget.colorHex)
                    Stepper("Width: \(widget.width) / \(ControlPage.columns)", value: $widget.width, in: 1...ControlPage.columns)
                    HStack {
                        Text("Range"); Spacer()
                        Text("\(Int(widget.minimum * 100))% – \(Int(widget.maximum * 100))%").foregroundColor(.secondary)
                    }
                    Slider(value: $widget.minimum, in: 0...1, step: 0.01)
                    Slider(value: $widget.maximum, in: 0...1, step: 0.01)
                }
                Section(widget.kind == .xy ? "Target X" : "Target") {
                    TargetPicker(target: $widget.target, allowNotes: widget.kind == .button || widget.kind == .toggle)
                }
                if widget.kind == .xy {
                    Section("Target Y") {
                        TargetPicker(target: $widget.targetY, allowNotes: false)
                    }
                }
                Section {
                    Button("Delete control", role: .destructive) { onDelete(); dismiss() }
                }
            }
            .navigationTitle(widget.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { onSave(widget); dismiss() } }
            }
        }
    }
}

enum TargetMode: String, CaseIterable, Identifiable {
    case none = "None", live = "Live parameter", cc = "MIDI CC", note = "MIDI note"
    var id: String { rawValue }
}

/// Picks a Live parameter (track → device → parameter) or a MIDI message.
struct TargetPicker: View {
    @Binding var target: ControlTarget
    let allowNotes: Bool
    @EnvironmentObject var live: LiveSession
    @EnvironmentObject var midi: MIDIService
    @State private var mode: TargetMode = .none
    @State private var trackIndex: Int = 0
    @State private var deviceIndex: Int = 0
    @State private var parameterIndex: Int = 0
    @State private var channel: Int = 1
    @State private var number: Int = 1
    @State private var port: MIDIPortID = .all

    var body: some View {
        Group {
            Picker("Type", selection: $mode) {
                ForEach(TargetMode.allCases.filter { allowNotes || $0 != .note }) { m in Text(m.rawValue).tag(m) }
            }
            .onChange(of: mode) { _ in commit() }
            switch mode {
            case .none:
                EmptyView()
            case .live:
                livePickers
            case .cc, .note:
                Stepper("Channel \(channel)", value: $channel, in: 1...16).onChange(of: channel) { _ in commit() }
                Stepper(mode == .cc ? "CC \(number)" : "Note \(MIDINote.name(number))", value: $number, in: 0...127).onChange(of: number) { _ in commit() }
                Picker("Port", selection: $port) {
                    Text("All enabled outputs").tag(MIDIPortID.all)
                    ForEach(midi.destinations) { d in Text(d.name).tag(MIDIPortID(String(d.id))) }
                }
                .onChange(of: port) { _ in commit() }
                Text("In Live: MIDI map mode → move this control → click the parameter. Works for hardware too.")
                    .font(.footnote).foregroundColor(.secondary)
            }
        }
        .onAppear(perform: load)
    }

    @ViewBuilder
    private var livePickers: some View {
        if live.song.tracks.isEmpty {
            Text("Connect to Live (or use demo mode) to pick a parameter.").font(.footnote).foregroundColor(.secondary)
        } else {
            Picker("Track", selection: $trackIndex) {
                ForEach(live.song.tracks) { t in Text(t.name).tag(t.index) }
            }
            .onChange(of: trackIndex) { _ in deviceIndex = 0; parameterIndex = 0; requestParams(); commit() }
            let devices = live.song.track(trackIndex)?.devices ?? []
            if devices.isEmpty {
                Text("No devices on this track.").font(.footnote).foregroundColor(.secondary)
            } else {
                Picker("Device", selection: $deviceIndex) {
                    ForEach(devices) { d in Text(d.name).tag(d.index) }
                }
                .onChange(of: deviceIndex) { _ in parameterIndex = 0; requestParams(); commit() }
                let params = devices[safeIndex: deviceIndex]?.parameters ?? []
                if params.isEmpty {
                    Text("Loading parameters…").font(.footnote).foregroundColor(.secondary)
                } else {
                    Picker("Parameter", selection: $parameterIndex) {
                        ForEach(params, id: \.index) { p in Text(p.name).tag(p.index) }
                    }
                    .onChange(of: parameterIndex) { _ in commit() }
                }
            }
            Button("Use the device selected in Live") {
                live.requestSelectedDevice { t, d in
                    trackIndex = t; deviceIndex = d; parameterIndex = 0
                    requestParams(); commit()
                }
            }
            if let sel = live.selectedDeviceInLive {
                Text("Live selection: \(live.song.track(sel.track)?.name ?? "?") · \(live.song.track(sel.track)?.devices[safeIndex: sel.device]?.name ?? "?")")
                    .font(.footnote).foregroundColor(.secondary)
            }
        }
    }

    private func requestParams() {
        guard live.song.track(trackIndex)?.devices[safeIndex: deviceIndex] != nil else { return }
        live.requestDeviceParameters(track: trackIndex, device: deviceIndex)
    }

    private func load() {
        switch target {
        case .none: mode = .none
        case .liveParameter(let tn, let ti, let dn, let di, let pn, let pi):
            mode = .live
            let song = live.song
            trackIndex = song.tracks.first(where: { $0.name.caseInsensitiveCompare(tn) == .orderedSame })?.index ?? ti
            deviceIndex = song.track(trackIndex)?.devices.first(where: { $0.name.caseInsensitiveCompare(dn) == .orderedSame })?.index ?? di
            parameterIndex = song.track(trackIndex)?.devices[safeIndex: deviceIndex]?.parameterIndex(named: pn) ?? pi
            requestParams()
        case .midiCC(let ch, let cc, let p): mode = .cc; channel = ch + 1; number = cc; port = p
        case .midiNote(let ch, let n, let p): mode = .note; channel = ch + 1; number = n; port = p
        }
    }

    private func commit() {
        switch mode {
        case .none: target = .none
        case .live:
            guard let t = live.song.track(trackIndex) else { target = .none; return }
            let d = t.devices[safeIndex: deviceIndex]
            let p = d?.parameters[safeIndex: parameterIndex]
            target = .liveParameter(track: t.name, trackIndex: t.index, device: d?.name ?? "", deviceIndex: deviceIndex,
                                    parameter: p?.name ?? "", parameterIndex: parameterIndex)
        case .cc: target = .midiCC(channel: channel - 1, controller: number, port: port)
        case .note: target = .midiNote(channel: channel - 1, note: number, port: port)
        }
    }
}
