///
/// A still picture: no state, no time, no input.
///
/// The smallest thing this runtime can draw, and the place to start reading. `scene` is an
/// ordinary function that happens to use the `Canvas` effect -- it does not know whether it
/// is drawing to a window or being recorded by a test.
///
/// Run it:   bin/sketch static
///
/// Try this: change `sun` to a different colour, or move it by editing the two numbers in
/// `Canvas.ellipse`. Re-run and see the difference.
///
mod Sketches.Still {

    def sky(): Color = Color.Rgb(28, 32, 64)
    def sun(): Color = Color.Rgb(240, 158, 74)
    def ground(): Color = Color.Rgb(18, 20, 34)
    def window(): Color = Color.Rgb(240, 214, 132)
    def ink(): Color = Color.Rgb(150, 158, 190)

    ///
    /// Draws one building: a dark block with a couple of lit windows.
    ///
    def building(x: Float32, y: Float32, w: Float32, h: Float32): Unit \ Canvas = {
        Canvas.fill(ground());
        Canvas.rect(x, y, w, h);
        Canvas.fill(window());
        Canvas.rect(x + 8.0f32, y + 12.0f32, 10.0f32, 14.0f32);
        Canvas.rect(x + w - 18.0f32, y + 34.0f32, 10.0f32, 14.0f32)
    }

    ///
    /// The whole picture. Pure apart from the `Canvas` effect.
    ///
    pub def scene(): Unit \ Canvas = {
        let (w, h) = Canvas.dimensions();
        let width = Int32.toFloat32(w);
        let height = Int32.toFloat32(h);
        let horizon = height * 0.68f32;

        Canvas.clear(sky());

        Canvas.fill(sun());
        Canvas.ellipse(width * 0.72f32, horizon - 54.0f32, 92.0f32, 92.0f32);

        Canvas.fill(ground());
        Canvas.rect(0.0f32, horizon, width, height - horizon);

        building(60.0f32, horizon - 120.0f32, 70.0f32, 120.0f32);
        building(150.0f32, horizon - 78.0f32, 54.0f32, 78.0f32);
        building(224.0f32, horizon - 150.0f32, 62.0f32, 150.0f32);

        Canvas.fill(ink());
        Canvas.textSize(13.0f32);
        Canvas.text("a still picture -- no state, no time", 24.0f32, height - 28.0f32)
    }

    pub def main(): Unit \ IO = {
        let limit = Sketch.maxFramesFromEnv();
        Sketch.start(
            {title = "Static", width = 640, height = 480, seed = 0i64, hz = 60, maxFrames = limit},
            _seed -> (),
            world -> _snapshot -> world,
            _world -> scene())
    }

}
