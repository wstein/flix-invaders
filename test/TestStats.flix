mod TestStats {

    use Assert.assertEq
    use Assert.assertTrue
    use Assert.assertFalse
    use Assert.assertTrueWithMsg

    ///
    /// The telemetry overlay.
    ///
    /// Two halves, both testable without a window. The arithmetic that turns nanoseconds into
    /// something readable, and the promise that switching the display on does not change the
    /// game underneath it -- which is the whole reason it is safe to leave in.
    ///

    def second(): Int64 = 1000000000i64
    def milli(): Int64 = 1000000i64

    def start(): Session = Session.initial(2026i64)

    // -- reading a frame ----------------------------------------------------------------------

    @Test
    def testTheFirstFrameIsBelievedWhole(): Unit \ Assert = {
        // Blending the first sample against an initial nought would show the frame rate
        // climbing from 0 to 60 over the first second of every run, which looks like a stall
        // and is really just the average filling up.
        let sample60 = { frameNs = second() / 60i64, simNs = 0i64, drawNs = 0i64, steps = 1, clamped = false };
        let after = Stats.observe(Stats.empty(), sample60);
        assertTrueWithMsg(after#fps > 55.0f32 and after#fps < 65.0f32,
            "the first frame reported ${after#fps} fps instead of about 60")
    }

    @Test
    def testLaterFramesAreSmoothed(): Unit \ Assert = {
        // A frame time read off a moving screen has to settle, or every digit flickers and it
        // tells you nothing.
        let sample60 = { frameNs = second() / 60i64, simNs = 0i64, drawNs = 0i64, steps = 1, clamped = false };
        let sample10 = { frameNs = second() / 10i64, simNs = 0i64, drawNs = 0i64, steps = 1, clamped = false };
        let steady = Stats.observe(Stats.empty(), sample60);
        let spike = Stats.observe(steady, sample10);
        assertTrueWithMsg(spike#fps > 50.0f32,
            "one slow frame dragged the rate to ${spike#fps}; the average is not smoothing")
    }

    @Test
    def testAStoppedClockIsNotAnInfiniteFrameRate(): Unit \ Assert = {
        // Coarse timers report a gap of nought between frames. Dividing by it is arithmetically
        // honest and useless to read.
        assertEq(expected = 0.0f32, Stats.rateFrom(0i64));
        assertEq(expected = 0.0f32, Stats.rateFrom(-5i64))
    }

    @Test
    def testTimingsAreReportedInMilliseconds(): Unit \ Assert = {
        let sample = { frameNs = second() / 60i64, simNs = 2i64 * milli(), drawNs = 3i64 * milli(), steps = 1, clamped = false };
        let after = Stats.observe(Stats.empty(), sample);
        assertEq(expected = 2.0f32, after#simMs);
        assertEq(expected = 3.0f32, after#drawMs)
    }

    @Test
    def testFramesAndCatchUpsAccumulate(): Unit \ Assert = {
        // Steps are this frame's; frames and catch-ups are running totals, because one dropped
        // frame is noise and a rising count is a problem.
        let sampleClamped = { frameNs = second() / 60i64, simNs = 0i64, drawNs = 0i64, steps = 1, clamped = true };
        let sample3 = { frameNs = second() / 60i64, simNs = 0i64, drawNs = 0i64, steps = 3, clamped = false };
        let one = Stats.observe(Stats.empty(), sampleClamped);
        let two = Stats.observe(one, sample3);
        assertEq(expected = 2, two#frames);
        assertEq(expected = 1, two#catchUps);
        assertEq(expected = 3, two#steps)
    }

    // -- printing numbers ----------------------------------------------------------------------

    @Test
    def testOneDecimalRoundsRatherThanTruncates(): Unit \ Assert = {
        assertEq(expected = "2.0", Stats.oneDecimal(1.99f32));
        assertEq(expected = "59.9", Stats.oneDecimal(59.94f32));
        assertEq(expected = "0.0", Stats.oneDecimal(0.0f32))
    }

    @Test
    def testSubMillisecondCostsKeepTwoPlaces(): Unit \ Assert = {
        // The simulation costs about 0.13ms. To one decimal that is 0.1, which cannot tell an
        // improvement from a regression -- and telling those apart is what this is for.
        assertEq(expected = "0.13", Stats.twoDecimals(0.13f32));
        assertEq(expected = "1.74", Stats.twoDecimals(1.74f32));
        assertEq(expected = "0.05", Stats.twoDecimals(0.05f32))
    }

    // -- the overlay ---------------------------------------------------------------------------

    @Test
    def testItIsOffUntilAskedFor(): Unit \ Assert =
        assertFalse(start()#nerds)

    @Test
    def testF3TurnsItOnAndOffAgain(): Unit \ Assert = {
        let press = Input.holding(Key.F3 :: Nil);
        let shown = Sound.runWithNoOp(() -> Session.step(start(), press));
        assertTrue(shown#nerds);
        let hidden = Sound.runWithNoOp(() -> Session.step(shown, press));
        assertFalse(hidden#nerds)
    }

    @Test
    def testItRespondsToThePressNotTheHold(): Unit \ Assert = {
        // Held down, an edge-triggered toggle stays put; a level-triggered one strobes at
        // sixty hertz and settles wherever the frame count happens to leave it.
        let held = Input.diff(previous = Set#{Key.F3}, current = Set#{Key.F3}, mouseX = 0, mouseY = 0);
        let shown = Sound.runWithNoOp(() -> Session.step(start(), Input.holding(Key.F3 :: Nil)));
        let still = Sound.runWithNoOp(() -> Session.step(shown, held));
        assertTrue(still#nerds)
    }

    @Test
    def testShowingItChangesNothingButTheScreen(): Unit \ Assert = {
        // The reason it is safe to leave in. If the overlay perturbed the game, a player who
        // opened it would be playing a different one -- and the replay tests would be lying.
        let press = Input.holding(Key.F3 :: Nil);
        let plain = Sound.runWithNoOp(() -> Session.step(start(), Input.empty()));
        let withOverlay = Sound.runWithNoOp(() -> Session.step(start(), press));
        assertEq(expected = Game.digest(Session.onScreen(plain)),
                 Game.digest(Session.onScreen(withOverlay)))
    }

    @Test
    def testItDrawsNothingWhileItIsOff(): Unit \ Assert = {
        let quiet = Canvas.commands((640, 480), () -> Screens.render(start(), Stats.empty()));
        let loud = Canvas.commands((640, 480), () ->
            Screens.render({ nerds = true | start() }, Stats.empty()));
        assertTrueWithMsg(List.length(loud) > List.length(quiet),
            "the overlay drew nothing when switched on")
    }

    @Test
    def testItReportsTheThingsWorthKnowing(): Unit \ Assert = {
        let labels = Screens.nerdLines(start(), Session.onScreen(start()), Stats.empty())
            |> List.map(fst);
        List.forEach(wanted ->
            assertTrueWithMsg(List.memberOf(wanted, labels),
                "the overlay does not report ${wanted}: ${labels}"),
            "FPS" :: "SIM" :: "DRAW" :: "STEPS" :: "TICK" :: "INVADERS" :: "DIGEST" :: Nil)
    }

    @Test
    def testTheDigestShownMatchesTheOneReplaysCompare(): Unit \ Assert = {
        // It is only useful if it is the same fingerprint, so two runs can be checked by eye.
        let w = Session.onScreen(start());
        let shown = Screens.nerdLines(start(), w, Stats.empty())
            |> List.filterMap(match (label, value) -> if (label == "DIGEST") Some(value) else None)
            |> List.head
            |> Option.getWithDefault("");
        assertTrueWithMsg(String.startsWith(prefix = String.takeLeft(20, shown), Game.digest(w)),
            "the overlay's digest ${shown} is not a prefix of ${Game.digest(w)}")
    }

    @Test
    def testTheOverlayFitsOnTheScreen(): Unit \ Assert = {
        // It is furniture in a corner, not a wall of text over the game.
        let lines = Screens.nerdLines(start(), Session.onScreen(start()), Stats.empty());
        assertTrueWithMsg(List.length(lines) <= 16,
            "the overlay has grown to ${List.length(lines)} lines and will not fit")
    }

}
