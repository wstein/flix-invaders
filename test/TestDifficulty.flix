mod TestDifficulty {

    use Assert.assertTrueWithMsg

    ///
    /// Is the game actually playable?
    ///
    /// Balance is easy to break by accident and hard to notice from unit tests: every rule
    /// can be individually correct while the combination is unwinnable. This drives the real
    /// game with a competent player and asserts on the outcome.
    ///
    /// It caught a real regression. With the march speed-up at five times, a bot that never
    /// misses cleared only 43-52% of the first formation and never reached level two --
    /// which matched exactly what a human reported after playing it.
    ///

    ///
    /// The bot under test is the one the game ships -- `Demo.aim`, the same code the attract
    /// screen drives. Two copies would let the demo drift away from the thing this file
    /// measures.
    ///
    def aim(w: World): Snapshot = Demo.aim(w)

    def playRaw(budget: Int32, w: World): World \ Sound =
        if (budget <= 0 or w#phase == Phase.Lost) w
        else playRaw(budget - 1, Game.step(w, aim(w)))

    def play(budget: Int32, w: World): World =
        Sound.runWithNoOp(() -> playRaw(budget, w))

    /// The same, driven by the shaky bot the attract screen actually runs.
    def playShakyRaw(budget: Int32, w: World, hand: Hand): World \ Sound =
        if (budget <= 0 or w#phase == Phase.Lost) w
        else {
            let (input, next) = Demo.imperfect(w, hand);
            playShakyRaw(budget - 1, Game.step(w, input), next)
        }

    def playShaky(budget: Int32, seed: Int64): World =
        Sound.runWithNoOp(() -> playShakyRaw(budget, Game.initial(seed), Demo.fresh(seed)))

    /// Long enough for a good run to end on its own rather than on the budget.
    def wholeGame(): Int32 = 30000

    def seeds(): List[Int64] = 2026i64 :: 7i64 :: 99i64 :: 1234i64 :: 555i64 :: 31i64 :: Nil

    /// How long the formation takes to land if nothing shoots it and bombs are ignored.
    def descentTicks(): Int32 = {
        def loop(n, w) =
            if (n <= 0 or w#phase == Phase.Lost) n
            else loop(n - 1, Game.step({ lives = 99, bombs = Nil | w }, Input.empty()));
        20000 - Sound.runWithNoOp(() -> loop(20000, Game.initial(1i64)))
    }

    @Test
    def testACompetentPlayerGetsPastTheFirstLevel(): Unit \ Assert = {
        // Not every seed -- bombs are luck -- but every one of them should manage this.
        let cleared = List.count(seed -> play(6000, Game.initial(seed))#level > 1, seeds());
        assertTrueWithMsg(cleared == List.length(seeds()),
            "a bot that never misses cleared level one on only ${cleared} of ${List.length(seeds())} seeds; "
            + "the game is too hard")
    }

    ///
    /// The demo should look like somebody who is good at this, and then lose.
    ///
    /// This is the acceptance criterion for the attract screen: a bot that dies on level one
    /// is embarrassing, and one that plays forever never shows the player a game ending.
    /// Both bounds are load-bearing -- the lower one guards the difficulty curve, the upper
    /// one guards the bot's deliberate imperfection.
    ///
    @Test
    def testTheDemoSurvivesToAboutLevelFour(): Unit \ Assert = {
        let reached = List.map(seed -> playShaky(wholeGame(), seed)#level, seeds());
        let good = List.count(level -> level >= 4, reached);
        assertTrueWithMsg(good >= List.length(seeds()) - 1,
            "the demo reached only ${reached} across ${List.length(seeds())} seeds; "
            + "it should get to about level four");
        assertTrueWithMsg(List.forAll(level -> level < 10, reached),
            "the demo ran away to ${reached}; it is meant to be beatable, not immortal")
    }

    @Test
    def testTheFirstLevelIsNotTrivialEither(): Unit \ Assert = {
        // The other side of the same guard: if the game never ends, there is no pressure.
        let ended = List.count(seed -> playShaky(wholeGame(), seed)#phase == Phase.Lost, seeds());
        assertTrueWithMsg(ended == List.length(seeds()),
            "the bot was still alive on ${List.length(seeds()) - ended} seeds after "
            + "${wholeGame()} ticks; the game is too easy")
    }

    @Test
    def testThereIsTimeToClearTheFormation(): Unit \ Assert = {
        // Every invader must be reachable within the descent, with room to spare for misses.
        let ticks = descentTicks();
        let shots = ticks / Rules.fireCooldown();
        assertTrueWithMsg(shots > Rules.totalInvaders() * 3,
            "only ${shots} shots fit into the ${ticks}-tick descent for ${Rules.totalInvaders()} invaders")
    }

    @Test
    def testTheDescentIsNotSoSlowThatNothingHappens(): Unit \ Assert = {
        let ticks = descentTicks();
        assertTrueWithMsg(ticks < 7200,
            "the formation takes ${ticks} ticks (${ticks / 60}s) to land, which is a stalemate")
    }

}
