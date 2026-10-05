import SwiftUI

/// Saved setups, sequencer projects and templates kept inside the app.
struct LibraryView: View {
    /// When set, only this category is shown (e.g. sequences from the SEQ screen).
    var only: LibraryCategory? = nil
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var live: LiveSession
    @EnvironmentObject var library: TemplateLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var saveName = ""
    @State private var saveCategory: LibraryCategory = .setup
    @State private var showSave = false
    @State private var renaming: LibraryEntry? = nil
    @State private var renameText = ""
    @State private var showCustomSave = false

    private var categories: [LibraryCategory] { only.map { [$0] } ?? LibraryCategory.allCases }

    var body: some View {
        NavigationStack {
            Form {
                Section("Save") {
                    if only != .sequence {
                        Button("Save current setup…") { saveCategory = .setup; saveName = defaultName("Setup"); showSave = true }
                    }
                    if only != .setup {
                        Button("Save sequencer project…") { saveCategory = .sequence; saveName = store.sequencer.project.name; showSave = true }
                    }
                    if only == nil {
                        Button("Save a custom template (choose sections)…") { showCustomSave = true }
                    }
                }
                ForEach(categories) { cat in
                    Section(cat.label) {
                        let list = library.entries(in: cat)
                        if list.isEmpty {
                            Text("Nothing saved yet.").foregroundColor(.secondary)
                        }
                        ForEach(list) { entry in
                            LibraryRow(entry: entry, onLoad: { load(entry) }, onRename: { renaming = entry; renameText = entry.name },
                                       onOverwrite: { overwrite(entry) }, onDelete: { library.delete(entry) })
                        }
                    }
                }
                if !library.lastError.isEmpty {
                    Section { Text(library.lastError).foregroundColor(.red).font(.footnote) }
                }
            }
            .navigationTitle(only?.label ?? "Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .alert("Name", isPresented: $showSave) {
                TextField("Name", text: $saveName)
                Button("Save") { save() }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $renameText)
                Button("Save") { if let r = renaming { library.rename(r, to: renameText) }; renaming = nil }
                Button("Cancel", role: .cancel) { renaming = nil }
            }
            .sheet(isPresented: $showCustomSave) {
                ExportTemplateSheet(saveToLibrary: true).environmentObject(store).environmentObject(live).environmentObject(library)
            }
        }
    }

    private func defaultName(_ base: String) -> String {
        let f = DateFormatter(); f.dateFormat = "d MMM HH:mm"
        return "\(base) \(f.string(from: Date()))"
    }

    private func save() {
        let t: StageDeckTemplate
        switch saveCategory {
        case .setup: t = LibrarySnapshots.setup(name: saveName, profile: store.profile, project: store.sequencer.project, song: live.song)
        case .sequence: t = LibrarySnapshots.sequence(name: saveName, profile: store.profile, project: store.sequencer.project, song: live.song)
        case .template: t = store.makeTemplate(name: saveName, author: "", description: "", sections: TemplateSections())
        }
        library.save(t, name: saveName, category: saveCategory)
    }

    private func overwrite(_ entry: LibraryEntry) {
        let t: StageDeckTemplate
        switch entry.category {
        case .setup: t = LibrarySnapshots.setup(name: entry.name, profile: store.profile, project: store.sequencer.project, song: live.song)
        case .sequence: t = LibrarySnapshots.sequence(name: entry.name, profile: store.profile, project: store.sequencer.project, song: live.song)
        case .template: t = store.makeTemplate(name: entry.name, author: "", description: "", sections: .everything)
        }
        library.update(entry, with: t)
    }

    private func load(_ entry: LibraryEntry) {
        guard let t = library.load(entry) else { return }
        dismiss()
        store.pendingTemplate = PendingTemplate(template: t, source: "Library · \(entry.category.label)")
    }
}

struct LibraryRow: View {
    let entry: LibraryEntry
    let onLoad: () -> Void
    let onRename: () -> Void
    let onOverwrite: () -> Void
    let onDelete: () -> Void
    @EnvironmentObject var library: TemplateLibrary
    @State private var confirmOverwrite = false
    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name).font(.system(size: 15, weight: .semibold))
                    Text(entry.contents.joined(separator: " · ")).font(.footnote).foregroundColor(.secondary).lineLimit(2)
                    Text(entry.updatedAt, style: .date).font(.footnote).foregroundColor(.secondary)
                }
                Spacer()
                Button("Load") { onLoad() }.buttonStyle(.bordered)
            }
            HStack(spacing: 14) {
                ShareLink(item: library.fileURL(for: entry)) { Label("Share", systemImage: "square.and.arrow.up") }
                Button("Rename") { onRename() }
                Button("Overwrite") { confirmOverwrite = true }
                Button("Delete", role: .destructive) { confirmDelete = true }
            }
            .font(.footnote)
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)
        }
        .padding(.vertical, 4)
        .confirmationDialog("Overwrite \"\(entry.name)\" with the current state?", isPresented: $confirmOverwrite, titleVisibility: .visible) {
            Button("Overwrite", role: .destructive) { onOverwrite() }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete \"\(entry.name)\"?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) {}
        }
    }
}
