import XCTest
@testable import StageDeckCore

final class SequencerTests: XCTestCase {
    func makeEngine(tracks: Int = 2, seed: UInt64 = 1) -> SequencerEngine {
        var project = SeqProject()
        project.patterns = [Pattern.empty(name: "A", trackCount: tracks)]
        project.sendMIDIClock = false
        project.sendDefaultsOnPatternStart = false
        return SequencerEngine(project: project, rng: SeededGenerator(seed: seed))
    }

    func noteOns(_ events: [ScheduledEvent]) -> [(tick: Int, note: UInt8)] {
        events.compactMap { e in
            if case .noteOn(_, let n, _) = e.message { return (e.tick, n) }
            return nil
        }
    }

    /// Renders in chunks of `chunk` ticks and concatenates.
    func renderAll(_ engine: SequencerEngine, upTo end: Int, chunk: Int = 7) -> [ScheduledEvent] {
        var out: [ScheduledEvent] = []
        var t = 0
        while t < end {
            let to = min(end, t + chunk)
            out.append(contentsOf: engine.render(from: t, to: to))
            t = to
        }
        return out
    }

    func testFourOnTheFloor() {
        let e = makeEngine()
        for i in [0, 4, 8, 12] { e.project.patterns[0].tracks[0].steps[i] = Step.on(note: 36) }
        _ = e.start(atTick: 0)
        let events = renderAll(e, upTo: 384) // one bar
        let ons = noteOns(events)
        XCTAssertEqual(ons.map { $0.tick }, [0, 96, 192, 288])
        XCTAssertEqual(ons.map { $0.note }, [36, 36, 36, 36])
        // every on has a matching off 12 ticks later (length 0.5 step)
        let offs = events.compactMap { e -> Int? in if case .noteOff = e.message { return e.tick } else { return nil } }
        XCTAssertEqual(offs, [12, 108, 204, 300])
        // chunked and single-shot rendering produce identical results
        let e2 = makeEngine()
        for i in [0, 4, 8, 12] { e2.project.patterns[0].tracks[0].steps[i] = Step.on(note: 36) }
        _ = e2.start(atTick: 0)
        XCTAssertEqual(e2.render(from: 0, to: 384), events)
    }

    func testEventOrderingWithinTick() {
        let e = makeEngine()
        var s = Step.on(note: 60)
        s.locks = [74: 10]
        s.length = 1.0
        e.project.patterns[0].tracks[0].steps[0] = s
        e.project.patterns[0].tracks[0].steps[1] = Step.on(note: 60)
        _ = e.start(atTick: 0)
        let events = e.render(from: 0, to: 48)
        // Step 0 note (length 24) overlaps step 1 note (same pitch) → off is pulled to tick 24 and ordered before the on.
        let at24 = events.filter { $0.tick == 24 }
        XCTAssertEqual(at24.count, 2)
        if case .noteOff = at24[0].message {} else { XCTFail("off first") }
        if case .noteOn = at24[1].message {} else { XCTFail("on second") }
        XCTAssertEqual(events.first?.message, .controlChange(channel: 9, controller: 74, value: 10))
    }

    func testMicroTimingAndSwing() {
        let e = makeEngine()
        var s = Step.on(note: 36); s.micro = -5
        e.project.patterns[0].tracks[0].steps[2] = s
        var s2 = Step.on(note: 36); s2.micro = 11
        e.project.patterns[0].tracks[0].steps[15] = s2
        e.project.patterns[0].tracks[0].steps[1] = Step.on(note: 36)
        e.project.patterns[0].swing = 66
        _ = e.start(atTick: 0)
        let events = renderAll(e, upTo: 400, chunk: 5)
        let ons = noteOns(events).map { $0.tick }
        // step 1 is an off-beat → swing delay round(24*(2*0.66-1)) = 8
        XCTAssertEqual(ons, [32, 43, 379]) // step 15 is also an off-beat: 360 + 11 + 8
    }

    func testNegativeMicroOnFirstStepClampsToStart() {
        let e = makeEngine()
        var s = Step.on(note: 36); s.micro = -8
        e.project.patterns[0].tracks[0].steps[0] = s
        _ = e.start(atTick: 100)
        let events = e.render(from: 100, to: 200)
        XCTAssertEqual(noteOns(events).map { $0.tick }, [100])
    }

    func testTrackSpeedAndLengthPolymeter() {
        let e = makeEngine()
        e.project.patterns[0].tracks[0].length = 3
        e.project.patterns[0].tracks[0].speed = .x1_2
        e.project.patterns[0].tracks[0].steps[0] = Step.on(note: 36)
        _ = e.start(atTick: 0)
        let ons = noteOns(renderAll(e, upTo: 384)).map { $0.tick }
        // 3 steps of 48 ticks = loop of 144 ticks; cycle is 384 → steps at 0, 144, 288
        XCTAssertEqual(ons, [0, 144, 288])
        // next cycle restarts the track → 384
        let ons2 = noteOns(e.render(from: 384, to: 400)).map { $0.tick }
        XCTAssertEqual(ons2, [384])
    }

    func testTrigConditionsRatioAndFirst() {
        let e = makeEngine()
        e.project.patterns[0].masterLength = 64
        var s = Step.on(note: 36); s.condition = .ratio(n: 2, of: 2)
        e.project.patterns[0].tracks[0].steps[0] = s
        var f = Step.on(note: 38); f.condition = .first
        e.project.patterns[0].tracks[0].steps[4] = f
        _ = e.start(atTick: 0)
        let ons = noteOns(renderAll(e, upTo: 384 * 4))
        XCTAssertEqual(ons.filter { $0.note == 36 }.map { $0.tick }, [384, 384 * 3])
        XCTAssertEqual(ons.filter { $0.note == 38 }.map { $0.tick }, [96])
    }

    func testLoopCountersSurviveCycleWrap() {
        let e = makeEngine()
        e.project.patterns[0].masterLength = 16
        var s = Step.on(note: 36); s.condition = .ratio(n: 1, of: 4)
        e.project.patterns[0].tracks[0].steps[0] = s
        _ = e.start(atTick: 0)
        let ons = noteOns(renderAll(e, upTo: 384 * 8))
        XCTAssertEqual(ons.map { $0.tick }, [0, 384 * 4])
    }

    func testFillAndPreConditions() {
        let e = makeEngine()
        var f = Step.on(note: 40); f.condition = .fill
        var nf = Step.on(note: 41); nf.condition = .notFill
        var pre = Step.on(note: 42); pre.condition = .pre
        e.project.patterns[0].tracks[0].steps[0] = f
        e.project.patterns[0].tracks[0].steps[1] = nf
        e.project.patterns[0].tracks[0].steps[2] = pre
        _ = e.start(atTick: 0)
        var ons = noteOns(e.render(from: 0, to: 96)).map { $0.note }
        XCTAssertEqual(ons, [41, 42]) // no fill: !FILL plays, PRE follows it (true)
        e.fillActive = true
        ons = noteOns(e.render(from: 384, to: 480)).map { $0.note }
        XCTAssertEqual(ons, [40]) // FILL plays, !FILL false → PRE false
    }

    func testProbabilityIsDeterministicWithSeed() {
        let e = makeEngine(seed: 42)
        var s = Step.on(note: 36); s.probability = 50
        for i in 0..<16 { e.project.patterns[0].tracks[0].steps[i] = s }
        _ = e.start(atTick: 0)
        let count = noteOns(renderAll(e, upTo: 384 * 4)).count
        XCTAssertGreaterThan(count, 16)
        XCTAssertLessThan(count, 48)
        let e2 = makeEngine(seed: 42)
        for i in 0..<16 { e2.project.patterns[0].tracks[0].steps[i] = s }
        _ = e2.start(atTick: 0)
        XCTAssertEqual(noteOns(renderAll(e2, upTo: 384 * 4)).count, count)
    }

    func testRetrig() {
        let e = makeEngine()
        var s = Step.on(note: 36, velocity: 100)
        s.retrig = Retrig(count: 4, rateTicks: 6, velocityRamp: -50)
        e.project.patterns[0].tracks[0].steps[0] = s
        _ = e.start(atTick: 0)
        let events = e.render(from: 0, to: 48)
        let ons = events.compactMap { e -> (Int, UInt8)? in if case .noteOn(_, _, let v) = e.message { return (e.tick, v) } else { return nil } }
        XCTAssertEqual(ons.map { $0.0 }, [0, 6, 12, 18])
        XCTAssertEqual(ons.map { $0.1 }, [100, 83, 67, 50])
        let offs = events.compactMap { e -> Int? in if case .noteOff = e.message { return e.tick } else { return nil } }
        XCTAssertEqual(offs, [5, 11, 17, 23])
    }

    func testSlideOverlapsNextNote() {
        let e = makeEngine()
        var a = Step.on(note: 48); a.slide = true
        e.project.patterns[0].tracks[0].steps[0] = a
        e.project.patterns[0].tracks[0].steps[1] = Step.on(note: 50)
        _ = e.start(atTick: 0)
        let events = e.render(from: 0, to: 96)
        let seq = events.map { "\($0.tick):\($0.message)" }
        // note 48 on @0, note 50 on @24, 48 off @26 (overlap), 50 off @36
        XCTAssertEqual(seq, ["0:NoteOn ch10 C2 v100", "24:NoteOn ch10 D2 v100", "26:NoteOff ch10 C2", "36:NoteOff ch10 D2"])
    }

    func testStopSendsNoteOffsForSoundingNotes() {
        let e = makeEngine()
        var s = Step.on(note: 60); s.length = 8
        e.project.patterns[0].tracks[0].steps[0] = s
        _ = e.start(atTick: 0)
        _ = e.render(from: 0, to: 10)
        let stop = e.stop(atTick: 10)
        XCTAssertEqual(stop.count, 1)
        XCTAssertEqual(stop.first?.message, .noteOff(channel: 9, note: 60, velocity: 0))
        XCTAssertFalse(e.isRunning)
    }

    func testPatternQueueSwitchesAtBoundary() {
        let e = makeEngine()
        var p2 = Pattern.empty(name: "B", trackCount: 2)
        p2.tracks[0].steps[0] = Step.on(note: 50)
        e.project.patterns.append(p2)
        e.project.patterns[0].tracks[0].steps[0] = Step.on(note: 36)
        _ = e.start(atTick: 0)
        _ = e.render(from: 0, to: 100)
        e.queuePattern(1)
        var events = e.render(from: 100, to: 400)
        XCTAssertEqual(e.currentPatternIndex, 1)
        XCTAssertEqual(e.position(atTick: 390).patternIndex, 1)
        XCTAssertEqual(e.position(atTick: 383).patternIndex, 0)
        events.append(contentsOf: renderAll(e, upTo: 800, chunk: 100).filter { $0.tick >= 400 })
        let ons = noteOns(events)
        XCTAssertEqual(ons.map { $0.note }, [50, 50]) // 384 and 768
        XCTAssertEqual(ons.map { $0.tick }, [384, 768])
    }

    func testChainAndSongModes() {
        let e = makeEngine()
        var p2 = Pattern.empty(name: "B", trackCount: 2)
        p2.tracks[0].steps[0] = Step.on(note: 50)
        e.project.patterns.append(p2)
        e.project.patterns[0].tracks[0].steps[0] = Step.on(note: 36)
        e.project.arrangeMode = .chain
        e.project.chain = [0, 1]
        _ = e.start(atTick: 0)
        var notes = noteOns(renderAll(e, upTo: 384 * 4, chunk: 50)).map { $0.note }
        XCTAssertEqual(notes, [36, 50, 36, 50])

        let s = makeEngine()
        s.project.patterns.append(p2)
        s.project.patterns[0].tracks[0].steps[0] = Step.on(note: 36)
        s.project.arrangeMode = .song
        s.project.song = [SongEntry(patternIndex: 0, repeats: 2), SongEntry(patternIndex: 1, repeats: 1)]
        _ = s.start(atTick: 0)
        notes = noteOns(renderAll(s, upTo: 384 * 6, chunk: 50)).map { $0.note }
        XCTAssertEqual(notes, [36, 36, 50, 36, 36, 50])
    }

    func testMuteSoloAndScaleLock() {
        let e = makeEngine(tracks: 3)
        e.project.patterns[0].tracks[0].steps[0] = Step.on(note: 36)
        e.project.patterns[0].tracks[1].steps[0] = Step.on(note: 38)
        e.project.patterns[0].tracks[2].steps[0] = Step.on(note: 61) // C#
        e.project.patterns[0].tracks[2].isDrum = false
        e.project.patterns[0].tracks[2].scaleLock = true
        e.project.scaleName = Scale.major.name
        e.project.rootNote = 0
        e.project.patterns[0].tracks[1].solo = true
        e.project.patterns[0].tracks[2].solo = true
        _ = e.start(atTick: 0)
        let notes = noteOns(e.render(from: 0, to: 24)).map { $0.note }
        XCTAssertEqual(notes, [38, 60]) // track 0 silenced by solo, C# quantized down to C
    }

    func testClockAndStartStop() {
        let e = makeEngine()
        e.project.sendMIDIClock = true
        let start = e.start(atTick: 0)
        XCTAssertEqual(start.first?.message, .start)
        let events = renderAll(e, upTo: 96, chunk: 10)
        let clocks = events.filter { $0.message == .clock }.map { $0.tick }
        XCTAssertEqual(clocks, Array(stride(from: 0, to: 96, by: 4)))
        XCTAssertEqual(e.stop(atTick: 96).last?.message, .stop)
    }

    func testLFOEmitsOnChangeOnly() {
        let e = makeEngine()
        var lfo = LFO()
        lfo.enabled = true
        lfo.shape = .square
        lfo.periodTicks = 96
        lfo.depth = 100
        lfo.destination = .cc(74)
        e.project.patterns[0].tracks[0].lfos[0] = lfo
        _ = e.start(atTick: 0)
        let events = renderAll(e, upTo: 192, chunk: 13)
        let ccs = events.compactMap { ev -> (Int, UInt8)? in if case .controlChange(_, 74, let v) = ev.message { return (ev.tick, v) } else { return nil } }
        XCTAssertEqual(ccs.map { $0.0 }, [0, 48, 96, 144])
        XCTAssertEqual(ccs.map { $0.1 }, [127, 0, 127, 0])
    }

    func testDirections() {
        let e = makeEngine()
        e.project.patterns[0].tracks[0].length = 4
        for i in 0..<4 { e.project.patterns[0].tracks[0].steps[i] = Step.on(note: 60 + i) }
        e.project.patterns[0].tracks[0].direction = .pingpong
        _ = e.start(atTick: 0)
        let notes = noteOns(e.render(from: 0, to: 24 * 8)).map { Int($0.note) - 60 }
        XCTAssertEqual(notes, [0, 1, 2, 3, 2, 1, 0, 1])
        let r = makeEngine()
        r.project.patterns[0].tracks[0].length = 4
        for i in 0..<4 { r.project.patterns[0].tracks[0].steps[i] = Step.on(note: 60 + i) }
        r.project.patterns[0].tracks[0].direction = .reverse
        _ = r.start(atTick: 0)
        XCTAssertEqual(noteOns(r.render(from: 0, to: 96)).map { Int($0.note) - 60 }, [3, 2, 1, 0])
    }

    func testRecordQuantizesToNearestStep() {
        let e = makeEngine()
        _ = e.start(atTick: 0)
        e.record(note: 62, velocity: 90, track: 0, atTick: 50) // nearest step = 2 (48)
        XCTAssertTrue(e.project.patterns[0].tracks[0].steps[2].isOn)
        XCTAssertEqual(e.project.patterns[0].tracks[0].steps[2].notes, [62])
        e.record(note: 65, velocity: 90, track: 0, atTick: 47)
        XCTAssertEqual(e.project.patterns[0].tracks[0].steps[2].notes, [62, 65])
    }

    func testTickClock() {
        var c = TickClock(tempo: 120)
        XCTAssertEqual(c.secondsPerTick, 0.5 / 96, accuracy: 1e-12)
        XCTAssertEqual(c.tick(at: 1.0), 192, accuracy: 1e-9)
        c.setTempo(60, at: 1.0)
        XCTAssertEqual(c.tick(at: 1.0), 192, accuracy: 1e-9)
        XCTAssertEqual(c.tick(at: 2.0), 288, accuracy: 1e-9)
        XCTAssertEqual(c.time(ofTick: 288), 2.0, accuracy: 1e-9)
    }

    func testScalesAndEuclid() {
        XCTAssertEqual(Scale.major.quantize(note: 61, root: 0), 60)
        XCTAssertEqual(Scale.minor.quantize(note: 64, root: 0), 63)
        XCTAssertTrue(Scale.minorPentatonic.contains(note: 67, root: 0))
        XCTAssertEqual(Scale.major.note(degree: 7, root: 0, octave: 3), 72)
        XCTAssertEqual(Scale.major.note(degree: -1, root: 0, octave: 3), 59)
        XCTAssertEqual(Euclid.pattern(steps: 8, pulses: 3), [true, false, false, true, false, false, true, false])
        XCTAssertEqual(Euclid.pattern(steps: 16, pulses: 4), (0..<16).map { $0 % 4 == 0 })
        XCTAssertEqual(Euclid.pattern(steps: 8, pulses: 3, rotation: 1), [false, true, false, false, true, false, false, true])
        XCTAssertEqual(MIDINote.name(60), "C3")
        XCTAssertEqual(MIDINote.name(61), "C#3")
        XCTAssertEqual(MIDINote.name(0), "C-2")
    }

    func testMIDIMessageBytesAndParse() {
        XCTAssertEqual(MIDIMessage.noteOn(channel: 9, note: 36, velocity: 100).bytes, [0x99, 36, 100])
        XCTAssertEqual(MIDIMessage.pitchBend(channel: 0, value: 8192).bytes, [0xE0, 0x00, 0x40])
        XCTAssertEqual(MIDIMessage.parse([0x90, 60, 0]), .noteOff(channel: 0, note: 60, velocity: 0))
        XCTAssertEqual(MIDIMessage.parse([0xF8]), .clock)
        XCTAssertEqual(MIDIMessage.parse([0xB3, 1, 2]), .controlChange(channel: 3, controller: 1, value: 2))
    }
}
