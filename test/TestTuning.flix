mod TestTuning {

    use Assert.assertEq
    use Assert.assertTrue
    use Assert.assertTrueWithMsg

    ///
    /// The tuning file's format.
    ///
    /// Pure throughout, like `TestScores` -- deciding what a tuning file means needs no
    /// handler. Reading and writing one is exercised in `TestScoresFile`'s company, on an
    /// in-memory filesystem.
    ///

    /// Records have no `Eq`, so tunings are compared by their own rendering.
    def shown(t: Tuning): String = Tuning.encode(t)

    def decoded(text: String): Tuning \ Assert = match Tuning.decode(Demo.defaults(), text) {
        case Ok(t) => t
        case Err(why) => { Assert.fail("decode failed: ${why}"); Demo.defaults() }
    }

    // -- the round trip ---------------------------------------------------------------------

    @Test
    def testATuningSurvivesEncodingAndDecoding(): Unit \ Assert = {
        let t = { dangerWidth = 44.5f32, stragglers = 2, aimJitter = 3 | Demo.defaults() };
        assertEq(expected = shown(t), shown(decoded(Tuning.encode(t))))
    }

    @Test
    def testTheDefaultsRoundTrip(): Unit \ Assert =
        assertEq(expected = shown(Demo.defaults()), shown(decoded(Tuning.encode(Demo.defaults()))))

    @Test
    def testWhatIsWrittenIsValidJson(): Unit \ Assert =
        assertTrue(Result.isOk(Util.Json.parse(Tuning.encode(Demo.defaults()))))

    // -- a file of overrides ------------------------------------------------------------------

    @Test
    def testAFileNamingOneFieldIsAValidFile(): Unit \ Assert = {
        // The point of the format. Trying a single change should not mean writing out all
        // sixteen numbers, and a config written by an older build must still load.
        let t = decoded("{ \"dangerWidth\": 12.5 }");
        assertEq(expected = 12.5f32, t#dangerWidth);
        assertEq(expected = Demo.defaults()#selfPreservation, t#selfPreservation);
        assertEq(expected = Demo.defaults()#stragglers, t#stragglers)
    }

    @Test
    def testAConfigCannotSwitchOffFlankFinishing(): Unit \ Assert = {
        // A config once carried `stragglers: 0`, written by a search optimising level reached,
        // and the game read it and quietly stopped narrowing the formation -- the demo looked
        // wrong and nothing in the code had changed. That key is now ignored in both
        // directions, so a stale config recovers on its own.
        let t = decoded("{ \"stragglers\": 0, \"dangerWidth\": 55 }");
        assertEq(expected = Demo.defaults()#stragglers, t#stragglers);
        assertEq(expected = 55.0f32, t#dangerWidth)
    }

    @Test
    def testTheFileDoesNotMentionStragglers(): Unit \ Assert =
        assertTrueWithMsg(not String.contains(substr = "stragglers", Tuning.encode(Demo.defaults())),
            "the tuning file offers a key that would overturn a design decision")

    @Test
    def testAnUnknownFieldIsIgnoredRatherThanFatal(): Unit \ Assert = {
        // A field this build has never heard of is somebody else's business, or a leftover.
        let t = decoded("{ \"dangerWidth\": 40, \"warpFactor\": 9 }");
        assertEq(expected = 40.0f32, t#dangerWidth)
    }

    @Test
    def testAFieldOfTheWrongKindFallsBackRatherThanFailing(): Unit \ Assert = {
        // A typo costs you that number, not the run.
        let t = decoded("{ \"dangerWidth\": \"wide\", \"calm\": 0.5 }");
        assertEq(expected = Demo.defaults()#dangerWidth, t#dangerWidth);
        assertEq(expected = 0.5f32, t#calm)
    }

    @Test
    def testOnlyBrokenJsonIsAnError(): Unit \ Assert = {
        assertTrue(Result.isErr(Tuning.decode(Demo.defaults(), "{ not json")));
        assertTrue(Result.isErr(Tuning.decode(Demo.defaults(), "[1, 2, 3]")));
        assertTrue(Result.isOk(Tuning.decode(Demo.defaults(), "{}")))
    }

    // -- keeping the bot usable -----------------------------------------------------------------

    @Test
    def testAbsurdValuesAreClampedRatherThanObeyed(): Unit \ Assert = {
        // A hand-edited file, or a search that wandered, should not be able to produce a bot
        // that never moves or divides by zero.
        let wild = { dangerWidth = -100.0f32, urgency = 0.0f32, calm = 9.0f32,
                     stragglers = 99, lapseOneIn = 0, fireWindow = 0.0f32 | Demo.defaults() };
        let fixed = Tuning.sane(wild);
        assertTrueWithMsg(fixed#dangerWidth > 0.0f32, "a negative threat width survived");
        assertTrueWithMsg(fixed#urgency > 0.0f32, "a zero urgency survived, which divides by zero");
        assertTrueWithMsg(fixed#calm <= 1.0f32, "calm above 1 survived; it is a fraction");
        assertTrueWithMsg(fixed#lapseOneIn >= 1, "a one-in-zero chance survived");
        // A window below the exact overlap is a bot that may not fire at all; above 20 it is
        // one firing across the whole field at nothing.
        assertTrueWithMsg(fixed#fireWindow >= 1.0f32, "a firing window narrower than a hit survived");
        assertTrueWithMsg(Tuning.sane({ fireWindow = 500.0f32 | Demo.defaults() })#fireWindow <= 20.0f32,
            "a firing window wider than the field survived")
    }

    @Test
    def testASensibleTuningIsLeftAlone(): Unit \ Assert =
        // Clamping must not quietly move the numbers the game actually ships with.
        assertEq(expected = shown(Demo.defaults()), shown(Tuning.sane(Demo.defaults())))

    // -- the search's judgement ------------------------------------------------------------------

    @Test
    def testMeritPrefersTheHigherMeanLevel(): Unit \ Assert = {
        let low = { seed = 1i64, level = 4, score = 0, lives = 3, deaths = 0,
                    kills = 0, drops = 0, ticks = 1000, invaded = true,
                    endgame = { pixels = 0.0f32, ticks = 0, kills = 0 } };
        let high = { level = 5 | low };
        assertTrue(Bench.merit(high :: Nil) > Bench.merit(low :: Nil))
    }

    @Test
    def testMeritPrefersTheSteadierBotAtEqualMeans(): Unit \ Assert = {
        // A mean of 4.5 made of 4 and 5 is worth more than one made of 3 and 6: a demo that
        // collapses one game in six reads as broken rather than fallible.
        let base = { seed = 1i64, level = 4, score = 0, lives = 3, deaths = 0,
                     kills = 0, drops = 0, ticks = 1000, invaded = true,
                     endgame = { pixels = 0.0f32, ticks = 0, kills = 0 } };
        let steady = base :: { level = 5 | base } :: Nil;
        let swingy = { level = 3 | base } :: { level = 6 | base } :: Nil;
        assertEq(expected = Bench.meanLevelTenths(steady), Bench.meanLevelTenths(swingy));
        assertTrueWithMsg(Bench.merit(steady) > Bench.merit(swingy),
            "the search would have taken the tuning that collapses on one seed")
    }

}
