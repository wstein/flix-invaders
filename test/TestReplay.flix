mod TestReplay {

    use Assert.assertEq
    use Assert.assertNeq

    ///
    /// The property the whole design exists to provide: a world plus a list of input
    /// snapshots completely determines every world that follows.
    ///
    /// Nothing in here opens a window, reads a clock, or touches `IO`. If any of that leaked
    /// into `Game.step`, these tests would stop compiling rather than start flaking.
    ///

    /// Builds a deterministic input script -- a stand-in for a recorded play session.
    def script(n: Int32, rng: Rng): List[Snapshot] =
        if (n <= 0) Nil
        else {
            let (choice, next) = Rng.nextInt32Below(5, rng);
            let keys =
                if (choice == 0) Key.Left :: Nil
                else if (choice == 1) Key.Right :: Nil
                else if (choice == 2) Key.Space :: Nil
                else if (choice == 3) Key.Left :: Key.Space :: Nil
                else Nil;
            Input.holding(keys) :: script(n - 1, next)
        }

    def demoScript(n: Int32): List[Snapshot] = script(n, Rng.fromSeed(99i64))

    def play(w: World, inputs: List[Snapshot]): World =
        List.foldLeft(Game.step, w, inputs)

    @Test
    def testTheSameSeedAndScriptReplayIdentically(): Unit \ Assert = {
        let inputs = demoScript(600);
        assertEq(expected = Game.digest(play(Game.initial(42i64), inputs)),
                 Game.digest(play(Game.initial(42i64), inputs)))
    }

    @Test
    def testTheSeedActuallyMatters(): Unit \ Assert = {
        // Without this, a `step` that ignored its generator entirely would pass the test
        // above trivially.
        let inputs = demoScript(600);
        assertNeq(unexpected = Game.digest(play(Game.initial(42i64), inputs)),
                  Game.digest(play(Game.initial(43i64), inputs)))
    }

    @Test
    def testDifferentInputProducesADifferentWorld(): Unit \ Assert = {
        let idle = List.repeat(400, Input.empty());
        let busy = demoScript(400);
        assertNeq(unexpected = Game.digest(play(Game.initial(7i64), idle)),
                  Game.digest(play(Game.initial(7i64), busy)))
    }

    @Test
    def testReplayDoesNotDependOnHowTheStepsAreGrouped(): Unit \ Assert = {
        // Running 600 steps in one go must equal running two batches of 300. A world that
        // secretly depended on anything outside itself would diverge here.
        let inputs = demoScript(600);
        let (first, second) = (List.take(300, inputs), List.drop(300, inputs));
        assertEq(expected = Game.digest(play(Game.initial(11i64), inputs)),
                 Game.digest(play(play(Game.initial(11i64), first), second)))
    }

    @Test
    def testResumingFromAMidGameWorldIsDeterministic(): Unit \ Assert = {
        // The generator is part of the world, so a world captured mid-game carries
        // everything needed to continue it reproducibly.
        let midGame = play(Game.initial(5i64), demoScript(250));
        let rest = script(250, Rng.fromSeed(1234i64));
        assertEq(expected = Game.digest(play(midGame, rest)), Game.digest(play(midGame, rest)))
    }

    @Test
    def testAnEmptyScriptChangesNothing(): Unit \ Assert =
        assertEq(expected = Game.digest(Game.initial(3i64)), Game.digest(play(Game.initial(3i64), Nil)))

    @Test
    def testReplayIsStableAcrossAFullGame(): Unit \ Assert = {
        // Long enough that the formation reaches the player and the game ends, so the
        // determinism claim covers the ending too, not just the quiet opening.
        let inputs = demoScript(4000);
        let a = play(Game.initial(21i64), inputs);
        let b = play(Game.initial(21i64), inputs);
        assertEq(expected = Game.digest(a), Game.digest(b));
        assertNeq(unexpected = Phase.Playing, a#phase)
    }

    @Test
    def testRenderingAReplayedWorldIsAlsoDeterministic(): Unit \ Assert = {
        let inputs = demoScript(500);
        let a = play(Game.initial(8i64), inputs);
        let b = play(Game.initial(8i64), inputs);
        assertEq(expected = Canvas.commands((640, 480), () -> View.render(a)),
                 Canvas.commands((640, 480), () -> View.render(b)))
    }

}
