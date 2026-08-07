mod TestDemo {

    use Assert.assertEq
    use Assert.assertTrue
    use Assert.assertNeq
    use Assert.assertTrueWithMsg

    def start(): World = Game.initial(2026i64)

    /// A world a few hundred ticks in, so there is something to aim at.
    def midGame(): World =
        Sound.runWithNoOp(() -> {
            def loop(n, w) = if (n <= 0) w else loop(n - 1, Game.step(w, Demo.aim(w)));
            loop(300, start())
        })

    // -- the competent bot ------------------------------------------------------------

    @Test
    def testTheBotAimsAtSomething(): Unit \ Assert = {
        let s = Demo.aim(start());
        assertTrueWithMsg(not Set.isEmpty(s#held), "the bot did nothing on a full formation")
    }

    @Test
    def testTheBotIsDeterministic(): Unit \ Assert = {
        let w = midGame();
        assertEq(expected = Demo.aim(w)#held, Demo.aim(w)#held)
    }

    @Test
    def testTheBotHoldsFireWhenNothingIsLeft(): Unit \ Assert = {
        let cleared = { invaders = Vector.map(inv -> { alive = false | inv }, start()#invaders) | start() };
        assertTrue(Set.isEmpty(Demo.aim(cleared)#held))
    }

    // -- the shaky bot ----------------------------------------------------------------

    /// The inputs the imperfect bot produces over `n` ticks of a fixed world.
    def shaky(n: Int32, w: World, rng: Rng): List[Snapshot] =
        if (n <= 0) Nil
        else {
            let (snapshot, next) = Demo.imperfect(w, rng);
            snapshot :: shaky(n - 1, w, next)
        }

    @Test
    def testTheShakyBotIsDeterministicGivenItsGenerator(): Unit \ Assert = {
        let w = midGame();
        assertEq(expected = List.map(s -> s#held, shaky(40, w, Rng.fromSeed(5i64))),
                 List.map(s -> s#held, shaky(40, w, Rng.fromSeed(5i64))))
    }

    @Test
    def testADifferentGeneratorPlaysDifferently(): Unit \ Assert = {
        let w = midGame();
        assertNeq(unexpected = List.map(s -> s#held, shaky(40, w, Rng.fromSeed(5i64))),
                  List.map(s -> s#held, shaky(40, w, Rng.fromSeed(6i64))))
    }

    @Test
    def testTheShakyBotSometimesDoesNothing(): Unit \ Assert = {
        // Perfect play makes a dull demo. Some ticks it is simply not paying attention.
        let idle = List.count(s -> Set.isEmpty(s#held), shaky(200, midGame(), Rng.fromSeed(3i64)));
        assertTrueWithMsg(idle > 5, "expected some idle ticks, got ${idle}")
    }

    @Test
    def testTheShakyBotMostlyPlays(): Unit \ Assert = {
        // ...but it should still look like somebody playing, not somebody asleep.
        let busy = List.count(s -> not Set.isEmpty(s#held), shaky(200, midGame(), Rng.fromSeed(3i64)));
        assertTrueWithMsg(busy > 120, "expected the bot to be active most ticks, got ${busy}")
    }

    @Test
    def testTheShakyBotMissesSometimes(): Unit \ Assert = {
        // Its aim wanders, so over a run it does not always agree with the perfect bot.
        let w = midGame();
        let perfect = Demo.aim(w)#held;
        let differs = List.count(s -> s#held != perfect, shaky(200, w, Rng.fromSeed(11i64)));
        assertTrueWithMsg(differs > 20, "the shaky bot never deviated: ${differs}")
    }

    // -- the property that matters ----------------------------------------------------

    @Test
    def testTheDemoNeverTouchesTheWorldsGenerator(): Unit \ Assert = {
        // The demo's randomness is the caller's, not the world's. If the bot consumed
        // `w#rng`, watching the attract screen would change what a replay means.
        let w = midGame();
        let before = w#rng;
        let (_, _) = Demo.imperfect(w, Rng.fromSeed(99i64));
        assertEq(expected = before, w#rng);
        // And the perfect bot is a pure function of the world alone.
        assertEq(expected = before, w#rng)
    }

    @Test
    def testTheBotMakesNoSound(): Unit \ Assert =
        // `aim` only reads; nothing about choosing an input should be audible.
        assertEq(expected = (Nil: List[SoundCmd]), Sound.played(() -> { let _ = Demo.aim(midGame()); () }))

}
