///
/// The frame loop's arithmetic, and the window's.
///
/// Everything here is the part of the runtime that can be checked without a display: how a
/// requested rate is brought into range, how long one logical tick covers, and how often the
/// window asks for a frame. The rest of `Sketch` and `Surface` needs a window, and is
/// exercised by the bounded windowed run the smoke workflow makes instead.
///
mod TestSketch {

    use Assert.assertEq
    use Assert.assertFalse
    use Assert.assertTrue

    // -- the simulation rate ------------------------------------------------------------

    @Test
    def testAnOrdinaryRateIsLeftAlone(): Unit \ Assert = {
        assertEq(expected = 60, Sketch.clampHz(60));
        assertEq(expected = 30, Sketch.clampHz(30));
        assertEq(expected = 144, Sketch.clampHz(144))
    }

    @Test
    def testARateOfNoughtIsRaisedRatherThanDividedBy(): Unit \ Assert =
        assertEq(expected = 1, Sketch.clampHz(0))

    @Test
    def testANegativeRateNeverRunsTheClockBackwards(): Unit \ Assert =
        assertEq(expected = 1, Sketch.clampHz(-60))

    @Test
    def testAnAbsurdRateIsBroughtBackToOneAMachineCouldMeet(): Unit \ Assert = {
        assertEq(expected = 1000, Sketch.clampHz(1001));
        assertEq(expected = 1000, Sketch.clampHz(2000000000))
    }

    // -- the length of a tick -----------------------------------------------------------

    @Test
    def testATickAtSixtyHertzIsASixtiethOfASecond(): Unit \ Assert =
        assertEq(expected = 16666666i64, Sketch.stepNsFor(60))

    @Test
    def testATickAtOneHertzIsAWholeSecond(): Unit \ Assert =
        assertEq(expected = 1000000000i64, Sketch.stepNsFor(1))

    ///
    /// The clamp is what keeps this from dividing by zero, so it is asserted here too: a
    /// tick must always cover some time, or the accumulator owes infinitely many of them.
    ///
    @Test
    def testATickAlwaysCoversSomeTime(): Unit \ Assert = {
        assertTrue(Sketch.stepNsFor(0) > 0i64);
        assertTrue(Sketch.stepNsFor(-1) > 0i64);
        assertTrue(Sketch.stepNsFor(2000000000) > 0i64)
    }

    // -- turning a span into something a timer understands ---------------------------------

    ///
    /// Swing's timer counts in whole milliseconds, and a sixtieth of a second is not one.
    /// Truncating is the safe direction of the two -- `reschedule` corrects it against a
    /// deadline, and a frame that arrives early owes fewer ticks while one that arrives late
    /// has to be caught up on.
    ///
    @Test
    def testASixtiethOfASecondIsSixteenMilliseconds(): Unit \ Assert =
        assertEq(expected = 16, Surface.millisOf(Sketch.stepNsFor(60)))

    @Test
    def testASpanAlreadySpentIsNoWaitAtAll(): Unit \ Assert = {
        assertEq(expected = 0, Surface.millisOf(0i64));
        assertEq(expected = 0, Surface.millisOf(-5000000i64))
    }

    @Test
    def testASpanShorterThanAMillisecondRoundsDownToNone(): Unit \ Assert =
        assertEq(expected = 0, Surface.millisOf(999999i64))

    ///
    /// The first frame is the one that cannot be hurried: until it has drawn there is no
    /// window worth talking to, and a timer asked for no delay at all never lets one appear.
    ///
    @Test
    def testTheFirstFrameIsNeverAskedForImmediately(): Unit \ Assert = {
        assertEq(expected = 16, Surface.firstDelay(Sketch.stepNsFor(60)));
        assertEq(expected = 1, Surface.firstDelay(Sketch.stepNsFor(1000)));
        assertEq(expected = 1, Surface.firstDelay(0i64))
    }

    // -- the one key the window keeps for itself ------------------------------------------

    ///
    /// Escape closes the window, so it never reaches a step. Nothing above the runtime may
    /// use it for anything else, and this is where that is written down.
    ///
    @Test
    def testEscapeClosesTheWindow(): Unit \ Assert =
        assertTrue(Surface.closesWindow(27))

    @Test
    def testTheKeysTheGamePlaysWithReachTheGame(): Unit \ Assert = {
        assertFalse(Surface.closesWindow(32));
        assertFalse(Surface.closesWindow(10));
        assertFalse(Surface.closesWindow(37));
        assertFalse(Surface.closesWindow(114))
    }

    // -- what a key event does to the held set --------------------------------------------

    @Test
    def testAPressJoinsTheKeysAlreadyHeld(): Unit \ Assert =
        assertEq(expected = Some(Set#{37, 32}), Surface.afterPress(Set#{37}, 32))

    ///
    /// Auto-repeat delivers the same press again and again while a key is down. Adding it to
    /// a set is what makes that harmless -- the alternative, a counter, would have to be
    /// decremented by exactly the releases the window system chose to send.
    ///
    @Test
    def testRepeatedPressesOfTheSameKeyChangeNothing(): Unit \ Assert =
        assertEq(expected = Some(Set#{37}), Surface.afterPress(Set#{37}, 37))

    ///
    /// `None` is the window taking the press: Escape closes it and never reaches a step.
    ///
    @Test
    def testEscapeIsTakenByTheWindowRatherThanHeld(): Unit \ Assert =
        assertEq(expected = None, Surface.afterPress(Set#{37}, 27))

    @Test
    def testAReleaseLetsGoOfOnlyThatKey(): Unit \ Assert =
        assertEq(expected = Set#{37}, Surface.afterRelease(Set#{37, 32}, 32))

    ///
    /// A release with no press before it arrives whenever a key goes down in another window
    /// and comes up in this one. It must not disturb what is held.
    ///
    @Test
    def testAReleaseOfAKeyNeverHeldIsHarmless(): Unit \ Assert =
        assertEq(expected = Set#{37}, Surface.afterRelease(Set#{37}, 32))

    // -- keeping the frame rate on target -------------------------------------------------

    ///
    /// The ordinary case: the next frame is due one period after the last one was.
    ///
    @Test
    def testTheDeadlineMovesOnByExactlyOnePeriod(): Unit \ Assert = {
        let period = Sketch.stepNsFor(60);
        let (target, waitMs) = Surface.reschedule(0i64, 0i64, period);
        assertEq(expected = period, target);
        assertEq(expected = 16, waitMs)
    }

    ///
    /// The case the deadline exists for. A frame that costs ten milliseconds must be waited
    /// out of the period it was drawn in, not added to the next one -- which is what a timer
    /// counting its delay from the moment it fires would do.
    ///
    @Test
    def testAFrameThatRanLongShortensTheNextWait(): Unit \ Assert = {
        let period = Sketch.stepNsFor(60);
        let (target, waitMs) = Surface.reschedule(0i64, 10000000i64, period);
        assertEq(expected = period, target);
        assertEq(expected = 6, waitMs)
    }

    ///
    /// A frame more than a whole period late gives up on the ones it missed. Firing them back
    /// to back would only put the next one further behind, and the accumulator still owes the
    /// ticks that time was worth.
    ///
    @Test
    def testAFrameMoreThanAPeriodLateStartsCountingAgain(): Unit \ Assert = {
        let period = Sketch.stepNsFor(60);
        let now = 50000000i64;
        let (target, waitMs) = Surface.reschedule(0i64, now, period);
        assertEq(expected = now + period, target);
        assertEq(expected = 16, waitMs)
    }

    @Test
    def testADeadlineAlreadyReachedIsNotWaitedFor(): Unit \ Assert = {
        let period = Sketch.stepNsFor(60);
        let (_target, waitMs) = Surface.reschedule(0i64, period, period);
        assertEq(expected = 0, waitMs)
    }

    ///
    /// The whole point, as a property: a timer that can only be asked for whole milliseconds
    /// still delivers 60 frames a second, because every wait is measured against where the
    /// frame *should* land rather than against where the last one did.
    ///
    /// Six hundred frames of three milliseconds' work each, with the timer waiting exactly as
    /// long as it was asked to. Without the deadline the run would finish a full second late.
    ///
    @Test
    def testTheAverageRateStaysOnTargetDespiteWholeMillisecondWaits(): Unit \ Assert = {
        let period = Sketch.stepNsFor(60);
        let workNs = 3000000i64;
        let frames = 600;
        let oneFrame = (state, _i) -> {
            let (now, due) = state;
            let drawn = now + workNs;
            let (target, waitMs) = Surface.reschedule(due, drawn, period);
            (drawn + Int32.toInt64(waitMs) * 1000000i64, target)
        };
        let (elapsed, _due) = List.foldLeft(oneFrame, (0i64, 0i64), List.range(0, frames));
        let ideal = Int32.toInt64(frames) * period;
        assertTrue(Int64.abs(elapsed - ideal) < period)
    }

    ///
    /// The display is paced in whole milliseconds and the simulation in nanoseconds, so the
    /// two never divide evenly -- and the point of the accumulator is that they do not have
    /// to. A frame that arrives early owes fewer ticks, not shorter ones, so a run of frames
    /// owes exactly the ticks the time they covered is worth.
    ///
    /// This is the property that would break if the frame rate were ever allowed to set the
    /// simulation rate, which is the mistake a fixed timestep exists to prevent.
    ///
    @Test
    def testTheDisplayRateDoesNotChangeTheSimulationRate(): Unit \ Assert = {
        let hz = 60;
        let stepNs = Sketch.stepNsFor(hz);
        let frameNs = Int32.toInt64(Surface.millisOf(stepNs)) * 1000000i64;
        let frames = 600;
        let oneFrame = (state, _i) -> {
            let (owed, ran) = state;
            let due = Input.ticksDue(owed + frameNs, stepNs, 5);
            (owed + frameNs - stepNs * Int32.toInt64(due), ran + due)
        };
        let (_left, ran) = List.foldLeft(oneFrame, (0i64, 0), List.range(0, frames));
        let covered = Int32.toInt64(frames) * frameNs;
        assertEq(expected = Int64.tryToInt32(covered / stepNs), Some(ran))
    }

}
