import Foundation

/// Cross-checks a profile (or a template) against the loaded Live set: finds names that no
/// longer exist after tracks, clips or devices were renamed, moved or deleted in Live.
public struct ProfileHealth: Equatable {
    public struct Issue: Equatable, Hashable, Identifiable {
        public enum Kind: String { case deckTrack, groupTrack, alias, clipNote, control, deckGroup }
        public var kind: Kind
        public var subject: String   // e.g. deck name, page name
        public var detail: String    // what is missing
        public var id: String { "\(kind.rawValue)|\(subject)|\(detail)" }
    }

    public var issues: [Issue] = []
    public var setLoaded: Bool = false

    public var isClean: Bool { issues.isEmpty }
    public func issues(of kind: Issue.Kind) -> [Issue] { issues.filter { $0.kind == kind } }

    public var summary: String {
        guard setLoaded else { return "No set loaded." }
        if issues.isEmpty { return "Everything in your setup matches the loaded set." }
        var parts: [String] = []
        let counts: [(Issue.Kind, String)] = [(.deckTrack, "deck track"), (.deckGroup, "deck group"), (.groupTrack, "launch-group track"),
                                              (.alias, "channel name"), (.clipNote, "clip note"), (.control, "control")]
        for (k, label) in counts {
            let n = issues(of: k).count
            if n > 0 { parts.append("\(n) \(label)\(n == 1 ? "" : "s")") }
        }
        return "Not found in this set: " + parts.joined(separator: ", ") + "."
    }

    public static func check(profile: PerformerProfile, song: LiveSongState) -> ProfileHealth {
        var h = ProfileHealth()
        h.setLoaded = !song.tracks.isEmpty
        guard h.setLoaded else { return h }
        func hasTrack(_ n: String) -> Bool { song.tracks.contains(where: { $0.name.caseInsensitiveCompare(n) == .orderedSame }) }
        func track(_ n: String) -> LiveTrack? { song.tracks.first(where: { $0.name.caseInsensitiveCompare(n) == .orderedSame }) }
        for d in profile.decks {
            if let g = d.groupTrackName, track(g)?.isGroup != true { h.issues.append(Issue(kind: .deckGroup, subject: d.name, detail: g)) }
            for t in d.trackNames where !hasTrack(t) { h.issues.append(Issue(kind: .deckTrack, subject: d.name, detail: t)) }
        }
        for g in profile.launchGroups {
            for t in g.trackNames where !hasTrack(t) { h.issues.append(Issue(kind: .groupTrack, subject: g.label, detail: t)) }
        }
        for (liveName, alias) in profile.trackAliases.sorted(by: { $0.key < $1.key }) where !hasTrack(liveName) {
            h.issues.append(Issue(kind: .alias, subject: alias, detail: liveName))
        }
        for key in profile.clipNotes.keys.sorted() {
            let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            guard let t = track(parts[0]) else { h.issues.append(Issue(kind: .clipNote, subject: key, detail: "track \(parts[0])")); continue }
            if !t.clips.values.contains(where: { $0.name == parts[1] }) {
                h.issues.append(Issue(kind: .clipNote, subject: key, detail: "clip \(parts[1]) on \(parts[0])"))
            }
        }
        for page in profile.controlPages {
            for w in page.widgets {
                for target in [w.target, w.targetY] {
                    guard case .liveParameter(let tn, _, let dn, _, let pn, _) = target else { continue }
                    guard let t = track(tn) else { h.issues.append(Issue(kind: .control, subject: "\(page.name) · \(w.name)", detail: "track \(tn)")); continue }
                    guard let d = t.devices.first(where: { $0.name.caseInsensitiveCompare(dn) == .orderedSame }) else {
                        h.issues.append(Issue(kind: .control, subject: "\(page.name) · \(w.name)", detail: "device \(dn) on \(tn)")); continue
                    }
                    if !d.parameters.isEmpty, d.parameterIndex(named: pn) == nil {
                        h.issues.append(Issue(kind: .control, subject: "\(page.name) · \(w.name)", detail: "parameter \(pn) on \(dn)"))
                    }
                }
            }
        }
        return h
    }

    /// Removes names and notes that point at things no longer in the set. Decks, groups and
    /// controls are kept (the performer may want to re-assign them).
    public static func removeStale(from profile: inout PerformerProfile, song: LiveSongState) -> Int {
        let h = check(profile: profile, song: song)
        var removed = 0
        for issue in h.issues(of: .alias) { profile.trackAliases.removeValue(forKey: issue.detail); removed += 1 }
        for issue in h.issues(of: .clipNote) { profile.clipNotes.removeValue(forKey: issue.subject); removed += 1 }
        return removed
    }
}
