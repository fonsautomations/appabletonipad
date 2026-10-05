import XCTest
@testable import StageDeckCore

final class AbletonSetTests: XCTestCase {
    static let xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <Ableton MajorVersion="5" MinorVersion="12.0_12203" Creator="Ableton Live 12.2.5">
      <LiveSet>
        <Tracks>
          <GroupTrack Id="100">
            <Name><EffectiveName Value="01 PULSO" /><UserName Value="" /></Name>
            <Color Value="14" />
            <TrackGroupId Value="-1" />
            <DeviceChain>
              <DeviceChain>
                <Devices>
                  <AudioEffectGroupDevice Id="1">
                    <UserName Value="ENERGIA subir y soltar" />
                    <MacroDisplayNames.0 Value="Energía" /><MacroDisplayNames.1 Value="Soltar" /><MacroDisplayNames.2 Value="Macro 3" />
                    <Branches><AudioEffectBranch><DeviceChain><DeviceChain><Devices><Eq8 Id="9"><UserName Value="" /></Eq8></Devices></DeviceChain></DeviceChain></AudioEffectBranch></Branches>
                  </AudioEffectGroupDevice>
                </Devices>
              </DeviceChain>
            </DeviceChain>
          </GroupTrack>
          <AudioTrack Id="132">
            <Name><EffectiveName Value="KICK" /></Name>
            <Color Value="15" />
            <TrackGroupId Value="100" />
            <DeviceChain>
              <MainSequencer>
                <ClipSlotList>
                  <ClipSlot Id="0"><ClipSlot><Value /></ClipSlot></ClipSlot>
                  <ClipSlot Id="1"><ClipSlot><Value>
                    <AudioClip Id="5">
                      <CurrentStart Value="0" /><CurrentEnd Value="8" />
                      <Loop><LoopStart Value="0" /><LoopEnd Value="4" /><LoopOn Value="true" /></Loop>
                      <Name Value="kick loop" /><Color Value="15" />
                    </AudioClip>
                  </Value></ClipSlot></ClipSlot>
                </ClipSlotList>
              </MainSequencer>
              <DeviceChain>
                <Devices>
                  <AudioEffectGroupDevice Id="2"><UserName Value="SOUND SYSTEM" /><MacroDisplayNames.0 Value="Boom" /><MacroDisplayNames.1 Value="Afinación" /></AudioEffectGroupDevice>
                  <AutoFilter Id="3"><UserName Value="" /></AutoFilter>
                </Devices>
              </DeviceChain>
            </DeviceChain>
          </AudioTrack>
          <MidiTrack Id="133">
            <Name><EffectiveName Value="GOTA" /></Name>
            <Color Value="24" />
            <TrackGroupId Value="-1" />
            <DeviceChain>
              <MainSequencer><ClipSlotList>
                <ClipSlot Id="0"><ClipSlot><Value><MidiClip Id="7"><CurrentStart Value="0" /><CurrentEnd Value="16" /><Loop><LoopStart Value="0" /><LoopEnd Value="16" /><LoopOn Value="false" /></Loop><Name Value="gota 1" /><Color Value="24" /></MidiClip></Value></ClipSlot></ClipSlot>
              </ClipSlotList></MainSequencer>
              <DeviceChain><Devices><InstrumentGroupDevice Id="4"><UserName Value="" /><MacroDisplayNames.0 Value="Macro 1" /></InstrumentGroupDevice></Devices></DeviceChain>
            </DeviceChain>
          </MidiTrack>
          <ReturnTrack Id="2"><Name><EffectiveName Value="A-A · CINTA" /></Name><Color Value="13" /><TrackGroupId Value="-1" /><DeviceChain><DeviceChain><Devices /></DeviceChain></DeviceChain></ReturnTrack>
        </Tracks>
        <MainTrack><DeviceChain><Mixer><Tempo><LomId Value="0" /><Manual Value="128.5" /></Tempo></Mixer><DeviceChain><Devices><AutoFilter Id="20"><UserName Value="" /></AutoFilter><AudioEffectGroupDevice Id="21"><UserName Value="MASTER FX" /><MacroDisplayNames.0 Value="Aire" /></AudioEffectGroupDevice></Devices></DeviceChain></DeviceChain></MainTrack>
        <Scenes>
          <Scene Id="0"><FollowAction /><Name Value="Océano" /></Scene>
          <Scene Id="1"><Name Value="Pulso" /></Scene>
        </Scenes>
      </LiveSet>
    </Ableton>
    """

    func testParsesStructure() throws {
        let snap = try AbletonSetParser.parse(xml: Data(AbletonSetTests.xml.utf8), name: "PLAYFIELD")
        XCTAssertEqual(snap.creator, "Ableton Live 12.2.5")
        XCTAssertEqual(snap.tempo, 128.5)
        XCTAssertEqual(snap.scenes, ["Océano", "Pulso"])
        XCTAssertEqual(snap.tracks.map { $0.name }, ["01 PULSO", "KICK", "GOTA", "A-A · CINTA"])
        XCTAssertEqual(snap.tracks.map { $0.kind }, [.group, .audio, .midi, .return])
        XCTAssertEqual(snap.tracks[1].groupId, 100)
        // nested rack devices inside branches are not counted as track devices
        XCTAssertEqual(snap.tracks[0].devices.count, 1)
        XCTAssertEqual(snap.tracks[0].devices[0].macroNames, ["Energía", "Soltar", "Macro 3"])
        XCTAssertEqual(snap.tracks[0].devices[0].namedMacros, ["Energía", "Soltar"])
        XCTAssertEqual(snap.tracks[1].devices.map { $0.displayName }, ["SOUND SYSTEM", "Auto Filter"])
        XCTAssertEqual(snap.tracks[1].clips.count, 1)
        XCTAssertEqual(snap.tracks[1].clips[0].sceneIndex, 1)
        XCTAssertEqual(snap.tracks[1].clips[0].name, "kick loop")
        XCTAssertEqual(snap.tracks[1].clips[0].length, 4) // looping → loop length
        XCTAssertEqual(snap.tracks[2].clips[0].length, 16) // not looping → start/end
        XCTAssertTrue(snap.tracks[2].clips[0].isMIDI)

        let song = snap.toSong()
        XCTAssertEqual(song.tracks.count, 3)
        XCTAssertTrue(song.tracks[0].isGroup)
        XCTAssertEqual(song.tracks[1].groupTrackIndex, 0)
        XCTAssertTrue(song.tracks[2].hasMIDIInput)
        XCTAssertEqual(song.returnTrackNames, ["A-A · CINTA"])
        XCTAssertEqual(song.returnTracks.count, 1)
        XCTAssertEqual(song.returnTracks[0].sends, [0])
        XCTAssertEqual(snap.masterDevices.map { $0.displayName }, ["Auto Filter", "MASTER FX"])
        XCTAssertEqual(song.masterDevices.map { $0.name }, ["Auto Filter", "MASTER FX"])
        XCTAssertEqual(song.masterDevices[0].trackIndex, LiveSongState.masterTrackIndex)
        XCTAssertEqual(song.masterDevices[1].parameters.map { $0.name }, ["Device On", "Aire"])
        XCTAssertNotNil(song.masterAutoFilter)
        XCTAssertEqual(song.tracks[1].devices[1].className, "AutoFilter")
        XCTAssertNotNil(song.tracks[1].autoFilter?.parameterIndex(named: "Frequency"))
        XCTAssertEqual(song.tracks[0].devices[0].parameters.map { $0.name }, ["Device On", "Energía", "Soltar", "Macro 3"])
        XCTAssertEqual(song.clip(track: 1, scene: 1)?.name, "kick loop")
        XCTAssertEqual(song.tracks[1].color, LiveColor(rgb: 0xF66C03))

        let t = snap.makeTemplate(options: AbletonSetSnapshot.TemplateOptions())
        XCTAssertEqual(t.decks?.map { $0.groupTrackName }, ["01 PULSO"])
        XCTAssertEqual(t.controlPages?.count, 1)
        let page = t.controlPages![0]
        XCTAssertEqual(page.name, "01 PULSO")
        XCTAssertEqual(page.widgets.map { $0.name }, ["Energía", "Soltar", "Boom", "Afinación"])
        if case .liveParameter(let track, _, let device, _, let param, let pi) = page.widgets[2].target {
            XCTAssertEqual(track, "KICK"); XCTAssertEqual(device, "SOUND SYSTEM"); XCTAssertEqual(param, "Boom"); XCTAssertEqual(pi, 1)
        } else { XCTFail("expected live target") }
        // Resolves against the offline song and would resolve against the real Live set (same names)
        XCTAssertEqual(ControlResolver.resolve(page.widgets[2].target, in: song), ControlResolver.Resolved(track: 1, device: 0, parameter: 1))
        XCTAssertTrue(TemplateImporter.check(t, against: song).isClean)
        XCTAssertNoThrow(try StageDeckTemplate.parse(try t.encodeJSON()))
    }

    func testRejectsOtherXML() {
        XCTAssertThrowsError(try AbletonSetParser.parse(xml: Data("<?xml version=\"1.0\"?><Other><Tracks/></Other>".utf8)))
        XCTAssertThrowsError(try AbletonSetParser.parse(xml: Data("not xml at all".utf8)))
    }
}
