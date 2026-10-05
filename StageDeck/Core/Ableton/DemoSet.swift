import Foundation

/// A believable demo set so every screen can be tried without Live.
public enum DemoSet {
    static let autoFilterParameters = [LiveDeviceParameter(index: 0, name: "Device On", value: 1, min: 0, max: 1),
                                       LiveDeviceParameter(index: 1, name: "Frequency", value: 1, min: 0, max: 1),
                                       LiveDeviceParameter(index: 2, name: "Resonance", value: 0.2, min: 0, max: 1)]

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
            group.canBeArmed = false
            group.sends = [0, 0, 0]
            group.devices = [LiveDevice(trackIndex: group.index, index: 0, name: "Auto Filter", className: "AutoFilter", parameters: autoFilterParameters)]
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
                t.devices = [LiveDevice(trackIndex: t.index, index: 0, name: "Auto Filter", className: "AutoFilter", parameters: autoFilterParameters),
                             LiveDevice(trackIndex: t.index, index: 1, name: "\(name) Rack", className: "AudioEffectGroupDevice",
                                        parameters: [LiveDeviceParameter(index: 0, name: "Device On", value: 1, min: 0, max: 1)] +
                                            (1...8).map { LiveDeviceParameter(index: $0, name: "Macro \($0)", value: Double($0) / 9.0, min: 0, max: 1) })]
                tracks.append(t)
            }
        }
        song.tracks = tracks
        song.returnTrackNames = ["liquid", "bV", "U-iV"]
        for i in song.returnTracks.indices {
            song.returnTracks[i].color = LiveColor(rgb: [0x3CC8E6, 0x9A6BFF, 0xE05A9A][i % 3])
            song.returnTracks[i].volume = 0.8
            song.returnTracks[i].sends = [0, 0, 0]
            song.returnTracks[i].devices = [LiveDevice(trackIndex: LiveSongState.trackIndex(forReturn: i), index: 0, name: "Auto Filter", className: "AutoFilter",
                                                       parameters: autoFilterParameters)]
        }
        song.masterDevices = [LiveDevice(trackIndex: LiveSongState.masterTrackIndex, index: 0, name: "Auto Filter", className: "AutoFilter", parameters: autoFilterParameters),
                              LiveDevice(trackIndex: LiveSongState.masterTrackIndex, index: 1, name: "Master Rack", className: "AudioEffectGroupDevice",
                                         parameters: [LiveDeviceParameter(index: 0, name: "Device On", value: 1, min: 0, max: 1)] +
                                            (1...8).map { LiveDeviceParameter(index: $0, name: "Macro \($0)", value: 0.5, min: 0, max: 1) })]
        song.tempo = 133
        song.liveVersion = "demo"
        return song
    }
}
