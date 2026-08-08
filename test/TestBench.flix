mod TestBench {

    use Assert.assertEq
    use Assert.assertTrue
    use Assert.assertFalse
    use Assert.assertTrueWithMsg

    ///
    /// The benchmark's arithmetic.
    ///
    /// Deliberately not a test of the bot -- `TestDifficulty` does that, and running whole
    /// games here would make the suite slow for no extra confidence. What is tested is the
    /// reporting, because a benchmark that quietly reports the wrong number is worse than no
    /// benchmark: it is a confident wrong answer, and every decision downstream inherits it.
    ///
    /// Each case below is a mistake actually made while tuning this bot.
    ///

    def game(level: Int32, deaths: Int32, ticks: Int32): Outcome =
        { seed = 1i64, level = level, score = 0, lives = 3, deaths = deaths,
          kills = 0, drops = 0, ticks = ticks, invaded = true,
          endgame = { pixels = 0.0f32, ticks = 0, kills = 0 } }

    // -- rates, not totals ------------------------------------------------------------------

    @Test
    def testAShorterGameWithTheSameTotalIsWorse(): Unit \ Assert = {
        // The mistake that made three separate measurements read backwards. Two runs post the
        // same six deaths, but one crammed them into half the play; totals call that a tie.
        let steady = game(5, 6, 8000) :: Nil;
        let brief = game(5, 6, 4000) :: Nil;
        assertEq(expected = Bench.deaths(steady), Bench.deaths(brief));
        assertTrueWithMsg(
            Bench.rateTenths(Bench.deaths(brief), Bench.totalTicks(brief))
                > Bench.rateTenths(Bench.deaths(steady), Bench.totalTicks(steady)),
            "the shorter game did not register as the worse one")
    }

    @Test
    def testRareEventsSurviveTheArithmetic(): Unit \ Assert = {
        // The improvement this harness exists to detect. Per thousand ticks in tenths, four
        // deaths across seventy-eight thousand ticks prints as 0.0 -- and so did twenty-four,
        // before the scale was widened.
        let bad = Bench.rateTenths(24, 78000);
        let good = Bench.rateTenths(4, 78000);
        assertTrueWithMsg(bad > good and good > 0,
            "24 deaths and 4 deaths over the same play reported as ${bad} and ${good}")
    }

    @Test
    def testARateOfNothingIsNotADivisionByZero(): Unit \ Assert =
        assertEq(expected = 0, Bench.rateTenths(0, 0))

    // -- the summary ------------------------------------------------------------------------

    @Test
    def testTheMeanIsCarriedToATenth(): Unit \ Assert = {
        // Half a level is a real difference here -- it is the whole cost of the flank rule --
        // so the mean has to be able to express one.
        let runs = game(4, 0, 100) :: game(5, 0, 100) :: Nil;
        assertEq(expected = 45, Bench.meanLevelTenths(runs));
        assertEq(expected = "4.5", Bench.showTenths(Bench.meanLevelTenths(runs)))
    }

    @Test
    def testAnEmptyRunReportsNothingRatherThanDividingByZero(): Unit \ Assert =
        assertEq(expected = 0, Bench.meanLevelTenths(Nil))

    @Test
    def testEndgameMetricsAreAggregatedPerKill(): Unit \ Assert = {
        let first = { endgame = { pixels = 120.0f32, ticks = 60, kills = 1 } | game(4, 0, 100) };
        let second = { endgame = { pixels = 300.0f32, ticks = 156, kills = 2 } | game(5, 0, 100) };
        let measured = Bench.endgame(first :: second :: Nil);
        assertEq(expected = 420.0f32, measured#pixels);
        assertEq(expected = 216, measured#ticks);
        assertEq(expected = 3, measured#kills);
        assertEq(expected = 140.0f32, Bench.pixelsPerKill(measured));
        assertEq(expected = 72.0f32, Bench.ticksPerKill(measured))
    }

    @Test
    def testTheWorstCaseIsReportedSeparately(): Unit \ Assert = {
        // A mean hides the seed that collapsed, and the collapse is usually the finding: a
        // tuning that lifted the mean while dropping one seed to level 3 was rejected for it.
        let runs = game(5, 0, 100) :: game(5, 0, 100) :: game(3, 0, 100) :: game(6, 0, 100) :: Nil;
        assertEq(expected = 3, Bench.worstLevel(runs));
        assertEq(expected = 6, Bench.bestLevel(runs))
    }

    // -- guarding the measurement itself ----------------------------------------------------

    @Test
    def testAGameCutShortByTheBudgetIsFlagged(): Unit \ Assert = {
        // A run stopped by the budget has not been measured, it has been interrupted, and
        // every rate computed from it is a rate of something else.
        let finished = game(5, 0, 8000) :: Nil;
        let cut = game(5, 0, Bench.budget()) :: Nil;
        assertEq(expected = 0, Bench.unfinished(finished));
        assertEq(expected = 1, Bench.unfinished(cut))
    }

    @Test
    def testHowAGameEndedIsCounted(): Unit \ Assert = {
        // Invasion and running out of lives call for opposite fixes, and the bot has done both
        // during tuning. A summary that did not separate them sent the last round of work
        // after the wrong problem.
        let mixed = game(5, 0, 100) :: { invaded = false | game(4, 3, 100) } :: Nil;
        assertEq(expected = 1, Bench.invasions(mixed))
    }

    @Test
    def testTheSeedListIsBigEnoughToMeanSomething(): Unit \ Assert =
        // Bomb luck moves a single seed by two whole levels. Three seeds measure noise.
        assertTrueWithMsg(List.length(Bench.seeds()) >= 8,
            "only ${List.length(Bench.seeds())} seeds; that is not enough to tell a change from luck")

    @Test
    def testTheSeedsAreDistinct(): Unit \ Assert = {
        let seeds = Bench.seeds();
        assertEq(expected = List.length(seeds), Set.size(List.toSet(seeds)))
    }

    @Test
    def testTheWideSampleIsBigEnoughToSettleAClaim(): Unit \ Assert =
        // Ten seeds separate things that differ by a level and not things that differ by a
        // third of one, which is the size of every honest improvement this bot has had. The
        // narrowing rule scores 4.6 against a 4.9 baseline on the ten and 4.95 against 4.52 on
        // these, so this sample is not a nicety -- it is the difference between adopting a
        // change and rejecting the same change.
        assertTrueWithMsg(List.length(Bench.wideSeeds()) >= 50,
            "only ${List.length(Bench.wideSeeds())} wide seeds; that cannot settle a close call")

    @Test
    def testTheWideSeedsAreDistinct(): Unit \ Assert = {
        // Two families multiplied out can collide, and a repeated seed is a repeated game --
        // it would narrow the sample while appearing to widen it.
        let seeds = Bench.wideSeeds();
        assertEq(expected = List.length(seeds), Set.size(List.toSet(seeds)))
    }

    @Test
    def testTheWideSampleDoesNotQuietlyReplaceTheNarrowOne(): Unit \ Assert = {
        // Every figure recorded in docs/ARCHITECTURE.md is on `seeds()`. If the wide sample
        // ever became a superset of it, a later reader would compare numbers from two
        // different samples without anything saying so.
        let overlap = Set.intersection(List.toSet(Bench.seeds()), List.toSet(Bench.wideSeeds()));
        assertTrueWithMsg(Set.isEmpty(overlap), "the two samples share ${overlap}")
    }

    // -- the benchmark is reproducible ------------------------------------------------------

    @Test
    def testTheSameSeedGivesTheSameGame(): Unit \ Assert = {
        // The whole method rests on this: if a build's numbers moved, the build moved them.
        // One seed only -- the point is determinism, not coverage, and games are not cheap.
        let first = Bench.one(Demo.defaults(), 2026i64);
        let again = Bench.one(Demo.defaults(), 2026i64);
        assertEq(expected = first#level, again#level);
        assertEq(expected = first#score, again#score);
        assertEq(expected = first#ticks, again#ticks);
        assertEq(expected = first#deaths, again#deaths)
    }

    @Test
    def testAMeasuredGameActuallyEnded(): Unit \ Assert = {
        // If this ever fails the budget is too small, and every rate in the report is wrong.
        let outcome = Bench.one(Demo.defaults(), 2026i64);
        assertTrueWithMsg(outcome#ticks < Bench.budget(),
            "seed 2026 was still running after ${outcome#ticks} ticks; raise Bench.budget()")
    }

}
