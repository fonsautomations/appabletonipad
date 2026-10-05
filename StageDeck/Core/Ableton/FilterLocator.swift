import Foundation

/// The parameter a mixer strip's FILTER control drives for a channel.
public struct FilterBinding: Equatable, Hashable {
    public var device: Int
    public var parameter: Int
    /// Short label shown on the control ("FREQ", "FILTER", "LPF"…).
    public var label: String
    public init(device: Int, parameter: Int, label: String) { self.device = device; self.parameter = parameter; self.label = label }
}

/// Finds a filter control in a channel's device chain: an Auto Filter's Frequency first, then any
/// rack macro or parameter called like a filter (FILTER, LPF, HPF, Cutoff…) or like the user's
/// own name. Channels with nothing suitable simply get no filter slot.
public enum FilterLocator {
    public static let commonNames = ["filter", "lpf", "hpf", "cutoff", "frequency", "freq", "filtro"]

    public static func find(in devices: [LiveDevice], customName: String = "") -> FilterBinding? {
        if let af = devices.first(where: { $0.isAutoFilter }), let f = af.parameterIndex(named: "Frequency") {
            return FilterBinding(device: af.index, parameter: f, label: "FREQ")
        }
        let custom = customName.trimmingCharacters(in: .whitespaces).lowercased()
        if !custom.isEmpty, custom != "frequency" {
            for d in devices { for p in d.parameters where p.index > 0 && p.name.lowercased() == custom {
                return FilterBinding(device: d.index, parameter: p.index, label: short(p.name))
            } }
        }
        for name in commonNames {
            for d in devices { for p in d.parameters where p.index > 0 && p.name.lowercased() == name {
                return FilterBinding(device: d.index, parameter: p.index, label: short(p.name))
            } }
        }
        for d in devices { for p in d.parameters where p.index > 0 && p.name.lowercased().contains("filter") {
            return FilterBinding(device: d.index, parameter: p.index, label: short(p.name))
        } }
        return nil
    }

    static func short(_ name: String) -> String {
        let s = name.uppercased()
        return s.count > 7 ? String(s.prefix(7)) : s
    }
}
