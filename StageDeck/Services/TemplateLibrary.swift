import Foundation
import Combine

/// On-device library of saved setups, sequencer projects and templates (Documents/Library).
@MainActor
final class TemplateLibrary: ObservableObject {
    @Published private(set) var entries: [LibraryEntry] = []
    @Published private(set) var lastError: String = ""

    private let folder: URL
    private let indexURL: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        folder = docs.appendingPathComponent("Library", isDirectory: true)
        indexURL = folder.appendingPathComponent("index.json")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: indexURL), let list = try? JSONDecoder().decode([LibraryEntry].self, from: data) {
            entries = list.sorted { $0.updatedAt > $1.updatedAt }
        }
    }

    func entries(in category: LibraryCategory) -> [LibraryEntry] {
        entries.filter { $0.category == category }
    }

    func fileURL(for entry: LibraryEntry) -> URL { folder.appendingPathComponent(entry.fileName) }

    /// Saves a template; returns the new entry (or nil on disk error).
    @discardableResult
    func save(_ template: StageDeckTemplate, name: String, category: LibraryCategory) -> LibraryEntry? {
        var t = template
        t.name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? template.name : name
        var entry = LibraryEntry(name: t.name, category: category, contents: t.contents, fileName: "")
        entry.fileName = LibrarySnapshots.fileName(for: entry.id)
        do {
            try t.encodeJSON().write(to: folder.appendingPathComponent(entry.fileName), options: .atomic)
            entries.insert(entry, at: 0)
            persistIndex()
            lastError = ""
            return entry
        } catch {
            lastError = "Could not save: \(error.localizedDescription)"
            return nil
        }
    }

    /// Overwrites the file of an existing entry with new content.
    func update(_ entry: LibraryEntry, with template: StageDeckTemplate) {
        guard let i = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        var t = template
        t.name = entry.name
        do {
            try t.encodeJSON().write(to: fileURL(for: entry), options: .atomic)
            entries[i].updatedAt = Date()
            entries[i].contents = t.contents
            persistIndex()
        } catch {
            lastError = "Could not save: \(error.localizedDescription)"
        }
    }

    func load(_ entry: LibraryEntry) -> StageDeckTemplate? {
        guard let data = try? Data(contentsOf: fileURL(for: entry)) else { lastError = "File missing for \(entry.name)"; return nil }
        do {
            var t = try StageDeckTemplate.parse(data)
            t.name = entry.name
            return t
        } catch {
            lastError = "\(entry.name): \(error)"
            return nil
        }
    }

    func rename(_ entry: LibraryEntry, to name: String) {
        guard let i = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return }
        entries[i].name = n
        entries[i].updatedAt = Date()
        if var t = load(entries[i]) {
            t.name = n
            try? t.encodeJSON().write(to: fileURL(for: entries[i]), options: .atomic)
        }
        persistIndex()
    }

    func delete(_ entry: LibraryEntry) {
        try? FileManager.default.removeItem(at: fileURL(for: entry))
        entries.removeAll { $0.id == entry.id }
        persistIndex()
    }

    private func persistIndex() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(entries) { try? data.write(to: indexURL, options: .atomic) }
    }
}
