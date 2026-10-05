import SwiftUI
import UniformTypeIdentifiers

/// CONTROL: user-built pages of knobs, faders, buttons and XY pads mapped to Live parameters or MIDI.
/// Shows 1, 2, 3 or 4 pages at once so macros from different groups can be played together without editing.
struct ControlView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var live: LiveSession
    @EnvironmentObject var control: ControlRuntime
    @State private var panelPages: [Int] = [0, 1, 2, 3]
    @State private var editing = false

    static let maxPanels = 4

    private var pages: [ControlPage] { store.profile.controlPages }
    private var panelCount: Int { pages.isEmpty ? 1 : max(1, min(ControlView.maxPanels, store.controlPanels)) }
    /// With 3-4 pages on screen each panel is half as wide and half as tall: use smaller widgets and compact headers.
    private var compact: Bool { panelCount >= 3 }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                CapsLabel("PAGES", size: 9, color: Theme.textSecondary)
                Segmented(options: [(1, "1"), (2, "2"), (3, "3"), (4, "4")], selection: $store.controlPanels, height: 30).frame(width: 150)
                Spacer()
                if !control.lastSent.isEmpty {
                    Text(control.lastSent).font(.system(size: 10, design: .monospaced)).foregroundColor(Theme.textSecondary).lineLimit(1)
                }
                if !control.unresolved.isEmpty {
                    CapsLabel("\(control.unresolved.count) unassigned in this set", size: 9, color: Theme.yellow)
                }
                PadButton(title: editing ? "DONE" : "EDIT", color: Theme.yellow, active: editing, height: 30, fontSize: 11) { editing.toggle() }.frame(width: 70)
            }
            switch panelCount {
            case 2:
                HStack(spacing: 10) {
                    panel(0)
                    Divider().background(Theme.line)
                    panel(1)
                }
            case 3:
                VStack(spacing: 10) {
                    HStack(spacing: 10) { panel(0); Divider().background(Theme.line); panel(1) }
                    Divider().background(Theme.line)
                    panel(2)
                }
            case 4:
                VStack(spacing: 10) {
                    HStack(spacing: 10) { panel(0); Divider().background(Theme.line); panel(1) }
                    Divider().background(Theme.line)
                    HStack(spacing: 10) { panel(2); Divider().background(Theme.line); panel(3) }
                }
            default:
                panel(0)
            }
        }
        .padding(8)
        .onAppear {
            control.seed(from: pages)
            let saved = UserDefaults.standard.integer(forKey: "stagedeck.controlPanels")
            if saved >= 1 && saved <= ControlView.maxPanels && store.controlPanels == 1 { store.controlPanels = saved }
        }
    }

    private func panel(_ i: Int) -> some View {
        ControlPagePanel(pageIndex: binding(i), editing: editing, compact: compact)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func binding(_ panel: Int) -> Binding<Int> {
        Binding(get: {
            let v = panelPages.indices.contains(panel) ? panelPages[panel] : panel
            return min(max(0, v), max(0, pages.count - 1))
        }, set: { v in
            while panelPages.count <= panel { panelPages.append(panelPages.count) }
            panelPages[panel] = v
        })
    }
}

/// One page with its tabs and (in edit mode) its add / rename / delete controls.
struct ControlPagePanel: View {
    @Binding var pageIndex: Int
    let editing: Bool
    var compact: Bool = false
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var live: LiveSession
    @EnvironmentObject var control: ControlRuntime
    @State private var editingWidget: ControlWidget? = nil
    @State private var showAddMenu = false
    @State private var showAddFromSet = false
    @State private var renamingPage = false
    @State private var pageName = ""
    /// Widget being dragged to a new place (edit mode).
    @State private var draggingWidget: UUID? = nil

    private var pages: [ControlPage] { store.profile.controlPages }
    private var page: ControlPage? { pages[safeIndex: pageIndex] }

    var body: some View {
        VStack(spacing: 6) {
            header
            if let page {
                let rows = ControlLayout.rows(page.widgets)
                let gutter: CGFloat = compact ? 18 : 32
                let gap: CGFloat = compact ? 6 : 10
                GeometryReader { geo in
                // Fixed 8-column grid: every control gets exactly its width; empty cells stay empty (no hit area).
                let unit = max(20, (geo.size.width - 2 * gutter - 7 * gap) / 8)
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 14) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { (ri, row) in
                            HStack(alignment: .top, spacing: gap) {
                                ForEach(row) { widget in
                                    let units = CGFloat(max(1, min(ControlPage.columns, widget.width)))
                                    ControlWidgetView(widget: widget, editing: editing, compact: compact, onEdit: { editingWidget = widget })
                                        .frame(width: unit * units + gap * (units - 1))
                                        .opacity(draggingWidget == widget.id ? 0.35 : 1)
                                        .modifier(ReorderDrag(enabled: editing, id: widget.id, dragging: $draggingWidget,
                                                              move: { from, to in moveWidget(from, before: to) }))
                                }
                                Spacer(minLength: 0)
                            }
                            .id(ri)
                        }
                        if page.widgets.isEmpty {
                            Text(editing ? "Empty page. Use ADD (one control) or ADD FROM SET (pick macros from any track or group)." : "Empty page. Tap EDIT to add controls.")
                                .font(.system(size: 13, design: .rounded)).foregroundColor(Theme.textSecondary).padding(30)
                        }
                    }
                    .padding(.vertical, 6)
                    // Free gutters on both sides: drag there (or on any label) to scroll; knobs and faders keep their own drag.
                    .padding(.horizontal, gutter)
                }
                }
                .onAppear { control.prepare(page: page) }
                .onChange(of: page.widgets) { _ in control.prepare(page: page) }
                .onChange(of: live.song.deviceSignature) { _ in control.prepare(page: page) }
                .onChange(of: live.state) { _ in control.prepare(page: page) }
            } else {
                Spacer()
                PadButton(title: "CREATE FIRST PAGE", color: Theme.accent, active: true, height: 44) { addPage() }.frame(width: 220)
                Spacer()
            }
        }
        .sheet(item: $editingWidget) { w in
            WidgetEditor(widget: w, pageIndex: pageIndex, onSave: { updated in updateWidget(updated) }, onDelete: { deleteWidget(w.id) })
                .environmentObject(store).environmentObject(live).environmentObject(store.midi)
        }
        .sheet(isPresented: $showAddFromSet) {
            AddFromSetSheet(pageIndex: pageIndex).environmentObject(store).environmentObject(live)
        }
        .confirmationDialog("Add control", isPresented: $showAddMenu, titleVisibility: .visible) {
            ForEach(ControlWidgetKind.allCases) { kind in
                Button(kind.label) { addWidget(kind) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Page name", isPresented: $renamingPage) {
            TextField("Name", text: $pageName)
            Button("Save") { if pageIndex < store.profile.controlPages.count { store.profile.controlPages[pageIndex].name = pageName } }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(pages.enumerated()), id: \.element.id) { (i, p) in
                        PadButton(title: p.name, color: Theme.accent, active: i == pageIndex, height: 28, fontSize: compact ? 10 : 11) { pageIndex = i }
                            .frame(width: compact ? 84 : 104)
                    }
                    if editing {
                        PadButton(title: "+ PAGE", color: Theme.panelRaised, active: false, height: 28, fontSize: 10) { addPage() }.frame(width: 64)
                    }
                }
            }
            if editing && compact {
                PadButton(title: "+ SET", color: Theme.green, active: true, height: 28, fontSize: 10) { showAddFromSet = true }.frame(width: 56)
                PadButton(title: "ADD", color: Theme.secondary, active: true, height: 28, fontSize: 11) { showAddMenu = true }.frame(width: 50)
                Menu {
                    Button("Rename page") { pageName = page?.name ?? ""; renamingPage = true }
                    Button("Delete page", role: .destructive) { deletePage() }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 14, weight: .bold)).foregroundColor(Theme.textPrimary)
                        .frame(width: 32, height: 28).background(Theme.panelRaised).cornerRadius(8)
                }
            } else if editing {
                PadButton(title: "RENAME", color: Theme.panelRaised, active: false, height: 28, fontSize: 10) {
                    pageName = page?.name ?? ""
                    renamingPage = true
                }.frame(width: 70)
                PadButton(title: "DELETE", color: Theme.red, active: false, height: 28, fontSize: 10) { deletePage() }.frame(width: 66)
                PadButton(title: "ADD FROM SET", color: Theme.green, active: true, height: 28, fontSize: 10) { showAddFromSet = true }.frame(width: 110)
                PadButton(title: "ADD", color: Theme.secondary, active: true, height: 28, fontSize: 11) { showAddMenu = true }.frame(width: 56)
            }
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

    /// Drag-to-reorder: puts `from` where `to` is (the rest shifts).
    private func moveWidget(_ from: UUID, before to: UUID) {
        guard pageIndex < store.profile.controlPages.count else { return }
        var ws = store.profile.controlPages[pageIndex].widgets
        guard let i = ws.firstIndex(where: { $0.id == from }), let j = ws.firstIndex(where: { $0.id == to }), i != j else { return }
        let w = ws.remove(at: i)
        ws.insert(w, at: j)
        store.profile.controlPages[pageIndex].widgets = ws
    }
}

/// Long-press and drag a control onto another one to swap places (EDIT mode only).
struct ReorderDrag: ViewModifier {
    let enabled: Bool
    let id: UUID
    @Binding var dragging: UUID?
    let move: (UUID, UUID) -> Void

    func body(content: Content) -> some View {
        if enabled {
            content
                .onDrag {
                    dragging = id
                    return NSItemProvider(object: id.uuidString as NSString)
                }
                .onDrop(of: [UTType.text], delegate: WidgetDropDelegate(target: id, dragging: $dragging, move: move))
        } else {
            content
        }
    }
}

struct WidgetDropDelegate: DropDelegate {
    let target: UUID
    @Binding var dragging: UUID?
    let move: (UUID, UUID) -> Void

    func dropEntered(info: DropInfo) {
        guard let from = dragging, from != target else { return }
        withAnimation(.easeInOut(duration: 0.15)) { move(from, target) }
    }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool { dragging = nil; return true }
}

extension ControlLayout {
    static func rowUnits(_ row: [ControlWidget]) -> Int {
        row.reduce(0) { $0 + max(1, min(ControlPage.columns, $1.width)) }
    }
}

/// Pick any parameters of any track or group in the loaded set and add them as controls in one go.
struct AddFromSetSheet: View {
    let pageIndex: Int
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var live: LiveSession
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []   // "track:device:param"
    @State private var kind: ControlWidgetKind = .knob
    @State private var filter = ""
    @State private var expanded: Set<Int> = []

    var body: some View {
        NavigationStack {
            Form {
                if live.song.tracks.isEmpty {
                    Text("Load a set first: connect to Live, import an .als, or use demo mode.").foregroundColor(.secondary)
                } else {
                    Section {
                        Picker("Add as", selection: $kind) {
                            Text("Knobs").tag(ControlWidgetKind.knob)
                            Text("Faders").tag(ControlWidgetKind.fader)
                        }
                        .pickerStyle(.segmented)
                        TextField("Filter by track, device or macro name", text: $filter).autocorrectionDisabled()
                        Text("\(selected.count) selected").font(.footnote).foregroundColor(.secondary)
                    }
                    ForEach(live.song.tracks) { track in
                        let devices = track.devices.filter { !$0.parameters.isEmpty || $0.className.hasSuffix("GroupDevice") || $0.isAutoFilter }
                        if !devices.isEmpty, matches(track: track) {
                            Section {
                                Button(action: { toggleExpanded(track) }) {
                                    HStack {
                                        RoundedRectangle(cornerRadius: 4).fill(Color(track.color)).frame(width: 12, height: 12)
                                        Text(track.isGroup ? "[GROUP] " + track.name : track.name).font(.system(size: 15, weight: .semibold))
                                        Spacer()
                                        Text("\(devices.count) device\(devices.count == 1 ? "" : "s")").foregroundColor(.secondary).font(.footnote)
                                        Image(systemName: expanded.contains(track.index) ? "chevron.down" : "chevron.right").foregroundColor(.secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                                if expanded.contains(track.index) || !filter.isEmpty {
                                    ForEach(devices) { device in
                                        DeviceParameterRows(track: track, device: device, filter: filter, selected: $selected)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add from set")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add \(selected.count)") { add(); dismiss() }.disabled(selected.isEmpty)
                }
            }
        }
    }

    private func matches(track: LiveTrack) -> Bool {
        guard !filter.isEmpty else { return true }
        let f = filter.lowercased()
        if track.name.lowercased().contains(f) { return true }
        return track.devices.contains { d in d.name.lowercased().contains(f) || d.parameters.contains { $0.name.lowercased().contains(f) } }
    }

    private func toggleExpanded(_ track: LiveTrack) {
        if expanded.contains(track.index) { expanded.remove(track.index) } else {
            expanded.insert(track.index)
            for d in track.devices where d.parameters.isEmpty { live.requestDeviceParameters(track: track.index, device: d.index) }
        }
    }

    private func add() {
        guard pageIndex < store.profile.controlPages.count else { return }
        var widgets: [ControlWidget] = []
        for track in live.song.tracks {
            for device in track.devices {
                for p in device.parameters where selected.contains("\(track.index):\(device.index):\(p.index)") {
                    var w = ControlWidget(name: p.name, kind: kind, colorHex: track.color.hexString)
                    w.target = .liveParameter(track: track.name, trackIndex: track.index, device: device.name, deviceIndex: device.index, parameter: p.name, parameterIndex: p.index)
                    w.value = p.normalized
                    widgets.append(w)
                }
            }
        }
        store.profile.controlPages[pageIndex].widgets.append(contentsOf: widgets)
    }
}

struct DeviceParameterRows: View {
    let track: LiveTrack
    let device: LiveDevice
    let filter: String
    @Binding var selected: Set<String>

    var body: some View {
        let params = device.parameters.filter { $0.name != "Device On" && (filter.isEmpty || $0.name.lowercased().contains(filter.lowercased()) || device.name.lowercased().contains(filter.lowercased()) || track.name.lowercased().contains(filter.lowercased())) }
        if params.isEmpty {
            Text("\(device.name): loading parameters…").font(.footnote).foregroundColor(.secondary)
        } else {
            ForEach(params, id: \.index) { p in
                let key = "\(track.index):\(device.index):\(p.index)"
                Toggle(isOn: Binding(get: { selected.contains(key) }, set: { on in if on { selected.insert(key) } else { selected.remove(key) } })) {
                    HStack {
                        Text(p.name)
                        Spacer()
                        Text(device.name).font(.footnote).foregroundColor(.secondary).lineLimit(1)
                    }
                }
            }
        }
    }
}

/// One widget (fader / knob / button / toggle / XY) with its label.
struct ControlWidgetView: View {
    let widget: ControlWidget
    let editing: Bool
    var compact: Bool = false
    let onEdit: () -> Void
    @EnvironmentObject var control: ControlRuntime
    @EnvironmentObject var live: LiveSession

    private var color: Color { Color(hex: widget.colorHex) }
    private var height: CGFloat { compact ? (widget.kind.isTall ? 118 : 64) : (widget.kind.isTall ? 170 : 96) }

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
                .font(.system(size: compact ? 10 : 11, weight: .bold, design: .rounded))
                .foregroundColor(Theme.textPrimary)
                .lineLimit(1)
            Text(widget.target.label + (widget.kind == .xy ? " / " + widget.targetY.label : ""))
                .font(.system(size: compact ? 7 : 8, design: .rounded))
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
            // Only the knob itself reacts: touches around it fall through (scrolling, nothing else).
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in
                    if startValue == nil { startValue = value }
                    value = max(0, min(1, (startValue ?? value) - Double(g.translation.height) / 150.0))
                }
                .onEnded { _ in startValue = nil })
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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

/// Edits a widget: name, colour, size, range, target, and copy / move to another page.
struct WidgetEditor: View {
    @State var widget: ControlWidget
    let pageIndex: Int
    let onSave: (ControlWidget) -> Void
    let onDelete: () -> Void
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var destinationPage: Int = 0
    @State private var copied = false

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
                Section("Other pages") {
                    Picker("Page", selection: $destinationPage) {
                        ForEach(Array(store.profile.controlPages.enumerated()), id: \.offset) { (i, p) in Text(p.name).tag(i) }
                    }
                    HStack {
                        Button(copied ? "Copied" : "Copy to that page") { copy(move: false) }
                        Spacer()
                        Button("Move to that page") { copy(move: true); dismiss() }.disabled(destinationPage == pageIndex)
                    }
                    Button("Move left in this page") { shift(-1) }
                    Button("Move right in this page") { shift(1) }
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
        .onAppear { destinationPage = pageIndex }
    }

    private func copy(move: Bool) {
        guard destinationPage < store.profile.controlPages.count else { return }
        var w = widget
        w.id = UUID()
        store.profile.controlPages[destinationPage].widgets.append(w)
        copied = true
        if move { onDelete() }
    }

    private func shift(_ by: Int) {
        guard pageIndex < store.profile.controlPages.count,
              let i = store.profile.controlPages[pageIndex].widgets.firstIndex(where: { $0.id == widget.id }) else { return }
        let j = i + by
        guard j >= 0, j < store.profile.controlPages[pageIndex].widgets.count else { return }
        store.profile.controlPages[pageIndex].widgets.swapAt(i, j)
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
            Text("Connect to Live, import an .als or use demo mode to pick a parameter.").font(.footnote).foregroundColor(.secondary)
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
