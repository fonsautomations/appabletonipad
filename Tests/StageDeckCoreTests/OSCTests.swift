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
