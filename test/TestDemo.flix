mod TestDemo {

    use Assert.assertEq
    use Assert.assertTrue
    use Assert.assertFalse
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

    // -- self-preservation and greed ------------------------------------------------------

    @Test
    def testTheBotGetsOutFromUnderABomb(): Unit \ Assert = {
        // Staying alive beats lining up a shot.
        let w = midGame();
        let overhead = { bombs = { x = w#playerX, y = Rules.playerY() - 60.0f32 } :: Nil | w };
        let moves = Demo.aim(overhead)#held;
        assertTrueWithMsg(Set.memberOf(Key.Left, moves) or Set.memberOf(Key.Right, moves),
            "the bot stood still under a falling bomb")
    }

    @Test
    def testTheBotIgnoresBombsThatWillMiss(): Unit \ Assert = {
        // A bomb far off to the side is not a reason to abandon a shot.
        let w = midGame();
        let wide = { bombs = { x = w#playerX + 300.0f32, y = Rules.playerY() - 60.0f32 } :: Nil | w };
        assertEq(expected = Demo.aim(w)#held, Demo.aim(wide)#held)
    }

    @Test
    def testTheBotDodgesTowardsTheOpenSide(): Unit \ Assert = {
        // Fleeing into a wall would be worse than not fleeing.
        let w = midGame();
        let cornered = { playerX = Rules.playerSize()#x / 2.0f32 | w };
        let bomb = { bombs = { x = cornered#playerX, y = Rules.playerY() - 40.0f32 } :: Nil | cornered };
        assertTrue(Set.memberOf(Key.Right, Demo.aim(bomb)#held))
    }

    @Test
    def testTheBotShootsWhateverIsOverhead(): Unit \ Assert = {
        // Not only its chosen target. Firing solely when lined up on the target wasted every
        // tick the cannon spent under some other column, and the formation landed.
        let w = { bombs = Nil | midGame() };
        let overhead = Vector.mapWithIndex((i, inv) ->
            if (i == 0) { pos = { x = w#playerX, y = 200.0f32 }, alive = true | inv }
            else { alive = false | inv }, w#invaders);
        // The saucer is the target, far away -- so the bot is not aimed at the invader.
        let distracted = { invaders = overhead, mystery = Some({ x = 20.0f32, dir = -1.0f32 }) | w };
        assertTrueWithMsg(Set.memberOf(Key.Space, Demo.aim(distracted)#held),
            "the bot walked past an invader directly overhead without firing")
    }

    @Test
    def testTheBotHoldsFireOverEmptySky(): Unit \ Assert = {
        // The other half: it should not fire at a column it has already cleared.
        let w = { bombs = Nil, playerX = 40.0f32 | midGame() };
        let farRight = Vector.mapWithIndex((i, inv) ->
            if (i == 0) { pos = { x = 600.0f32, y = 200.0f32 }, alive = true | inv }
            else { alive = false | inv }, w#invaders);
        assertFalse(Set.memberOf(Key.Space, Demo.aim({ invaders = farRight | w })#held))
    }

    @Test
    def testTheBotChasesTheSaucer(): Unit \ Assert = {
        // Worth up to 300 and a shield -- what a human would go for.
        let w = midGame();
        let far = Rules.fieldWidth() - 40.0f32;
        let ufo = { mystery = Some({ x = far, dir = 1.0f32 }), bombs = Nil | { playerX = 60.0f32 | w } };
        assertTrueWithMsg(Set.memberOf(Key.Right, Demo.aim(ufo)#held),
            "the bot ignored a saucer on the far side")
    }

    @Test
    def testTheBotReturnsToTheFormationWhenTheSaucerLeaves(): Unit \ Assert = {
        // Put the two candidate targets on opposite sides so the choice is legible in the
        // direction it moves: saucer far left, the surviving invader far right.
        let base = { bombs = Nil, playerX = 320.0f32 | midGame() };
        let oneRight = Vector.mapWithIndex((i, inv) ->
            if (i == 0) { pos = { x = 600.0f32, y = 300.0f32 }, alive = true | inv }
            else { alive = false | inv }, base#invaders);
        let w = { invaders = oneRight | base };
        let withUfo = { mystery = Some({ x = 40.0f32, dir = -1.0f32 }) | w };
        assertTrueWithMsg(Set.memberOf(Key.Left, Demo.aim(withUfo)#held),
            "the bot did not go for the saucer on its left");
        assertTrueWithMsg(Set.memberOf(Key.Right, Demo.aim({ mystery = None | w })#held),
            "the bot did not return to the invader on its right")
    }

}
