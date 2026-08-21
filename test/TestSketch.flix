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
