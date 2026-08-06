mod TestCanvas {

    use Assert.assertEq
    use Assert.assertTrue

    ///
    /// These tests are the point of the `Canvas` effect: rendering is checked as data, with
    /// no window and no `IO`. If any of them needed a display, the effect boundary would
    /// have leaked.
    ///

    @Test
    def testRecordsOperationsInOrder(): Unit \ Assert = {
        let cmds = Canvas.commands((640, 480), () -> {
            Canvas.clear(Color.black());
            Canvas.fill(Color.white());
            Canvas.rect(1.0f32, 2.0f32, 3.0f32, 4.0f32)
        });
        let expected =
            DrawCmd.Clear(Color.Rgb(0, 0, 0)) ::
            DrawCmd.Fill(Color.Rgb(255, 255, 255)) ::
            DrawCmd.Rect(1.0f32, 2.0f32, 3.0f32, 4.0f32) :: Nil;
        assertEq(expected = expected, cmds)
    }

    @Test
    def testDrawingNothingRecordsNothing(): Unit \ Assert =
        assertEq(expected = (Nil: List[DrawCmd]), Canvas.commands((640, 480), () -> ()))

    @Test
    def testDimensionsReportsTheConfiguredSize(): Unit \ Assert = {
        let (dims, cmds) = Canvas.runWithCollector((320, 240), () -> Canvas.dimensions());
        assertEq(expected = (320, 240), dims);
        // Querying the canvas must not be recorded as a drawing operation.
        assertEq(expected = (Nil: List[DrawCmd]), cmds)
    }

    @Test
    def testRunCollectingReturnsTheResult(): Unit \ Assert = {
        let (value, _) = Canvas.runWithCollector((10, 10), () -> {
            Canvas.rect(0.0f32, 0.0f32, 1.0f32, 1.0f32);
            42
        });
        assertEq(expected = 42, value)
    }

    @Test
    def testPaintRoundTrips(): Unit \ Assert = {
        let cmds =
            DrawCmd.Clear(Color.grey(30)) ::
            DrawCmd.TextSize(12.0f32) ::
            DrawCmd.Text("hi", 5.0f32, 6.0f32) ::
            DrawCmd.Ellipse(1.0f32, 2.0f32, 3.0f32, 4.0f32) :: Nil;
        assertEq(expected = cmds, Canvas.commands((640, 480), () -> Canvas.paint(cmds)))
    }

    @Test
    def testRenderingIsDeterministic(): Unit \ Assert = {
        let scene = () -> { Canvas.clear(Color.grey(10)); Canvas.rect(1.0f32, 1.0f32, 2.0f32, 2.0f32) };
        assertEq(expected = Canvas.commands((64, 64), scene), Canvas.commands((64, 64), scene))
    }

    @Test
    def testColorChannelAccessors(): Unit \ Assert = {
        let c = Color.Rgb(10, 20, 30);
        assertEq(expected = 10, Color.redOf(c));
        assertEq(expected = 20, Color.greenOf(c));
        assertEq(expected = 30, Color.blueOf(c))
    }

    @Test
    def testColorChannelsAreClamped(): Unit \ Assert = {
        let high = Color.Rgb(999, 300, 256);
        assertEq(expected = 255, Color.redOf(high));
        assertEq(expected = 255, Color.greenOf(high));
        assertEq(expected = 255, Color.blueOf(high));

        let low = Color.Rgb(-1, -50, -999);
        assertEq(expected = 0, Color.redOf(low));
        assertEq(expected = 0, Color.greenOf(low));
        assertEq(expected = 0, Color.blueOf(low))
    }

    // -- the interpretations -----------------------------------------------------------

    @Test
    def testRunWithNoOpDiscardsDrawingButKeepsTheResult(): Unit \ Assert = {
        // A third interpretation of `Canvas`, added without touching the runtime -- which is
        // the point of keeping the handlers in the companion module.
        let value = Canvas.runWithNoOp((640, 480), () -> {
            Canvas.clear(Color.black());
            Canvas.rect(0.0f32, 0.0f32, 10.0f32, 10.0f32);
            7
        });
        assertEq(expected = 7, value)
    }

    @Test
    def testRunWithNoOpStillAnswersDimensions(): Unit \ Assert =
        // Discarding the drawing must not mean discarding the queries too, or a sketch that
        // lays itself out from `dimensions` would silently collapse.
        assertEq(expected = (320, 240), Canvas.runWithNoOp((320, 240), () -> Canvas.dimensions()))

    @Test
    def testHandleWithCollectorTakesAnArgument(): Unit \ Assert = {
        // The `handle` form transforms a function rather than running a thunk, so the same
        // interpretation can be applied to many inputs.
        let render = Canvas.handleWithCollector((640, 480), n ->
            Canvas.rect(0.0f32, 0.0f32, Int32.toFloat32(n), Int32.toFloat32(n)));
        let (_, one) = render(1);
        let (_, two) = render(2);
        assertEq(expected = 1, List.length(one));
        assertTrue(one != two)
    }

}
