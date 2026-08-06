mod TestGame {

    use Assert.assertEq
    use Assert.assertTrue
    use Assert.assertFalse
    use Assert.assertTrueWithMsg

    def seed(): Int64 = 2026i64

    def start(): World = Game.initial(seed())

    def steps(n: Int32, w: World, input: Snapshot): World =
        if (n <= 0) w else steps(n - 1, Game.step(w, input), input)

    def livingCount(w: World): Int32 =
        Vector.count(inv -> inv#alive, w#invaders)

    // -- setup ------------------------------------------------------------------------

    @Test
    def testAFreshGameIsPlayable(): Unit \ Assert = {
        let w = start();
        assertEq(expected = Phase.Playing, w#phase);
        assertEq(expected = 0, w#score);
        assertEq(expected = Rules.startingLives(), w#lives);
        assertEq(expected = Rules.totalInvaders(), livingCount(w))
    }

    @Test
    def testTickAdvancesWhilePlaying(): Unit \ Assert =
        assertEq(expected = 5, steps(5, start(), Input.empty())#tick)

    // -- the player -------------------------------------------------------------------

    @Test
    def testHoldingLeftMovesTheePlayerLeft(): Unit \ Assert = {
        let w = Game.step(start(), Input.holding(Key.Left :: Nil));
        assertEq(expected = start()#playerX - Rules.playerSpeed(), w#playerX)
    }

    @Test
    def testHoldingRightMovesThePlayerRight(): Unit \ Assert = {
        let w = Game.step(start(), Input.holding(Key.Right :: Nil));
        assertEq(expected = start()#playerX + Rules.playerSpeed(), w#playerX)
    }

    @Test
    def testThePlayerStopsAtBothWalls(): Unit \ Assert = {
        let half = Rules.playerSize()#x / 2.0f32;
        let left = steps(400, start(), Input.holding(Key.Left :: Nil));
        assertEq(expected = half, left#playerX);
        let right = steps(400, start(), Input.holding(Key.Right :: Nil));
        assertEq(expected = Rules.fieldWidth() - half, right#playerX)
    }

    @Test
    def testOppositeDirectionsCancel(): Unit \ Assert = {
        let w = Game.step(start(), Input.holding(Key.Left :: Key.Right :: Nil));
        assertEq(expected = start()#playerX, w#playerX)
    }

    // -- firing -----------------------------------------------------------------------

    @Test
    def testSpaceFiresABullet(): Unit \ Assert =
        assertEq(expected = 1, List.length(Game.step(start(), Input.holding(Key.Space :: Nil))#bullets))

    @Test
    def testTheCooldownLimitsTheRateOfFire(): Unit \ Assert = {
        // Holding fire for one cooldown's worth of ticks must not empty the magazine.
        let held = Input.holding(Key.Space :: Nil);
        let w = steps(Rules.fireCooldown(), start(), held);
        assertTrueWithMsg(List.length(w#bullets) <= 2,
            "expected at most 2 shots in ${Rules.fireCooldown()} ticks, got ${List.length(w#bullets)}")
    }

    @Test
    def testBulletsRise(): Unit \ Assert = {
        let fired = Game.step(start(), Input.holding(Key.Space :: Nil));
        let later = Game.step(fired, Input.empty());
        match (List.head(fired#bullets), List.head(later#bullets)) {
            case (Some(a), Some(b)) => assertTrue(b#y < a#y)
            case _ => Assert.fail("expected a bullet in flight")
        }
    }

    @Test
    def testBulletsAreDroppedWhenTheyLeaveTheField(): Unit \ Assert = {
        // Fire once, then wait long enough for it to fly off the top without firing again.
        let fired = Game.step(start(), Input.holding(Key.Space :: Nil));
        let later = steps(200, fired, Input.empty());
        assertEq(expected = 0, List.length(later#bullets))
    }

    // -- the formation ----------------------------------------------------------------

    @Test
    def testTheFormationMarchesSideways(): Unit \ Assert = {
        let before = Vector.get(0, start()#invaders)#pos#x;
        let after = Vector.get(0, Game.step(start(), Input.empty())#invaders)#pos#x;
        assertTrue(after != before)
    }

    @Test
    def testTheFormationReversesAndDropsAtAWall(): Unit \ Assert = {
        // March long enough to reach a wall, and check the direction flipped and the
        // formation moved down.
        let before = start();
        let after = steps(2000, before, Input.empty());
        assertTrue(Vector.get(0, after#invaders)#pos#y > Vector.get(0, before#invaders)#pos#y)
    }

    @Test
    def testInvadersNeverLeaveTheField(): Unit \ Assert = {
        let half = Rules.invaderSize()#x / 2.0f32;
        def loop(n, w) =
            if (n <= 0) ()
            else {
                Vector.forEach(inv ->
                    if (inv#alive)
                        assertTrueWithMsg(inv#pos#x >= half - 1.0f32
                                          and inv#pos#x <= Rules.fieldWidth() - half + 1.0f32,
                            "invader left the field at x=${inv#pos#x}")
                    else (), w#invaders);
                loop(n - 1, Game.step(w, Input.empty()))
            };
        loop(1500, start())
    }

    // -- collisions -------------------------------------------------------------------

    /// Puts a bullet exactly on top of the first living invader.
    def bulletOnFirstInvader(w: World): World = {
        let target = Vector.get(0, w#invaders);
        { bullets = target#pos :: Nil | w }
    }

    @Test
    def testABulletKillsAnInvaderAndScores(): Unit \ Assert = {
        let w = Game.step(bulletOnFirstInvader(start()), Input.empty());
        assertEq(expected = Rules.totalInvaders() - 1, livingCount(w));
        assertEq(expected = Rules.pointsFor(Vector.get(0, start()#invaders)#kind), w#score);
        assertEq(expected = 0, List.length(w#bullets))
    }

    @Test
    def testOneBulletCannotKillTwoInvaders(): Unit \ Assert = {
        // Place a bullet where two invaders overlap it, which cannot happen in a real game
        // but is exactly the case a careless fold would get wrong.
        let base = start();
        let a = Vector.get(0, base#invaders);
        let stacked = Vector.update(1, { pos = a#pos | Vector.get(1, base#invaders) }, base#invaders);
        let w = Game.step({ bullets = a#pos :: Nil, invaders = stacked | base }, Input.empty());
        assertEq(expected = Rules.totalInvaders() - 1, Vector.count(inv -> inv#alive, w#invaders));
        assertEq(expected = Rules.pointsFor(Vector.get(0, start()#invaders)#kind), w#score)
    }

    @Test
    def testABulletThatMissesChangesNothing(): Unit \ Assert = {
        let miss = { x = 5.0f32, y = 300.0f32 };
        let w = Game.step({ bullets = miss :: Nil | start() }, Input.empty());
        assertEq(expected = Rules.totalInvaders(), livingCount(w));
        assertEq(expected = 0, w#score)
    }

    @Test
    def testABombHittingThePlayerCostsALife(): Unit \ Assert = {
        let base = start();
        let bomb = { x = base#playerX, y = Rules.playerY() };
        let w = Game.step({ bombs = bomb :: Nil | base }, Input.empty());
        assertEq(expected = Rules.startingLives() - 1, w#lives)
    }

    @Test
    def testABombThatMissesCostsNothing(): Unit \ Assert = {
        let base = start();
        let bomb = { x = base#playerX + 300.0f32, y = Rules.playerY() };
        let w = Game.step({ bombs = bomb :: Nil | base }, Input.empty());
        assertEq(expected = Rules.startingLives(), w#lives)
    }

    // -- ending and restarting --------------------------------------------------------

    /// A world with the whole formation shot away.
    def swept(): World = {
        let base = start();
        { invaders = Vector.map(inv -> { alive = false | inv }, base#invaders) | base }
    }

    @Test
    def testClearingEveryInvaderEndsTheLevel(): Unit \ Assert = {
        let w = Game.step(swept(), Input.empty());
        assertEq(expected = Phase.Cleared, w#phase);
        assertTrue(w#pause > 0)
    }

    @Test
    def testTheNextLevelStartsAfterThePause(): Unit \ Assert = {
        let cleared = Game.step(swept(), Input.empty());
        let next = steps(Rules.levelPauseTicks() + 1, cleared, Input.empty());
        assertEq(expected = Phase.Playing, next#phase);
        assertEq(expected = 2, next#level);
        assertEq(expected = Rules.totalInvaders(), livingCount(next))
    }

    @Test
    def testTheNextLevelKeepsScoreAndLives(): Unit \ Assert = {
        let scored = { score = 250, lives = 2 | swept() };
        let next = steps(Rules.levelPauseTicks() + 2, Game.step(scored, Input.empty()), Input.empty());
        assertEq(expected = 250, next#score);
        assertEq(expected = 2, next#lives)
    }

    @Test
    def testTheNextLevelRebuildsTheBunkers(): Unit \ Assert = {
        // Without this a cleared level would leave you with whatever cover survived, and
        // the game would get brutal within two levels.
        let worn = { bunkers = Vector.map(b -> Bunkers.damage(b, Bunkers.cellCentre(b, 40), 40.0f32),
                                          swept()#bunkers) | swept() };
        assertTrue(Bunkers.totalRemaining(worn#bunkers) < Bunkers.totalRemaining(start()#bunkers));
        let next = steps(Rules.levelPauseTicks() + 2, Game.step(worn, Input.empty()), Input.empty());
        assertEq(expected = Bunkers.totalRemaining(start()#bunkers), Bunkers.totalRemaining(next#bunkers))
    }

    @Test
    def testAClearedLevelDoesNotSimulate(): Unit \ Assert = {
        // Nothing should move during the between-levels beat except the countdown.
        let cleared = Game.step(swept(), Input.empty());
        let midway = steps(10, cleared, Input.holding(Key.Right :: Nil));
        assertEq(expected = cleared#playerX, midway#playerX);
        assertEq(expected = cleared#pause - 10, midway#pause)
    }

    // -- difficulty ------------------------------------------------------------------

    @Test
    def testTheFormationSpeedsUpAsItThins(): Unit \ Assert = {
        let full = Rules.marchSpeedFor(Rules.totalInvaders(), 1);
        let half = Rules.marchSpeedFor(Rules.totalInvaders() / 2, 1);
        let last = Rules.marchSpeedFor(1, 1);
        assertTrue(half > full);
        assertTrue(last > half);
        assertTrueWithMsg(last > full * 4.0f32,
            "the last invader should be dramatically faster: ${full} -> ${last}")
    }

    @Test
    def testAFullFormationMovesAtTheBaseSpeed(): Unit \ Assert =
        assertEq(expected = Rules.baseMarchSpeed(), Rules.marchSpeedFor(Rules.totalInvaders(), 1))

    @Test
    def testEachLevelStartsFasterThanTheLast(): Unit \ Assert = {
        let full = Rules.totalInvaders();
        assertTrue(Rules.marchSpeedFor(full, 2) > Rules.marchSpeedFor(full, 1));
        assertTrue(Rules.marchSpeedFor(full, 5) > Rules.marchSpeedFor(full, 2))
    }

    @Test
    def testSpeedIsSafeAtTheEdges(): Unit \ Assert = {
        // Guard the arithmetic rather than the gameplay: no negative or zero speeds.
        assertTrue(Rules.marchSpeedFor(0, 1) > 0.0f32);
        assertTrue(Rules.marchSpeedFor(-5, 1) > 0.0f32);
        assertTrue(Rules.marchSpeedFor(Rules.totalInvaders(), 0) > 0.0f32)
    }

    @Test
    def testBombsGetMoreFrequentWithLevel(): Unit \ Assert = {
        // A one-in-N chance, so a smaller number is more dangerous.
        assertTrue(Rules.bombChanceFor(3) < Rules.bombChanceFor(1));
        assertEq(expected = Rules.bombChance(), Rules.bombChanceFor(1))
    }

    @Test
    def testTheBombRateIsFloored(): Unit \ Assert = {
        // However far the levels run, bombs must not become a solid wall.
        assertTrue(Rules.bombChanceFor(100) > 1);
        assertEq(expected = Rules.bombChanceFor(100), Rules.bombChanceFor(50))
    }

    @Test
    def testAHigherLevelActuallyMarchesFaster(): Unit \ Assert = {
        // End to end through `step`, not just the rules table.
        let base = start();
        let move = w -> Vector.get(0, Game.step(w, Input.empty())#invaders)#pos#x - Vector.get(0, w#invaders)#pos#x;
        assertTrue(move({ level = 4 | base }) > move(base))
    }

    @Test
    def testRunningOutOfLivesLoses(): Unit \ Assert = {
        let base = start();
        let bomb = { x = base#playerX, y = Rules.playerY() };
        let w = Game.step({ bombs = bomb :: Nil, lives = 1 | base }, Input.empty());
        assertEq(expected = Phase.Lost, w#phase)
    }

    @Test
    def testInvadersReachingThePlayerLineLoses(): Unit \ Assert = {
        let base = start();
        let landed = Vector.map(inv -> { pos = { y = Rules.invasionLine() | inv#pos } | inv }, base#invaders);
        assertEq(expected = Phase.Lost, Game.step({ invaders = landed | base }, Input.empty())#phase)
    }

    @Test
    def testALostGameIsStable(): Unit \ Assert = {
        // Stepping a lost world with no input must change nothing at all, including the
        // tick -- otherwise the end screen would keep simulating underneath.
        let lost = { phase = Phase.Lost | start() };
        assertEq(expected = lost#tick, steps(50, lost, Input.empty())#tick);
        assertEq(expected = lost#score, steps(50, lost, Input.empty())#score)
    }

    @Test
    def testEnterRestartsFromTheEndScreen(): Unit \ Assert = {
        let lost = { phase = Phase.Lost, score = 500, lives = 0, level = 4 | steps(120, start(), Input.empty()) };
        let restarted = Game.step(lost, Input.holding(Key.Enter :: Nil));
        assertEq(expected = Phase.Playing, restarted#phase);
        assertEq(expected = 0, restarted#score);
        assertEq(expected = Rules.startingLives(), restarted#lives);
        assertEq(expected = 0, restarted#tick);
        assertEq(expected = 1, restarted#level);
        assertEq(expected = Rules.totalInvaders(), livingCount(restarted))
    }

    @Test
    def testRestartRebuildsTheOriginalStartingPosition(): Unit \ Assert = {
        // Restarting must not depend on how long the previous game ran.
        let lost = { phase = Phase.Lost | steps(300, start(), Input.holding(Key.Right :: Nil)) };
        let restarted = Game.step(lost, Input.holding(Key.Enter :: Nil));
        assertEq(expected = start()#playerX, restarted#playerX);
        assertEq(expected = Vector.get(0, start()#invaders)#pos#x,
                 Vector.get(0, restarted#invaders)#pos#x)
    }

    @Test
    def testHoldingEnterDoesNotRestartRepeatedly(): Unit \ Assert = {
        // Restart is on the rising edge, not on `held`. A held Enter would otherwise reset
        // the game on every single tick.
        let lost = { phase = Phase.Lost | start() };
        let heldEnter = Input.diff(Set#{Key.Enter}, Set#{Key.Enter}, 0, 0);
        assertEq(expected = Phase.Lost, Game.step(lost, heldEnter)#phase)
    }

    // -- rendering --------------------------------------------------------------------

    def rectCount(w: World): Int32 =
        List.count(cmd -> match cmd {
            case DrawCmd.Rect(_, _, _, _) => true
            case _ => false
        }, Canvas.commands((640, 480), () -> View.render(w)))

    @Test
    def testDeadInvadersAreNotDrawn(): Unit \ Assert = {
        // Killing one invader must remove exactly that sprite's rectangles -- no more, no
        // fewer. Sprites are drawn as horizontal runs of lit pixels, so the count is the
        // number of runs in its current frame.
        let base = start();
        let target = Vector.get(0, base#invaders);
        let killed = Vector.update(0, { alive = false | target }, base#invaders);
        let expectedDrop = List.length(Sprite.runs(Sprites.forKind(target#kind, 0)));
        assertEq(expected = rectCount(base) - expectedDrop, rectCount({ invaders = killed | base }))
    }

    @Test
    def testEveryLivingInvaderIsDrawn(): Unit \ Assert = {
        // Clearing the whole formation must remove every invader rectangle, which pins that
        // each one is drawn exactly once.
        let base = start();
        let cleared = Vector.map(inv -> { alive = false | inv }, base#invaders);
        let formationRects = Vector.foldLeft((total, inv) ->
            total + List.length(Sprite.runs(Sprites.forKind(inv#kind, 0))), 0, base#invaders);
        assertEq(expected = rectCount(base) - formationRects,
                 rectCount({ invaders = cleared | base }))
    }

    @Test
    def testTheInvadersAnimate(): Unit \ Assert = {
        // The two frames of a sprite differ, so the drawn commands must differ once the
        // animation has flipped. A frozen frame counter would make these identical.
        let base = start();
        let early = Canvas.commands((640, 480), () -> View.render({ tick = 0 | base }));
        let later = Canvas.commands((640, 480), () -> View.render({ tick = 30 | base }));
        assertTrue(early != later)
    }

    @Test
    def testRenderIsPure(): Unit \ Assert = {
        let w = steps(120, start(), Input.holding(Key.Space :: Nil));
        assertEq(expected = Canvas.commands((640, 480), () -> View.render(w)),
                 Canvas.commands((640, 480), () -> View.render(w)))
    }

    @Test
    def testTheEndScreenSaysHowToRestart(): Unit \ Assert = {
        let cmds = Canvas.commands((640, 480), () -> View.render({ phase = Phase.Lost | start() }));
        let hasHint = List.exists(cmd -> match cmd {
            case DrawCmd.Text(s, _, _) => String.contains(substr = "ENTER", s)
            case _ => false
        }, cmds);
        Assert.assertTrue(hasHint)
    }

    // -- explosions ------------------------------------------------------------------

    def blastCount(w: World): Int32 = List.length(w#blasts)

    def hasPlayerBlast(w: World): Bool =
        List.exists(b -> b#kind == BlastKind.PlayerBlast, w#blasts)

    /// A world with a bomb sitting exactly on the cannon.
    def aboutToBeHit(): World = {
        let base = start();
        { bombs = { x = base#playerX, y = Rules.playerY() } :: Nil | base }
    }

    @Test
    def testKillingAnInvaderLeavesAStarburst(): Unit \ Assert = {
        let w = Game.step(bulletOnFirstInvader(start()), Input.empty());
        assertEq(expected = 1, blastCount(w));
        // The formation marches before collisions resolve, so the blast belongs at the
        // invader's position at the moment it died, not where it was a tick earlier.
        let died = Vector.get(0, w#invaders)#pos;
        match List.head(w#blasts) {
            case Some(b) => {
                assertEq(expected = BlastKind.InvaderBlast, b#kind);
                assertEq(expected = died#x, b#pos#x);
                assertEq(expected = died#y, b#pos#y)
            }
            case None => Assert.fail("expected a blast")
        }
    }

    @Test
    def testAStarburstBurnsOut(): Unit \ Assert = {
        let w = Game.step(bulletOnFirstInvader(start()), Input.empty());
        assertEq(expected = 1, blastCount(w));
        assertEq(expected = 0, blastCount(steps(Rules.invaderBlastTicks() + 2, w, Input.empty())))
    }

    @Test
    def testBeingHitLeavesWreckageAndFreezesTheGame(): Unit \ Assert = {
        let w = Game.step(aboutToBeHit(), Input.empty());
        assertTrue(hasPlayerBlast(w));
        assertTrue(w#pause > 0);
        assertEq(expected = Rules.startingLives() - 1, w#lives)
    }

    @Test
    def testNothingMovesWhileTheCannonBurns(): Unit \ Assert = {
        // The freeze has to stop the formation too, not just the player -- otherwise the
        // invaders march on while you cannot shoot back.
        let hit = Game.step(aboutToBeHit(), Input.empty());
        let during = Game.step(hit, Input.holding(Key.Right :: Nil));
        assertEq(expected = hit#playerX, during#playerX);
        assertEq(expected = Vector.get(0, hit#invaders)#pos#x, Vector.get(0, during#invaders)#pos#x)
    }

    @Test
    def testPlayResumesAfterTheFreeze(): Unit \ Assert = {
        let hit = Game.step(aboutToBeHit(), Input.empty());
        let after = steps(Rules.deathPauseTicks() + 2, hit, Input.empty());
        assertEq(expected = Phase.Playing, after#phase);
        assertEq(expected = 0, after#pause);
        // Moving works again.
        assertTrue(Game.step(after, Input.holding(Key.Right :: Nil))#playerX > after#playerX)
    }

    @Test
    def testTheWreckageOutlivesTheFreeze(): Unit \ Assert =
        // Deliberate: the cannon is back before the debris has quite faded.
        assertTrue(Rules.playerBlastTicks() > Rules.deathPauseTicks())

    @Test
    def testTheCannonIsNotDrawnWhileItIsWreckage(): Unit \ Assert = {
        // Drawing the intact cannon underneath its own wreckage would look wrong. With the
        // wreck present the frame should gain the wreck's rectangles and lose the cannon's.
        let hit = Game.step(aboutToBeHit(), Input.empty());
        let intact = { blasts = Nil | hit };
        let wreck = List.foldLeft((total, b) ->
            total + List.length(Sprite.runs(Sprites.forBlast(b#kind, b#ticksLeft))), 0, hit#blasts);
        let cannon = List.length(Sprite.runs(Sprites.cannon()));
        assertEq(expected = rectCount(intact) + wreck - cannon, rectCount(hit))
    }

    @Test
    def testBlastsAreDrawn(): Unit \ Assert = {
        let w = Game.step(bulletOnFirstInvader(start()), Input.empty());
        assertTrue(rectCount(w) > rectCount({ blasts = Nil | w }))
    }

    @Test
    def testANewLevelClearsTheDebris(): Unit \ Assert = {
        let messy = { blasts = { pos = { x = 10.0f32, y = 10.0f32 },
                                 ticksLeft = 999,
                                 kind = BlastKind.InvaderBlast } :: Nil | swept() };
        let next = steps(Rules.levelPauseTicks() + 2, Game.step(messy, Input.empty()), Input.empty());
        assertEq(expected = 0, blastCount(next))
    }

    // -- the mystery ship ------------------------------------------------------------

    /// A world with the ship on screen at `x`, travelling right.
    def withMystery(x: Float32): World =
        { mystery = Some({ x = x, dir = 1.0f32 }) | start() }

    @Test
    def testNoMysteryShipAtTheStart(): Unit \ Assert = {
        assertTrue(Option.isEmpty(start()#mystery));
        assertEq(expected = Rules.mysteryInterval(), start()#mysteryTimer)
    }

    @Test
    def testTheTimerCountsDownAndThenLaunchesTheShip(): Unit \ Assert = {
        let nearly = { mysteryTimer = 2 | start() };
        assertTrue(Option.isEmpty(Game.step(nearly, Input.empty())#mystery));
        let launched = steps(2, nearly, Input.empty());
        assertTrue(not Option.isEmpty(launched#mystery));
        // The timer resets, so ships keep coming.
        assertEq(expected = Rules.mysteryInterval(), launched#mysteryTimer)
    }

    @Test
    def testTheShipCrossesTheScreen(): Unit \ Assert = {
        let w = Game.step(withMystery(100.0f32), Input.empty());
        match w#mystery {
            case Some(m) => assertEq(expected = 100.0f32 + Rules.mysterySpeed(), m#x)
            case None => Assert.fail("the ship vanished mid-screen")
        }
    }

    @Test
    def testTheShipLeavesAtTheFarSide(): Unit \ Assert = {
        let leaving = withMystery(Rules.fieldWidth() + Rules.mysterySize()#x);
        assertTrue(Option.isEmpty(Game.step(leaving, Input.empty())#mystery))
    }

    @Test
    def testAShipThatEscapesScoresNothing(): Unit \ Assert = {
        let leaving = withMystery(Rules.fieldWidth() + Rules.mysterySize()#x);
        assertEq(expected = 0, Game.step(leaving, Input.empty())#score)
    }

    @Test
    def testShootingTheShipScoresAndDestroysIt(): Unit \ Assert = {
        let base = withMystery(300.0f32);
        let shot = { bullets = { x = 300.0f32, y = Rules.mysteryY() } :: Nil | base };
        let w = Game.step(shot, Input.empty());
        assertTrue(Option.isEmpty(w#mystery));
        assertTrue(w#score > 0);
        assertEq(expected = 0, List.length(w#bullets));
        assertTrue(List.exists(b -> b#kind == BlastKind.InvaderBlast, w#blasts))
    }

    @Test
    def testTheShipIsWorthOneOfItsTableValues(): Unit \ Assert = {
        let base = withMystery(300.0f32);
        let shot = { bullets = { x = 300.0f32, y = Rules.mysteryY() } :: Nil | base };
        let scored = Game.step(shot, Input.empty())#score;
        Assert.assertTrueWithMsg(Vector.exists(v -> v == scored, Rules.mysteryScores()),
            "scored ${scored}, which is not in the table")
    }

    @Test
    def testAMissedShotLeavesTheShipAlone(): Unit \ Assert = {
        let base = withMystery(300.0f32);
        let wide = { bullets = { x = 100.0f32, y = Rules.mysteryY() } :: Nil | base };
        assertTrue(not Option.isEmpty(Game.step(wide, Input.empty())#mystery))
    }

    @Test
    def testTheShipFliesAboveTheFormation(): Unit \ Assert =
        // A bullet must pass every invader before it can reach the bonus.
        assertTrue(Rules.mysteryY() + Rules.mysterySize()#y / 2.0f32 < Rules.formationTop())

    @Test
    def testTheShipIsDrawnWhenPresent(): Unit \ Assert =
        assertTrue(rectCount(withMystery(300.0f32)) > rectCount(start()))

    @Test
    def testANewLevelClearsTheShip(): Unit \ Assert = {
        let messy = { mystery = Some({ x = 300.0f32, dir = 1.0f32 }) | swept() };
        let next = steps(Rules.levelPauseTicks() + 2, Game.step(messy, Input.empty()), Input.empty());
        assertTrue(Option.isEmpty(next#mystery))
    }

    @Test
    def testTheShipDoesNotMoveWhileTheCannonBurns(): Unit \ Assert = {
        let hit = Game.step({ mystery = Some({ x = 300.0f32, dir = 1.0f32 }) | aboutToBeHit() }, Input.empty());
        let during = Game.step(hit, Input.empty());
        match (hit#mystery, during#mystery) {
            case (Some(a), Some(b)) => assertEq(expected = a#x, b#x)
            case _ => Assert.fail("expected the ship to still be there")
        }
    }

}
