import Foundation

/// A believable demo set so every screen can be tried without Live.
public enum DemoSet {
    public static func make() -> LiveSongState {
        var song = LiveSongState()
        let sectionNames = ["BASIL", "PERPEN", "BERLIN", "lasP"]
        var scenes: [LiveScene] = []
        for sec in sectionNames {
            for i in 1...6 {
                scenes.append(LiveScene(index: scenes.count, name: "\(sec)_\(i)", color: LiveColor(rgb: 0x3A3A3A)))
            }
        }
        song.scenes = scenes
        let stems: [(String, Int)] = [("KICK", 0xF28C28), ("KICK2", 0xC8762A), ("LO", 0x4CC24C), ("HI PERC", 0xE6DC3C), ("MID PERC", 0xE0A830),
                                      ("SYN-1", 0x3CBEE6), ("SYN-2", 0x2AA8D0), ("FX", 0xE05AE0), ("FX2-PAD", 0xC84AC8), ("ATMOS", 0x8A5AF0)]
        var tracks: [LiveTrack] = []
        for deck in ["A", "B"] {
            var group = LiveTrack(index: tracks.count, name: deck, color: LiveColor(rgb: deck == "A" ? 0xF28C28 : 0x8FB4DD))
            group.isGroup = true
            let groupIndex = group.index
            tracks.append(group)
            for (name, rgb) in stems {
                var t = LiveTrack(index: tracks.count, name: name, color: LiveColor(rgb: rgb))
                t.groupTrackIndex = groupIndex
                t.volume = 0.85 - Double.random(in: 0...0.2)
                t.sends = [0.1, 0.0, 0.3]
                t.hasMIDIInput = name.hasPrefix("SYN")
                var seed = (name.count * 7 + tracks.count * 13)
                for scene in scenes {
                    seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
                    if seed % 3 == 0 { continue }
                    let base = scene.name.lowercased().replacingOccurrences(of: "_", with: "ar_")
                    t.clips[scene.index] = LiveClip(trackIndex: t.index, sceneIndex: scene.index, name: "\(base)-\(name)", color: LiveColor(rgb: rgb), length: Double([4, 8, 16, 32][seed % 4]))
                }
                t.devices = [LiveDevice(trackIndex: t.index, index: 0, name: "Auto Filter", className: "AutoFilter",
                                        parameters: [LiveDeviceParameter(index: 0, name: "Device On", value: 1, min: 0, max: 1),
                                                     LiveDeviceParameter(index: 1, name: "Frequency", value: 1, min: 0, max: 1),
                                                     LiveDeviceParameter(index: 2, name: "Resonance", value: 0.2, min: 0, max: 1)]),
                             LiveDevice(trackIndex: t.index, index: 1, name: "\(name) Rack", className: "AudioEffectGroupDevice",
                                        parameters: [LiveDeviceParameter(index: 0, name: "Device On", value: 1, min: 0, max: 1)] +
                                            (1...8).map { LiveDeviceParameter(index: $0, name: "Macro \($0)", value: Double($0) / 9.0, min: 0, max: 1) })]
                tracks.append(t)
            }
        }
        song.tracks = tracks
        song.returnTrackNames = ["liquid", "bV", "U-iV"]
        song.tempo = 133
        song.liveVersion = "demo"
        return song
    }
}
