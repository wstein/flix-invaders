mod TestBunkers {

    use Assert.assertEq
    use Assert.assertTrue
    use Assert.assertFalse
    use Assert.assertTrueWithMsg
    use Assert.assertFalseWithMsg

    def first(): Bunker = Vector.get(0, Bunkers.initial())

    /// The x of the centre of block `column` in the first bunker, where a camper lines up.
    def columnCentre(column: Int32): Float32 =
        first()#origin#x + (Int32.toFloat32(column) + 0.5f32) * Rules.bunkerCell()

    ///
    /// The first bunker after the cannon has drilled a channel up `column`.
    ///
    /// One shot, rising from under the bunker until it meets a block -- which is what a bullet
    /// does. Absorbing at a fixed height would only ever chip one row.
    ///
    def drilledAt(column: Int32, bunkers: Vector[Bunker]): Vector[Bunker] =
        drilledFrom(columnCentre(column), bunkers)

    def drilledFrom(x: Float32, bunkers: Vector[Bunker]): Vector[Bunker] = {
        let bTop = Rules.bunkerTop();
        let bRows = Int32.toFloat32(Rules.bunkerRows());
        let bCell = Rules.bunkerCell();
        let floor = bTop + bRows * bCell;
        def shoot(acc) = {
            def rise(y, seen) = {
                let minY = bTop - Rules.bulletSize()#y;
                if (y < minY)
                    seen
                else {
                    let shotPos = { x = x, y = y };
                    let (damaged, hit) =
                        Bunkers.absorb(seen, shotPos, Rules.bulletSize(), Rules.bulletCrater());
                    if (hit) damaged else rise(y - 2.0f32, seen)
                }
            };
            rise(floor, acc)
        };
        def drill(n, acc) =
            if (n <= 0 or not Bunkers.blocks(acc, x))
                acc
            else
                drill(n - 1, shoot(acc));
        drill(60, bunkers)
    }

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
        let spot = { x = solidSpot()#x, y = solidSpot()#y - Rules.bombSpeedFor(BombKind.Slow) };
        let before = List.length(start()#bombs);
        let w = stepped({ bombs = Rules.bombAt(spot, BombKind.Slow) :: Nil | start() }, Input.empty());
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
        let bomb = { x = bunkerX, y = Rules.bunkerTop() - Rules.bombSpeedFor(BombKind.Slow) + 2.0f32 };
        let w = stepped({ playerX = bunkerX, bombs = Rules.bombAt(bomb, BombKind.Slow) :: Nil | base }, Input.empty());
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
        let x = columnCentre(column);
        let lane = { x = x, y = Rules.bunkerTop() + 2.0f32 };

        let drilled = drilledAt(column, Bunkers.initial());

        assertTrueWithMsg(not Bunkers.blocks(drilled, x),
            "60 shots did not open a channel; the cannon cannot drill at all");

        // Aligned on a column centre, the channel is open to a whole bullet and not merely to
        // a point, so the guard must say so. This assertion used to read the other way, and
        // contradicted the one below it in the same test: `obstructs` called the lane blocked
        // while `absorb` let the shot through at every height.
        assertFalseWithMsg(Bunkers.obstructs(drilled, x, Rules.bulletSize()#x),
            "a channel drilled on a column centre still reports itself blocked for a "
            + "${Rules.bulletSize()#x}px shot; the bot can never aim to camp");

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

    ///
    /// The guard agrees with the collision, everywhere.
    ///
    /// `obstructs` exists to answer, before firing, what `absorb` will do after. Any position
    /// where the two disagree is a position where the bot is either wasting shots on its own
    /// cover or refusing shots that would have flown. Both have happened, in that order, from
    /// two different approximations of this one question -- so the property, and not a handful
    /// of positions, is what is worth asserting.
    ///
    /// Swept at 1px across a whole bunker and a margin either side, over an eroded bunker
    /// rather than a fresh one: a fresh bunker is a solid slab for most of its width and would
    /// agree by accident.
    ///
    @Test
    def testTheFiringGuardAgreesWithTheCollision(): Unit \ Assert = {
        let eroded = drilledAt(6, Bunkers.initial());
        let left = first()#origin#x - 8.0f32;
        let width = Int32.toFloat32(Rules.bunkerColumns()) * Rules.bunkerCell() + 16.0f32;
        let disagreements = List.range(0, Float32.tryToInt32(width) |> Option.getWithDefault(0))
            |> List.filterMap(step -> {
                let x = left + Int32.toFloat32(step);
                let guarded = Bunkers.obstructs(eroded, x, Rules.bulletSize()#x);
                // What the shot actually does: rise through every row and see if anything stops it.
                let stopped = List.exists(row -> {
                    let y = Rules.bunkerTop() + (Int32.toFloat32(row) + 0.5f32) * Rules.bunkerCell();
                    let (_, hit) =
                        Bunkers.absorb(eroded, { x = x, y = y }, Rules.bulletSize(), Rules.bulletCrater());
                    hit
                }, List.range(0, Rules.bunkerRows()));
                if (guarded == stopped) None else Some((x, guarded, stopped))
            });
        assertTrueWithMsg(List.isEmpty(disagreements),
            "the guard and the collision disagree at ${disagreements} "
            + "-- each triple is (x, obstructs, actually stopped)")
    }

    ///
    /// Every x the cannon can ever occupy.
    ///
    /// It starts at the middle of the field and moves by whole `playerSpeed` steps, so its
    /// positions form a lattice. `clampTo` at either wall parks it exactly on the wall, which
    /// starts a second and a third lattice offset from the first.
    ///
    def latticeStarts(): List[Float32] = {
        let half = Rules.playerSize()#x / 2.0f32;
        Rules.fieldWidth() / 2.0f32 :: half :: Rules.fieldWidth() - half :: Nil
    }

    /// The nearest position to `target` the cannon can actually stand on, starting from `from`.
    def nearestStand(base: Float32, target: Float32): Float32 = {
        let steps = Float32.round((target - base) / Rules.playerSpeed());
        base + steps * Rules.playerSpeed()
    }

    ///
    /// The bot cannot camp, because it cannot line up.
    ///
    /// `testASlitLetsYouShootOutButNotThemIn` drills on a block column's centre and gets a
    /// shelter that stops bombs. Nothing checked whether the *cannon* can stand there, and it
    /// cannot: its lattice is 4px from the middle of the field, the block centres are on a 4px
    /// lattice of their own, and the two never coincide on any of the three starts. It is
    /// typically 2px out -- exactly on a seam, the worst case, where a shot straddles two
    /// columns and opens a channel twice as wide as intended.
    ///
    /// So the arcade tactic is not merely hard for the bot, it is unreachable. Drilling from
    /// where the cannon can actually stand carves a lane its own shots pass through *and* the
    /// invaders' bombs fall down, which is not shelter -- it is a hole in the roof.
    ///
    @Test
    def testTheCannonCannotLineUpToCamp(): Unit \ Assert = {
        let centres = List.range(0, Rules.bunkerCount()) |> List.flatMap(b ->
            List.range(0, Rules.bunkerColumns()) |> List.map(c ->
                Vector.get(b, Bunkers.initial())#origin#x
                    + (Int32.toFloat32(c) + 0.5f32) * Rules.bunkerCell()));

        let aligned = latticeStarts() |> List.flatMap(base ->
            centres |> List.filter(centre -> nearestStand(base, centre) == centre));
        assertTrueWithMsg(List.isEmpty(aligned),
            "the cannon can stand on block centres ${aligned}; the camping tactic is reachable "
            + "after all, and the bot should be taught it");

        // The consequence, from the closest the cannon ever gets to the column the shelter
        // test drills. Its own shots fly, so the lane is real -- and a bomb comes straight
        // down it, so the lane is not cover.
        let stand = nearestStand(Rules.fieldWidth() / 2.0f32, columnCentre(6));
        let camped = drilledFrom(stand, Bunkers.initial());
        assertFalseWithMsg(Bunkers.obstructs(camped, stand, Rules.bulletSize()#x),
            "the cannon drilled from ${stand} and still cannot shoot out");
        let (_, bombStopped) =
            Bunkers.absorb(camped, { x = stand, y = Rules.bunkerTop() + 2.0f32 },
                           Rules.bombSize(), Rules.bombCrater());
        assertFalseWithMsg(bombStopped,
            "a lane drilled from ${stand} stopped a bomb, so the cannon can shelter without "
            + "lining up and the tactic is worth teaching")
    }

    @Test
    def testTheCannonsCraterIsNarrowerThanABomb(): Unit \ Assert =
        // The inequality the whole tactic rests on. If this ever stops holding, the test above
        // is the one that will fail, and this is the reason why.
        assertTrueWithMsg(Rules.bulletCrater() * 2.0f32 < Rules.bombSize()#x,
            "a ${Rules.bulletCrater()}px crater leaves a channel a ${Rules.bombSize()#x}px bomb fits through")

}
