///
/// What the runtime knows about its own performance.
///
/// The frame loop is the only thing that can measure any of this, and the view is the only
/// thing that can show it, so it travels from one to the other as an ordinary value. Nothing
/// in between -- not the rules, not the cabinet -- learns that a clock exists.
///
/// Timings are of the *work*, not of the frame. Processing sleeps to hold the target rate, so
/// a stopwatch around a whole frame measures the rate limiter: at 60Hz every sketch reports
/// about 16.7ms whether it spends 1ms or 15ms. `simMs` and `drawMs` bracket the simulation and
/// the drawing themselves, which is the number that tells you anything.
///
pub type alias Stats = {
    fps = Float32,
    simMs = Float32,
    drawMs = Float32,
    steps = Int32,
    frames = Int32,
    catchUps = Int32
}

///
/// Keeping the performance figures.
///
/// Pure arithmetic, so the awkward part -- a rolling average that has to start somewhere -- is
/// testable without opening a window.
///
mod Stats {

    pub def empty(): Stats =
        { fps = 0.0f32, simMs = 0.0f32, drawMs = 0.0f32, steps = 0, frames = 0, catchUps = 0 }

    ///
    /// How much of each new sample to believe.
    ///
    /// Low, because these numbers are read by eye off a moving screen. An unsmoothed frame
    /// time flickers through every digit and tells you nothing; this settles in about a second
    /// and still moves when the load really changes.
    ///
    def weight(): Float32 = 0.1f32

    ///
    /// A rolling average that does not have to crawl up from zero.
    ///
    /// The first sample is taken whole. Blending it against an initial nought would show a
    /// frame rate climbing from 0 to 60 over the first second of every run, which looks like a
    /// stall and is really just the average filling up.
    ///
    pub def blend(first: Bool, previous: Float32, sample: Float32): Float32 =
        if (first) sample else previous * (1.0f32 - weight()) + sample * weight()

    def nanosPerSecond(): Float32 = 1000000000.0f32
    def nanosPerMilli(): Float32 = 1000000.0f32

    pub def millis(nanos: Int64): Float32 = Int64.toFloat32(nanos) / nanosPerMilli()

    ///
    /// The frame rate a gap of `frameNs` between frames implies.
    ///
    /// A gap of nought or less means the clock has not moved, which happens on the first frame
    /// and on machines whose timer granularity is coarser than a frame. Reporting an infinity
    /// there would be arithmetically honest and useless to read.
    ///
    pub def rateFrom(frameNs: Int64): Float32 =
        if (frameNs <= 0i64) 0.0f32 else nanosPerSecond() / Int64.toFloat32(frameNs)

    pub type alias Sample = {
        frameNs = Int64,
        simNs = Int64,
        drawNs = Int64,
        steps = Int32,
        clamped = Bool
    }

    ///
    /// Folds one frame's measurements into the running figures.
    ///
    pub def observe(previous: Stats, sample: Sample): Stats = {
        let first = previous#frames == 0;
        { fps = blend(first, previous#fps, rateFrom(sample#frameNs)),
          simMs = blend(first, previous#simMs, millis(sample#simNs)),
          drawMs = blend(first, previous#drawMs, millis(sample#drawNs)),
          steps = sample#steps,
          frames = previous#frames + 1,
          catchUps = previous#catchUps + (if (sample#clamped) 1 else 0) }
    }

    ///
    /// A `Float32` to one decimal place, without `String.format`.
    ///
    /// Rounds rather than truncates, so 1.99 does not read as 1.9. Negatives are not expected
    /// -- these are durations and rates -- but they are handled rather than silently mangled.
    ///
    pub def oneDecimal(value: Float32): String = {
        let negative = value < 0.0f32;
        let scaled = Float32.abs(value) * 10.0f32 + 0.5f32;
        let tenths = Float32.tryToInt32(Float32.floor(scaled)) |> Option.getWithDefault(0);
        let sign = if (negative and tenths > 0) "-" else "";
        "${sign}${tenths / 10}.${Int32.remainder(tenths, 10)}"
    }

    ///
    /// A `Float32` to two decimal places, for the sub-millisecond timings.
    ///
    /// The simulation costs about 0.13ms. To one decimal that is 0.1, which cannot tell an
    /// improvement from a regression.
    ///
    pub def twoDecimals(value: Float32): String = {
        let scaled = Float32.abs(value) * 100.0f32 + 0.5f32;
        let parts = Float32.tryToInt32(Float32.floor(scaled)) |> Option.getWithDefault(0);
        let fraction = Int32.remainder(parts, 100);
        let padded = if (fraction < 10) "0${fraction}" else "${fraction}";
        "${parts / 100}.${padded}"
    }

}
