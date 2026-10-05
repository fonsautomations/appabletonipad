import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// A template waiting for the user's confirmation (file opened, pasted or built-in).
struct PendingTemplate: Identifiable {
    let id = UUID()
    let template: StageDeckTemplate
    let source: String
}

extension UTType {
    static var stageDeckTemplate: UTType {
        UTType(exportedAs: "com.fonsautomations.stagedeck.template", conformingTo: .json)
    }
}

/// Settings section: import (file / paste / built-in), export, set description for AI prompts.
struct TemplatesSection: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var live: LiveSession
    @State private var showFileImporter = false
    @State private var showPaste = false
    @State private var showExport = false
    @State private var importError: String? = nil
    @State private var copied = false

    var body: some View {
        Section("Templates") {
            Text("A template is a .stagedeck file (readable JSON) with control pages, decks, launch groups, channel names, clip notes, layout and sequencer patterns. Share one with a friend, or ask an AI to write one for your set.")
                .font(.footnote).foregroundColor(.secondary)
            NavigationLink { LibraryView().environmentObject(store).environmentObject(live).environmentObject(store.library) } label: {
                HStack { Label("Library (saved setups, sequences, templates)", systemImage: "books.vertical"); Spacer(); Text("\(store.library.entries.count)").foregroundColor(.secondary) }
            }
            Button("Import from Files / AirDrop…") { showFileImporter = true }
            Button("Paste template JSON…") { showPaste = true }
            ForEach(Array(BuiltInTemplates.all.enumerated()), id: \.offset) { (_, t) in
                Button {
                    store.pendingTemplate = PendingTemplate(template: t, source: "Built-in")
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(t.name)
                            Text(t.description ?? "").font(.footnote).foregroundColor(.secondary).lineLimit(2)
                        }
                        Spacer()
                        Image(systemName: "square.and.arrow.down")
                    }
                }
            }
            Button("Export my setup as a template…") { showExport = true }
            Button(copied ? "Copied set description" : "Copy my set description (for an AI prompt)") {
                UIPasteboard.general.string = SetDescriber.describe(live.song, profile: store.profile)
                copied = true
            }
            .disabled(live.song.tracks.isEmpty)
            if let e = importError { Text(e).font(.footnote).foregroundColor(.red) }
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.stageDeckTemplate, .json, .plainText]) { result in
            switch result {
            case .success(let url):
                if let message = store.openTemplate(url: url) { importError = message } else { importError = nil }
            case .failure(let error):
                importError = error.localizedDescription
            }
        }
        .sheet(isPresented: $showPaste) { PasteTemplateSheet().environmentObject(store) }
        .sheet(isPresented: $showExport) { ExportTemplateSheet().environmentObject(store).environmentObject(live) }
    }
}

/// Paste JSON (from a friend, an AI, a chat) and validate it.
struct PasteTemplateSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var error: String? = nil

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                Text("Paste the template JSON below. It must contain \"format\": \"stagedeck-template\" and at least one section.")
                    .font(.footnote).foregroundColor(.secondary)
                TextEditor(text: $text)
                    .font(.system(size: 12, design: .monospaced))
                    .autocorrectionDisabled()
                    .frame(minHeight: 260)
                    .padding(6)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(8)
                if let error { Text(error).font(.footnote).foregroundColor(.red) }
                HStack {
                    Button("Paste from clipboard") { text = UIPasteboard.general.string ?? text }
                    Spacer()
                    Button("Check and import") {
                        do {
                            let t = try StageDeckTemplate.parse(text: text)
                            error = nil
                            dismiss()
                            store.pendingTemplate = PendingTemplate(template: t, source: "Pasted")
                        } catch let e as StageDeckTemplate.ParseError {
                            error = e.description
                        } catch {
                            self.error = error.localizedDescription
                        }
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(16)
            .navigationTitle("Paste template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

/// Shows what a template contains, what is missing in the loaded set, and imports it.
struct TemplatePreviewSheet: View {
    let pending: PendingTemplate
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var live: LiveSession
    @Environment(\.dismiss) private var dismiss
    @State private var mode: TemplateImportMode = .add
    @State private var keepInLibrary = false

    var body: some View {
        let t = pending.template
        let check = TemplateImporter.check(t, against: live.song)
        NavigationStack {
            Form {
                Section(t.name) {
                    if let a = t.author { Text("By \(a)").foregroundColor(.secondary) }
                    if let d = t.description { Text(d) }
                    Text("Source: \(pending.source)").font(.footnote).foregroundColor(.secondary)
                }
                Section("Contains") {
                    ForEach(t.contents, id: \.self) { line in Text(line) }
                }
                Section("Fits your set?") {
                    if !check.setLoaded {
                        Text("No set loaded: names will be checked when Live connects. Unknown targets show in yellow.").foregroundColor(.secondary)
                    } else if check.isClean {
                        Label("All referenced tracks and devices exist in the current set.", systemImage: "checkmark.circle").foregroundColor(.green)
                    } else {
                        if !check.missingTracks.isEmpty { Text("Missing tracks: " + check.missingTracks.joined(separator: ", ")).foregroundColor(.orange) }
                        if !check.missingDevices.isEmpty { Text("Missing devices: " + check.missingDevices.joined(separator: ", ")).foregroundColor(.orange) }
                        if !check.missingClips.isEmpty { Text("Notes for clips not in this set: " + check.missingClips.joined(separator: ", ")).foregroundColor(.orange) }
                        Text("You can import anyway and re-assign those controls, or rename your tracks to match.").font(.footnote).foregroundColor(.secondary)
                    }
                }
                Section("How to import") {
                    Picker("Mode", selection: $mode) {
                        Text("Add to what I have").tag(TemplateImportMode.add)
                        Text("Replace those sections").tag(TemplateImportMode.replace)
                    }
                    Text("Connection settings are never changed by a template.").font(.footnote).foregroundColor(.secondary)
                    if !pending.source.hasPrefix("Library") {
                        Toggle("Also keep a copy in my library", isOn: $keepInLibrary)
                    }
                }
            }
            .navigationTitle("Import template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        store.importTemplate(t, mode: mode)
                        if keepInLibrary { store.library.save(t, name: t.name, category: t.patterns != nil && t.controlPages == nil ? .sequence : .template) }
                        dismiss()
                    }
                }
            }
        }
    }
}

/// Picks sections, names the template and shares the .stagedeck file (or copies the JSON).
struct ExportTemplateSheet: View {
    var saveToLibrary: Bool = false
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var live: LiveSession
    @EnvironmentObject var library: TemplateLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var name = "My setup"
    @State private var author = ""
    @State private var notes = ""
    @State private var sections = TemplateSections()
    @State private var fileURL: URL? = nil
    @State private var copied = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Template") {
                    TextField("Name", text: $name)
                    TextField("Author", text: $author)
                    TextField("Description", text: $notes)
                }
                Section("Include") {
                    Toggle("Control pages", isOn: $sections.controlPages)
                    Toggle("Decks", isOn: $sections.decks)
                    Toggle("Launch groups", isOn: $sections.launchGroups)
                    Toggle("Channel names", isOn: $sections.trackAliases)
                    Toggle("Clip notes", isOn: $sections.clipNotes)
                    Toggle("Launcher / mixer layout", isOn: $sections.layout)
                    Toggle("Sequencer patterns", isOn: $sections.patterns)
                    Toggle("Sequencer settings (tempo, scale, chain, song)", isOn: $sections.sequencerSettings)
                }
                if saveToLibrary {
                    Section("Library") {
                        Button("Save to library") {
                            library.save(store.makeTemplate(name: name, author: author, description: notes, sections: sections), name: name, category: .template)
                            dismiss()
                        }
                    }
                }
                Section("Share") {
                    if let url = fileURL {
                        ShareLink(item: url) { Label("Share \(url.lastPathComponent)", systemImage: "square.and.arrow.up") }
                    } else {
                        Button("Create file") { fileURL = store.exportTemplateFile(name: name, author: author, description: notes, sections: sections) }
                    }
                    Button(copied ? "JSON copied" : "Copy JSON to clipboard") {
                        let t = store.makeTemplate(name: name, author: author, description: notes, sections: sections)
                        if let data = try? t.encodeJSON() { UIPasteboard.general.string = String(decoding: data, as: UTF8.self); copied = true }
                    }
                }
            }
            .navigationTitle(saveToLibrary ? "Save template" : "Export template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onChange(of: sections) { _ in fileURL = nil }
            .onChange(of: name) { _ in fileURL = nil }
        }
    }
}

/// Settings section: editable display names for every Live track (launcher, mixer and control pages use them).
struct ChannelNamesSection: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var live: LiveSession

    var body: some View {
        Section("Channel names") {
            if live.song.tracks.isEmpty {
                Text("Connect to Live (or use demo mode) to name your channels. Names are kept per Live track name and travel inside templates.")
                    .font(.footnote).foregroundColor(.secondary)
            } else {
                ForEach(live.song.tracks) { t in
                    HStack {
                        Text(t.name).foregroundColor(.secondary).frame(width: 150, alignment: .leading).lineLimit(1)
                        TextField("Display name", text: Binding(get: { store.profile.trackAliases[t.name] ?? "" },
                                                                 set: { store.setAlias($0, forTrack: t.name) }))
                            .autocorrectionDisabled()
                    }
                }
                if !store.profile.trackAliases.isEmpty {
                    Button("Clear all custom names", role: .destructive) { store.profile.trackAliases = [:] }
                }
            }
        }
    }
}

/// Quick rename from the launcher header or a mixer strip (long press).
struct RenameTrackSheet: View {
    let liveName: String
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Live track: \(liveName)") {
                    TextField("Display name", text: $text).autocorrectionDisabled()
                    Text("Shown in the launcher, mixer and templates. Leave empty to use the Live name.").font(.footnote).foregroundColor(.secondary)
                }
            }
            .navigationTitle("Rename channel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { store.setAlias(text, forTrack: liveName); dismiss() } }
            }
        }
        .onAppear { text = store.profile.trackAliases[liveName] ?? "" }
    }
}

/// Identifiable wrapper so `.sheet(item:)` can present a rename.
struct RenameRequest: Identifiable {
    let id = UUID()
    let liveName: String
}

/// Settings section: everything in the profile that no longer matches the loaded set.
struct SetCheckSection: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var live: LiveSession
    @State private var lastRemoved: Int? = nil

    var body: some View {
        let health = ProfileHealth.check(profile: store.profile, song: live.song)
        Section("Set check") {
            HStack {
                Image(systemName: !health.setLoaded ? "questionmark.circle" : (health.isClean ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"))
                    .foregroundColor(!health.setLoaded ? .secondary : (health.isClean ? .green : .orange))
                Text(health.summary)
            }
            ForEach(health.issues) { issue in
                HStack {
                    Text(label(for: issue.kind)).font(.footnote).foregroundColor(.secondary).frame(width: 110, alignment: .leading)
                    Text(issue.subject).lineLimit(1)
                    Spacer()
                    Text(issue.detail).font(.footnote).foregroundColor(.orange).lineLimit(1)
                }
            }
            if !health.issues(of: .alias).isEmpty || !health.issues(of: .clipNote).isEmpty {
                Button("Remove stale channel names and clip notes", role: .destructive) {
                    var p = store.profile
                    lastRemoved = ProfileHealth.removeStale(from: &p, song: live.song)
                    store.profile = p
                }
            }
            if let n = lastRemoved { Text("Removed \(n) stale item\(n == 1 ? "" : "s").").font(.footnote).foregroundColor(.secondary) }
            Text("Decks, launch groups and controls that point at missing tracks are kept so you can re-assign them (Settings → Decks / Launch groups, or EDIT in CTRL).")
                .font(.footnote).foregroundColor(.secondary)
        }
    }

    private func label(for kind: ProfileHealth.Issue.Kind) -> String {
        switch kind {
        case .deckTrack: return "Deck track"
        case .deckGroup: return "Deck group"
        case .groupTrack: return "Group track"
        case .alias: return "Channel name"
        case .clipNote: return "Clip note"
        case .control: return "Control"
        }
    }
}
