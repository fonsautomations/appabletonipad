import XCTest
@testable import StageDeckCore

final class OSCTests: XCTestCase {
    func testEncodeDecodeRoundTrip() {
        let m = OSCMessage("/live/clip_slot/fire", [.int32(3), .int32(7), .float(0.5), .string("hola"), .bool(true), .bool(false), .null, .int64(1 << 40), .double(1.25)])
        let data = m.encode()
        XCTAssertEqual(data.count % 4, 0)
        let decoded = OSCMessage.decodePacket(data)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded.first, m)
    }

    func testEncodeMatchesSpecBytes() {
        // "/a" + ",i" + 1 → /a\0\0 ,i\0\0 00000001
        let m = OSCMessage("/a", [.int32(1)])
        XCTAssertEqual(Array(m.encode()), [0x2F, 0x61, 0, 0, 0x2C, 0x69, 0, 0, 0, 0, 0, 1])
    }

    func testDecodeBundle() {
        let a = OSCMessage("/x", [.int32(1)]).encode()
        let b = OSCMessage("/y", [.string("z")]).encode()
        var bundle = Data()
        bundle.append(contentsOf: Array("#bundle".utf8) + [0])
        bundle.append(contentsOf: [UInt8](repeating: 0, count: 8))
        for e in [a, b] {
            OSCCodec.appendInt32(Int32(e.count), to: &bundle)
            bundle.append(e)
        }
        let decoded = OSCMessage.decodePacket(bundle)
        XCTAssertEqual(decoded.map { $0.address }, ["/x", "/y"])
    }

    func testGarbageDoesNotCrash() {
        XCTAssertTrue(OSCMessage.decodePacket(Data([1, 2, 3])).isEmpty)
        XCTAssertTrue(OSCMessage.decodePacket(Data()).isEmpty)
        XCTAssertTrue(OSCMessage.decodePacket(Data(Array("/abc".utf8))).isEmpty) // no terminator
    }

    func testValueCoercions() {
        XCTAssertEqual(OSCValue.float(3.0).intValue, 3)
        XCTAssertEqual(OSCValue.bool(true).intValue, 1)
        XCTAssertEqual(OSCValue.int32(0).boolValue, false)
        XCTAssertEqual(OSCValue.string("7").intValue, 7)
        XCTAssertTrue(OSCValue.null.isNull)
    }

    func testLiveEventDecoding() {
        XCTAssertEqual(LiveEventDecoder.decode(OSCMessage("/live/test", [.string("ok")])), .testOK)
        XCTAssertEqual(LiveEventDecoder.decode(OSCMessage("/live/song/get/tempo", [.float(133)])), .tempo(133))
        XCTAssertEqual(LiveEventDecoder.decode(OSCMessage("/live/track/get/playing_slot_index", [.int32(2), .int32(5)])), .trackPlayingSlot(track: 2, 5))
        XCTAssertEqual(LiveEventDecoder.decode(OSCMessage("/live/track/get/clips/name", [.int32(1), .string("a"), .null, .string("c")])), .trackClipNames(track: 1, ["a", nil, "c"]))
        XCTAssertEqual(LiveEventDecoder.decode(OSCMessage("/live/clip/get/playing_position", [.int32(1), .int32(2), .float(3.5)])), .clipPlayingPosition(track: 1, scene: 2, 3.5))
        XCTAssertEqual(LiveEventDecoder.decode(OSCMessage("/live/track/get/send", [.int32(1), .int32(0), .float(0.25)])), .trackSend(track: 1, send: 0, 0.25))
        XCTAssertEqual(LiveEventDecoder.decode(OSCMessage("/live/track/get/color", [.int32(0), .int32(0xFF8000)])), .trackColor(track: 0, LiveColor(rgb: 0xFF8000)))
        XCTAssertEqual(LiveEventDecoder.decode(OSCMessage("/live/song/get/clip_trigger_quantization", [.int32(4)])), .quantization(.bar))
        XCTAssertEqual(LiveEventDecoder.decode(OSCMessage("/live/device/get/parameters/name", [.int32(0), .int32(1), .string("Device On"), .string("Frequency")])), .deviceParameterNames(track: 0, device: 1, ["Device On", "Frequency"]))
        if case .unknown = LiveEventDecoder.decode(OSCMessage("/live/whatever")) {} else { XCTFail("expected unknown") }
    }

    func testCommandsAddresses() {
        XCTAssertEqual(LiveCommand.fireClip(track: 2, scene: 3).description, "/live/clip_slot/fire 2 3")
        XCTAssertEqual(LiveCommand.setVolume(track: 1, value: 2).arguments.last, .float(1))
        XCTAssertEqual(LiveCommand.trackListen("output_meter_level", track: 4, start: true).address, "/live/track/start_listen/output_meter_level")
        XCTAssertEqual(LiveCommand.trackData(from: 0, to: -1, properties: ["track.name"]).arguments, [.int32(0), .int32(-1), .string("track.name")])
    }

    func testVolumeConversion() {
        XCTAssertEqual(LiveVolume.decibels(fromFader: 0.85), 0, accuracy: 0.001)
        XCTAssertEqual(LiveVolume.decibels(fromFader: 1.0), 6, accuracy: 0.001)
        XCTAssertEqual(LiveVolume.decibels(fromFader: 0.4), -18, accuracy: 0.001)
        XCTAssertEqual(LiveVolume.fader(fromDecibels: 0), 0.85, accuracy: 0.001)
        XCTAssertEqual(LiveVolume.fader(fromDecibels: LiveVolume.decibels(fromFader: 0.2)), 0.2, accuracy: 0.001)
        XCTAssertEqual(LiveVolume.label(fader: 0), "-inf")
        XCTAssertEqual(LiveVolume.decibels(fromFader: 0), -Double.infinity)
    }

    func testSections() {
        let scenes = ["BASIL_1", "BASIL_2", "BASIL_3", "PERPEN_1", "PERPEN_2", "BERLIN 1", "BERLIN 2", "Intro", "BASIL_4"]
            .enumerated().map { LiveScene(index: $0.offset, name: $0.element) }
        let sections = SetLayout.sections(from: scenes)
        XCTAssertEqual(sections.map { $0.name }, ["BASIL", "PERPEN", "BERLIN", "Intro", "BASIL"])
        XCTAssertEqual(sections[0].sceneRange, 0...2)
        XCTAssertEqual(sections[1].sceneRange, 3...4)
        XCTAssertEqual(SetLayout.sectionKey(forSceneName: "basilar_10-"), "basilar_10-")
        XCTAssertEqual(SetLayout.sectionKey(forSceneName: "12"), "12")
        XCTAssertEqual(SetLayout.sectionKey(forSceneName: ""), "")
    }

    func testDeckResolution() {
        var song = LiveSongState()
        var g = LiveTrack(index: 0, name: "A"); g.isGroup = true
        var t1 = LiveTrack(index: 1, name: "KICK"); t1.groupTrackIndex = 0
        var t2 = LiveTrack(index: 2, name: "LO"); t2.groupTrackIndex = 0
        let t3 = LiveTrack(index: 3, name: "SOLO")
        song.tracks = [g, t1, t2, t3]
        let decks = DeckDefinition.automatic(from: song)
        XCTAssertEqual(decks.count, 1)
        XCTAssertEqual(decks[0].resolveTracks(in: song).map { $0.name }, ["KICK", "LO"])
        let manual = DeckDefinition(name: "X", trackNames: ["lo", "solo"])
        XCTAssertEqual(manual.resolveTracks(in: song).map { $0.index }, [2, 3])
        XCTAssertEqual("#FF8000".liveColorFromHex, LiveColor(rgb: 0xFF8000))
        XCTAssertEqual(LiveColor(rgb: 0xFF8000).hexString, "#FF8000")
    }

    func testProfileRoundTrip() throws {
        var doc = AppDocument()
        doc.profile.setClipNote(track: "KICK", clip: "basilar_5-K", note: "drop here")
        doc.project.patterns[0].tracks[0].steps[0] = Step.on(note: 36)
        doc.project.patterns[0].tracks[0].steps[0].locks = [74: 100]
        doc.project.patterns[0].tracks[0].steps[0].condition = .ratio(n: 1, of: 2)
        let data = try doc.encodeJSON()
        let back = try AppDocument.decodeJSON(data)
        XCTAssertEqual(back, doc)
        XCTAssertEqual(back.profile.clipNote(track: "KICK", clip: "basilar_5-K"), "drop here")
    }
}

final class ControlPageTests: XCTestCase {
    func testLayoutPacksRows() {
        var a = ControlWidget(name: "a", kind: .knob); a.width = 3
        var b = ControlWidget(name: "b", kind: .knob); b.width = 3
        var c = ControlWidget(name: "c", kind: .knob); c.width = 3
        let d = ControlWidget(name: "d", kind: .xy) // width 2
        let rows = ControlLayout.rows([a, b, c, d])
        XCTAssertEqual(rows.map { $0.map { $0.name } }, [["a", "b"], ["c", "d"]])
        XCTAssertEqual(ControlLayout.rows([]).count, 0)
        var huge = ControlWidget(name: "h", kind: .fader); huge.width = 99
        XCTAssertEqual(ControlLayout.rows([huge, a]).count, 2)
    }

    func testTargetCodableAndResolve() throws {
        let page = ControlPage.starter()
        let data = try JSONEncoder().encode(page)
        let back = try JSONDecoder().decode(ControlPage.self, from: data)
        XCTAssertEqual(back, page)

        var song = LiveSongState()
        var t = LiveTrack(index: 3, name: "SYN-1")
        t.devices = [LiveDevice(trackIndex: 3, index: 0, name: "Auto Filter", className: "AutoFilter"),
                     LiveDevice(trackIndex: 3, index: 1, name: "Rack", className: "AudioEffectGroupDevice",
                                parameters: [LiveDeviceParameter(index: 0, name: "Device On", value: 1, min: 0, max: 1),
                                             LiveDeviceParameter(index: 1, name: "Macro 1", value: 0.3, min: 0, max: 1)])]
        song.tracks = [LiveTrack(index: 0, name: "KICK"), LiveTrack(index: 1, name: "x"), LiveTrack(index: 2, name: "y"), t]
        let target = ControlTarget.liveParameter(track: "syn-1", trackIndex: 0, device: "rack", deviceIndex: 5, parameter: "macro 1", parameterIndex: 9)
        XCTAssertEqual(ControlResolver.resolve(target, in: song), ControlResolver.Resolved(track: 3, device: 1, parameter: 1))
        XCTAssertNil(ControlResolver.resolve(.midiCC(channel: 0, controller: 1, port: .all), in: song))
        XCTAssertEqual(target.label, "syn-1 · rack · macro 1")
        var w = ControlWidget(name: "w", kind: .fader); w.minimum = 0.25; w.maximum = 0.75
        XCTAssertEqual(w.scaled(0.5), 0.5, accuracy: 1e-9)
        XCTAssertEqual(w.unscaled(0.75), 1, accuracy: 1e-9)
    }

    func testProfileDecodesWithMissingKeys() throws {
        let json = #"{"name":"old","liveHost":"10.0.0.2","clipHeight":60}"#
        let p = try JSONDecoder().decode(PerformerProfile.self, from: Data(json.utf8))
        XCTAssertEqual(p.liveHost, "10.0.0.2")
        XCTAssertEqual(p.clipHeight, 60)
        XCTAssertTrue(p.showSections)
        XCTAssertEqual(p.controlPages.count, 1)
        XCTAssertEqual(LiveEventDecoder.decode(OSCMessage("/live/view/get/selected_device", [.int32(2), .int32(1)])), .selectedDevice(track: 2, device: 1))
    }
}

final class TemplateTests: XCTestCase {
    func testBuiltInsRoundTripAndParse() throws {
        for t in BuiltInTemplates.all {
            let data = try t.encodeJSON()
            let back = try StageDeckTemplate.parse(data)
            XCTAssertEqual(back, t)
            XCTAssertFalse(back.contents.isEmpty)
        }
    }

    func testParseErrors() {
        XCTAssertThrowsError(try StageDeckTemplate.parse(text: "{ not json")) { e in
            if case StageDeckTemplate.ParseError.notJSON = e {} else { XCTFail("\(e)") }
        }
        XCTAssertThrowsError(try StageDeckTemplate.parse(text: #"{"format":"other","name":"x","decks":[]}"#)) { e in
            XCTAssertEqual(e as? StageDeckTemplate.ParseError, .wrongFormat)
        }
        XCTAssertThrowsError(try StageDeckTemplate.parse(text: #"{"format":"stagedeck-template","version":99,"name":"x","decks":[]}"#)) { e in
            XCTAssertEqual(e as? StageDeckTemplate.ParseError, .newerVersion(99))
        }
        XCTAssertThrowsError(try StageDeckTemplate.parse(text: #"{"format":"stagedeck-template","name":"x"}"#)) { e in
            XCTAssertEqual(e as? StageDeckTemplate.ParseError, .empty)
        }
        // Minimal hand-written (AI-style) template with only names
        let t = try? StageDeckTemplate.parse(text: #"{"format":"stagedeck-template","name":"Names","trackAliases":{"KICK":"BOMBO"}}"#)
        XCTAssertEqual(t?.trackAliases?["KICK"], "BOMBO")
    }

    func testCheckAndApply() throws {
        var song = DemoSet.make()
        _ = song
        song.tracks = song.tracks.filter { $0.name != "ATMOS" }
        let t = BuiltInTemplates.stemsAB
        let check = TemplateImporter.check(t, against: song)
        XCTAssertTrue(check.setLoaded)
        XCTAssertEqual(check.missingTracks, ["ATMOS"])
        XCTAssertTrue(TemplateImporter.check(t, against: LiveSongState()).isClean)

        var profile = PerformerProfile()
        var project = SeqProject()
        profile.controlPages = []
        TemplateImporter.apply(t, mode: .add, to: &profile, project: &project)
        XCTAssertEqual(profile.decks.map { $0.name }, ["A", "B"])
        XCTAssertEqual(profile.displayName(forTrack: "KICK"), "BOMBO")
        XCTAssertEqual(profile.launchGroups.count, 2)
        TemplateImporter.apply(t, mode: .add, to: &profile, project: &project)
        XCTAssertEqual(profile.decks.count, 4)
        TemplateImporter.apply(t, mode: .replace, to: &profile, project: &project)
        XCTAssertEqual(profile.decks.count, 2)

        let drums = BuiltInTemplates.drumSeq909
        TemplateImporter.apply(drums, mode: .add, to: &profile, project: &project)
        XCTAssertEqual(project.patterns.count, 3)
        XCTAssertEqual(project.tempo, 128)
        XCTAssertEqual(project.chain, [0, 0, 0, 1])
        TemplateImporter.apply(drums, mode: .replace, to: &profile, project: &project)
        XCTAssertEqual(project.patterns.count, 2)
        XCTAssertEqual(Set(project.patterns.map { $0.id }).count, 2)
    }

    func testExportAndDescribe() throws {
        let profile = PerformerProfile()
        let project = SeqProject()
        let song = DemoSet.make()
        let t = TemplateExporter.make(name: "Mine", author: "me", description: nil, sections: .everything, profile: profile, project: project, song: song)
        XCTAssertEqual(t.controlPages?.count, 1)
        XCTAssertEqual(t.patterns?.count, 1)
        XCTAssertNotNil(t.layout)
        let json = String(decoding: try t.encodeJSON(), as: UTF8.self)
        XCTAssertTrue(json.contains("\"format\" : \"stagedeck-template\""))
        let desc = SetDescriber.describe(song, profile: profile)
        XCTAssertTrue(desc.contains("SYN-1 Rack"))
        XCTAssertTrue(desc.contains("Macro 8"))
        XCTAssertTrue(desc.contains("[GROUP] A"))
    }
}

final class HealthTests: XCTestCase {
    func testHealthFindsStaleThings() {
        let song = DemoSet.make()
        let existingClip = song.tracks.first(where: { $0.name == "KICK" })!.clips.values.first!.name
        var profile = PerformerProfile()
        profile.trackAliases = ["KICK": "BOMBO", "GHOST": "X"]
        profile.clipNotes = ["KICK|\(existingClip)": "ok", "KICK|nope": "stale", "NOPE|x": "stale"]
        profile.decks = [DeckDefinition(name: "A", trackNames: [], groupTrackName: "A"), DeckDefinition(name: "C", trackNames: ["LO", "ZZZ"], groupTrackName: "C")]
        profile.launchGroups = [LaunchGroup(label: "K", trackNames: ["KICK", "YYY"])]
        var w = ControlWidget(name: "Bad", kind: .knob)
        w.target = .liveParameter(track: "SYN-1", trackIndex: 0, device: "Nope Rack", deviceIndex: 9, parameter: "Macro 1", parameterIndex: 1)
        var w2 = ControlWidget(name: "BadParam", kind: .knob)
        w2.target = .liveParameter(track: "SYN-1", trackIndex: 0, device: "SYN-1 Rack", deviceIndex: 1, parameter: "Macro 99", parameterIndex: 99)
        profile.controlPages = [ControlPage(name: "P", widgets: [w, w2])]
        let h = ProfileHealth.check(profile: profile, song: song)
        XCTAssertEqual(h.issues(of: .alias).map { $0.detail }, ["GHOST"])
        XCTAssertEqual(h.issues(of: .clipNote).count, 2)
        XCTAssertEqual(h.issues(of: .deckGroup).map { $0.detail }, ["C"])
        XCTAssertEqual(h.issues(of: .deckTrack).map { $0.detail }, ["ZZZ"])
        XCTAssertEqual(h.issues(of: .groupTrack).map { $0.detail }, ["YYY"])
        XCTAssertEqual(h.issues(of: .control).count, 2)
        XCTAssertFalse(h.isClean)
        XCTAssertTrue(h.summary.hasPrefix("Not found in this set:"))
        let removed = ProfileHealth.removeStale(from: &profile, song: song)
        XCTAssertEqual(removed, 3)
        XCTAssertEqual(profile.trackAliases, ["KICK": "BOMBO"])
        XCTAssertEqual(profile.clipNotes.count, 1)
        XCTAssertTrue(ProfileHealth.check(profile: PerformerProfile(), song: LiveSongState()).summary.hasPrefix("No set"))

        var t = StageDeckTemplate(name: "n")
        t.clipNotes = ["KICK|\(existingClip)": "ok", "KICK|nope": "x", "ZED|c": "y"]
        let c = TemplateImporter.check(t, against: song)
        XCTAssertEqual(c.missingClips, ["KICK|nope"])
        XCTAssertEqual(c.missingTracks, ["ZED"])
    }
}


final class MixerBusTests: XCTestCase {
    func testReturnNamesKeepState() {
        var song = LiveSongState()
        song.returnTrackNames = ["A", "B"]
        song.returnTracks[1].volume = 0.3
        song.returnTrackNames = ["A-Reverb", "B-Delay", "C"]
        XCTAssertEqual(song.returnTracks.map { $0.name }, ["A-Reverb", "B-Delay", "C"])
        XCTAssertEqual(song.returnTracks[1].volume, 0.3)
        XCTAssertEqual(song.returnTracks[2].index, 2)
        XCTAssertEqual(song.numSends, 3)
    }

    func testPseudoTrackIndices() {
        XCTAssertEqual(LiveSongState.returnIndex(fromTrackIndex: LiveSongState.trackIndex(forReturn: 2)), 2)
        XCTAssertNil(LiveSongState.returnIndex(fromTrackIndex: 0))
        XCTAssertNil(LiveSongState.returnIndex(fromTrackIndex: LiveSongState.masterTrackIndex))
        let m = LiveCommand.deviceParameterNames(track: LiveSongState.masterTrackIndex, device: 1)
        XCTAssertEqual(m.address, "/live/master/device/get/parameters/name")
        XCTAssertEqual(m.arguments, [.int32(1)])
        let r = LiveCommand.setDeviceParameter(track: LiveSongState.trackIndex(forReturn: 1), device: 0, parameter: 1, value: 0.5)
        XCTAssertEqual(r.address, "/live/return/device/set/parameter/value")
        XCTAssertEqual(r.arguments, [.int32(1), .int32(0), .int32(1), .float(0.5)])
        let t = LiveCommand.deviceParameterListen(track: 3, device: 0, parameter: 1, start: true)
        XCTAssertEqual(t.address, "/live/device/start_listen/parameter/value")
        XCTAssertEqual(t.arguments, [.int32(3), .int32(0), .int32(1)])
        XCTAssertEqual(LiveCommand.trackDeviceNames(track: LiveSongState.masterTrackIndex).address, "/live/master/get/devices/name")
    }

    func testDecodesMasterAndReturnEvents() {
        if case .deviceParameterNames(let t, let d, let names) = LiveEventDecoder.decode(OSCMessage("/live/master/device/get/parameters/name", [.int32(0), .string("Device On"), .string("Frequency")])) {
            XCTAssertEqual(t, LiveSongState.masterTrackIndex); XCTAssertEqual(d, 0); XCTAssertEqual(names, ["Device On", "Frequency"])
        } else { XCTFail() }
        if case .deviceParameterValue(let t, let d, let p, let v) = LiveEventDecoder.decode(OSCMessage("/live/return/device/get/parameter/value", [.int32(1), .int32(0), .int32(1), .float(0.25)])) {
            XCTAssertEqual(t, LiveSongState.trackIndex(forReturn: 1)); XCTAssertEqual(d, 0); XCTAssertEqual(p, 1); XCTAssertEqual(v, 0.25, accuracy: 0.0001)
        } else { XCTFail() }
        if case .returnSend(let r, let s, let v) = LiveEventDecoder.decode(OSCMessage("/live/return/get/send", [.int32(0), .int32(1), .float(0.7)])) {
            XCTAssertEqual(r, 0); XCTAssertEqual(s, 1); XCTAssertEqual(v, 0.7, accuracy: 0.0001)
        } else { XCTFail() }
        if case .trackDeviceClassNames(let t, let names) = LiveEventDecoder.decode(OSCMessage("/live/master/get/devices/class_name", [.string("AutoFilter")])) {
            XCTAssertEqual(t, LiveSongState.masterTrackIndex); XCTAssertEqual(names, ["AutoFilter"])
        } else { XCTFail() }
    }

    func testBusesRoundTripAndTemplate() throws {
        var profile = PerformerProfile()
        profile.mixerBuses = [MixerBus(kind: .group, name: "A"), MixerBus(kind: .returnTrack, name: "liquid", showFilter: false), MixerBus(kind: .master)]
        profile.visibleSends = ["liquid", "bV"]
        profile.showGroupStrips = true
        let data = try JSONEncoder().encode(profile)
        let back = try JSONDecoder().decode(PerformerProfile.self, from: data)
        XCTAssertEqual(back.mixerBuses.map { $0.kind }, [.group, .returnTrack, .master])
        XCTAssertEqual(back.mixerBuses[1].showFilter, false)
        XCTAssertEqual(back.mixerBuses[2].displayName, "MASTER")
        XCTAssertEqual(back.visibleSends, ["liquid", "bV"])
        XCTAssertTrue(back.showGroupStrips)
        let song = DemoSet.make()
        XCTAssertEqual(profile.sendIndices(in: song), [0, 1])
        XCTAssertEqual(PerformerProfile().sendIndices(in: song), [0, 1, 2])

        let t = TemplateExporter.make(name: "buses", author: nil, description: nil, sections: TemplateSections(), profile: profile, project: SeqProject(), song: song)
        XCTAssertEqual(t.mixerBuses?.count, 3)
        XCTAssertEqual(t.layout?.visibleSends, ["liquid", "bV"])
        XCTAssertTrue(t.referencedTracks.contains("A"))
        XCTAssertTrue(TemplateImporter.check(t, against: song).isClean)
        var missing = t; missing.mixerBuses?[1].name = "nope"
        XCTAssertEqual(TemplateImporter.check(missing, against: song).missingTracks, ["nope (return)"])
        var fresh = PerformerProfile(); var proj = SeqProject()
        TemplateImporter.apply(t, mode: .replace, to: &fresh, project: &proj)
        XCTAssertEqual(fresh.mixerBuses.count, 3)
        XCTAssertTrue(fresh.showGroupStrips)
        XCTAssertTrue(t.contents.contains(where: { $0.contains("mixer bus") }))
    }

    func testDemoSetHasBusChannels() {
        let song = DemoSet.make()
        XCTAssertNotNil(song.masterAutoFilter)
        XCTAssertEqual(song.returnTracks.count, 3)
        XCTAssertNotNil(song.returnTracks[0].autoFilter)
        XCTAssertNotNil(song.groupTracks.first?.autoFilter)
        XCTAssertEqual(song.devices(ofTrack: LiveSongState.trackIndex(forReturn: 1)).count, 1)
        XCTAssertEqual(song.devices(ofTrack: LiveSongState.masterTrackIndex).count, 2)
    }
}

final class MixerLayoutTests: XCTestCase {
    func testTwoDecksFitInTwoRowsWithoutScrolling() {
        // 11" iPad landscape, master column removed: ~970 x 640, two decks of 10 stems + a 3-bus section.
        let plan = MixerLayoutPlan.plan(width: 970, height: 640, counts: [10, 10, 3], sends: 3)
        XCTAssertEqual(plan.rows, [[0], [1, 2]])
        XCTAssertTrue(plan.overflowingSections.isEmpty)
        XCTAssertGreaterThanOrEqual(plan.metrics.stripWidth, MixerLayoutPlan.minStripWidth)
        XCTAssertLessThanOrEqual(MixerLayoutPlan.rowWidth(strips: 13, sections: 2, stripWidth: plan.metrics.stripWidth), 970)
        XCTAssertEqual(plan.metrics.density, .medium)
        XCTAssertGreaterThanOrEqual(plan.metrics.faderHeight, 80)
    }

    func testFocusedDeckIsFullSize() {
        let plan = MixerLayoutPlan.plan(width: 970, height: 640, counts: [10, 10], sends: 3, focus: 1)
        XCTAssertEqual(plan.rows, [[1]])
        XCTAssertEqual(plan.metrics.density, .full)
        XCTAssertEqual(plan.metrics.stripWidth, 91)
    }

    func testManyDecksGoCompactNotScrolling() {
        let plan = MixerLayoutPlan.plan(width: 970, height: 640, counts: [7, 7, 8, 8, 10], sends: 2)
        XCTAssertEqual(plan.rows, [[0, 1], [2, 3], [4]])
        XCTAssertEqual(plan.metrics.density, .compact)
        XCTAssertTrue(plan.overflowingSections.isEmpty)
        XCTAssertGreaterThanOrEqual(plan.metrics.faderHeight, 60)
    }

    func testHugeDeckOverflows() {
        let plan = MixerLayoutPlan.plan(width: 600, height: 640, counts: [30], sends: 0)
        XCTAssertEqual(plan.overflowingSections, [0])
        XCTAssertEqual(plan.metrics.stripWidth, MixerLayoutPlan.minStripWidth)
    }
}

final class ResolverIndexTests: XCTestCase {
    func testUnloadedParametersResolveToMinusOne() {
        var song = LiveSongState()
        var t = LiveTrack(index: 0, name: "01 PULSO")
        t.devices = [LiveDevice(trackIndex: 0, index: 0, name: "ENERGIA subir y soltar", className: "AudioEffectGroupDevice")] // parameters not loaded
        song.tracks = [t]
        let target = ControlTarget.liveParameter(track: "01 PULSO", trackIndex: -1, device: "ENERGIA subir y soltar", deviceIndex: -1, parameter: "Energía", parameterIndex: -1)
        let r = ControlResolver.resolve(target, in: song)
        XCTAssertEqual(r?.track, 0); XCTAssertEqual(r?.device, 0); XCTAssertEqual(r?.parameter, -1)
        song.tracks[0].devices[0].parameters = [LiveDeviceParameter(index: 0, name: "Device On", value: 1, min: 0, max: 1), LiveDeviceParameter(index: 1, name: "Energía", value: 0, min: 0, max: 1)]
        XCTAssertEqual(ControlResolver.resolve(target, in: song)?.parameter, 1)
        XCTAssertNotEqual(song.deviceSignature, LiveSongState().deviceSignature)
    }
}
