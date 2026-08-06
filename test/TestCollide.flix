mod TestCollide {

    use Assert.assertTrue
    use Assert.assertFalse

    def at(x: Float32, y: Float32): Vec2 = { x = x, y = y }
    def size(w: Float32, h: Float32): Vec2 = { x = w, y = h }

    /// The standard 20x20 box used by most of these cases.
    def box(): Vec2 = size(20.0f32, 20.0f32)

    /// `overlaps` with every argument named, which is how it must now be called.
    def hits(aPos: Vec2, aSize: Vec2, bPos: Vec2, bSize: Vec2): Bool =
        Collide.overlaps(aPos = aPos, aSize = aSize, bPos = bPos, bSize = bSize)

    @Test
    def testConcentricRectanglesOverlap(): Unit \ Assert =
        assertTrue(hits(at(100.0f32, 100.0f32), box(), at(100.0f32, 100.0f32), size(10.0f32, 10.0f32)))

    @Test
    def testPartialOverlapCounts(): Unit \ Assert =
        assertTrue(hits(at(100.0f32, 100.0f32), box(), at(115.0f32, 100.0f32), box()))

    @Test
    def testSeparatedRectanglesDoNotOverlap(): Unit \ Assert =
        assertFalse(hits(at(100.0f32, 100.0f32), box(), at(200.0f32, 100.0f32), box()))

    @Test
    def testExactlyTouchingEdgesDoNotCount(): Unit \ Assert = {
        // The convention is strict inequality: touching is not hitting. Pinned here so a
        // later change to `overlaps` cannot quietly flip it.
        assertFalse(hits(at(100.0f32, 100.0f32), box(), at(120.0f32, 100.0f32), box()));
        assertFalse(hits(at(100.0f32, 100.0f32), box(), at(100.0f32, 120.0f32), box()))
    }

    @Test
    def testOneUnitInsideTheEdgeCounts(): Unit \ Assert =
        assertTrue(hits(at(100.0f32, 100.0f32), box(), at(119.0f32, 100.0f32), box()))

    @Test
    def testOverlapOnOneAxisOnlyIsNotAHit(): Unit \ Assert = {
        // Aligned horizontally but far apart vertically. A missing `and` in the
        // implementation would report a hit here.
        assertFalse(hits(at(100.0f32, 100.0f32), box(), at(100.0f32, 300.0f32), box()));
        assertFalse(hits(at(100.0f32, 100.0f32), box(), at(300.0f32, 100.0f32), box()))
    }

    @Test
    def testOverlapIsSymmetric(): Unit \ Assert = {
        let a = at(100.0f32, 100.0f32);
        let b = at(112.0f32, 108.0f32);
        let sa = box();
        let sb = size(14.0f32, 14.0f32);
        assertTrue(hits(a, sa, b, sb) == hits(b, sb, a, sa))
    }

    @Test
    def testPositionAndSizePlayDifferentRoles(): Unit \ Assert = {
        // The reason every argument is named. These two calls use the same four values in
        // the same order and differ only in how big the boxes are; if position and size were
        // interchangeable a transposed call site would be undetectable.
        let pos = at(100.0f32, 100.0f32);
        let other = at(130.0f32, 100.0f32);
        let small = size(4.0f32, 4.0f32);
        let large = size(80.0f32, 80.0f32);
        assertTrue(hits(pos, large, other, large));
        assertFalse(hits(pos, small, other, small))
    }

    @Test
    def testABulletSizedRectHitsAnInvaderSizedRect(): Unit \ Assert =
        // The real pairing the game relies on.
        assertTrue(hits(at(200.0f32, 100.0f32), Rules.bulletSize(),
                        at(200.0f32, 100.0f32), Rules.invaderSize()))

}
