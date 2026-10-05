import Foundation

/// Fits every mixer section (decks, buses) on screen with no horizontal scrolling:
/// sections are packed into rows, strips shrink down to a minimum width and the strip
/// contents (sends, filter, fader) adapt to the row height.
public struct MixerLayoutPlan: Equatable {
    public enum Density: Equatable {
        /// Sends, filter, dB, fader, pan, buttons.
        case full
        /// Thin sends, short filter, fader, buttons.
        case medium
        /// Name, fader and mute only (overview).
        case compact
    }

    public struct Metrics: Equatable {
        public var stripWidth: Double
        public var sendHeight: Double
        public var filterHeight: Double
        public var faderHeight: Double
        public var density: Density
        public var showSends: Bool { density != .compact }
        public var showFilter: Bool { density != .compact }
        public var showDB: Bool { density == .full }
        public var fontScale: Double { stripWidth < 56 ? 0.85 : 1 }
    }

    /// Section indices per row, in order.
    public var rows: [[Int]]
    public var rowHeight: Double
    public var metrics: Metrics
    /// True when a section alone needs more width than available (its row scrolls horizontally).
    public var overflowingSections: [Int]

    public static let stripGap = 6.0
    public static let sectionGap = 14.0
    public static let rowGap = 10.0
    public static let minStripWidth = 48.0
    public static let preferredStripWidth = 64.0
    public static let maxStripWidth = 104.0
    /// Deck button + HPF row above the strips.
    public static let sectionHeaderHeight = 40.0

    /// - Parameters:
    ///   - width/height: available area for the sections (master column excluded).
    ///   - counts: strips per section.
    ///   - sends: number of sends shown per strip.
    ///   - focus: when set, only that section is laid out, as large as possible.
    public static func plan(width: Double, height: Double, counts: [Int], sends: Int, showPan: Bool = false, focus: Int? = nil) -> MixerLayoutPlan {
        var rows: [[Int]] = []
        var overflow: [Int] = []
        if let f = focus, f >= 0, f < counts.count {
            rows = [[f]]
        } else {
            var current: [Int] = []
            var currentStrips = 0
            for (i, n) in counts.enumerated() {
                let strips = max(1, n)
                if current.isEmpty {
                    current = [i]; currentStrips = strips
                    continue
                }
                let needed = rowWidth(strips: currentStrips + strips, sections: current.count + 1, stripWidth: minStripWidth)
                if needed <= width {
                    current.append(i); currentStrips += strips
                } else {
                    rows.append(current)
                    current = [i]; currentStrips = strips
                }
            }
            if !current.isEmpty { rows.append(current) }
        }
        if rows.isEmpty { rows = [[]] }

        // Strip width: the narrowest row decides, clamped.
        var stripWidth = maxStripWidth
        for row in rows {
            let strips = row.reduce(0) { $0 + max(1, counts[$1]) }
            guard strips > 0 else { continue }
            let gaps = Double(strips - row.count) * stripGap + Double(max(0, row.count - 1)) * sectionGap
            let w = (width - gaps) / Double(strips)
            stripWidth = min(stripWidth, w)
        }
        if stripWidth < minStripWidth {
            for row in rows where rowWidth(strips: row.reduce(0) { $0 + max(1, counts[$1]) }, sections: row.count, stripWidth: minStripWidth) > width {
                overflow.append(contentsOf: row)
            }
            stripWidth = minStripWidth
        }
        stripWidth = max(minStripWidth, min(maxStripWidth, stripWidth.rounded(.down)))

        let rowHeight = max(0, (height - Double(rows.count - 1) * rowGap) / Double(rows.count))
        let metrics = metrics(rowHeight: rowHeight, stripWidth: stripWidth, sends: sends, showPan: showPan)
        return MixerLayoutPlan(rows: rows, rowHeight: rowHeight, metrics: metrics, overflowingSections: overflow)
    }

    /// One row of full-size strips; the row scrolls horizontally when it does not fit.
    public static func scrolling(width: Double, height: Double, counts: [Int], sends: Int, showPan: Bool = false) -> MixerLayoutPlan {
        let row = Array(counts.indices)
        let strips = counts.reduce(0) { $0 + max(1, $1) }
        let fits = rowWidth(strips: strips, sections: counts.count, stripWidth: preferredStripWidth) <= width
        let m = metrics(rowHeight: height, stripWidth: preferredStripWidth, sends: sends, showPan: showPan)
        return MixerLayoutPlan(rows: [row], rowHeight: height, metrics: m, overflowingSections: fits ? [] : row)
    }

    static func rowWidth(strips: Int, sections: Int, stripWidth: Double) -> Double {
        Double(strips) * stripWidth + Double(max(0, strips - sections)) * stripGap + Double(max(0, sections - 1)) * sectionGap
    }

    /// Picks the richest strip layout whose fader keeps a usable height.
    static func metrics(rowHeight: Double, stripWidth: Double, sends: Int, showPan: Bool) -> Metrics {
        let nameH = 22.0, dbH = 16.0, buttonsH = 28.0, panH = showPan ? 18.0 : 0, gap = 5.0
        let stripArea = rowHeight - sectionHeaderHeight
        func fader(sendH: Double, filterH: Double, db: Bool, parts: Int) -> Double {
            let fixed = nameH + Double(sends) * sendH + filterH + (db ? dbH : 0) + buttonsH + panH
            return stripArea - fixed - Double(parts) * gap
        }
        // Full strips may also show pan and an ARM row (MIDI tracks): reserve both so nothing overlaps.
        let fullFader = fader(sendH: 34, filterH: 110, db: true, parts: 7 + sends) - 24 - (showPan ? 0 : 18)
        if fullFader >= 120 {
            return Metrics(stripWidth: stripWidth, sendHeight: 34, filterHeight: 110, faderHeight: min(260, fullFader), density: .full)
        }
        let mediumFader = fader(sendH: 18, filterH: 52, db: false, parts: 4 + sends) + Double(4 + sends) // 4pt gaps instead of 5
        if mediumFader >= 80 {
            return Metrics(stripWidth: stripWidth, sendHeight: 18, filterHeight: 52, faderHeight: mediumFader, density: .medium)
        }
        let compactFader = max(60, stripArea - nameH - buttonsH - 2 * gap)
        return Metrics(stripWidth: stripWidth, sendHeight: 0, filterHeight: 0, faderHeight: compactFader, density: .compact)
    }
}
