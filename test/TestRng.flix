mod TestRng {

    use Assert.assertEq
    use Assert.assertTrue
    use Assert.assertNeq

    /// Draws `n` values, returning them oldest-first.
    def take(n: Int32, r: Rng): List[Int64] =
        if (n <= 0) Nil
        else {
            let (value, next) = Rng.nextInt64(r);
            value :: take(n - 1, next)
        }

    @Test
    def testSameSeedGivesTheSameSequence(): Unit \ Assert =
        assertEq(expected = take(50, Rng.fromSeed(42i64)), take(50, Rng.fromSeed(42i64)))

    @Test
    def testDifferentSeedsDiverge(): Unit \ Assert =
        assertNeq(unexpected = take(50, Rng.fromSeed(42i64)), take(50, Rng.fromSeed(43i64)))

    @Test
    def testAdjacentSeedsAreNotCorrelated(): Unit \ Assert = {
        // A bare LCG seeded directly would make these first values near-identical, which is
        // why `fromSeed` advances the state once.
        let (a, _) = Rng.nextInt64(Rng.fromSeed(1i64));
        let (b, _) = Rng.nextInt64(Rng.fromSeed(2i64));
        assertNeq(unexpected = a, b)
    }

    @Test
    def testNextNonNegativeIsNeverNegative(): Unit \ Assert = {
        def loop(n, r) =
            if (n <= 0) ()
            else {
                let (value, next) = Rng.nextNonNegative(r);
                Assert.assertTrueWithMsg(value >= 0i64, "got a negative value: ${value}");
                loop(n - 1, next)
            };
        loop(500, Rng.fromSeed(7i64))
    }

    @Test
    def testNextInt32BelowStaysInRange(): Unit \ Assert = {
        def loop(n, r) =
            if (n <= 0) ()
            else {
                let (value, next) = Rng.nextInt32Below(6, r);
                Assert.assertTrueWithMsg(value >= 0 and value < 6, "out of range: ${value}");
                loop(n - 1, next)
            };
        loop(500, Rng.fromSeed(11i64))
    }

    @Test
    def testNextInt32BelowCoversItsRange(): Unit \ Assert = {
        // Guards against a generator that is deterministic but constant.
        def collect(n, r, acc) =
            if (n <= 0) acc
            else {
                let (value, next) = Rng.nextInt32Below(6, r);
                collect(n - 1, next, Set.insert(value, acc))
            };
        assertEq(expected = 6, Set.size(collect(500, Rng.fromSeed(3i64), Set.empty())))
    }

    @Test
    def testNonPositiveBoundIsSafe(): Unit \ Assert = {
        let (zero, _) = Rng.nextInt32Below(0, Rng.fromSeed(1i64));
        assertEq(expected = 0, zero);
        let (negative, _) = Rng.nextInt32Below(-5, Rng.fromSeed(1i64));
        assertEq(expected = 0, negative)
    }

    @Test
    def testChanceOneInOneIsAlwaysTrue(): Unit \ Assert = {
        let (hit, _) = Rng.chance(1, Rng.fromSeed(99i64));
        assertTrue(hit)
    }

    @Test
    def testChanceIsRoughlyFair(): Unit \ Assert = {
        // 2000 draws at 1-in-4; a correct generator lands well inside these bounds, and a
        // broken one (always true, always false, stuck) falls outside.
        def count(n, r, hits) =
            if (n <= 0) hits
            else {
                let (hit, next) = Rng.chance(4, r);
                count(n - 1, next, if (hit) hits + 1 else hits)
            };
        let hits = count(2000, Rng.fromSeed(5i64), 0);
        Assert.assertTrueWithMsg(hits > 380 and hits < 620, "expected ~500 hits, got ${hits}")
    }

    @Test
    def testGeneratorIsAValueNotSharedState(): Unit \ Assert = {
        // Drawing from the same generator twice gives the same answer: nothing is mutated.
        let r = Rng.fromSeed(21i64);
        let (a, _) = Rng.nextInt64(r);
        let (b, _) = Rng.nextInt64(r);
        assertEq(expected = a, b)
    }

}
