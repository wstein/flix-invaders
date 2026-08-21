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

    // -- how often the window asks for a frame -------------------------------------------

    @Test
    def testSixtyHertzAsksForAFrameEverySixteenMilliseconds(): Unit \ Assert =
        assertEq(expected = 16, Surface.delayFor(60))

    @Test
    def testTheDelayIsNeverZero(): Unit \ Assert = {
        assertEq(expected = 1, Surface.delayFor(1000));
        assertEq(expected = 1, Surface.delayFor(4000))
    }

    @Test
    def testARateOfNoughtStillAsksForFrames(): Unit \ Assert = {
        assertEq(expected = 1000, Surface.delayFor(0));
        assertEq(expected = 1000, Surface.delayFor(-1))
    }

    @Test
    def testAFramePeriodIsTheRateTurnedIntoNanoseconds(): Unit \ Assert = {
        assertEq(expected = 16666666i64, Surface.periodFor(60));
        assertEq(expected = 1000000000i64, Surface.periodFor(1))
    }

    @Test
    def testAFramePeriodAlwaysCoversSomeTime(): Unit \ Assert =
        assertTrue(Surface.periodFor(0) > 0i64)

    // -- keeping the frame rate on target -------------------------------------------------

    ///
    /// The ordinary case: the next frame is due one period after the last one was.
    ///
    @Test
    def testTheDeadlineMovesOnByExactlyOnePeriod(): Unit \ Assert = {
        let period = Surface.periodFor(60);
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
        let period = Surface.periodFor(60);
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
        let period = Surface.periodFor(60);
        let now = 50000000i64;
        let (target, waitMs) = Surface.reschedule(0i64, now, period);
        assertEq(expected = now + period, target);
        assertEq(expected = 16, waitMs)
    }

    @Test
    def testADeadlineAlreadyReachedIsNotWaitedFor(): Unit \ Assert = {
        let period = Surface.periodFor(60);
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
        let period = Surface.periodFor(60);
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
        let frameNs = Int32.toInt64(Surface.delayFor(hz)) * 1000000i64;
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
