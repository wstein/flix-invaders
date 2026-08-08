mod TestBunkers {

    use Assert.assertEq
    use Assert.assertTrue
    use Assert.assertFalse
    use Assert.assertTrueWithMsg
    use Assert.assertFalseWithMsg

    def first(): Bunker = Vector.get(0, Bunkers.initial())

    /// A point in the solid top of the first bunker.
    def solidSpot(): Vec2 = {
        let b = first();
        { x = b#origin#x + 24.0f32, y = b#origin#y + 6.0f32 }
    }

    @Test
    def testThereAreFourBunkers(): Unit \ Assert =
        assertEq(expected = Rules.bunkerCount(), Vector.length(Bunkers.initial()))

    @Test
    def testBunkersStartIntactAndIdentical(): Unit \ Assert = {
        let bunkers = Bunkers.initial();
        let counts = Vector.toList(bunkers) |> List.map(Bunkers.remaining);
        assertTrueWithMsg(Bunkers.remaining(first()) > 0, "a bunker started empty");
        assertEq(expected = List.repeat(Rules.bunkerCount(), Bunkers.remaining(first())), counts)
    }

    @Test
    def testBunkersDoNotOverlapEachOther(): Unit \ Assert = {
        let width = Int32.toFloat32(Rules.bunkerColumns()) * Rules.bunkerCell();
        def loop(i) =
            if (i >= Rules.bunkerCount() - 1) ()
            else {
                let gap = Rules.bunkerLeft(i + 1) - (Rules.bunkerLeft(i) + width);
                assertTrueWithMsg(gap > 0.0f32, "bunkers ${i} and ${i + 1} overlap");
                loop(i + 1)
            };
        loop(0)
    }

    @Test
    def testBunkersSitBetweenTheInvadersAndThePlayer(): Unit \ Assert = {
        let bottom = Rules.bunkerTop() + Int32.toFloat32(Rules.bunkerRows()) * Rules.bunkerCell();
        assertTrue(Rules.bunkerTop() > Rules.formationTop());
        assertTrueWithMsg(bottom < Rules.playerY() - Rules.playerSize()#y / 2.0f32,
            "a bunker overlaps the cannon")
    }

    // -- damage -----------------------------------------------------------------------

    @Test
    def testAShotThatHitsIsAbsorbed(): Unit \ Assert = {
        let (_, hit) = Bunkers.absorb(Bunkers.initial(), solidSpot(), Rules.bulletSize(), Rules.bulletCrater());
        assertTrue(hit)
    }

    @Test
    def testAShotThatHitsDestroysBlocks(): Unit \ Assert = {
        let (damaged, _) = Bunkers.absorb(Bunkers.initial(), solidSpot(), Rules.bulletSize(), Rules.bulletCrater());
        assertTrue(Bunkers.totalRemaining(damaged) < Bunkers.totalRemaining(Bunkers.initial()))
    }

    @Test
    def testAShotThatMissesChangesNothing(): Unit \ Assert = {
        let far = { x = 5.0f32, y = 5.0f32 };
        let (untouched, hit) = Bunkers.absorb(Bunkers.initial(), far, Rules.bulletSize(), Rules.bulletCrater());
        assertFalse(hit);
        assertEq(expected = Bunkers.totalRemaining(Bunkers.initial()), Bunkers.totalRemaining(untouched))
    }

    @Test
    def testDamageIsLocal(): Unit \ Assert = {
        // A hit on one bunker must not touch the others, and must leave most of its own
        // bunker standing -- a blast radius bug would show up as the whole thing vanishing.
        let (damaged, _) = Bunkers.absorb(Bunkers.initial(), solidSpot(), Rules.bulletSize(), Rules.bulletCrater());
        assertEq(expected = Bunkers.remaining(Vector.get(1, Bunkers.initial())),
                 Bunkers.remaining(Vector.get(1, damaged)));
        assertTrue(Bunkers.remaining(Vector.get(0, damaged)) > Bunkers.remaining(first()) / 2)
    }

    @Test
    def testShootingTheSameSpotEventuallyPunchesThrough(): Unit \ Assert = {
        // Hammering one place must clear it, and then stop absorbing shots there.
        def hammer(n, bunkers) =
            if (n <= 0) bunkers
            else {
                let (damaged, _) = Bunkers.absorb(bunkers, solidSpot(), Rules.bulletSize(), Rules.bulletCrater());
                hammer(n - 1, damaged)
            };
        let worn = hammer(20, Bunkers.initial());
        let (_, stillHits) = Bunkers.absorb(worn, solidSpot(), Rules.bulletSize(), Rules.bulletCrater());
        assertFalse(stillHits)
    }

    @Test
    def testDamageNeverRepairsItself(): Unit \ Assert = {
        let (once, _) = Bunkers.absorb(Bunkers.initial(), solidSpot(), Rules.bulletSize(), Rules.bulletCrater());
        let elsewhere = { x = solidSpot()#x + 24.0f32, y = solidSpot()#y };
        let (twice, _) = Bunkers.absorb(once, elsewhere, Rules.bulletSize(), Rules.bulletCrater());
        assertTrue(Bunkers.totalRemaining(twice) <= Bunkers.totalRemaining(once))
    }

    @Test
    def testAbsorbAllKeepsOnlyTheShotsThatGotThrough(): Unit \ Assert = {
        let hits = solidSpot();
        let misses = { x = 5.0f32, y = 5.0f32 };
        let (_, survivors) = Bunkers.absorbAll(Bunkers.initial(), hits :: misses :: Nil, Rules.bulletSize(), Rules.bulletCrater());
        assertEq(expected = 1, List.length(survivors));
        assertEq(expected = misses#x :: Nil, List.map(shot -> shot#x, survivors))
    }

    // -- in the game ------------------------------------------------------------------

    def start(): World = Game.initial(2026i64)

    /// One step, discarding sound: none of these tests are about it.
    def stepped(w: World, input: Snapshot): World =
        Sound.runWithNoOp(() -> Game.step(w, input))

    @Test
    def testAGameStartsWithIntactBunkers(): Unit \ Assert =
        assertEq(expected = Bunkers.totalRemaining(Bunkers.initial()),
                 Bunkers.totalRemaining(start()#bunkers))

    @Test
    def testAPlayerBulletIsStoppedByABunker(): Unit \ Assert = {
        let w = stepped({ bullets = solidSpot() :: Nil | start() }, Input.empty());
        assertEq(expected = 0, List.length(w#bullets));
        assertTrue(Bunkers.totalRemaining(w#bunkers) < Bunkers.totalRemaining(start()#bunkers))
    }

    @Test
    def testAnInvaderBombIsStoppedByABunker(): Unit \ Assert = {
        // The bomb is placed just above the bunker so that one step's fall lands it inside.
        let spot = { x = solidSpot()#x, y = solidSpot()#y - Rules.bombSpeed() };
        let before = List.length(start()#bombs);
        let w = stepped({ bombs = spot :: Nil | start() }, Input.empty());
        assertEq(expected = before, List.length(w#bombs));
        assertTrue(Bunkers.totalRemaining(w#bunkers) < Bunkers.totalRemaining(start()#bunkers))
    }

    @Test
    def testABunkerProtectsThePlayer(): Unit \ Assert = {
        // Park the cannon under a bunker and drop a bomb onto it: the bunker takes the hit
        // and the player keeps every life. This is the difference between bunkers that work
        // and bunkers that are merely drawn.
        let base = start();
        let bunkerX = Vector.get(0, base#bunkers)#origin#x + 24.0f32;
        let bomb = { x = bunkerX, y = Rules.bunkerTop() - Rules.bombSpeed() + 2.0f32 };
        let w = stepped({ playerX = bunkerX, bombs = bomb :: Nil | base }, Input.empty());
        assertEq(expected = Rules.startingLives(), w#lives);
        assertTrue(Bunkers.totalRemaining(w#bunkers) < Bunkers.totalRemaining(base#bunkers))
    }

    @Test
    def testInvadersGrindDownABunkerTheyReach(): Unit \ Assert = {
        let base = start();
        let landed = Vector.map(inv -> { pos = { y = Rules.bunkerTop() + 8.0f32 | inv#pos } | inv },
                                base#invaders);
        let eroded = Bunkers.erode(base#bunkers, landed);
        assertTrue(Bunkers.totalRemaining(eroded) < Bunkers.totalRemaining(base#bunkers))
    }

    @Test
    def testHighInvadersLeaveBunkersAlone(): Unit \ Assert =
        assertEq(expected = Bunkers.totalRemaining(start()#bunkers),
                 Bunkers.totalRemaining(Bunkers.erode(start()#bunkers, start()#invaders)))

    @Test
    def testBunkerDamageShowsUpInTheDigest(): Unit \ Assert = {
        // The digest backs the replay tests, so it has to notice bunker damage.
        let base = start();
        let damaged = stepped({ bullets = solidSpot() :: Nil | base }, Input.empty());
        Assert.assertNeq(unexpected = Game.digest(base), Game.digest(damaged))
    }

    @Test
    def testDestroyedBlocksAreNotDrawn(): Unit \ Assert = {
        // Drawing collapses each row into horizontal runs, so punching a hole in the middle
        // of a row can *increase* the rectangle count by splitting one run in two. What must
        // fall is the number of blocks those runs cover.
        let covered = bunker -> List.foldLeft((total, segment) -> {
            let (_, _, length) = segment;
            total + length
        }, 0, Bunkers.runs(bunker));
        let base = start();
        let damaged = stepped({ bullets = solidSpot() :: Nil | base }, Input.empty());
        assertTrue(covered(Vector.get(0, damaged#bunkers)) < covered(Vector.get(0, base#bunkers)))
    }

    @Test
    def testRunsCoverExactlyTheSurvivingBlocks(): Unit \ Assert = {
        let covered = bunker -> List.foldLeft((total, segment) -> {
            let (_, _, length) = segment;
            total + length
        }, 0, Bunkers.runs(bunker));
        let (damaged, _) = Bunkers.absorb(Bunkers.initial(), solidSpot(), Rules.bulletSize(), Rules.bulletCrater());
        Vector.forEach(bunker ->
            assertEq(expected = Bunkers.remaining(bunker), covered(bunker)), damaged)
    }

    @Test
    def testAnAbsorbedShotAlwaysDestroysSomething(): Unit \ Assert = {
        // The bug this guards against: a shot is up to twelve pixels tall, so it can overlap
        // a block whose centre lies outside the blast radius. Centring the crater on the shot
        // rather than on the block it struck meant the bunker swallowed the shot and took no
        // damage at all. Sweep the whole bunker to be sure it cannot come back.
        let bunkers = Bunkers.initial();
        let b = Vector.get(0, bunkers);
        def sweep(ix, iy) =
            if (iy > 40) ()
            else if (ix > 52) sweep(-2, iy + 2)
            else {
                let at = { x = b#origin#x + Int32.toFloat32(ix), y = b#origin#y + Int32.toFloat32(iy) };
                let (after, hit) = Bunkers.absorb(bunkers, at, Rules.bulletSize(), Rules.bulletCrater());
                if (hit)
                    assertTrueWithMsg(Bunkers.totalRemaining(after) < Bunkers.totalRemaining(bunkers),
                        "a shot at (${at#x}, ${at#y}) was absorbed but destroyed nothing")
                else ();
                sweep(ix + 2, iy)
            };
        sweep(-2, -2)
    }

    @Test
    def testTheSameSweepHoldsForBombs(): Unit \ Assert = {
        // Bombs are a different size, so they need their own pass.
        let bunkers = Bunkers.initial();
        let b = Vector.get(0, bunkers);
        def sweep(ix, iy) =
            if (iy > 40) ()
            else if (ix > 52) sweep(-2, iy + 2)
            else {
                let at = { x = b#origin#x + Int32.toFloat32(ix), y = b#origin#y + Int32.toFloat32(iy) };
                let (after, hit) = Bunkers.absorb(bunkers, at, Rules.bombSize(), Rules.bombCrater());
                if (hit)
                    assertTrueWithMsg(Bunkers.totalRemaining(after) < Bunkers.totalRemaining(bunkers),
                        "a bomb at (${at#x}, ${at#y}) was absorbed but destroyed nothing")
                else ();
                sweep(ix + 2, iy)
            };
        sweep(-2, -2)
    }

    @Test
    def testFiringIntoABunkerDamagesIt(): Unit \ Assert = {
        // End to end, through the real pipeline: park the cannon under a bunker, fire, and
        // let the bullet fly until it is gone. The bunker must have lost blocks.
        let base = start();
        let x = Vector.get(0, base#bunkers)#origin#x + 24.0f32;
        def fly(n, w) =
            if (n <= 0 or List.isEmpty(w#bullets)) w
            else fly(n - 1, stepped(w, Input.empty()));
        let fired = stepped({ playerX = x | base }, Input.holding(Key.Space :: Nil));
        let after = fly(20, fired);
        assertTrueWithMsg(
            Bunkers.totalRemaining(after#bunkers) < Bunkers.totalRemaining(base#bunkers),
            "the bullet vanished without damaging the bunker")
    }


    // -- camping behind a slit --------------------------------------------------------------

    ///
    /// The arcade's oldest trick: drill a narrow channel through your own shelter, then stand
    /// in it and shoot out while their bombs still break on the blocks either side.
    ///
    /// It works only because the two craters differ. The cannon's is 2px, so the channel it
    /// leaves is about one block wide; a bomb is 6px, wider than the channel, so it always
    /// clips a standing block on one side. Make the cannon's crater as wide as a bomb and the
    /// trick dies -- the hole you make becomes a hole they can drop through, which is exactly
    /// what happened when both used a single shared radius.
    ///
    @Test
    def testASlitLetsYouShootOutButNotThemIn(): Unit \ Assert = {
        // Lined up on the *centre* of a block column, not the seam between two. A shot on the
        // seam straddles both and drills a channel twice as wide -- wide enough for a bomb, so
        // the trick quietly stops working. Alignment is part of the tactic, for the bot and for
        // a player at the cabinet alike.
        let column = 6;
        let x = first()#origin#x + (Int32.toFloat32(column) + 0.5f32) * Rules.bunkerCell();
        let lane = { x = x, y = Rules.bunkerTop() + 2.0f32 };

        // One shot, rising from under the bunker until it meets a block -- which is what a
        // bullet does. Absorbing at a fixed height would only ever chip one row.
        let floor = Rules.bunkerTop() + Int32.toFloat32(Rules.bunkerRows()) * Rules.bunkerCell();
        def shoot(bunkers) = {
            def rise(y, acc) =
                if (y < Rules.bunkerTop() - Rules.bulletSize()#y) acc
                else {
                    let (damaged, hit) =
                        Bunkers.absorb(acc, { x = x, y = y }, Rules.bulletSize(), Rules.bulletCrater());
                    if (hit) damaged else rise(y - 2.0f32, acc)
                };
            rise(floor, bunkers)
        };
        def drill(n, bunkers) =
            if (n <= 0 or not Bunkers.blocks(bunkers, x)) bunkers
            else drill(n - 1, shoot(bunkers));
        let drilled = drill(60, Bunkers.initial());

        assertTrueWithMsg(not Bunkers.blocks(drilled, x),
            "60 shots did not open a channel; the cannon cannot drill at all");

        // The channel is open to a *point* and not to a bullet. This is the gap the bot fell
        // into: `blocks` samples the centre column, `absorb` tests the whole four-pixel
        // footprint, so a shot fired down a slit this narrow still takes the block beside it.
        assertTrueWithMsg(Bunkers.obstructs(drilled, x, Rules.bulletSize()#x),
            "a channel one point wide reported itself clear for a "
            + "${Rules.bulletSize()#x}px shot");

        // The cannon's own shots now pass straight through, at every height.
        let ownShotStopped = List.exists(row -> {
            let y = Rules.bunkerTop() + (Int32.toFloat32(row) + 0.5f32) * Rules.bunkerCell();
            let (_, hit) = Bunkers.absorb(drilled, { x = x, y = y }, Rules.bulletSize(), Rules.bulletCrater());
            hit
        }, List.range(0, Rules.bunkerRows()));
        assertFalseWithMsg(ownShotStopped, "the channel is open but still swallows the cannon's shots");

        // Their bombs do not: 6px is wider than the channel, so one side always clips.
        let (_, bombStopped) = Bunkers.absorb(drilled, lane, Rules.bombSize(), Rules.bombCrater());
        assertTrueWithMsg(bombStopped,
            "a bomb fell straight down the channel; the slit shelters nobody")
    }

    @Test
    def testTheCannonsCraterIsNarrowerThanABomb(): Unit \ Assert =
        // The inequality the whole tactic rests on. If this ever stops holding, the test above
        // is the one that will fail, and this is the reason why.
        assertTrueWithMsg(Rules.bulletCrater() * 2.0f32 < Rules.bombSize()#x,
            "a ${Rules.bulletCrater()}px crater leaves a channel a ${Rules.bombSize()#x}px bomb fits through")

}
