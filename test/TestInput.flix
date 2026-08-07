mod TestInput {

    use Assert.assertEq
    use Assert.assertTrue
    use Assert.assertFalse
    use Assert.assertTrueWithMsg

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


    // -- one frame, many ticks --------------------------------------------------------------
    //
    // A frame does not map to a tick: the display runs at whatever the machine manages and the
    // simulation at a fixed rate, so a frame may owe several ticks or none. Getting that wrong
    // loses presses or repeats them, and neither is visible in a screenshot.

    def tick(): Int64 = 16666666i64

    @Test
    def testAFrameThatOwesNothingRunsNothing(): Unit \ Assert =
        assertEq(expected = 0, Input.ticksDue(tick() / 2i64, tick(), 5))

    @Test
    def testAFrameOwesOneTickPerWholeStepAccumulated(): Unit \ Assert = {
        assertEq(expected = 1, Input.ticksDue(tick(), tick(), 5));
        assertEq(expected = 3, Input.ticksDue(3i64 * tick(), tick(), 5))
    }

    @Test
    def testCatchUpIsCapped(): Unit \ Assert =
        // A stall must not be paid off in one frame; that is what the budget is for.
        assertEq(expected = 5, Input.ticksDue(100i64 * tick(), tick(), 5))

    @Test
    def testAnImpossibleStepLengthOwesNothing(): Unit \ Assert = {
        // Rather than dividing by it.
        assertEq(expected = 0, Input.ticksDue(tick(), 0i64, 5));
        assertEq(expected = 0, Input.ticksDue(tick(), -1i64, 5))
    }

    @Test
    def testOnlyTheFirstTickOfAFrameSeesTheEdges(): Unit \ Assert = {
        // Handing the same `pressed` set to every catch-up tick fires a one-off action once
        // per stalled frame instead of once per press -- and anything that toggles, like the
        // stats overlay, can flip twice and end up back where it started.
        let press = Input.diff(previous = Set.empty(), current = Set#{Key.F3}, mouseX = 0, mouseY = 0);
        let ticks = Input.acrossTicks(3, press);
        assertEq(expected = 3, List.length(ticks));
        let sawPress = List.count(t -> Set.memberOf(Key.F3, t#pressed), ticks);
        assertEq(expected = 1, sawPress)
    }

    @Test
    def testEveryTickOfAFrameStillSeesTheKeyHeld(): Unit \ Assert = {
        // Holding is a state rather than a transition, and it does last all frame.
        let press = Input.diff(previous = Set.empty(), current = Set#{Key.Left}, mouseX = 0, mouseY = 0);
        let ticks = Input.acrossTicks(4, press);
        assertTrueWithMsg(List.forAll(t -> Set.memberOf(Key.Left, t#held), ticks),
            "the cannon would stop moving partway through a catch-up frame")
    }

    @Test
    def testReleasesAreAlsoOnlyDeliveredOnce(): Unit \ Assert = {
        let letGo = Input.diff(previous = Set#{Key.Space}, current = Set.empty(), mouseX = 0, mouseY = 0);
        let ticks = Input.acrossTicks(3, letGo);
        assertEq(expected = 1, List.count(t -> Set.memberOf(Key.Space, t#released), ticks))
    }

    @Test
    def testAFrameOwingNothingDeliversNothing(): Unit \ Assert =
        // The other half of not retiring the previous key state: a frame that runs no tick
        // must hand out no input at all, or the press is consumed by nobody.
        assertTrue(List.isEmpty(Input.acrossTicks(0, Input.holding(Key.Space :: Nil))))

    @Test
    def testSteadyKeepsTheKeysAndTheMouse(): Unit \ Assert = {
        let s = Input.diff(previous = Set.empty(), current = Set#{Key.Right},
                           mouseX = 12, mouseY = 34);
        let quiet = Input.steady(s);
        assertEq(expected = s#held, quiet#held);
        assertEq(expected = 12, quiet#mouseX);
        assertEq(expected = 34, quiet#mouseY);
        assertTrue(Set.isEmpty(quiet#pressed) and Set.isEmpty(quiet#released))
    }

}
