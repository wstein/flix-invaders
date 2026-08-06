mod TestInput {

    use Assert.assertEq
    use Assert.assertTrue
    use Assert.assertFalse

    @Test
    def testKeyCodesMapToNamedKeys(): Unit \ Assert = {
        assertEq(expected = Key.Left, Key.fromCode(37));
        assertEq(expected = Key.Up, Key.fromCode(38));
        assertEq(expected = Key.Right, Key.fromCode(39));
        assertEq(expected = Key.Down, Key.fromCode(40));
        assertEq(expected = Key.Space, Key.fromCode(32));
        assertEq(expected = Key.Enter, Key.fromCode(10));
        assertEq(expected = Key.Escape, Key.fromCode(27))
    }

    @Test
    def testUnknownKeyCodeIsPreserved(): Unit \ Assert =
        assertEq(expected = Key.Other(65), Key.fromCode(65))

    @Test
    def testPressedIsTheRisingEdge(): Unit \ Assert = {
        let s = Input.diff(previous = Set.empty(), current = Set#{Key.Left}, mouseX = 0, mouseY = 0);
        assertTrue(Set.memberOf(Key.Left, s#pressed));
        assertTrue(Set.memberOf(Key.Left, s#held));
        assertTrue(Set.isEmpty(s#released))
    }

    @Test
    def testReleasedIsTheFallingEdge(): Unit \ Assert = {
        let s = Input.diff(previous = Set#{Key.Left}, current = Set.empty(), mouseX = 0, mouseY = 0);
        assertTrue(Set.memberOf(Key.Left, s#released));
        assertTrue(Set.isEmpty(s#held));
        assertTrue(Set.isEmpty(s#pressed))
    }

    @Test
    def testKeyHeldAcrossStepsIsNotPressedAgain(): Unit \ Assert = {
        // This is what stops "hold to fire" from firing once per frame.
        let s = Input.diff(previous = Set#{Key.Space}, current = Set#{Key.Space}, mouseX = 0, mouseY = 0);
        assertTrue(Set.memberOf(Key.Space, s#held));
        assertFalse(Set.memberOf(Key.Space, s#pressed));
        assertTrue(Set.isEmpty(s#released))
    }

    @Test
    def testEdgesAreIndependentPerKey(): Unit \ Assert = {
        let s = Input.diff(previous = Set#{Key.Left, Key.Space},
                           current = Set#{Key.Space, Key.Right}, mouseX = 0, mouseY = 0);
        assertEq(expected = Set#{Key.Right}, s#pressed);
        assertEq(expected = Set#{Key.Left}, s#released);
        assertEq(expected = Set#{Key.Space, Key.Right}, s#held)
    }

    @Test
    def testMousePositionIsCarried(): Unit \ Assert = {
        let s = Input.diff(previous = Set.empty(), current = Set.empty(), mouseX = 12, mouseY = 34);
        assertEq(expected = 12, s#mouseX);
        assertEq(expected = 34, s#mouseY)
    }

    @Test
    def testEmptySnapshotHoldsNothing(): Unit \ Assert = {
        let s = Input.empty();
        assertTrue(Set.isEmpty(s#held));
        assertTrue(Set.isEmpty(s#pressed));
        assertTrue(Set.isEmpty(s#released))
    }

    @Test
    def testPollIsIdempotentWithinAStep(): Unit \ Assert = {
        // The whole replay story depends on this: polling twice in one step must not
        // observe two different worlds.
        let snap = Input.holding(Key.Left :: Nil);
        let (a, b) = Input.runWith(snap, () -> (Input.poll(), Input.poll()));
        assertEq(expected = a#held, b#held);
        assertEq(expected = snap#held, a#held)
    }

}
