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
        assertEq(expected = Rules.pointsPerInvader(), w#score);
        assertEq(expected = 0, List.length(w#bullets))
    }

    @Test
    def testOneBulletCannotKillTwoInvaders(): Unit \ Assert = {
        // Place a bullet where two invaders overlap it, which cannot happen in a real game
        // but is exactly the case a careless fold would get wrong.
        let base = start();
        let a = Vector.get(0, base#invaders);
        let stacked = Vector.update(1, { pos = a#pos, alive = true }, base#invaders);
        let w = Game.step({ bullets = a#pos :: Nil, invaders = stacked | base }, Input.empty());
        assertEq(expected = Rules.totalInvaders() - 1, Vector.count(inv -> inv#alive, w#invaders));
        assertEq(expected = Rules.pointsPerInvader(), w#score)
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

    @Test
    def testClearingEveryInvaderWins(): Unit \ Assert = {
        let base = start();
        let cleared = Vector.map(inv -> { alive = false | inv }, base#invaders);
        assertEq(expected = Phase.Won, Game.step({ invaders = cleared | base }, Input.empty())#phase)
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
    def testAFinishedGameIsStable(): Unit \ Assert = {
        // Stepping a won or lost world with no input must change nothing at all, including
        // the tick -- otherwise the end screen would keep simulating underneath.
        let won = { phase = Phase.Won | start() };
        assertEq(expected = won#tick, steps(50, won, Input.empty())#tick);
        let lost = { phase = Phase.Lost | start() };
        assertEq(expected = lost#tick, steps(50, lost, Input.empty())#tick)
    }

    @Test
    def testEnterRestartsFromTheEndScreen(): Unit \ Assert = {
        let lost = { phase = Phase.Lost, score = 500, lives = 0 | steps(120, start(), Input.empty()) };
        let restarted = Game.step(lost, Input.holding(Key.Enter :: Nil));
        assertEq(expected = Phase.Playing, restarted#phase);
        assertEq(expected = 0, restarted#score);
        assertEq(expected = Rules.startingLives(), restarted#lives);
        assertEq(expected = 0, restarted#tick);
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

    @Test
    def testRenderDrawsOneRectPerLivingInvaderPlusThePlayer(): Unit \ Assert = {
        let cmds = Canvas.commands((640, 480), () -> View.render(start()));
        let rects = List.count(cmd -> match cmd {
            case DrawCmd.Rect(_, _, _, _) => true
            case _ => false
        }, cmds);
        assertEq(expected = Rules.totalInvaders() + 1, rects)
    }

    @Test
    def testDeadInvadersAreNotDrawn(): Unit \ Assert = {
        let base = start();
        let killed = Vector.update(0, { alive = false | Vector.get(0, base#invaders) }, base#invaders);
        let cmds = Canvas.commands((640, 480), () -> View.render({ invaders = killed | base }));
        let rects = List.count(cmd -> match cmd {
            case DrawCmd.Rect(_, _, _, _) => true
            case _ => false
        }, cmds);
        assertEq(expected = Rules.totalInvaders(), rects)
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
            case DrawCmd.Text(s, _, _) => String.contains(substr = "enter", s)
            case _ => false
        }, cmds);
        Assert.assertTrue(hasHint)
    }

}
