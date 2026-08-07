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

    ///
    /// Builds a deterministic input script -- a stand-in for a recorded play session.
    ///
    /// Accumulated and reversed rather than consed onto the recursive call. Consing afterwards
    /// puts the `::` outside the call, so it is not a tail call and every element costs a stack
    /// frame: a four-thousand-tick script overflowed on CI's Linux runner while passing on a
    /// macOS machine with a larger default stack. The lengths here are chosen by what the test
    /// needs to prove, so they must not be limited by how the list is built.
    ///
    def script(n: Int32, rng: Rng): List[Snapshot] = {
        def loop(remaining, generator, acc) =
            if (remaining <= 0) List.reverse(acc)
            else {
                let (choice, next) = Rng.nextInt32Below(5, generator);
                let keys =
                    if (choice == 0) Key.Left :: Nil
                    else if (choice == 1) Key.Right :: Nil
                    else if (choice == 2) Key.Space :: Nil
                    else if (choice == 3) Key.Left :: Key.Space :: Nil
                    else Nil;
                loop(remaining - 1, next, Input.holding(keys) :: acc)
            };
        loop(n, rng, Nil)
    }

    def demoScript(n: Int32): List[Snapshot] = script(n, Rng.fromSeed(99i64))

    def play(w: World, inputs: List[Snapshot]): World =
        Sound.runWithNoOp(() -> List.foldLeft(Game.step, w, inputs))

    /// The same run, keeping what it played instead of discarding it.
    def playedBy(w: World, inputs: List[Snapshot]): List[SoundCmd] =
        Sound.played(() -> List.foldLeft(Game.step, w, inputs))

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

    @Test
    def testTheSoundtrackReplaysIdentically(): Unit \ Assert = {
        // Sounds used to live on the world and so were covered by the digest. Now that they
        // are an effect, determinism of what is *heard* needs asserting directly -- and this
        // is the stronger check, because it compares the whole ordered sequence.
        let inputs = demoScript(600);
        assertEq(expected = playedBy(Game.initial(42i64), inputs),
                 playedBy(Game.initial(42i64), inputs))
    }

    @Test
    def testADifferentSeedEventuallySoundsDifferent(): Unit \ Assert = {
        // Needs a long run, and the reason is worth knowing: most of the soundtrack is
        // decided by the *input*, not the generator. Shots, march notes and kills all follow
        // from the script and the deterministic march. The generator only drives bomb drops,
        // which are silent, and saucer timing -- and no saucer appears inside the first few
        // hundred ticks. A 600-step comparison finds two identical soundtracks.
        let inputs = demoScript(3000);
        assertNeq(unexpected = playedBy(Game.initial(42i64), inputs),
                  playedBy(Game.initial(43i64), inputs))
    }

    @Test
    def testTheSoundtrackIsNotEmpty(): Unit \ Assert =
        // Guards the two tests above from passing vacuously on two empty lists.
        Assert.assertTrue(List.length(playedBy(Game.initial(42i64), demoScript(600))) > 10)

}
