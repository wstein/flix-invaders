mod TestCollide {

    use Assert.assertTrue
    use Assert.assertFalse

    def at(x: Float32, y: Float32): Vec2 = { x = x, y = y }
    def size(w: Float32, h: Float32): Vec2 = { x = w, y = h }

    @Test
    def testConcentricRectanglesOverlap(): Unit \ Assert =
        assertTrue(Collide.overlaps(at(100.0f32, 100.0f32), size(20.0f32, 20.0f32),
                                    at(100.0f32, 100.0f32), size(10.0f32, 10.0f32)))

    @Test
    def testPartialOverlapCounts(): Unit \ Assert =
        assertTrue(Collide.overlaps(at(100.0f32, 100.0f32), size(20.0f32, 20.0f32),
                                    at(115.0f32, 100.0f32), size(20.0f32, 20.0f32)))

    @Test
    def testSeparatedRectanglesDoNotOverlap(): Unit \ Assert =
        assertFalse(Collide.overlaps(at(100.0f32, 100.0f32), size(20.0f32, 20.0f32),
                                     at(200.0f32, 100.0f32), size(20.0f32, 20.0f32)))

    @Test
    def testExactlyTouchingEdgesDoNotCount(): Unit \ Assert = {
        // The convention is strict inequality: touching is not hitting. Pinned here so a
        // later change to `overlaps` cannot quietly flip it.
        assertFalse(Collide.overlaps(at(100.0f32, 100.0f32), size(20.0f32, 20.0f32),
                                     at(120.0f32, 100.0f32), size(20.0f32, 20.0f32)));
        assertFalse(Collide.overlaps(at(100.0f32, 100.0f32), size(20.0f32, 20.0f32),
                                     at(100.0f32, 120.0f32), size(20.0f32, 20.0f32)))
    }

    @Test
    def testOneUnitInsideTheEdgeCounts(): Unit \ Assert =
        assertTrue(Collide.overlaps(at(100.0f32, 100.0f32), size(20.0f32, 20.0f32),
                                    at(119.0f32, 100.0f32), size(20.0f32, 20.0f32)))

    @Test
    def testOverlapOnOneAxisOnlyIsNotAHit(): Unit \ Assert = {
        // Aligned horizontally but far apart vertically. A missing `and` in the
        // implementation would report a hit here.
        assertFalse(Collide.overlaps(at(100.0f32, 100.0f32), size(20.0f32, 20.0f32),
                                     at(100.0f32, 300.0f32), size(20.0f32, 20.0f32)));
        assertFalse(Collide.overlaps(at(100.0f32, 100.0f32), size(20.0f32, 20.0f32),
                                     at(300.0f32, 100.0f32), size(20.0f32, 20.0f32)))
    }

    @Test
    def testOverlapIsSymmetric(): Unit \ Assert = {
        let a = at(100.0f32, 100.0f32);
        let b = at(112.0f32, 108.0f32);
        let sa = size(20.0f32, 20.0f32);
        let sb = size(14.0f32, 14.0f32);
        assertTrue(Collide.overlaps(a, sa, b, sb) == Collide.overlaps(b, sb, a, sa))
    }

    @Test
    def testABulletSizedRectHitsAnInvaderSizedRect(): Unit \ Assert =
        // The real pairing the game relies on.
        assertTrue(Collide.overlaps(at(200.0f32, 100.0f32), Rules.bulletSize(),
                                    at(200.0f32, 100.0f32), Rules.invaderSize()))

}
