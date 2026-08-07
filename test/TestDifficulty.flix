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
    /// A competent player: pick the lowest living invader, lead it by the bullet's flight
    /// time, and fire when lined up.
    ///
    /// The leading is essential to the measurement. A bullet takes roughly forty ticks to
    /// reach the formation, during which the invaders move most of their own width, so
    /// aiming where a target *is* rather than where it will *be* misses nearly every shot
    /// and tells you nothing about whether the game is fair.
    ///
    /// It does not dodge, so its results are a floor: a human who also dodges does better.
    ///
    def aim(w: World): Snapshot = {
        let target = Vector.foldLeft((best, inv) ->
            if (not inv#alive) best
            else match best {
                case None => Some(inv#pos)
                case Some(p) => if (inv#pos#y > p#y) Some(inv#pos) else best
            }, None, w#invaders);
        match target {
            case None => Input.empty()
            case Some(p) => {
                let living = Vector.count(inv -> inv#alive, w#invaders);
                let flight = (Rules.playerY() - p#y) / Rules.bulletSpeed();
                let lead = w#marchDir * Rules.marchSpeedFor(living, w#level) * flight;
                let dx = (p#x + lead) - w#playerX;
                let move =
                    if (dx < -1.5f32) Key.Left :: Nil
                    else if (dx > 1.5f32) Key.Right :: Nil
                    else Nil;
                let fire = if (Float32.abs(dx) < 6.0f32) Key.Space :: Nil else Nil;
                Input.holding(List.append(move, fire))
            }
        }
    }

    def playRaw(budget: Int32, w: World): World \ Sound =
        if (budget <= 0 or w#phase == Phase.Lost) w
        else playRaw(budget - 1, Game.step(w, aim(w)))

    def play(budget: Int32, w: World): World =
        Sound.runWithNoOp(() -> playRaw(budget, w))

    /// How long the formation takes to land if nothing shoots it and bombs are ignored.
    def descentTicks(): Int32 = {
        def loop(n, w) =
            if (n <= 0 or w#phase == Phase.Lost) n
            else loop(n - 1, Game.step({ lives = 99, bombs = Nil | w }, Input.empty()));
        20000 - Sound.runWithNoOp(() -> loop(20000, Game.initial(1i64)))
    }

    @Test
    def testACompetentPlayerGetsPastTheFirstLevel(): Unit \ Assert = {
        // Not every seed -- bombs are luck -- but most of them.
        let seeds = 2026i64 :: 7i64 :: 99i64 :: 1234i64 :: Nil;
        let cleared = List.count(seed -> play(6000, Game.initial(seed))#level > 1, seeds);
        assertTrueWithMsg(cleared >= 2,
            "a bot that never misses cleared level one on only ${cleared} of ${List.length(seeds)} seeds; "
            + "the game is too hard")
    }

    @Test
    def testTheFirstLevelIsNotTrivialEither(): Unit \ Assert = {
        // The other side of the same guard: if a non-dodging bot runs forever, there is no
        // pressure at all.
        let survived = play(6000, Game.initial(2026i64));
        assertTrueWithMsg(survived#level < 12,
            "the bot reached level ${survived#level} unchallenged; the game is too easy")
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
