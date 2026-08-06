mod TestBunkers {

    use Assert.assertEq
    use Assert.assertTrue
    use Assert.assertFalse
    use Assert.assertTrueWithMsg

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
        let (_, hit) = Bunkers.absorb(Bunkers.initial(), solidSpot(), Rules.bulletSize());
        assertTrue(hit)
    }

    @Test
    def testAShotThatHitsDestroysBlocks(): Unit \ Assert = {
        let (damaged, _) = Bunkers.absorb(Bunkers.initial(), solidSpot(), Rules.bulletSize());
        assertTrue(Bunkers.totalRemaining(damaged) < Bunkers.totalRemaining(Bunkers.initial()))
    }

    @Test
    def testAShotThatMissesChangesNothing(): Unit \ Assert = {
        let far = { x = 5.0f32, y = 5.0f32 };
        let (untouched, hit) = Bunkers.absorb(Bunkers.initial(), far, Rules.bulletSize());
        assertFalse(hit);
        assertEq(expected = Bunkers.totalRemaining(Bunkers.initial()), Bunkers.totalRemaining(untouched))
    }

    @Test
    def testDamageIsLocal(): Unit \ Assert = {
        // A hit on one bunker must not touch the others, and must leave most of its own
        // bunker standing -- a blast radius bug would show up as the whole thing vanishing.
        let (damaged, _) = Bunkers.absorb(Bunkers.initial(), solidSpot(), Rules.bulletSize());
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
                let (damaged, _) = Bunkers.absorb(bunkers, solidSpot(), Rules.bulletSize());
                hammer(n - 1, damaged)
            };
        let worn = hammer(20, Bunkers.initial());
        let (_, stillHits) = Bunkers.absorb(worn, solidSpot(), Rules.bulletSize());
        assertFalse(stillHits)
    }

    @Test
    def testDamageNeverRepairsItself(): Unit \ Assert = {
        let (once, _) = Bunkers.absorb(Bunkers.initial(), solidSpot(), Rules.bulletSize());
        let elsewhere = { x = solidSpot()#x + 24.0f32, y = solidSpot()#y };
        let (twice, _) = Bunkers.absorb(once, elsewhere, Rules.bulletSize());
        assertTrue(Bunkers.totalRemaining(twice) <= Bunkers.totalRemaining(once))
    }

    @Test
    def testAbsorbAllKeepsOnlyTheShotsThatGotThrough(): Unit \ Assert = {
        let hits = solidSpot();
        let misses = { x = 5.0f32, y = 5.0f32 };
        let (_, survivors) = Bunkers.absorbAll(Bunkers.initial(), hits :: misses :: Nil, Rules.bulletSize());
        assertEq(expected = 1, List.length(survivors));
        assertEq(expected = misses#x :: Nil, List.map(shot -> shot#x, survivors))
    }

    // -- in the game ------------------------------------------------------------------

    def start(): World = Game.initial(2026i64)

    @Test
    def testAGameStartsWithIntactBunkers(): Unit \ Assert =
        assertEq(expected = Bunkers.totalRemaining(Bunkers.initial()),
                 Bunkers.totalRemaining(start()#bunkers))

    @Test
    def testAPlayerBulletIsStoppedByABunker(): Unit \ Assert = {
        let w = Game.step({ bullets = solidSpot() :: Nil | start() }, Input.empty());
        assertEq(expected = 0, List.length(w#bullets));
        assertTrue(Bunkers.totalRemaining(w#bunkers) < Bunkers.totalRemaining(start()#bunkers))
    }

    @Test
    def testAnInvaderBombIsStoppedByABunker(): Unit \ Assert = {
        // The bomb is placed just above the bunker so that one step's fall lands it inside.
        let spot = { x = solidSpot()#x, y = solidSpot()#y - Rules.bombSpeed() };
        let before = List.length(start()#bombs);
        let w = Game.step({ bombs = spot :: Nil | start() }, Input.empty());
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
        let w = Game.step({ playerX = bunkerX, bombs = bomb :: Nil | base }, Input.empty());
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
        let damaged = Game.step({ bullets = solidSpot() :: Nil | base }, Input.empty());
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
        let damaged = Game.step({ bullets = solidSpot() :: Nil | base }, Input.empty());
        assertTrue(covered(Vector.get(0, damaged#bunkers)) < covered(Vector.get(0, base#bunkers)))
    }

    @Test
    def testRunsCoverExactlyTheSurvivingBlocks(): Unit \ Assert = {
        let covered = bunker -> List.foldLeft((total, segment) -> {
            let (_, _, length) = segment;
            total + length
        }, 0, Bunkers.runs(bunker));
        let (damaged, _) = Bunkers.absorb(Bunkers.initial(), solidSpot(), Rules.bulletSize());
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
                let (after, hit) = Bunkers.absorb(bunkers, at, Rules.bulletSize());
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
                let (after, hit) = Bunkers.absorb(bunkers, at, Rules.bombSize());
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
            else fly(n - 1, Game.step(w, Input.empty()));
        let fired = Game.step({ playerX = x | base }, Input.holding(Key.Space :: Nil));
        let after = fly(20, fired);
        assertTrueWithMsg(
            Bunkers.totalRemaining(after#bunkers) < Bunkers.totalRemaining(base#bunkers),
            "the bullet vanished without damaging the bunker")
    }

}
