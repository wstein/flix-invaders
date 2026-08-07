mod TestView {

    use Assert.assertEq
    use Assert.assertTrue
    use Assert.assertTrueWithMsg

    ///
    /// Layout, as far as it can be checked without a window.
    ///
    /// Two things are worth pinning here. Where the game's banners sit relative to the attract
    /// screen's panel, because the demo plays *behind* that panel and the two were overlapping
    /// -- a level banner at the middle of the field landed inside the title box and neither was
    /// readable. And the between-levels countdown, which is ordinary arithmetic and so has no
    /// business being discovered wrong on screen.
    ///

    def start(): World = Game.initial(2026i64)

    def texts(w: World): List[String] =
        Canvas.commands((640, 480), () -> View.render(w))
            |> List.filterMap(cmd -> match cmd {
                case DrawCmd.Text(s, _, _) => Some(s)
                case _ => None
            })

    /// The baseline of the first text matching `wanted`.
    def baselineOf(wanted: String, w: World): Option[Float32] =
        Canvas.commands((640, 480), () -> View.render(w))
            |> List.filterMap(cmd -> match cmd {
                case DrawCmd.Text(s, _, y) => if (s == wanted) Some(y) else None
                case _ => None
            })
            |> List.head

    // -- the banners clear the attract panel --------------------------------------------------

    @Test
    def testTheBannersSitAboveTheAttractPanel(): Unit \ Assert = {
        // The demo plays behind the title panel, so anything drawn at the centre of the field
        // is drawn underneath it. This is the constraint that was violated, and the reason
        // `Screens.attractPanelTop` is public at all.
        assertTrueWithMsg(View.bannerY() < Screens.attractPanelTop(),
            "the banner baseline ${View.bannerY()} is inside the attract panel, "
            + "which starts at ${Screens.attractPanelTop()}")
    }

    @Test
    def testEverythingTheClearedScreenDrawsClearsThePanel(): Unit \ Assert = {
        // Not just the banner: the countdown digit sits below it and is the thing most likely
        // to creep back into the panel when the layout is next adjusted.
        let cleared = { phase = Phase.Cleared, pause = Rules.levelPauseTicks() | start() };
        let below = Canvas.commands((640, 480), () -> View.render(cleared))
            |> List.filterMap(cmd -> match cmd {
                case DrawCmd.Text(s, _, y) =>
                    if (y >= Screens.attractPanelTop() and y < Rules.fieldHeight() - 40.0f32) Some(s)
                    else None
                case _ => None
            });
        assertTrueWithMsg(List.isEmpty(below),
            "these are drawn inside the attract panel: ${below}")
    }

    // -- the countdown -------------------------------------------------------------------------

    @Test
    def testEachNumberIsShownForExactlyOneSecond(): Unit \ Assert = {
        // The point of a countdown. Half-second steps still reach one at the right moment and
        // still look like a countdown, which is why this needs saying out loud.
        let held = List.range(1, Rules.levelPauseTicks() + 1)
            |> List.map(View.countdown)
            |> List.foldLeft((tally, n) -> Map.insertWith(a -> b -> a + b, n, 1, tally),
                             (Map.empty(): Map[Int32, Int32]));
        let wrong = Map.toList(held)
            |> List.filter(match (_, ticks) -> ticks != Rules.ticksPerSecond());
        assertTrueWithMsg(List.isEmpty(wrong),
            "these numbers are not shown for a second: ${wrong}")
    }

    @Test
    def testTheCountdownRunsThreeTwoOne(): Unit \ Assert = {
        let seen = List.range(1, Rules.levelPauseTicks() + 1)
            |> List.map(View.countdown)
            |> List.toSet;
        assertEq(expected = Set#{1, 2, 3}, seen)
    }

    @Test
    def testTheCountdownStartsFullAndEndsAtOne(): Unit \ Assert = {
        assertEq(expected = Rules.countdownSteps(), View.countdown(Rules.levelPauseTicks()));
        assertEq(expected = 1, View.countdown(1))
    }

    @Test
    def testTheCountdownNeverShowsZeroWhileThePauseRuns(): Unit \ Assert = {
        // `pause` reaches 1 and then the level changes, so nought is never a frame anyone sees.
        let zeros = List.range(1, Rules.levelPauseTicks() + 1)
            |> List.count(n -> View.countdown(n) <= 0);
        assertEq(expected = 0, zeros)
    }

    @Test
    def testTheCountdownOnlyEverGoesDown(): Unit \ Assert = {
        // In *time* order, which runs from a full pause down to one -- not in `pause` order,
        // where the digit naturally rises. Getting the rounding wrong would make it climb on
        // screen, which reads as a bug in the clock.
        let steps = List.range(1, Rules.levelPauseTicks() + 1)
            |> List.reverse
            |> List.map(View.countdown);
        let rising = List.zipWith((a, b) -> a < b, steps, List.drop(1, steps));
        assertTrueWithMsg(not List.exists(x -> x, rising),
            "the countdown climbs as the pause runs out: ${steps}")
    }

    @Test
    def testTheCountdownIsDrawnWhileTheLevelIsChanging(): Unit \ Assert = {
        let cleared = { phase = Phase.Cleared, pause = Rules.levelPauseTicks() | start() };
        assertTrueWithMsg(List.memberOf("${Rules.countdownSteps()}", texts(cleared)),
            "no countdown digit on the cleared screen: ${texts(cleared)}")
    }

    @Test
    def testThereIsNoCountdownDuringPlay(): Unit \ Assert = {
        // It belongs to the pause between waves, not to the game. Checked by position rather
        // than by text: a bare "3" is also what three lives in reserve looks like, which is
        // what the first version of this test actually caught.
        let atCountdown = Canvas.commands((640, 480), () -> View.render(start()))
            |> List.filterMap(cmd -> match cmd {
                case DrawCmd.Text(t, _, y) => if (y == View.countdownY()) Some(t) else None
                case _ => None
            });
        assertTrueWithMsg(List.isEmpty(atCountdown),
            "something is drawn in the countdown's place during play: ${atCountdown}")
    }

    // -- the banners themselves ------------------------------------------------------------------

    @Test
    def testTheLevelBannerNamesTheLevelBeingStarted(): Unit \ Assert = {
        // The one about to be played, not the one just finished.
        let cleared = { phase = Phase.Cleared, level = 4, pause = 30 | start() };
        assertTrue(List.memberOf("LEVEL 5", texts(cleared)))
    }

    @Test
    def testGameOverSaysHowToPlayAgain(): Unit \ Assert = {
        let lost = { phase = Phase.Lost | start() };
        let shown = texts(lost);
        assertTrue(List.memberOf("GAME OVER", shown));
        assertTrueWithMsg(List.exists(t -> String.contains(substr = "ENTER", t), shown),
            "game over does not say how to start again: ${shown}")
    }

    @Test
    def testGameOverAndTheLevelBannerShareABaseline(): Unit \ Assert = {
        // They are the same furniture in the same place; a reader should not have to hunt.
        let lost = { phase = Phase.Lost | start() };
        let cleared = { phase = Phase.Cleared, pause = 30 | start() };
        assertEq(expected = baselineOf("GAME OVER", lost),
                 baselineOf("LEVEL ${start()#level + 1}", cleared))
    }

}
