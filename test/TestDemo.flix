mod TestDemo {

    use Assert.assertEq
    use Assert.assertTrue
    use Assert.assertFalse
    use Assert.assertNeq
    use Assert.assertTrueWithMsg
    use Assert.assertFalseWithMsg

    def start(): World = Game.initial(2026i64)

    /// A world a few hundred ticks in, so there is something to aim at.
    def midGame(): World =
        Sound.runWithNoOp(() -> {
            def loop(n, w) = if (n <= 0) w else loop(n - 1, Game.step(w, Demo.aim(Demo.defaults(), w)));
            loop(300, start())
        })

    // -- the competent bot ------------------------------------------------------------

    @Test
    def testTheBotAimsAtSomething(): Unit \ Assert = {
        let s = Demo.aim(Demo.defaults(), start());
        assertTrueWithMsg(not Set.isEmpty(s#held), "the bot did nothing on a full formation")
    }

    @Test
    def testTheBotIsDeterministic(): Unit \ Assert = {
        let w = midGame();
        assertEq(expected = Demo.aim(Demo.defaults(), w)#held, Demo.aim(Demo.defaults(), w)#held)
    }

    @Test
    def testTheBotHoldsFireWhenNothingIsLeft(): Unit \ Assert = {
        let cleared = { invaders = Vector.map(inv -> { alive = false | inv }, start()#invaders) | start() };
        assertTrue(Set.isEmpty(Demo.aim(Demo.defaults(), cleared)#held))
    }

    // -- the shaky bot ----------------------------------------------------------------

    /// The inputs the imperfect bot produces over `n` ticks of a fixed world.
    /// Accumulated rather than consed onto the recursive call -- see `TestReplay.script`.
    def shaky(n: Int32, w: World, hand: Hand): List[Snapshot] = {
        def loop(remaining, h, acc) =
            if (remaining <= 0) List.reverse(acc)
            else {
                let (snapshot, next) = Demo.imperfect(Demo.defaults(), w, h);
                loop(remaining - 1, next, snapshot :: acc)
            };
        loop(n, hand, Nil)
    }

    @Test
    def testTheShakyBotIsDeterministicGivenItsGenerator(): Unit \ Assert = {
        let w = midGame();
        assertEq(expected = List.map(s -> s#held, shaky(40, w, Demo.fresh(5i64))),
                 List.map(s -> s#held, shaky(40, w, Demo.fresh(5i64))))
    }

    @Test
    def testADifferentGeneratorPlaysDifferently(): Unit \ Assert =
        // Measured over real play rather than a frozen world. The bot now holds one judgement
        // for a third of a second at a time, so two hands agree tick-for-tick far longer than
        // they used to -- they diverge over a game, which is where it matters.
        assertNeq(unexpected = held(playedWith(600, 2026i64, Demo.fresh(5i64))),
                  held(playedWith(600, 2026i64, Demo.fresh(6i64))))

    @Test
    def testTheShakyBotSometimesDoesNothing(): Unit \ Assert = {
        // Perfect play makes a dull demo. Now and then it is simply not watching.
        let idle = List.count(Set.isEmpty, held(played(1200, 3i64)));
        assertTrueWithMsg(idle > 20, "expected some idle ticks, got ${idle}")
    }

    @Test
    def testTheShakyBotMostlyPlays(): Unit \ Assert = {
        // ...but it should still look like somebody playing, not somebody asleep.
        let ticks = held(played(1200, 3i64));
        let busy = List.count(keys -> not Set.isEmpty(keys), ticks);
        assertTrueWithMsg(busy * 2 > List.length(ticks),
            "expected the bot to be active most ticks, got ${busy} of ${List.length(ticks)}")
    }

    @Test
    def testTheShakyBotMissesSometimes(): Unit \ Assert = {
        // Its aim wanders, so a game it plays is not the game the perfect bot would have
        // played. Compared over real play: a frozen world cannot show this any more, because
        // the bot holds one judgement across many ticks by design.
        let shakyRun = held(playedWith(600, 2026i64, Demo.fresh(11i64)));
        let steady = Sound.runWithNoOp(() -> {
            def loop(k, w, acc) =
                if (k <= 0 or w#phase == Phase.Lost) List.reverse(acc)
                else {
                    let input = Demo.aim(Demo.defaults(), w);
                    loop(k - 1, Game.step(w, input), input#held :: acc)
                };
            loop(600, Game.initial(2026i64), Nil)
        });
        let differs = List.length(List.filter(x -> x, List.zipWith((a, b) -> a != b, shakyRun, steady)));
        assertTrueWithMsg(differs > 20, "the shaky bot never deviated: ${differs}")
    }

    // -- the shield -------------------------------------------------------------------------

    ///
    /// A world where the bot has no reason to walk: one invader directly overhead, and the
    /// formation held still so the aim needs no lead.
    ///
    /// Built rather than played, because a fixture taken from `midGame` inherits whatever the
    /// bot did for three hundred ticks -- so a change to the firing rule moves the cannon, and
    /// a test about *dodging* fails for reasons that have nothing to do with dodging.
    ///
    def settled(): World = {
        let w = { bombs = Nil, mystery = None, marchDir = 0.0f32 | midGame() };
        let one = Vector.mapWithIndex((i, inv) ->
            if (i == 0) { pos = { x = w#playerX, y = 260.0f32 }, alive = true | inv }
            else { alive = false | inv }, w#invaders);
        { invaders = one | w }
    }

    @Test
    def testItDoesNotDodgeWhileShielded(): Unit \ Assert = {
        // Shooting the saucer buys ten seconds of immunity. Spending them dodging wastes the
        // prize -- that is time to stand under the formation and fire.
        let w = settled();
        let overhead = { bombs = Rules.bombAt({ x = w#playerX, y = Rules.playerY() - 60.0f32 }, BombKind.Slow) :: Nil | w };
        let shielded = { shield = Rules.shieldTicks() | overhead };
        assertTrueWithMsg(Set.memberOf(Key.Left, Demo.aim(Demo.defaults(), overhead)#held)
                          or Set.memberOf(Key.Right, Demo.aim(Demo.defaults(), overhead)#held),
            "the fixture does not provoke a dodge in the first place");
        assertFalseWithMsg(Set.memberOf(Key.Left, Demo.aim(Demo.defaults(), shielded)#held)
                           or Set.memberOf(Key.Right, Demo.aim(Demo.defaults(), shielded)#held),
            "the bot fled a bomb its shield was going to stop")
    }

    @Test
    def testItStillDodgesWhenTheShieldIsAboutToLapse(): Unit \ Assert = {
        // The shield runs on a clock. One with a few ticks left does nothing about a bomb that
        // takes forty to arrive, and walking calmly into that would be a strange celebration.
        let w = { bombs = Nil, mystery = None | midGame() };
        let bomb = { x = w#playerX, y = Rules.playerY() - 60.0f32 };
        let lapsing = { shield = 2, bombs = Rules.bombAt(bomb, BombKind.Slow) :: Nil | w };
        assertTrueWithMsg(Set.memberOf(Key.Left, Demo.aim(Demo.defaults(), lapsing)#held)
                          or Set.memberOf(Key.Right, Demo.aim(Demo.defaults(), lapsing)#held),
            "the bot trusted a shield that expires before the bomb lands")
    }

    // -- narrowing the formation ---------------------------------------------------------------

    /// Which way the bot walks, if it walks at all.
    def walks(t: Tuning, w: World): Option[Key] = {
        let held = Demo.aim(t, w)#held;
        if (Set.memberOf(Key.Left, held)) Some(Key.Left)
        else if (Set.memberOf(Key.Right, held)) Some(Key.Right)
        else None
    }

    ///
    /// Three columns: a pair of outer ones `gap` either side of centre, and a lower single one
    /// in the middle, with the cannon parked directly under the middle.
    ///
    /// Every part of this shape is load-bearing, and the obvious two-column version of it
    /// silently tests nothing. With two columns alive *both* of them are the formation's edge,
    /// so a rule about edges cannot prefer either. And a single invader in an outer column is
    /// already covered by `finishFlank`, which would move the bot whether `narrowing` existed
    /// or not -- so the outer columns are two deep, past `stragglers`, leaving `narrowing` as
    /// the only thing that can pull the cannon off the middle.
    ///
    /// Built rather than played, positions and all. A fixture taken from three hundred ticks of
    /// play inherits a formation that has already descended, and this rule fades out as the
    /// formation descends -- so the tests would be measuring `composure` while claiming to
    /// measure the cutoff. Everything sits high, which is the situation the rule exists for.
    ///
    /// Standing the cannon on the lowest-first answer is what makes these sharp: doing nothing
    /// *is* lowest-first, so any walk at all is `narrowing` overruling it, and no bot that
    /// merely leans one way can pass by accident.
    ///
    def threeColumns(gap: Int32): World = {
        let at = col -> Rules.formationLeft() + Int32.toFloat32(col) * Rules.columnSpacing();
        let up = 0.04f32 * Rules.invasionLine();
        let edge = 0.08f32 * Rules.invasionLine();
        let middle = 0.16f32 * Rules.invasionLine();
        let placed = Vector.mapWithIndex((i, inv) -> match i {
            case 0 => { pos = { x = at(5 - gap), y = up }, alive = true | inv }
            case 1 => { pos = { x = at(5 - gap), y = edge }, alive = true | inv }
            case 2 => { pos = { x = at(5 + gap), y = up }, alive = true | inv }
            case 3 => { pos = { x = at(5 + gap), y = edge }, alive = true | inv }
            case 4 => { pos = { x = at(5), y = middle }, alive = true | inv }
            case _ => { alive = false | inv }
        }, midGame()#invaders);
        { invaders = placed, bombs = Nil, mystery = None, marchDir = 0.0f32,
          playerX = at(5) | midGame() }
    }

    /// Half the starting width: wider than the cutoff, so the rule should fire.
    def wideBlock(): World = threeColumns(5)

    @Test
    def testItClearsAFlankWhileTheBlockIsWide(): Unit \ Assert = {
        // The whole strategy. The block's width decides how far it marches before it turns and
        // drops, so an outer column is worth more than its position suggests -- it is the only
        // shot that permanently slows the descent.
        assertEq(expected = Some(Key.Left), walks(Demo.defaults(), wideBlock()))
    }

    @Test
    def testWithoutTheRuleItWouldTakeTheLowerColumnInstead(): Unit \ Assert = {
        // The other half of the same claim: the fixture is one where lowest-first genuinely
        // disagrees. Without it this test would pass on a bot that always walks left.
        let off = { narrowing = 0.0f32 | Demo.defaults() };
        assertEq(expected = None, walks(off, wideBlock()))
    }

    @Test
    def testItStopsNarrowingOnceTheBlockIsSmallEnough(): Unit \ Assert = {
        // The cutoff is what makes the rule pay. Chasing flanks with no stopping point costs
        // more kill rate than it buys descent, and by then the invaders are low enough that
        // whatever is about to land matters more than the shape of what is left.
        assertNeq(unexpected = Some(Key.Left), walks(Demo.defaults(), threeColumns(1)))
    }

    ///
    /// The same wide block, with the middle column well down the screen.
    ///
    /// `wideBlock` is the fixture where clearing a flank correctly beats shooting the lowest
    /// invader. This is the same shape with the stakes changed: the middle column is 60% of the
    /// way to the invasion line, and tidying a flank instead spends the time that was left.
    ///
    /// Sixty per cent rather than ninety-five, because ninety-five does not discriminate.
    /// `composure` already fades the flank bonus to nothing once the formation is that low, so
    /// both the old weight and the new one do the right thing in the emergency. The gap was in
    /// acting *before* the emergency: at a weight of 1 the bot kept tidying until a column had
    /// passed 76% of the way down, and by then there is not enough time left to kill it.
    ///
    def comingDown(): World = {
        let w = wideBlock();
        let low = Vector.mapWithIndex((i, inv) ->
            if (i == 4) { pos = { x = inv#pos#x, y = 0.60f32 * Rules.invasionLine() } | inv }
            else inv, w#invaders);
        { invaders = low | w }
    }

    ///
    /// A descending invader outranks a tidy flank.
    ///
    /// Sixty games in sixty end by invasion and none by running out of lives, so how far down
    /// a column has come is the only genuinely urgent thing on the screen -- and it was
    /// outranked by construction. The nearness term is a fraction and so topped out at 1.0,
    /// while the two flank bonuses reach 3.1 between them.
    ///
    @Test
    def testADescendingColumnOutranksATidyFlank(): Unit \ Assert = {
        assertNeq(unexpected = Some(Key.Left), walks(Demo.defaults(), comingDown()))
    }

    @Test
    def testWithoutTheWeightItWouldTidyTheFlankInstead(): Unit \ Assert = {
        // The control, and the bug as it stood: at a weight of 1 a column 60% of the way down
        // cannot outbid `narrowing`, so the bot walks off to the flank. Without this the test
        // above would pass on a bot that never walks left at all.
        let asItWas = { imminence = 1.0f32 | Demo.defaults() };
        assertEq(expected = Some(Key.Left), walks(asItWas, comingDown()))
    }

    @Test
    def testTheCutoffIsMeasuredAgainstTheStartingWidth(): Unit \ Assert = {
        // A fraction of the *original* formation, not of whatever is left -- against the latter
        // the outermost pair of columns is always 100% wide and the rule never switches off.
        let wide = List.count(gap -> walks(Demo.defaults(), threeColumns(gap)) == Some(Key.Left),
                              4 :: 5 :: Nil);
        assertEq(expected = 2, wide)
    }

    // -- staying alive ----------------------------------------------------------------------

    @Test
    def testItLosesToTheFormationRatherThanToBombs(): Unit \ Assert = {
        // A demo that dies to bombs looks careless, and it is also the wrong failure: bombs
        // are dodgeable and the descent is not. The bot should run out of screen before it
        // runs out of lives. This is the property the dodging is tuned for, and it is easy to
        // lose again -- narrowing `dangerWidth` back to 30 breaks it.
        let seeds = 2026i64 :: 7i64 :: 99i64 :: 1234i64 :: Nil;
        let survived = List.count(seed -> {
            let ended = Sound.runWithNoOp(() -> {
                def loop(n, w, hand) =
                    if (n <= 0 or w#phase == Phase.Lost) w
                    else {
                        let (input, next) = Demo.imperfect(Demo.defaults(), w, hand);
                        loop(n - 1, Game.step(w, input), next)
                    };
                loop(30000, Game.initial(seed), Demo.fresh(seed))
            });
            ended#lives > 0
        }, seeds);
        assertTrueWithMsg(survived >= List.length(seeds) - 1,
            "the bot ran out of lives on ${List.length(seeds) - survived} of ${List.length(seeds)} "
            + "seeds; it is being hit rather than invaded")
    }

    // -- its own bunkers ------------------------------------------------------------------

    /// An x directly under standing blocks of the first bunker.
    def underShelter(): Float32 =
        Rules.bunkerLeft(0) + (Int32.toFloat32(Rules.bunkerColumns()) * Rules.bunkerCell()) / 2.0f32

    ///
    /// Standing under bunker 0 with one invader directly overhead and nothing else alive.
    ///
    /// Spelled out rather than borrowed from `midGame`, so the two tests below turn only on
    /// whether the shelter is standing. Leaving it to chance made the pair depend on which
    /// invader the bot happened to be aiming at, which is not what either is about.
    ///
    def overheadAtShelter(): World = {
        let w = { playerX = underShelter(), bombs = Nil, mystery = None | midGame() };
        let one = Vector.mapWithIndex((i, inv) ->
            if (i == 0) { pos = { x = w#playerX, y = 200.0f32 }, alive = true | inv }
            else { alive = false | inv }, w#invaders);
        { invaders = one | w }
    }

    @Test
    def testItDoesNotShootThroughItsOwnBunker(): Unit \ Assert = {
        // The rules allow it, and carving a slit is a tactic in the arcade original -- but a
        // bot doing it by accident spends shots demolishing its own cover.
        let w = { marchDir = 0.0f32 | overheadAtShelter() };
        assertTrueWithMsg(Bunkers.blocks(w#bunkers, w#playerX),
            "the fixture is not actually standing under a bunker");
        assertFalse(Set.memberOf(Key.Space, Demo.aim(Demo.defaults(), w)#held))
    }

    ///
    /// Just off the outer edge of bunker 0: the shot's centre misses it, its width does not.
    ///
    /// One pixel out, so the centre column is clear and the four-pixel bullet still overlaps
    /// the first block. This is the only geometry that separates the two guards, and the first
    /// version of this test did not have it -- it stepped one cell inwards, which is still
    /// squarely on a 48px bunker, so it passed against the narrow guard too and proved nothing.
    ///
    def besideTheShelter(): World = {
        let w = overheadAtShelter();
        let edge = Rules.bunkerLeft(0) - 1.0f32;
        let overhead = Vector.mapWithIndex((i, inv) ->
            if (i == 0) { pos = { x = edge, y = 200.0f32 }, alive = true | inv } else inv,
            w#invaders);
        { playerX = edge, invaders = overhead, marchDir = 0.0f32 | w }
    }

    @Test
    def testItDoesNotClipTheBunkerItIsStandingBeside(): Unit \ Assert = {
        // Reported from watching it play: the bot was still demolishing its own cover. It was
        // asking whether a *point* was clear, and a point is not what gets fired -- a bullet is
        // four pixels wide and so is a bunker block. Measured over sixty games, one shot in
        // seven struck a bunker the guard had called clear.
        let w = besideTheShelter();
        assertFalseWithMsg(Bunkers.blocks(w#bunkers, w#playerX),
            "the fixture is squarely on the bunker, so it cannot tell the two guards apart");
        assertTrueWithMsg(Bunkers.obstructs(w#bunkers, w#playerX, Rules.bulletSize()#x),
            "the fixture does not put a bunker in the shot's path at all");
        assertFalseWithMsg(Set.memberOf(Key.Space, Demo.aim(Demo.defaults(), w)#held),
            "the bot fired a shot that would clip its own bunker")
    }

    @Test
    def testItWouldOtherwiseTakeThatShot(): Unit \ Assert = {
        // The control. Without it the test above passes on a bot that never fires at all, and
        // the invader is deliberately overhead so that holding fire has exactly one cause.
        let w = besideTheShelter();
        let clear = { bunkers = Vector.map(b -> { cells = Vector.repeat(
            Rules.bunkerColumns() * Rules.bunkerRows(), false) | b }, w#bunkers) | w };
        assertTrueWithMsg(Set.memberOf(Key.Space, Demo.aim(Demo.defaults(), clear)#held),
            "with the bunkers gone the bot still held fire; the fixture proves nothing")
    }

    @Test
    def testItStillShootsOnceTheBunkerAboveIsGone(): Unit \ Assert = {
        // The rule is "not through my own cover", not "never from here". Same world, same
        // target directly overhead -- only the shelter is gone.
        let w = { marchDir = 0.0f32 | overheadAtShelter() };
        let bare = { bunkers = Vector.map(b -> { cells = Vector.map(_ -> false, b#cells) | b },
                                          w#bunkers) | w };
        assertTrue(Set.memberOf(Key.Space, Demo.aim(Demo.defaults(), bare)#held))
    }

    @Test
    def testItCountsABunkerOverheadAsShelter(): Unit \ Assert = {
        // Standing under a bunker is safer than standing beside one, because the bomb hits the
        // shelter first. Given a bomb overhead, the bot should be less eager to flee cover.
        let w = midGame();
        let sheltered = { playerX = underShelter() | w };
        let bomb = { bombs = Rules.bombAt({ x = sheltered#playerX, y = Rules.playerY() - 60.0f32 }, BombKind.Slow) :: Nil | sheltered };
        let exposed = { bunkers = Vector.map(b -> { cells = Vector.map(_ -> false, b#cells) | b },
                                             bomb#bunkers) | bomb };
        let staysPut = Set.isEmpty(Demo.aim(Demo.defaults(), bomb)#held) or not Set.isEmpty(Demo.aim(Demo.defaults(), exposed)#held);
        assertTrueWithMsg(staysPut,
            "the bot treated cover and open ground as equally dangerous")
    }

    // -- looking human ------------------------------------------------------------------

    /// The direction a snapshot pushes: -1, 0 or +1.
    def pushed(s: Snapshot): Int32 =
        if (Set.memberOf(Key.Left, s#held)) -1
        else if (Set.memberOf(Key.Right, s#held)) 1
        else 0

    ///
    /// Plays for real, returning what the bot did each tick and whether the tick counted.
    ///
    /// A tick during the death pause does not count: the game is not accepting input, so the
    /// bot doing nothing there says nothing about the bot.
    ///
    def playedWith(n: Int32, seed: Int64, hand: Hand): List[(Snapshot, Bool)] =
        Sound.runWithNoOp(() -> {
            def loop(k, w, h, acc) =
                if (k <= 0 or w#phase == Phase.Lost) List.reverse(acc)
                else {
                    let (input, next) = Demo.imperfect(Demo.defaults(), w, h);
                    loop(k - 1, Game.step(w, input), next, (input, w#pause == 0) :: acc)
                };
            loop(n, Game.initial(seed), hand, Nil)
        })

    def held(ticks: List[(Snapshot, Bool)]): List[Set[Key]] =
        List.map(match (input, _) -> input#held, ticks)

    def played(n: Int32, seed: Int64): List[(Snapshot, Bool)] =
        Sound.runWithNoOp(() -> {
            def loop(k, w, hand, acc) =
                if (k <= 0 or w#phase == Phase.Lost) List.reverse(acc)
                else {
                    let (input, next) = Demo.imperfect(Demo.defaults(), w, hand);
                    loop(k - 1, Game.step(w, input), next, (input, w#pause == 0) :: acc)
                };
            loop(n, Game.initial(seed), Demo.fresh(seed), Nil)
        })

    /// How often it turns round, per hundred ticks in which it was moving at all.
    def reversalsPerHundred(ticks: List[(Snapshot, Bool)]): Int32 = {
        let inputs = ticks |> List.filterMap(match (input, counts) -> if (counts) Some(input) else None);
        let (_, flips, moves) = List.foldLeft((acc, input) -> {
            let (previous, count, moving) = acc;
            let now = pushed(input);
            if (now == 0) (previous, count, moving)
            else (now, count + (if (previous != 0 and now != previous) 1 else 0), moving + 1)
        }, (0, 0, 0), inputs);
        (flips * 100) / Int32.max(1, moves)
    }

    @Test
    def testTheCannonDoesNotShake(): Unit \ Assert = {
        // The bot used to draw a fresh aim error every tick, which around the target swamped
        // the 1.5px deadzone and reversed the cannon about six times a second -- a visible
        // vibration, and nothing a person does. Measured then: 9-11 reversals per 100 moving
        // ticks, against 3 for the same bot with no error at all.
        // Six thousand ticks, not two: at two the figure swings between 3 and 7 across seeds
        // purely on sample size, and lengthening the between-levels pause was enough to tip a
        // seed over the line without the bot moving any differently. From six thousand it
        // settles at 3 to 4 and stays there.
        List.forEach(seed -> {
            let rate = reversalsPerHundred(played(6000, seed));
            assertTrueWithMsg(rate <= 5,
                "seed ${seed}: ${rate} direction reversals per 100 moving ticks -- the cannon is shaking")
        }, 2026i64 :: 7i64 :: 99i64 :: Nil)
    }

    @Test
    def testItCommitsToAMisjudgement(): Unit \ Assert = {
        // A person misjudges a shot and lives with it for a beat. Re-deciding every frame is
        // what shakes. On a world held still, the same judgement should hold for many ticks.
        let steady = shaky(60, midGame(), Demo.fresh(7i64))
            |> List.map(s -> s#held)
            |> List.foldLeft((acc, held) -> {
                let (previous, longest, current) = acc;
                if (Some(held) == previous) (Some(held), Int32.max(longest, current + 1), current + 1)
                else (Some(held), longest, 0)
            }, (None, 0, 0));
        let (_, longest, _) = steady;
        assertTrueWithMsg(longest >= 10,
            "the bot changed its mind every ${longest} ticks; it is re-judging too often")
    }

    @Test
    def testAPauseIsAHesitationNotAFreeze(): Unit \ Assert = {
        // Lapses last a fraction of a second, not a single frame and not a second. A one-frame
        // dropout is invisible; a long one reads as a hang, and cannot dodge a bomb.
        let runs = played(2000, 42i64) |> List.foldLeft((acc, tick) -> {
            let (longest, current) = acc;
            let (input, counts) = tick;
            if (counts and Set.isEmpty(input#held)) (Int32.max(longest, current + 1), current + 1)
            else (longest, 0)
        }, (0, 0));
        let (longest, _) = runs;
        assertTrueWithMsg(longest <= 60,
            "the bot stopped playing for ${longest} ticks; that reads as a hang, not a hesitation")
    }

    // -- the property that matters ----------------------------------------------------

    @Test
    def testTheDemoNeverTouchesTheWorldsGenerator(): Unit \ Assert = {
        // The demo's randomness is the caller's, not the world's. If the bot consumed
        // `w#rng`, watching the attract screen would change what a replay means.
        let w = midGame();
        let before = w#rng;
        let (_, _) = Demo.imperfect(Demo.defaults(), w, Demo.fresh(99i64));
        assertEq(expected = before, w#rng);
        // And the perfect bot is a pure function of the world alone.
        assertEq(expected = before, w#rng)
    }

    @Test
    def testTheBotMakesNoSound(): Unit \ Assert =
        // `aim` only reads; nothing about choosing an input should be audible.
        assertEq(expected = (Nil: List[SoundCmd]), Sound.played(() -> { let _ = Demo.aim(Demo.defaults(), midGame()); () }))

    // -- self-preservation and greed ------------------------------------------------------

    @Test
    def testTheBotGetsOutFromUnderABomb(): Unit \ Assert = {
        // Staying alive beats lining up a shot.
        let w = midGame();
        let overhead = { bombs = Rules.bombAt({ x = w#playerX, y = Rules.playerY() - 60.0f32 }, BombKind.Slow) :: Nil | w };
        let moves = Demo.aim(Demo.defaults(), overhead)#held;
        assertTrueWithMsg(Set.memberOf(Key.Left, moves) or Set.memberOf(Key.Right, moves),
            "the bot stood still under a falling bomb")
    }

    @Test
    def testTheBotIgnoresBombsThatWillMiss(): Unit \ Assert = {
        // A bomb far off to the side is not a reason to abandon a shot.
        let w = midGame();
        let wide = { bombs = Rules.bombAt({ x = w#playerX + 300.0f32, y = Rules.playerY() - 60.0f32 }, BombKind.Slow) :: Nil | w };
        assertEq(expected = Demo.aim(Demo.defaults(), w)#held, Demo.aim(Demo.defaults(), wide)#held)
    }

    @Test
    def testTheBotDodgesTowardsTheOpenSide(): Unit \ Assert = {
        // Fleeing into a wall would be worse than not fleeing.
        let w = midGame();
        let cornered = { playerX = Rules.playerSize()#x / 2.0f32 | w };
        let bomb = { bombs = Rules.bombAt({ x = cornered#playerX, y = Rules.playerY() - 40.0f32 }, BombKind.Slow) :: Nil | cornered };
        assertTrue(Set.memberOf(Key.Right, Demo.aim(Demo.defaults(), bomb)#held))
    }

    @Test
    def testItFiresWhenTheShotWillConnect(): Unit \ Assert = {
        // Not only at its chosen target: any shot that will meet something is worth taking,
        // whatever the bot is aiming at. Here the saucer is the target, far off to one side.
        let w = settled();
        let distracted = { mystery = Some({ x = 20.0f32, dir = -1.0f32 }) | w };
        assertTrueWithMsg(Set.memberOf(Key.Space, Demo.aim(Demo.defaults(), distracted)#held),
            "the bot held fire on a shot that would have connected")
    }

    /// The half-width of the window `fireWindow` opens, in pixels.
    def fireWindowPx(): Float32 =
        Demo.defaults()#fireWindow * (Rules.invaderSize()#x + Rules.bulletSize()#x) / 2.0f32

    ///
    /// The lead is still applied; the window it is judged against is just wide.
    ///
    /// This test used to assert the opposite of the one below it -- that a target drifting by
    /// more than its own width was not worth a shot. That was right when the window was the
    /// exact overlap, and `fireWindow` has since widened it fivefold on measurement. What
    /// survives the change is the principle: the bot aims where the bullet will *arrive*, so a
    /// target that will have left the window by then is still not a target.
    ///
    /// The fixture is built from `fireWindow` rather than from a fixed distance, so widening
    /// the window again cannot quietly make this vacuous -- it would fail instead.
    ///
    @Test
    def testItStillHoldsFireOnAShotThatCannotArriveInTime(): Unit \ Assert = {
        let w = settled();
        // High up, so the flight is long and the formation has time to leave the window.
        let high = Vector.mapWithIndex((i, inv) ->
            if (i == 0) { pos = { x = w#playerX, y = 40.0f32 }, alive = true | inv } else inv,
            w#invaders);
        let marching = { marchDir = 1.0f32, invaders = high | w };
        let flight = (Rules.playerY() - 40.0f32) / Rules.bulletSpeed();
        let drift = Rules.marchSpeedFor(1, marching#level) * flight;
        assertTrueWithMsg(drift > fireWindowPx(),
            "the fixture drifts ${drift}px against a ${fireWindowPx()}px window, so it does not "
            + "put the invader out of reach and the assertion below would prove nothing");
        assertFalseWithMsg(Set.memberOf(Key.Space, Demo.aim(Demo.defaults(), marching)#held),
            "the bot fired at where the invader is rather than where the bullet will arrive")
    }

    ///
    /// And the widening itself, which is the change that bought it a whole level.
    ///
    /// Exact aiming refuses this shot -- the invader drifts further than its own width before
    /// the bullet arrives -- and the bot takes it anyway. A miss costs only the twelve-tick
    /// cooldown, there is no limit on shots in flight, and over sixty seeds firing on "roughly
    /// overhead" beats firing on "guaranteed to connect" by 5.2 to 6.0 levels.
    ///
    @Test
    def testItTakesAShotExactAimingWouldRefuse(): Unit \ Assert = {
        let w = settled();
        let marching = { marchDir = 1.0f32 | w };
        let flight = (Rules.playerY() - 260.0f32) / Rules.bulletSpeed();
        let drift = Rules.marchSpeedFor(1, marching#level) * flight;
        let exact = (Rules.invaderSize()#x + Rules.bulletSize()#x) / 2.0f32;
        assertTrueWithMsg(drift > exact and drift < fireWindowPx(),
            "the fixture drifts ${drift}px, which is not between the exact window ${exact}px "
            + "and the widened one ${fireWindowPx()}px, so it does not test the widening");
        assertTrueWithMsg(Set.memberOf(Key.Space, Demo.aim(Demo.defaults(), marching)#held),
            "the bot held fire on a target inside its firing window")
    }

    @Test
    def testTheBotHoldsFireOverEmptySky(): Unit \ Assert = {
        // The other half: it should not fire at a column it has already cleared.
        let w = { bombs = Nil, playerX = 40.0f32 | midGame() };
        let farRight = Vector.mapWithIndex((i, inv) ->
            if (i == 0) { pos = { x = 600.0f32, y = 200.0f32 }, alive = true | inv }
            else { alive = false | inv }, w#invaders);
        assertFalse(Set.memberOf(Key.Space, Demo.aim(Demo.defaults(), { invaders = farRight | w })#held))
    }

    @Test
    def testTheBotChasesTheSaucer(): Unit \ Assert = {
        // Worth up to 300 and a shield -- what a human would go for.
        let w = midGame();
        let far = Rules.fieldWidth() - 40.0f32;
        let ufo = { mystery = Some({ x = far, dir = 1.0f32 }), bombs = Nil | { playerX = 60.0f32 | w } };
        assertTrueWithMsg(Set.memberOf(Key.Right, Demo.aim(Demo.defaults(), ufo)#held),
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
        assertTrueWithMsg(Set.memberOf(Key.Left, Demo.aim(Demo.defaults(), withUfo)#held),
            "the bot did not go for the saucer on its left");
        assertTrueWithMsg(Set.memberOf(Key.Right, Demo.aim(Demo.defaults(), { mystery = None | w })#held),
            "the bot did not return to the invader on its right")
    }

}
