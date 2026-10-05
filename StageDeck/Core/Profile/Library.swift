import Foundation

/// What a saved library entry represents. All entries are templates underneath.
public enum LibraryCategory: String, Codable, CaseIterable, Identifiable {
    case setup      // whole performer setup (pages, decks, groups, names, notes, layout)
    case sequence   // sequencer project (patterns + settings)
    case template   // anything else: a single page, a shared or imported template
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .setup: return "Setups"
        case .sequence: return "Sequences"
        case .template: return "Templates"
        }
    }
}

/// Index record of a saved template inside the app's library.
public struct LibraryEntry: Codable, Equatable, Identifiable {
    public var id: UUID = UUID()
    public var name: String
    public var category: LibraryCategory
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var contents: [String] = []
    public var fileName: String

    public init(name: String, category: LibraryCategory, contents: [String], fileName: String) {
        self.name = name; self.category = category; self.contents = contents; self.fileName = fileName
    }
}

/// Pure helpers for building the templates that the library stores.
public enum LibrarySnapshots {
    public static func setup(name: String, profile: PerformerProfile, project: SeqProject, song: LiveSongState) -> StageDeckTemplate {
        var sections = TemplateSections()
        sections.clipNotes = true
        return TemplateExporter.make(name: name, author: nil, description: "Setup saved in StageDeck", sections: sections, profile: profile, project: project, song: song)
    }

    public static func sequence(name: String, profile: PerformerProfile, project: SeqProject, song: LiveSongState) -> StageDeckTemplate {
        var sections = TemplateSections()
        sections.controlPages = false; sections.decks = false; sections.launchGroups = false; sections.trackAliases = false; sections.layout = false
        sections.patterns = true; sections.sequencerSettings = true
        return TemplateExporter.make(name: name, author: nil, description: "Sequencer project saved in StageDeck", sections: sections, profile: profile, project: project, song: song)
    }

    public static func fileName(for id: UUID) -> String { "\(id.uuidString).\(StageDeckTemplate.fileExtension)" }
}
